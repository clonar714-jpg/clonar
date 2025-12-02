import express from "express";
import { Request, Response } from "express";
import OpenAI from "openai";
import { 
  searchMovies, 
  getMovieDetails, 
  getPopularMovies, 
  getTrendingMovies,
  getMovieCredits,
  getMovieVideos,
  getMovieImages,
  getMovieReviews,
  getPersonDetails
} from "@/services/tmdbService";

// Lazy-load OpenAI client
let clientInstance: OpenAI | null = null;

function getOpenAIClient(): OpenAI {
  if (!clientInstance) {
    const apiKey = process.env.OPENAI_API_KEY;
    if (!apiKey) {
      throw new Error("Missing OPENAI_API_KEY environment variable");
    }
    clientInstance = new OpenAI({
      apiKey: apiKey,
    });
  }
  return clientInstance;
}

const router = express.Router();

/**
 * Search for movies
 * GET /api/movies/search?q=query&page=1
 */
router.get("/search", async (req: Request, res: Response) => {
  try {
    const query = req.query.q as string;
    const page = parseInt(req.query.page as string) || 1;

    if (!query || query.trim().length === 0) {
      return res.status(400).json({ error: "Query parameter 'q' is required" });
    }

    const results = await searchMovies(query, page);
    res.json(results);
  } catch (error: any) {
    console.error("❌ Error in movie search:", error);
    res.status(500).json({ 
      error: "Failed to search movies",
      message: error.message 
    });
  }
});

/**
 * Get movie details by ID
 * GET /api/movies/:id
 */
router.get("/:id", async (req: Request, res: Response) => {
  try {
    const movieId = parseInt(req.params.id);
    
    if (isNaN(movieId)) {
      return res.status(400).json({ error: "Invalid movie ID" });
    }

    const movie = await getMovieDetails(movieId);
    
    // Check if movie is currently in theaters
    let isInTheaters = false;
    try {
      const { getNowPlayingMovies } = await import("@/services/tmdbService");
      const nowPlaying1 = await getNowPlayingMovies(1, 'US');
      const nowPlaying2 = await getNowPlayingMovies(2, 'US');
      const allNowPlaying = [
        ...(nowPlaying1.results || []),
        ...(nowPlaying2.results || []),
      ];
      const nowPlayingMovieIds = new Set(allNowPlaying.map((m: any) => m.id));
      isInTheaters = nowPlayingMovieIds.has(movieId);
    } catch (err: any) {
      // Fallback: check release date
      if (movie.release_date) {
        try {
          const release = new Date(movie.release_date);
          const now = new Date();
          const daysSinceRelease = Math.floor((now.getTime() - release.getTime()) / (1000 * 60 * 60 * 24));
          const daysUntilRelease = -daysSinceRelease;
          isInTheaters = (daysSinceRelease >= 0 && daysSinceRelease <= 120) || (daysUntilRelease > 0 && daysUntilRelease <= 30);
        } catch (e) {
          // Invalid date format
        }
      }
    }
    
    // Add isInTheaters flag to movie details
    const movieWithTheaterStatus = { ...movie, isInTheaters };
    res.json(movieWithTheaterStatus);
  } catch (error: any) {
    console.error("❌ Error fetching movie details:", error);
    res.status(500).json({ 
      error: "Failed to fetch movie details",
      message: error.message 
    });
  }
});

/**
 * Get popular movies
 * GET /api/movies/popular?page=1
 */
router.get("/popular", async (req: Request, res: Response) => {
  try {
    const page = parseInt(req.query.page as string) || 1;
    const results = await getPopularMovies(page);
    res.json(results);
  } catch (error: any) {
    console.error("❌ Error fetching popular movies:", error);
    res.status(500).json({ 
      error: "Failed to fetch popular movies",
      message: error.message 
    });
  }
});

/**
 * Get trending movies
 * GET /api/movies/trending?timeWindow=day
 */
router.get("/trending", async (req: Request, res: Response) => {
  try {
    const timeWindow = (req.query.timeWindow as 'day' | 'week') || 'day';
    const results = await getTrendingMovies(timeWindow);
    res.json(results);
  } catch (error: any) {
    console.error("❌ Error fetching trending movies:", error);
    res.status(500).json({ 
      error: "Failed to fetch trending movies",
      message: error.message 
    });
  }
});

/**
 * Get movie credits (cast and crew)
 * GET /api/movies/:id/credits
 */
router.get("/:id/credits", async (req: Request, res: Response) => {
  try {
    const movieId = parseInt(req.params.id);
    
    if (isNaN(movieId)) {
      return res.status(400).json({ error: "Invalid movie ID" });
    }

    const credits = await getMovieCredits(movieId);
    res.json(credits);
  } catch (error: any) {
    console.error("❌ Error fetching movie credits:", error);
    res.status(500).json({ 
      error: "Failed to fetch movie credits",
      message: error.message 
    });
  }
});

/**
 * Get movie videos (trailers, teasers)
 * GET /api/movies/:id/videos
 */
router.get("/:id/videos", async (req: Request, res: Response) => {
  try {
    const movieId = parseInt(req.params.id);
    
    if (isNaN(movieId)) {
      return res.status(400).json({ error: "Invalid movie ID" });
    }

    const videos = await getMovieVideos(movieId);
    res.json(videos);
  } catch (error: any) {
    console.error("❌ Error fetching movie videos:", error);
    res.status(500).json({ 
      error: "Failed to fetch movie videos",
      message: error.message 
    });
  }
});

/**
 * Get movie images (posters, backdrops)
 * GET /api/movies/:id/images
 */
router.get("/:id/images", async (req: Request, res: Response) => {
  try {
    const movieId = parseInt(req.params.id);
    
    if (isNaN(movieId)) {
      return res.status(400).json({ error: "Invalid movie ID" });
    }

    const images = await getMovieImages(movieId);
    res.json(images);
  } catch (error: any) {
    console.error("❌ Error fetching movie images:", error);
    res.status(500).json({ 
      error: "Failed to fetch movie images",
      message: error.message 
    });
  }
});

/**
 * Get movie reviews
 * GET /api/movies/:id/reviews?page=1
 */
router.get("/:id/reviews", async (req: Request, res: Response) => {
  try {
    const movieId = parseInt(req.params.id);
    const page = parseInt(req.query.page as string || "1");
    
    if (isNaN(movieId)) {
      return res.status(400).json({ error: "Invalid movie ID" });
    }

    const reviews = await getMovieReviews(movieId, page);
    res.json(reviews);
  } catch (error: any) {
    console.error("❌ Error fetching movie reviews:", error);
    res.status(500).json({ 
      error: "Failed to fetch movie reviews",
      message: error.message 
    });
  }
});

/**
 * Get movie reviews summary
 * POST /api/movies/:id/reviews/summary
 * Body: { reviews: Array<Review> }
 */
router.post("/:id/reviews/summary", async (req: Request, res: Response) => {
  try {
    const movieId = parseInt(req.params.id);
    const { reviews, movieTitle } = req.body;
    
    if (isNaN(movieId)) {
      return res.status(400).json({ error: "Invalid movie ID" });
    }

    if (!reviews || !Array.isArray(reviews) || reviews.length === 0) {
      return res.status(400).json({ error: "Reviews array is required and must not be empty" });
    }

    // Extract review content and ratings
    const reviewTexts = reviews
      .map((review: any) => {
        const content = review.content || review.text || '';
        const rating = review.author_details?.rating || review.rating;
        const author = review.author || 'Anonymous';
        return rating ? `[${rating}/10] ${author}: ${content}` : `${author}: ${content}`;
      })
      .filter((text: string) => text.length > 0)
      .slice(0, 20); // Limit to first 20 reviews to avoid token limits

    const reviewsContext = reviewTexts.join('\n\n');

    const prompt = `You are a movie review analyst. Analyze the following user reviews for ${movieTitle ? `"${movieTitle}"` : 'this movie'} and create a comprehensive summary.

Reviews:
${reviewsContext}

Create a concise summary (2-3 paragraphs) that:
1. Highlights the overall sentiment (positive, negative, mixed)
2. Mentions common themes, strengths, and weaknesses mentioned by reviewers
3. Provides a balanced perspective on what audiences are saying

Write the summary in a natural, engaging tone. Do not use bullet points or lists.`;

    const client = getOpenAIClient();
    const completion = await client.chat.completions.create({
      model: "gpt-4o-mini",
      messages: [
        {
          role: "system",
          content: "You are a professional movie review analyst. Summarize reviews concisely and accurately.",
        },
        {
          role: "user",
          content: prompt,
        },
      ],
      temperature: 0.7,
      max_tokens: 500,
    });

    const summary = completion.choices[0]?.message?.content?.trim() || "Unable to generate summary.";

    res.json({ summary });
  } catch (error: any) {
    console.error("❌ Error generating review summary:", error);
    res.status(500).json({ 
      error: "Failed to generate review summary",
      message: error.message 
    });
  }
});

/**
 * Get person details (biography, etc.)
 * GET /api/movies/person/:id
 */
router.get("/person/:id", async (req: Request, res: Response) => {
  try {
    const personId = parseInt(req.params.id);
    
    if (isNaN(personId)) {
      return res.status(400).json({ error: "Invalid person ID" });
    }

    const person = await getPersonDetails(personId);
    res.json(person);
  } catch (error: any) {
    console.error("❌ Error fetching person details:", error);
    res.status(500).json({ 
      error: "Failed to fetch person details",
      message: error.message 
    });
  }
});

export default router;

