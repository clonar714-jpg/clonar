
import express from "express";
import { Request, Response } from "express";
import { search } from "../services/searchService";

const router = express.Router();

router.post("/", async (req: Request, res: Response) => {
  try {
    const { query, conversationHistory, needsMultipleSources, needsFreshness, maxResults } = req.body;

    if (!query || typeof query !== "string") {
      return res.status(400).json({
        success: false,
        error: "Query is required and must be a string",
      });
    }

    console.log(`🔍 Search endpoint: "${query}"`);
    
    const result = await search(query, conversationHistory || [], {
      needsMultipleSources,
      needsFreshness,
      maxResults,
      searchType: "web",
    });

  
    const sources = result.documents.map(doc => ({
      title: doc.title,
      link: doc.url,
    }));

    res.json({
      success: true,
      documents: result.documents,
      sources,
      images: result.images || [],
      videos: result.videos || [],
    });
  } catch (error: any) {
    console.error("❌ Search endpoint error:", error);
    res.status(500).json({
      success: false,
      error: error.message || "Search failed",
    });
  }
});

export default router;

