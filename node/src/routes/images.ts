/**
 * ✅ PERPLEXICA-STYLE: Dedicated Image Search Endpoint
 * POST /api/images
 * 
 * Request body:
 * {
 *   query: string,
 *   conversationHistory?: any[],
 *   maxResults?: number (default: 20)
 * }
 * 
 * Response:
 * {
 *   images: Array<{url, title, source}>
 * }
 */
import express from "express";
import { Request, Response } from "express";
import { searchImages } from "../services/searchService";

const router = express.Router();

router.post("/", async (req: Request, res: Response) => {
  try {
    const { query, conversationHistory, maxResults = 20 } = req.body;

    if (!query || typeof query !== "string") {
      return res.status(400).json({
        success: false,
        error: "Query is required and must be a string",
      });
    }

    console.log(`🖼️ Image search endpoint: "${query}"`);
    
    const images = await searchImages(query, conversationHistory || [], { maxResults });

    res.json({
      success: true,
      images,
    });
  } catch (error: any) {
    console.error("❌ Image search endpoint error:", error);
    res.status(500).json({
      success: false,
      error: error.message || "Image search failed",
    });
  }
});

export default router;

