import express from 'express';
import { v4 as uuidv4 } from 'uuid';
import Joi from 'joi';
import { db } from '@/services/database';
import { authenticateToken as verifyToken, optionalAuth } from '@/middleware/auth';
import skipAuthInDev from '@/middleware/skipAuthInDev';
import { ApiResponse, CreateCollageRequest, UpdateCollageRequest, AddCollageItemRequest, CollageFilters, AuthenticatedRequest } from '@/types';

const router = express.Router();

// Validation schemas
const createCollageSchema = Joi.object({
  title: Joi.string().min(1).max(100).required(),
  description: Joi.string().max(500).allow('', null).optional(),
  cover_image_url: Joi.string().uri().allow('', null).optional(),
  layout: Joi.string()
    .valid('grid', 'masonry', 'carousel', 'stack', 'diagonal', 'spiral')
    .optional(),
  settings: Joi.object().optional(),
  tags: Joi.array().items(Joi.string().max(50)).max(20).optional(),
  is_published: Joi.boolean().optional(),
  items: Joi.array().optional(),
});

const updateCollageSchema = Joi.object({
  title: Joi.string().min(1).max(100).optional(),
  description: Joi.string().max(500).allow('', null).optional(),
  cover_image_url: Joi.string().uri().allow('', null).optional(),
  layout: Joi.string().valid('grid', 'masonry', 'carousel', 'stack', 'diagonal', 'spiral').optional(),
  settings: Joi.object().optional(),
  tags: Joi.array().items(Joi.string().max(50)).max(20).optional(),
  is_published: Joi.boolean().optional(),
  items: Joi.array().optional(),
});

const addItemSchema = Joi.object({
  image_url: Joi.string().uri().required(),
  position: Joi.object({
    x: Joi.number().min(0).max(1).required(),
    y: Joi.number().min(0).max(1).required(),
  }).required(),
  size: Joi.object({
    width: Joi.number().min(0.1).max(1).required(),
    height: Joi.number().min(0.1).max(1).required(),
  }).required(),
  rotation: Joi.number().min(0).max(2 * Math.PI).optional(),
  opacity: Joi.number().min(0).max(1).optional(),
  z_index: Joi.number().integer().min(0).optional(),
});

// Get all collages with filtering and pagination
router.get('/', optionalAuth, async (req: AuthenticatedRequest, res) => {
  try {
    const {
      query,
      page = 1,
      limit = 20,
      sort_by = 'created_at',
      sort_order = 'desc',
      tags,
      user_id,
      is_published,
      layout,
      created_after,
      created_before,
    } = req.query as CollageFilters;

    const offset = (Number(page) - 1) * Number(limit);

    // Build query
    let queryBuilder = db.collages()
      .select(`
        *,
        collage_items (
          id,
          image_url,
          position,
          size,
          rotation,
          opacity,
          z_index,
          created_at
        )
      `);

    // Apply filters
    console.log('🔍 GET /collages - User context:', req.user ? `user_id: ${req.user.id}` : 'not authenticated');
    console.log('🔍 Query params:', { user_id, is_published, page, limit });
    
    if (user_id) {
      queryBuilder = queryBuilder.eq('user_id', user_id);
      console.log('🔍 Filtering by user_id:', user_id);
    } else if (req.user && req.user.id) {
      // If authenticated, show user's collages by default
      queryBuilder = queryBuilder.eq('user_id', req.user.id);
      console.log('🔍 Filtering by authenticated user_id:', req.user.id);
      if (is_published !== undefined) {
        queryBuilder = queryBuilder.eq('is_published', String(is_published) === 'true');
        console.log('🔍 Also filtering by is_published:', String(is_published) === 'true');
      }
    } else if (!req.user) {
      // If not authenticated, only show published collages
      queryBuilder = queryBuilder.eq('is_published', true);
      console.log('🔍 Not authenticated - showing only published collages');
    } else if (is_published !== undefined) {
      queryBuilder = queryBuilder.eq('is_published', String(is_published) === 'true');
      console.log('🔍 Filtering by is_published:', String(is_published) === 'true');
    }

    if (query) {
      queryBuilder = queryBuilder.or(`title.ilike.%${query}%,description.ilike.%${query}%`);
    }

    if (tags && Array.isArray(tags)) {
      queryBuilder = queryBuilder.overlaps('tags', tags);
    }

    if (layout) {
      queryBuilder = queryBuilder.eq('layout', layout);
    }

    if (created_after) {
      queryBuilder = queryBuilder.gte('created_at', created_after);
    }

    if (created_before) {
      queryBuilder = queryBuilder.lte('created_at', created_before);
    }

    // Apply sorting
    const orderColumn = sort_by === 'title' ? 'title' : 'created_at';
    const ascending = sort_order === 'asc';
    queryBuilder = queryBuilder.order(orderColumn, { ascending });

    // Apply pagination
    queryBuilder = queryBuilder.range(offset, offset + Number(limit) - 1);

    const { data: collages, error, count } = await queryBuilder;

    if (error) {
      throw error;
    }

    console.log('🔍 Query result - Found collages:', collages?.length || 0);
    if (collages && collages.length > 0) {
      console.log('🔍 First collage:', {
        id: collages[0].id,
        title: collages[0].title,
        user_id: collages[0].user_id,
        is_published: collages[0].is_published
      });
    }

    const response: ApiResponse = {
      success: true,
      data: {
        collages: collages || [],
        pagination: {
          page: Number(page),
          limit: Number(limit),
          total: count || 0,
          total_pages: Math.ceil((count || 0) / Number(limit)),
        },
      },
    };

    res.json(response);
  } catch (error) {
    console.error('Get collages error:', error);
    const response: ApiResponse = {
      success: false,
      error: 'Failed to fetch collages',
    };
    res.status(500).json(response);
  }
});

// Get single collage by ID
router.get('/:id', optionalAuth, async (req: AuthenticatedRequest, res) => {
  try {
    const { id } = req.params;

    const { data: collage, error } = await db.collages()
      .select(`
        *,
        collage_items (
          id,
          image_url,
          position,
          size,
          rotation,
          opacity,
          z_index,
          created_at
        )
      `)
      .eq('id', id)
      .single();

    if (error || !collage) {
      const response: ApiResponse = {
        success: false,
        error: 'Collage not found',
      };
      return res.status(404).json(response);
    }

    // Check if user can view this collage
    if (!collage.is_published && (!req.user || req.user.id !== collage.user_id)) {
      const response: ApiResponse = {
        success: false,
        error: 'Access denied',
      };
      return res.status(403).json(response);
    }

    const response: ApiResponse = {
      success: true,
      data: collage,
    };

    res.json(response);
  } catch (error) {
    console.error('Get collage error:', error);
    const response: ApiResponse = {
      success: false,
      error: 'Failed to fetch collage',
    };
    res.status(500).json(response);
  }
});

// Create new collage
router.post('/', skipAuthInDev(), async (req: AuthenticatedRequest, res) => {
  try {
    console.log('🔍 POST /collages - Request body:', JSON.stringify(req.body, null, 2));
    
    // ✅ Validate user context
    if (!req.user || !req.user.id) {
      return res.status(401).json({ success: false, message: 'Unauthorized: No user context' });
    }
    const userId = req.user.id;

    const { error, value } = createCollageSchema.validate(req.body);
    if (error) {
      const response: ApiResponse = {
        success: false,
        error: error.details[0].message,
      };
      return res.status(400).json(response);
    }

    const { title, description, cover_image_url, layout, settings, tags, is_published, items }: CreateCollageRequest = value;

    // ✅ Auto-set published if essential info is complete
    const autoPublished =
      title?.trim()?.length > 0 &&
      cover_image_url &&
      cover_image_url.trim().length > 0;
    
    console.log('🔍 Backend auto-publish check:');
    console.log('🔍 title:', title, 'length:', title?.trim()?.length);
    console.log('🔍 cover_image_url:', cover_image_url, 'length:', cover_image_url?.trim()?.length);
    console.log('🔍 autoPublished:', autoPublished);

    const collageId = uuidv4();
    const { data: newCollage, error: createError } = await db.collages()
      .insert({
        id: collageId,
        user_id: userId,
        title,
        description: description || null,
        cover_image_url: cover_image_url || null,
        layout: layout || 'grid',
        settings: settings || {},
        tags: tags || [],
        is_published: autoPublished,
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .select(`
        *,
        collage_items (
          id,
          image_url,
          position,
          size,
          rotation,
          opacity,
          z_index,
          created_at
        )
      `)
      .single();

    if (createError) {
      throw createError;
    }

    // ✅ Process collage items if provided
    console.log('🔍 Items check - items:', items, 'length:', items?.length);
    if (items && items.length > 0) {
      console.log('🔍 Processing collage items:', items.length);
      
      const collageItems = items.map((item: any) => {
        console.log('🔍 Processing item:', JSON.stringify(item, null, 2));
        
        // For text items, we need to store the text in a way that can be retrieved
        // Since we don't have text columns yet, let's store text in the image_url field temporarily
        let imageUrl = item.image_url || 'https://via.placeholder.com/100x100';
        if (item.type === 'text' && item.text) {
          // Store text with font info as a special URL that we can detect
          const textData = {
            text: item.text,
            fontFamily: item.fontFamily || 'Roboto',
            fontSize: item.fontSize || 20,
            textColor: item.textColor || 0xFF000000,
            isBold: item.isBold || false,
            hasBackground: item.hasBackground || false,
            color: item.color || 0xFFFFFFFF
          };
          imageUrl = `text://${encodeURIComponent(JSON.stringify(textData))}`;
        }
        
        return {
          id: uuidv4(),
          collage_id: collageId,
          image_url: imageUrl,
          position: item.position ? {
            x: item.position.x || 0,
            y: item.position.y || 0,
          } : { x: 0, y: 0 },
          size: item.size ? {
            width: item.size.width || 100,
            height: item.size.height || 100,
          } : { width: 100, height: 100 },
          rotation: item.rotation || 0,
          opacity: item.opacity || 1.0,
          z_index: item.z_index || 0,
          created_at: new Date().toISOString(),
        };
      });

      console.log('🔍 Attempting to insert collage items:', JSON.stringify(collageItems, null, 2));
      
      const { error: itemsError } = await db.collageItems().insert(collageItems);
      
      if (itemsError) {
        console.error('❌ Error inserting collage items:', itemsError);
        console.error('❌ Error details:', JSON.stringify(itemsError, null, 2));
        // Don't fail the entire request, just log the error
      } else {
        console.log('✅ Successfully inserted collage items');
      }
    }

    // ✅ Fetch the complete collage with items for response
    console.log('🔍 Fetching complete collage with items for ID:', collageId);
    const { data: completeCollage, error: fetchError } = await db.collages()
      .select(`
        *,
        collage_items (
          id,
          image_url,
          position,
          size,
          rotation,
          opacity,
          z_index,
          created_at
        )
      `)
      .eq('id', collageId)
      .single();

    if (fetchError) {
      console.error('❌ Error fetching complete collage:', fetchError);
    } else {
      console.log('✅ Fetched complete collage:', JSON.stringify(completeCollage, null, 2));
    }

    const response: ApiResponse = {
      success: true,
      data: completeCollage || newCollage,
      message: 'Collage created successfully',
    };

    res.status(201).json(response);
  } catch (error) {
    console.error('Create collage error:', error);
    const response: ApiResponse = {
      success: false,
      error: 'Failed to create collage',
    };
    res.status(500).json(response);
  }
});

// Update collage
router.put('/:id', skipAuthInDev(), async (req: AuthenticatedRequest, res) => {
  try {
    // ✅ Validate user context
    if (!req.user || !req.user.id) {
      return res.status(401).json({ success: false, message: 'Unauthorized: No user context' });
    }
    const userId = req.user.id;

    const { id } = req.params;
    const { error, value } = updateCollageSchema.validate(req.body);
    
    if (error) {
      const response: ApiResponse = {
        success: false,
        error: error.details[0].message,
      };
      return res.status(400).json(response);
    }

    // Check if collage exists and user owns it
    const { data: existingCollage, error: findError } = await db.collages()
      .select('user_id')
      .eq('id', id)
      .single();

    if (findError || !existingCollage) {
      const response: ApiResponse = {
        success: false,
        error: 'Collage not found',
      };
      return res.status(404).json(response);
    }

    if (existingCollage.user_id !== userId) {
      const response: ApiResponse = {
        success: false,
        error: 'Access denied',
      };
      return res.status(403).json(response);
    }

    // ✅ Auto-publish when user adds missing cover image
    if (value.cover_image_url && value.title && !value.is_published) {
      value.is_published = true;
    }

    // ✅ Process items if provided
    if (value.items && Array.isArray(value.items)) {
      console.log('🔍 Processing items for update:', value.items.length);
      
      // Delete existing items
      await db.collageItems().delete().eq('collage_id', id);
      
      // Insert new items
      const itemsToInsert = value.items.map((item: any) => {
        let imageUrl = item.image_url || 'https://via.placeholder.com/100x100';
        if (item.type === 'text' && item.text) {
          const textData = {
            text: item.text,
            fontFamily: item.fontFamily || 'Roboto',
            fontSize: item.fontSize || 20,
            textColor: item.textColor || 0xFF000000,
            isBold: item.isBold || false,
            hasBackground: item.hasBackground || false,
            color: item.color || 0xFFFFFFFF
          };
          imageUrl = `text://${encodeURIComponent(JSON.stringify(textData))}`;
        }
        
        return {
          id: uuidv4(),
          collage_id: id,
          image_url: imageUrl,
          position: item.position ? {
            x: item.position.x || 0,
            y: item.position.y || 0,
          } : { x: 0, y: 0 },
          size: item.size ? {
            width: item.size.width || 100,
            height: item.size.height || 100,
          } : { width: 100, height: 100 },
          rotation: item.rotation || 0,
          opacity: item.opacity || 1.0,
          z_index: item.z_index || 0,
          created_at: new Date().toISOString(),
        };
      });
      
      console.log('🔍 Items to insert:', JSON.stringify(itemsToInsert, null, 2));
      
      const { error: itemsError } = await db.collageItems().insert(itemsToInsert);
      if (itemsError) {
        console.error('❌ Error inserting items:', itemsError);
        console.error('❌ Error details:', JSON.stringify(itemsError, null, 2));
        throw itemsError;
      }
      
      console.log('✅ Items processed successfully');
    }

    // Remove items from the main update since we handle them separately
    const { items, ...updateData } = value;
    
    const { data: updatedCollage, error: updateError } = await db.collages()
      .update({
        ...updateData,
        updated_at: new Date().toISOString(),
      })
      .eq('id', id)
      .select(`
        *,
        collage_items (
          id,
          image_url,
          position,
          size,
          rotation,
          opacity,
          z_index,
          created_at
        )
      `)
      .single();

    if (updateError) {
      throw updateError;
    }

    const response: ApiResponse = {
      success: true,
      data: updatedCollage,
      message: 'Collage updated successfully',
    };

    res.json(response);
  } catch (error) {
    console.error('Update collage error:', error);
    const response: ApiResponse = {
      success: false,
      error: 'Failed to update collage',
    };
    res.status(500).json(response);
  }
});

// Delete collage
router.delete('/:id', skipAuthInDev(), async (req: AuthenticatedRequest, res) => {
  try {
    console.log('🗑️ DELETE /collages/:id - Request received');
    
    // ✅ Validate user context
    if (!req.user || !req.user.id) {
      return res.status(401).json({ success: false, message: 'Unauthorized: No user context' });
    }
    const userId = req.user.id;

    const { id } = req.params;
    console.log('🗑️ Deleting collage with ID:', id);

    // Check if collage exists and user owns it
    const { data: existingCollage, error: findError } = await db.collages()
      .select('user_id')
      .eq('id', id)
      .single();

    if (findError || !existingCollage) {
      const response: ApiResponse = {
        success: false,
        error: 'Collage not found',
      };
      return res.status(404).json(response);
    }

    if (existingCollage.user_id !== userId) {
      const response: ApiResponse = {
        success: false,
        error: 'Access denied',
      };
      return res.status(403).json(response);
    }

    // Delete collage items first
    await db.collageItems().delete().eq('collage_id', id);

    // Delete collage
    const { error: deleteError } = await db.collages().delete().eq('id', id);

    if (deleteError) {
      throw deleteError;
    }

    const response: ApiResponse = {
      success: true,
      message: 'Collage deleted successfully',
    };

    res.json(response);
  } catch (error) {
    console.error('Delete collage error:', error);
    const response: ApiResponse = {
      success: false,
      error: 'Failed to delete collage',
    };
    res.status(500).json(response);
  }
});

// Add item to collage
router.post('/:id/items', skipAuthInDev(), async (req: AuthenticatedRequest, res) => {
  try {
    // ✅ Validate user context
    if (!req.user || !req.user.id) {
      return res.status(401).json({ success: false, message: 'Unauthorized: No user context' });
    }
    const userId = req.user.id;

    const { id } = req.params;
    const { error, value } = addItemSchema.validate(req.body);
    
    if (error) {
      const response: ApiResponse = {
        success: false,
        error: error.details[0].message,
      };
      return res.status(400).json(response);
    }

    // Check if collage exists and user owns it
    const { data: existingCollage, error: findError } = await db.collages()
      .select('user_id')
      .eq('id', id)
      .single();

    if (findError || !existingCollage) {
      const response: ApiResponse = {
        success: false,
        error: 'Collage not found',
      };
      return res.status(404).json(response);
    }

    if (existingCollage.user_id !== userId) {
      const response: ApiResponse = {
        success: false,
        error: 'Access denied',
      };
      return res.status(403).json(response);
    }

    const itemId = uuidv4();
    const { data: newItem, error: createError } = await db.collageItems()
      .insert({
        id: itemId,
        collage_id: id,
        image_url: value.image_url,
        position: value.position,
        size: value.size,
        rotation: value.rotation || 0,
        opacity: value.opacity || 1,
        z_index: value.z_index || 0,
        created_at: new Date().toISOString(),
      })
      .select()
      .single();

    if (createError) {
      throw createError;
    }

    // Update collage updated_at
    await db.collages()
      .update({ updated_at: new Date().toISOString() })
      .eq('id', id);

    const response: ApiResponse = {
      success: true,
      data: newItem,
      message: 'Item added to collage successfully',
    };

    res.status(201).json(response);
  } catch (error) {
    console.error('Add collage item error:', error);
    const response: ApiResponse = {
      success: false,
      error: 'Failed to add item to collage',
    };
    res.status(500).json(response);
  }
});

// Update collage item
router.put('/:id/items/:itemId', skipAuthInDev(), async (req: AuthenticatedRequest, res) => {
  try {
    // ✅ Validate user context
    if (!req.user || !req.user.id) {
      return res.status(401).json({ success: false, message: 'Unauthorized: No user context' });
    }
    const userId = req.user.id;

    const { id, itemId } = req.params;
    const { error, value } = addItemSchema.validate(req.body);
    
    if (error) {
      const response: ApiResponse = {
        success: false,
        error: error.details[0].message,
      };
      return res.status(400).json(response);
    }

    // Check if collage exists and user owns it
    const { data: existingCollage, error: findError } = await db.collages()
      .select('user_id')
      .eq('id', id)
      .single();

    if (findError || !existingCollage) {
      const response: ApiResponse = {
        success: false,
        error: 'Collage not found',
      };
      return res.status(404).json(response);
    }

    if (existingCollage.user_id !== userId) {
      const response: ApiResponse = {
        success: false,
        error: 'Access denied',
      };
      return res.status(403).json(response);
    }

    const { data: updatedItem, error: updateError } = await db.collageItems()
      .update({
        image_url: value.image_url,
        position: value.position,
        size: value.size,
        rotation: value.rotation || 0,
        opacity: value.opacity || 1,
        z_index: value.z_index || 0,
      })
      .eq('id', itemId)
      .eq('collage_id', id)
      .select()
      .single();

    if (updateError) {
      throw updateError;
    }

    // Update collage updated_at
    await db.collages()
      .update({ updated_at: new Date().toISOString() })
      .eq('id', id);

    const response: ApiResponse = {
      success: true,
      data: updatedItem,
      message: 'Collage item updated successfully',
    };

    res.json(response);
  } catch (error) {
    console.error('Update collage item error:', error);
    const response: ApiResponse = {
      success: false,
      error: 'Failed to update collage item',
    };
    res.status(500).json(response);
  }
});

// Remove item from collage
router.delete('/:id/items/:itemId', skipAuthInDev(), async (req: AuthenticatedRequest, res) => {
  try {
    // ✅ Validate user context
    if (!req.user || !req.user.id) {
      return res.status(401).json({ success: false, message: 'Unauthorized: No user context' });
    }
    const userId = req.user.id;

    const { id, itemId } = req.params;

    // Check if collage exists and user owns it
    const { data: existingCollage, error: findError } = await db.collages()
      .select('user_id')
      .eq('id', id)
      .single();

    if (findError || !existingCollage) {
      const response: ApiResponse = {
        success: false,
        error: 'Collage not found',
      };
      return res.status(404).json(response);
    }

    if (existingCollage.user_id !== userId) {
      const response: ApiResponse = {
        success: false,
        error: 'Access denied',
      };
      return res.status(403).json(response);
    }

    // Delete the item
    const { error: deleteError } = await db.collageItems()
      .delete()
      .eq('id', itemId)
      .eq('collage_id', id);

    if (deleteError) {
      throw deleteError;
    }

    // Update collage updated_at
    await db.collages()
      .update({ updated_at: new Date().toISOString() })
      .eq('id', id);

    const response: ApiResponse = {
      success: true,
      message: 'Item removed from collage successfully',
    };

    res.json(response);
  } catch (error) {
    console.error('Remove collage item error:', error);
    const response: ApiResponse = {
      success: false,
      error: 'Failed to remove item from collage',
    };
    res.status(500).json(response);
  }
});

export default router;
