
import express from "express";
import { Request, Response } from "express";
import { searchVideos } from "../services/searchService";

const router = express.Router();

router.post("/", async (req: Request, res: Response) => {
  try {
    const { query, conversationHistory, maxResults = 10 } = req.body;

    if (!query || typeof query !== "string") {
      return res.status(400).json({
        success: false,
        error: "Query is required and must be a string",
      });
    }

    console.log(`🎥 Video search endpoint: "${query}"`);
    
    const videos = await searchVideos(query, conversationHistory || [], { maxResults });

    res.json({
      success: true,
      videos,
    });
  } catch (error: any) {
    console.error("❌ Video search endpoint error:", error);
    res.status(500).json({
      success: false,
      error: error.message || "Video search failed",
    });
  }
});

export default router;

