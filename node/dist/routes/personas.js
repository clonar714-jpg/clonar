import express from "express";
import { v4 as uuidv4 } from "uuid";
import Joi from "joi";
import multer from "multer";
import sharp from "sharp";
import path from "path";
import fs from "fs";
import { db, supabase } from "@/services/database";
import skipAuthInDev from "@/middleware/skipAuthInDev";
const router = express.Router();
// 📁 Multer configuration for file uploads
const storage = multer.memoryStorage();
const upload = multer({
    storage,
    limits: {
        fileSize: 10 * 1024 * 1024, // 10MB limit
    },
    fileFilter: (req, file, cb) => {
        if (file.mimetype.startsWith("image/") ||
            (process.env.NODE_ENV === "development" && file.mimetype === "application/octet-stream")) {
            cb(null, true);
        }
        else {
            console.warn("⚠️ Rejected file type:", file.mimetype);
            cb(new Error("Only image files are allowed"));
        }
    },
});
// 🧩 Validation schema
const createPersonaSchema = Joi.object({
    name: Joi.string().min(1).max(100).required(),
    description: Joi.string().max(500).optional().allow(""),
    cover_image_url: Joi.string().uri().optional().allow(""),
    tags: Joi.array().items(Joi.string().max(50)).max(20).optional(),
    is_secret: Joi.boolean().optional(),
    extra_image_urls: Joi.array().items(Joi.string().uri()).max(10).optional(),
});
// ✅ GET all personas (with persona_items)
router.get("/", skipAuthInDev, async (req, res) => {
    try {
        console.log("📡 [GET] /api/personas (dev override)");
        const { data, error } = await supabase()
            .from("personas")
            .select(`
        *,
        persona_items (
          id,
          image_url,
          title,
          description,
          created_at
        )
      `)
            .order("created_at", { ascending: false });
        if (error)
            throw error;
        console.log(`✅ Fetched ${data?.length || 0} personas (with items)`);
        return res.status(200).json({ success: true, data });
    }
    catch (err) {
        console.error("💥 Persona fetch error:", err);
        return res.status(500).json({
            success: false,
            error: err.message || "Internal server error",
        });
    }
});
// ✅ GET single persona by ID (with dev mode placeholder)
router.get('/:id', skipAuthInDev, async (req, res) => {
    try {
        const { id } = req.params;
        console.log(`📡 [GET] /api/personas/${id}`);
        const { data: persona, error } = await supabase()
            .from("personas")
            .select(`
        *,
        persona_items (
          id,
          image_url,
          title,
          description,
          created_at
        )
      `)
            .eq("id", id)
            .single();
        if (!persona || error) {
            if (process.env.NODE_ENV === 'development') {
                console.log(`⚠️ Dev mode: persona ${id} not found — returning placeholder`);
                return res.json({
                    success: true,
                    data: {
                        id,
                        name: 'Placeholder Persona',
                        description: 'This persona does not exist in dev mode. This is a fallback placeholder.',
                        cover_image_url: 'https://via.placeholder.com/600x300.png?text=Placeholder+Image',
                        tags: ['#placeholder', '#dev'],
                        is_secret: false,
                        persona_items: [],
                        created_at: new Date().toISOString(),
                        updated_at: new Date().toISOString(),
                    },
                });
            }
            else {
                return res.status(404).json({
                    success: false,
                    error: 'Persona not found',
                });
            }
        }
        // Normal case — persona found
        console.log(`✅ Fetched persona: ${persona.name}`);
        return res.json({
            success: true,
            data: persona,
        });
    }
    catch (err) {
        console.error('❌ Error fetching persona by ID:', err);
        res.status(500).json({
            success: false,
            error: 'Server error while fetching persona',
        });
    }
});
// ✅ CREATE persona (atomic insert)
router.post("/", skipAuthInDev(), async (req, res) => {
    try {
        console.log("🟣 Persona create request:", req.body);
        const { error, value } = createPersonaSchema.validate(req.body);
        if (error)
            return res
                .status(400)
                .json({ success: false, error: error.details[0].message });
        const { name, description, cover_image_url, tags, is_secret, extra_image_urls } = value;
        const isDev = process.env.NODE_ENV === "development";
        // Force user_id in dev mode, use real user_id in production
        const userId = isDev ? "00000000-0000-0000-0000-000000000000" : req.user?.id;
        if (!isDev && !userId) {
            console.warn("⚠️ Missing user_id in production!");
            return res.status(400).json({ success: false, error: "User not authenticated" });
        }
        // 1️⃣ Check duplicate name (only in production)
        if (!isDev) {
            const { data: existing } = await db.personas()
                .select("id")
                .eq("user_id", userId)
                .eq("name", name)
                .maybeSingle();
            if (existing)
                return res
                    .status(400)
                    .json({ success: false, error: "Persona with this name already exists" });
        }
        // 2️⃣ Insert main persona
        const personaId = uuidv4();
        const insertPayload = {
            id: personaId,
            user_id: userId,
            name,
            description: description || "",
            cover_image_url: cover_image_url || "",
            tags: tags || [],
            is_secret: is_secret || false,
            created_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
        };
        console.log(`🧩 Creating persona in ${isDev ? "DEV" : "PROD"} mode`);
        console.log("📦 Payload:", insertPayload);
        // Use service role client for dev mode
        const client = isDev ? db.personas() : supabase().from("personas");
        const { data: newPersona, error: createError } = await client
            .insert(insertPayload)
            .select("*")
            .single();
        if (createError)
            throw createError;
        // 3️⃣ Insert extra images into persona_items
        if (extra_image_urls && Array.isArray(extra_image_urls) && extra_image_urls.length > 0) {
            console.log(`📸 Adding ${extra_image_urls.length} extra images to persona ${personaId}`);
            const items = extra_image_urls.map((url, i) => ({
                persona_id: personaId,
                image_url: url,
                title: "",
                description: "",
                position: i,
                created_at: new Date().toISOString(),
            }));
            // Use appropriate client for persona_items
            const itemsClient = isDev ? db.personaItems() : supabase().from("persona_items");
            const { error: itemsError } = await itemsClient.insert(items);
            if (itemsError) {
                console.error("❌ persona_items insert failed:", itemsError.message);
            }
            else {
                console.log(`✅ Successfully added ${extra_image_urls.length} extra images`);
            }
        }
        // 4️⃣ Return fresh persona with persona_items
        const { data: freshPersona, error: fetchError } = await supabase()
            .from("personas")
            .select(`
        *,
        persona_items (
          id,
          image_url,
          title,
          description,
          created_at
        )
      `)
            .eq("id", personaId)
            .single();
        if (fetchError) {
            console.error("❌ Failed to fetch fresh persona:", fetchError.message);
            return res.status(201).json({ success: true, data: newPersona });
        }
        console.log(`✅ Persona created successfully: ${personaId}`);
        console.log(`✅ Persona refreshed: ${personaId}, ${freshPersona.persona_items?.length || 0} items`);
        return res.status(201).json({ success: true, data: freshPersona });
    }
    catch (error) {
        console.error("🔥 Create persona error:", error.message || error);
        return res
            .status(500)
            .json({ success: false, error: error.message || "Failed to create persona" });
    }
});
router.put('/:id', skipAuthInDev, async (req, res) => {
    try {
        const { id } = req.params;
        const { name, description, cover_image_url, tags, is_secret } = req.body;
        console.log('🟣 Updating persona:', id, 'with tags:', tags);
        console.log('🔍 Tags type:', typeof tags);
        console.log('🔍 Is array:', Array.isArray(tags));
        console.log('🔍 Full request body:', req.body);
        // Fetch existing record
        const { data: persona, error: fetchError } = await db.personas()
            .select('*')
            .eq('id', id)
            .single();
        if (fetchError || !persona) {
            console.error('❌ Persona not found:', fetchError);
            return res.status(404).json({ success: false, error: 'Persona not found' });
        }
        // ✅ Keep consistent JSON array format for tags
        const updatePayload = {
            name: name ?? persona.name,
            description: description ?? persona.description,
            cover_image_url: cover_image_url ?? persona.cover_image_url,
            tags: Array.isArray(tags) ? tags : persona.tags || [],
            is_secret: is_secret ?? persona.is_secret,
            updated_at: new Date().toISOString(),
        };
        const { data, error } = await db.personas()
            .update(updatePayload)
            .eq('id', id)
            .select()
            .single();
        if (error)
            throw error;
        console.log(`✅ Persona updated successfully: ${id}`);
        console.log('🔍 Updated persona data:', data);
        console.log('🔍 Updated tags:', data?.tags);
        return res.json({ success: true, data });
    }
    catch (error) {
        console.error('❌ Update error:', error.message);
        return res.status(500).json({ success: false, error: error.message });
    }
});
// ✅ DELETE persona
router.delete('/:id', skipAuthInDev, async (req, res) => {
    try {
        const { id } = req.params;
        console.log('🗑️ Deleting persona:', id);
        // Check if persona exists
        const { data: persona, error: fetchError } = await db.personas()
            .select('id, name')
            .eq('id', id)
            .single();
        if (fetchError || !persona) {
            console.error('❌ Persona not found:', fetchError);
            return res.status(404).json({ success: false, error: 'Persona not found' });
        }
        // Delete persona items first (cascade delete)
        const { error: itemsError } = await db.personaItems()
            .delete()
            .eq('persona_id', id);
        if (itemsError) {
            console.error('❌ Failed to delete persona items:', itemsError);
            return res.status(500).json({ success: false, error: 'Failed to delete persona items' });
        }
        // Delete the persona
        const { error: deleteError } = await db.personas()
            .delete()
            .eq('id', id);
        if (deleteError) {
            console.error('❌ Failed to delete persona:', deleteError);
            return res.status(500).json({ success: false, error: 'Failed to delete persona' });
        }
        console.log(`✅ Persona deleted successfully: ${id}`);
        return res.json({ success: true, message: 'Persona deleted successfully' });
    }
    catch (error) {
        console.error('❌ Delete persona error:', error.message);
        return res.status(500).json({ success: false, error: error.message });
    }
});
// ✅ DELETE persona item (individual image)
router.delete('/:id/items/:itemId', skipAuthInDev, async (req, res) => {
    try {
        const { id, itemId } = req.params;
        console.log('🗑️ Deleting persona item:', itemId, 'from persona:', id);
        // Check if persona exists
        const { data: persona, error: personaError } = await db.personas()
            .select('id')
            .eq('id', id)
            .single();
        if (personaError || !persona) {
            console.error('❌ Persona not found:', personaError);
            return res.status(404).json({ success: false, error: 'Persona not found' });
        }
        // Delete the persona item
        const { error: deleteError } = await db.personaItems()
            .delete()
            .eq('id', itemId)
            .eq('persona_id', id);
        if (deleteError) {
            console.error('❌ Failed to delete persona item:', deleteError);
            return res.status(500).json({ success: false, error: 'Failed to delete persona item' });
        }
        console.log(`✅ Persona item deleted successfully: ${itemId}`);
        return res.json({ success: true, message: 'Persona item deleted successfully' });
    }
    catch (error) {
        console.error('❌ Delete persona item error:', error.message);
        return res.status(500).json({ success: false, error: error.message });
    }
});
// ✅ ADD image to persona (multipart/form-data upload)
router.post("/:id/items", skipAuthInDev, upload.single('image'), async (req, res) => {
    try {
        console.log("🟢 POST /api/personas/:id/items called");
        console.log("📝 Persona ID:", req.params.id);
        console.log("📦 Request body:", req.body);
        console.log("📁 Uploaded file:", req.file ? `${req.file.originalname} (${req.file.size} bytes)` : 'No file');
        const personaId = req.params.id;
        const { title, description } = req.body;
        const isDev = process.env.NODE_ENV === "development";
        // ✅ Allow direct URL insert when no file is uploaded (useful for dev mode / Flutter JSON)
        if (!req.file) {
            if (req.body.image_url) {
                console.log("🧪 Dev mode: Using provided image_url instead of file upload");
                const { image_url, title, description, position } = req.body;
                const { data, error } = await supabase()
                    .from("persona_items")
                    .insert([
                    {
                        persona_id: req.params.id,
                        image_url,
                        title: title || "",
                        description: description || "",
                        position: position || 0,
                        created_at: new Date().toISOString(),
                    },
                ])
                    .select("*");
                if (error) {
                    console.error("❌ Failed to insert persona item via image_url:", error.message);
                    return res.status(500).json({ success: false, error: error.message });
                }
                console.log(`✅ Added persona item via image_url: ${image_url}`);
                return res.status(201).json({ success: true, data: data[0] });
            }
            // If neither file nor image_url was provided
            return res.status(400).json({
                success: false,
                error: "Either image file or image_url must be provided",
            });
        }
        // ✅ Dev mode bypass for ownership check
        let persona;
        if (isDev) {
            console.log("🧪 Dev mode: Skipping user_id ownership check ✅");
            const { data, error } = await supabase()
                .from("personas")
                .select("id")
                .eq("id", personaId)
                .single();
            persona = data;
        }
        else {
            const { data, error } = await supabase()
                .from("personas")
                .select("id, user_id")
                .eq("id", personaId)
                .eq("user_id", req.user?.id || '00000000-0000-0000-0000-000000000000')
                .single();
            persona = data;
        }
        if (!persona) {
            console.error("❌ Persona not found");
            return res.status(404).json({ success: false, error: "Persona not found" });
        }
        // Ensure uploads directory exists
        const uploadsDir = path.join(process.cwd(), 'uploads');
        if (!fs.existsSync(uploadsDir)) {
            fs.mkdirSync(uploadsDir, { recursive: true });
        }
        // Process image with sharp
        const filename = `${uuidv4()}.jpg`;
        const filepath = path.join(uploadsDir, filename);
        console.log("🖼️ Processing image with sharp...");
        await sharp(req.file.buffer)
            .resize({ width: 1080, height: 1080, fit: "inside" })
            .jpeg({ quality: 85 })
            .toFile(filepath);
        // Generate full absolute URL for proper image display
        const imageUrl = `${isDev
            ? "http://10.0.2.2:4000"
            : "https://your-production-domain.com"}/uploads/${filename}`;
        console.log("🖼️ Final image URL:", imageUrl);
        // Insert into persona_items
        const { data, error } = await supabase()
            .from("persona_items")
            .insert([
            {
                persona_id: personaId,
                image_url: imageUrl,
                title: title || '',
                description: description || '',
            },
        ])
            .select();
        if (error) {
            console.error("❌ Failed to insert persona item:", error.message);
            // Clean up uploaded file if database insert fails
            if (fs.existsSync(filepath)) {
                fs.unlinkSync(filepath);
            }
            return res.status(500).json({ success: false, error: error.message });
        }
        // Return fresh persona with persona_items
        const { data: freshPersona, error: fetchError } = await supabase()
            .from("personas")
            .select(`
        *,
        persona_items (
          id,
          image_url,
          title,
          description,
          created_at
        )
      `)
            .eq("id", personaId)
            .single();
        if (fetchError) {
            console.error("❌ Failed to fetch fresh persona:", fetchError.message);
            return res.status(201).json({ success: true, data: data[0] });
        }
        console.log("✅ Added image to persona", personaId, "URL:", imageUrl);
        console.log(`✅ Persona refreshed: ${personaId}, ${freshPersona.persona_items?.length || 0} items`);
        return res.status(201).json({ success: true, data: freshPersona });
    }
    catch (err) {
        console.error("💥 Error in /api/personas/:id/items:", err);
        // Clean up uploaded file if processing fails
        if (req.file) {
            const uploadsDir = path.join(process.cwd(), 'uploads');
            const filename = `${uuidv4()}.jpg`;
            const filepath = path.join(uploadsDir, filename);
            if (fs.existsSync(filepath)) {
                fs.unlinkSync(filepath);
            }
        }
        return res.status(500).json({ success: false, error: "Internal server error" });
    }
});
export default router;
