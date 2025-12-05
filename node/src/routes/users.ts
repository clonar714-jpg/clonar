import express from 'express';
import Joi from 'joi';
import { db } from '@/services/database';
import { authenticateToken as verifyToken } from '@/middleware/auth';
import skipAuthInDev from '@/middleware/skipAuthInDev';
import { ApiResponse, AuthenticatedRequest } from '@/types';

const router = express.Router();

// Validation schemas
const updateProfileSchema = Joi.object({
  username: Joi.string().alphanum().min(3).max(30).optional(),
  full_name: Joi.string().max(100).optional().allow(''),
  bio: Joi.string().max(500).optional().allow(''),
  avatar_url: Joi.string().uri().optional().allow(''),
});

// Get user profile by ID
router.get('/:id', skipAuthInDev(), async (req, res) => {
  try {
    const { id } = req.params;

    const { data: user, error } = await db.users()
      .select('id, username, full_name, avatar_url, bio, is_verified, created_at')
      .eq('id', id)
      .single();

    if (error || !user) {
      const response: ApiResponse = {
        success: false,
        error: 'User not found',
      };
      return res.status(404).json(response);
    }

    const response: ApiResponse = {
      success: true,
      data: user,
    };

    res.json(response);
  } catch (error) {
    console.error('Get user profile error:', error);
    const response: ApiResponse = {
      success: false,
      error: 'Failed to fetch user profile',
    };
    res.status(500).json(response);
  }
});

// Update user profile
router.put('/profile', skipAuthInDev(), async (req: AuthenticatedRequest, res) => {
  try {
    const { error, value } = updateProfileSchema.validate(req.body);
    
    if (error) {
      const response: ApiResponse = {
        success: false,
        error: error.details[0].message,
      };
      return res.status(400).json(response);
    }

    // Check if username is already taken (if being updated)
    if (value.username) {
      const { data: existingUser, error: checkError } = await db.users()
        .select('id')
        .eq('username', value.username)
        .neq('id', req.user!.id)
        .single();

      if (existingUser) {
        const response: ApiResponse = {
          success: false,
          error: 'Username already taken',
        };
        return res.status(400).json(response);
      }
    }

    const { data: updatedUser, error: updateError } = await db.users()
      .update({
        ...value,
        updated_at: new Date().toISOString(),
      })
      .eq('id', req.user!.id)
      .select('id, email, username, full_name, avatar_url, bio, is_verified, created_at, updated_at')
      .single();

    if (updateError) {
      throw updateError;
    }

    const response: ApiResponse = {
      success: true,
      data: updatedUser,
      message: 'Profile updated successfully',
    };

    res.json(response);
  } catch (error) {
    console.error('Update profile error:', error);
    const response: ApiResponse = {
      success: false,
      error: 'Failed to update profile',
    };
    res.status(500).json(response);
  }
});

// Get user's personas
router.get('/:id/personas', skipAuthInDev(), async (req, res) => {
  try {
    const { id } = req.params;
    const { page = 1, limit = 20 } = req.query;
    const offset = (Number(page) - 1) * Number(limit);

    const { data: personas, error, count } = await db.personas()
      .select(`
        *,
        persona_items (
          id,
          image_url,
          title,
          description,
          position,
          created_at
        )
      `)
      .eq('user_id', id)
      .eq('is_secret', false) // Only show public personas
      .order('created_at', { ascending: false })
      .range(offset, offset + Number(limit) - 1);

    if (error) {
      throw error;
    }

    const response: ApiResponse = {
      success: true,
      data: {
        personas: personas || [],
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
    console.error('Get user personas error:', error);
    const response: ApiResponse = {
      success: false,
      error: 'Failed to fetch user personas',
    };
    res.status(500).json(response);
  }
});

// Get user's collages
router.get('/:id/collages', skipAuthInDev(), async (req, res) => {
  try {
    const { id } = req.params;
    const { page = 1, limit = 20 } = req.query;
    const offset = (Number(page) - 1) * Number(limit);

    const { data: collages, error, count } = await db.collages()
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
      .eq('user_id', id)
      .eq('is_published', true) // Only show published collages
      .order('created_at', { ascending: false })
      .range(offset, offset + Number(limit) - 1);

    if (error) {
      throw error;
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
    console.error('Get user collages error:', error);
    const response: ApiResponse = {
      success: false,
      error: 'Failed to fetch user collages',
    };
    res.status(500).json(response);
  }
});

// Get user's private content (only for the user themselves)
router.get('/:id/private', skipAuthInDev(), async (req: AuthenticatedRequest, res) => {
  try {
    const { id } = req.params;

    // Check if user is accessing their own private content
    if (req.user!.id !== id) {
      const response: ApiResponse = {
        success: false,
        error: 'Access denied',
      };
      return res.status(403).json(response);
    }

    const { page = 1, limit = 20 } = req.query;
    const offset = (Number(page) - 1) * Number(limit);

    // Get private personas
    const { data: privatePersonas, error: personasError } = await db.personas()
      .select(`
        *,
        persona_items (
          id,
          image_url,
          title,
          description,
          position,
          created_at
        )
      `)
      .eq('user_id', id)
      .eq('is_secret', true)
      .order('created_at', { ascending: false });

    // Get unpublished collages
    const { data: privateCollages, error: collagesError } = await db.collages()
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
      .eq('user_id', id)
      .eq('is_published', false)
      .order('created_at', { ascending: false });

    if (personasError || collagesError) {
      throw personasError || collagesError;
    }

    const response: ApiResponse = {
      success: true,
      data: {
        private_personas: privatePersonas || [],
        private_collages: privateCollages || [],
      },
    };

    res.json(response);
  } catch (error) {
    console.error('Get private content error:', error);
    const response: ApiResponse = {
      success: false,
      error: 'Failed to fetch private content',
    };
    res.status(500).json(response);
  }
});

export default router;
