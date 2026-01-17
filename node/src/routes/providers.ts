
import express from "express";
import { Request, Response } from "express";

const router = express.Router();

router.get("/", async (req: Request, res: Response) => {
  try {
    
    const providers = [
      {
        id: "openai",
        name: "OpenAI",
        models: [
          {
            id: "gpt-4o-mini",
            name: "GPT-4o Mini",
            description: "Fast and efficient model for classification, summarization, and answer generation",
          },
          {
            id: "gpt-4o",
            name: "GPT-4o",
            description: "Advanced model for complex reasoning and high-quality answers (if available)",
          },
        ],
      },
      
    ];

    res.json({
      success: true,
      providers,
    });
  } catch (error: any) {
    console.error("❌ Providers endpoint error:", error);
    res.status(500).json({
      success: false,
      error: error.message || "Failed to fetch providers",
    });
  }
});

export default router;

