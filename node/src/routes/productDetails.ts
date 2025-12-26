// src/routes/productDetails.ts
import express from "express";
import { handleDetailRequest } from "../agent/detail.handler";

const router = express.Router();

/**
 * ✅ UNIFIED: Generate details for products, hotels, places, movies
 * - "Buy this if" / "Stay here if" / "Visit this if" / "Watch this if"
 * - "What people say" (review summary)
 * - "Key features" (specs/amenities/characteristics)
 * - Additional images
 * 
 * Request body:
 * {
 *   domain: "product" | "hotel" | "place" | "movie",
 *   id: string,
 *   title: string,
 *   description?: string,
 *   price?: string,
 *   rating?: number,
 *   source?: string,
 *   link?: string,
 *   ...additionalInfo
 * }
 */
router.post("/", handleDetailRequest);

export default router;
