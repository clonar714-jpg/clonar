import express from "express";
import { Request, Response } from "express";
import { db } from "../services/database";

const router = express.Router();

/**
 * ✅ GET /api/chats
 * Get all conversations for the current user
 */
router.get("/", async (req: Request, res: Response) => {
  try {
    // TODO: Get user_id from auth token (currently using dev mode)
    const userId = req.headers["user-id"] as string || "dev-user-id";
    
    // ✅ FIX: Select only columns that exist (query and image_url may not exist if migration not run)
    // Try to select query, but fallback if column doesn't exist
    let selectColumns = "id, title, created_at, updated_at";
    
    // Check if query column exists by trying to select it
    const { data, error } = await db.conversations()
      .select(selectColumns)
      .eq("user_id", userId)
      .is("deleted_at", null)
      .order("updated_at", { ascending: false })
      .limit(50); // Limit to 50 most recent
    
    if (error) {
      console.error("❌ Error fetching conversations:", error);
      return res.status(500).json({ error: "Failed to fetch conversations" });
    }
    
    res.json({ conversations: data || [] });
  } catch (err: any) {
    console.error("❌ Unexpected error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

/**
 * ✅ GET /api/chats/:id
 * Get a single conversation with all messages
 */
router.get("/:id", async (req: Request, res: Response) => {
  try {
    const conversationId = req.params.id;
    const userId = req.headers["user-id"] as string || "dev-user-id";
    
    // Get conversation
    const { data: conversation, error: convError } = await db.conversations()
      .select("*")
      .eq("id", conversationId)
      .eq("user_id", userId)
      .is("deleted_at", null)
      .single();
    
    if (convError || !conversation) {
      return res.status(404).json({ error: "Conversation not found" });
    }
    
    // Get all messages for this conversation
    const { data: messages, error: msgError } = await db.conversationMessages()
      .select("*")
      .eq("conversation_id", conversationId)
      .order("created_at", { ascending: true });
    
    if (msgError) {
      console.error("❌ Error fetching messages:", msgError);
      return res.status(500).json({ error: "Failed to fetch messages" });
    }
    
    res.json({
      conversation,
      messages: messages || [],
    });
  } catch (err: any) {
    console.error("❌ Unexpected error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

/**
 * ✅ POST /api/chats
 * Create a new conversation
 */
router.post("/", async (req: Request, res: Response) => {
  try {
    const userId = req.headers["user-id"] as string || "dev-user-id";
    const { title, query, imageUrl } = req.body;
    
    if (!title) {
      return res.status(400).json({ error: "Title is required" });
    }
    
    // ✅ FIX: Build insert object conditionally (query and image_url columns may not exist if migration not run)
    const insertData: any = {
      user_id: userId,
      title: title.substring(0, 255), // Limit title length
    };
    
    // Only include query if provided (column may not exist)
    if (query) {
      insertData.query = query;
    }
    
    // Only include image_url if provided (and column exists)
    if (imageUrl) {
      insertData.image_url = imageUrl;
    }
    
    const { data, error } = await db.conversations()
      .insert(insertData)
      .select()
      .single();
    
    if (error) {
      console.error("❌ Error creating conversation:", error);
      return res.status(500).json({ error: "Failed to create conversation" });
    }
    
    res.status(201).json({ conversation: data });
  } catch (err: any) {
    console.error("❌ Unexpected error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

/**
 * ✅ POST /api/chats/:id/messages
 * Add a message to a conversation
 */
router.post("/:id/messages", async (req: Request, res: Response) => {
  try {
    const conversationId = req.params.id;
    const userId = req.headers["user-id"] as string || "dev-user-id";
    
    // Verify conversation belongs to user
    const { data: conversation, error: convError } = await db.conversations()
      .select("id")
      .eq("id", conversationId)
      .eq("user_id", userId)
      .is("deleted_at", null)
      .single();
    
    if (convError || !conversation) {
      return res.status(404).json({ error: "Conversation not found" });
    }
    
    const {
      query,
      summary,
      intent,
      cardType,
      cards,
      results,
      sections,
      answer,
      imageUrl,
    } = req.body;
    
    if (!query) {
      return res.status(400).json({ error: "Query is required" });
    }
    
    // ✅ FIX: Build insert object conditionally (image_url column may not exist)
    const messageData: any = {
      conversation_id: conversationId,
      query: query,
      summary: summary || null,
      intent: intent || null,
      card_type: cardType || null,
      cards: cards ? JSON.stringify(cards) : null,
      results: results ? JSON.stringify(results) : null,
      sections: sections ? JSON.stringify(sections) : null,
      answer: answer ? JSON.stringify(answer) : null,
    };
    
    // Only include image_url if provided (column may not exist)
    if (imageUrl) {
      messageData.image_url = imageUrl;
    }
    
    const { data, error } = await db.conversationMessages()
      .insert(messageData)
      .select()
      .single();
    
    if (error) {
      console.error("❌ Error creating message:", error);
      return res.status(500).json({ error: "Failed to create message" });
    }
    
    // Update conversation's updated_at timestamp
    await db.conversations()
      .update({ updated_at: new Date().toISOString() })
      .eq("id", conversationId);
    
    res.status(201).json({ message: data });
  } catch (err: any) {
    console.error("❌ Unexpected error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

/**
 * ✅ PUT /api/chats/:id
 * Update conversation (e.g., rename)
 */
router.put("/:id", async (req: Request, res: Response) => {
  try {
    const conversationId = req.params.id;
    const userId = req.headers["user-id"] as string || "dev-user-id";
    const { title } = req.body;
    
    if (!title) {
      return res.status(400).json({ error: "Title is required" });
    }
    
    // Verify conversation belongs to user
    const { data: conversation, error: convError } = await db.conversations()
      .select("id")
      .eq("id", conversationId)
      .eq("user_id", userId)
      .is("deleted_at", null)
      .single();
    
    if (convError || !conversation) {
      return res.status(404).json({ error: "Conversation not found" });
    }
    
    const { data, error } = await db.conversations()
      .update({
        title: title.substring(0, 255),
        updated_at: new Date().toISOString(),
      })
      .eq("id", conversationId)
      .select()
      .single();
    
    if (error) {
      console.error("❌ Error updating conversation:", error);
      return res.status(500).json({ error: "Failed to update conversation" });
    }
    
    res.json({ conversation: data });
  } catch (err: any) {
    console.error("❌ Unexpected error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

/**
 * ✅ DELETE /api/chats/:id
 * Soft delete a conversation
 */
router.delete("/:id", async (req: Request, res: Response) => {
  try {
    const conversationId = req.params.id;
    const userId = req.headers["user-id"] as string || "dev-user-id";
    
    // Verify conversation belongs to user
    const { data: conversation, error: convError } = await db.conversations()
      .select("id")
      .eq("id", conversationId)
      .eq("user_id", userId)
      .is("deleted_at", null)
      .single();
    
    if (convError || !conversation) {
      return res.status(404).json({ error: "Conversation not found" });
    }
    
    // Soft delete
    const { error } = await db.conversations()
      .update({
        deleted_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq("id", conversationId);
    
    if (error) {
      console.error("❌ Error deleting conversation:", error);
      return res.status(500).json({ error: "Failed to delete conversation" });
    }
    
    res.json({ success: true });
  } catch (err: any) {
    console.error("❌ Unexpected error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

export default router;

