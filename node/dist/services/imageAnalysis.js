// src/services/imageAnalysis.ts
import OpenAI from "openai";
import axios from "axios";
import fs from "fs";
import path from "path";
// Lazy-load OpenAI client
let clientInstance = null;
function getOpenAIClient() {
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
/**
 * 🖼️ Image Analysis Service using OpenAI Vision API
 *
 * Analyzes uploaded images to extract:
 * - Product/item description
 * - Visual features (color, style, type)
 * - Searchable keywords
 * - Context for enhancing search queries
 */
/**
 * Converts image to base64 - handles both local files and remote URLs
 */
async function downloadImageAsBase64(imageUrl) {
    try {
        // ✅ Check if this is a local upload file (from our own server)
        const uploadDir = process.env.UPLOAD_PATH || './uploads';
        const uploadsPattern = /\/uploads\/([^\/]+)$/;
        const match = imageUrl.match(uploadsPattern);
        if (match) {
            // This is a local file - read it directly from filesystem
            const filename = match[1];
            const filePath = path.join(uploadDir, filename);
            console.log(`📁 Reading local file: ${filePath}`);
            if (!fs.existsSync(filePath)) {
                throw new Error(`File not found: ${filePath}`);
            }
            // Read file and convert to base64
            const fileBuffer = fs.readFileSync(filePath);
            const base64 = fileBuffer.toString('base64');
            // Determine content type from file extension
            const ext = path.extname(filename).toLowerCase();
            const contentTypeMap = {
                '.jpg': 'image/jpeg',
                '.jpeg': 'image/jpeg',
                '.png': 'image/png',
                '.webp': 'image/webp',
                '.gif': 'image/gif',
            };
            const contentType = contentTypeMap[ext] || 'image/jpeg';
            return `data:${contentType};base64,${base64}`;
        }
        else {
            // This is a remote URL - download it
            console.log(`🌐 Downloading remote image: ${imageUrl.substring(0, 60)}...`);
            const response = await axios.get(imageUrl, {
                responseType: 'arraybuffer',
                timeout: 30000, // 30 second timeout for remote images
            });
            const base64 = Buffer.from(response.data, 'binary').toString('base64');
            // Determine image type from URL or content-type
            const contentType = response.headers['content-type'] || 'image/jpeg';
            return `data:${contentType};base64,${base64}`;
        }
    }
    catch (error) {
        console.error('❌ Error processing image:', error.message);
        throw new Error(`Failed to process image: ${error.message}`);
    }
}
/**
 * Analyzes an image using OpenAI Vision API
 * Returns a description and searchable keywords
 */
export async function analyzeImage(imageUrl) {
    try {
        console.log(`🖼️ Analyzing image: ${imageUrl.substring(0, 60)}...`);
        // Download and convert image to base64 with timeout
        const base64ImagePromise = downloadImageAsBase64(imageUrl);
        const timeoutPromise = new Promise((_, reject) => setTimeout(() => reject(new Error('Image processing timeout after 20 seconds')), 20000));
        const base64Image = await Promise.race([base64ImagePromise, timeoutPromise]);
        const client = getOpenAIClient();
        // Use GPT-4 Vision to analyze the image with timeout
        const visionPromise = client.chat.completions.create({
            model: "gpt-4o", // or "gpt-4-vision-preview" if gpt-4o is not available
            messages: [
                {
                    role: "user",
                    content: [
                        {
                            type: "text",
                            text: `Analyze this image and provide:
1. A detailed description of what you see (product, item, scene, etc.)
2. Key visual features: colors, style, type, brand (if visible), materials
3. Searchable keywords that would help find similar items
4. An enhanced search query that combines the visual description with search intent

IMPORTANT: Return ONLY valid JSON, no markdown code blocks, no explanations, just the JSON object.

Format your response as pure JSON (no markdown):
{
  "description": "detailed description",
  "keywords": ["keyword1", "keyword2", ...],
  "enhancedQuery": "search query combining visual features"
}

Be specific and detailed. If it's a product, describe it like a shopping search. If it's a place/hotel, describe it like a travel search.`,
                        },
                        {
                            type: "image_url",
                            image_url: {
                                url: base64Image,
                            },
                        },
                    ],
                },
            ],
            max_tokens: 500,
            temperature: 0.3, // Lower temperature for more consistent analysis
        });
        // Add timeout for OpenAI API call (30 seconds)
        const visionTimeoutPromise = new Promise((_, reject) => setTimeout(() => reject(new Error('OpenAI Vision API timeout after 30 seconds')), 30000));
        const response = await Promise.race([visionPromise, visionTimeoutPromise]);
        const content = response.choices[0]?.message?.content;
        if (!content) {
            throw new Error("No response from OpenAI Vision API");
        }
        // ✅ Clean content: Remove markdown code blocks if present
        let cleanedContent = content.trim();
        // Remove markdown code blocks (```json ... ```)
        if (cleanedContent.startsWith('```')) {
            // Extract content between code blocks
            const codeBlockMatch = cleanedContent.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
            if (codeBlockMatch && codeBlockMatch[1]) {
                cleanedContent = codeBlockMatch[1].trim();
            }
            else {
                // Fallback: remove first and last lines if they're code block markers
                cleanedContent = cleanedContent.replace(/^```(?:json)?\s*/m, '').replace(/\s*```$/m, '').trim();
            }
        }
        // Try to parse JSON response
        try {
            const parsed = JSON.parse(cleanedContent);
            console.log(`✅ Image analyzed: ${parsed.description?.substring(0, 60)}...`);
            return {
                description: parsed.description || "Image analyzed",
                keywords: parsed.keywords || [],
                enhancedQuery: parsed.enhancedQuery,
            };
        }
        catch (parseError) {
            // If JSON parsing fails, extract information from text
            console.warn('⚠️ Could not parse JSON response, extracting from text');
            // Try to extract JSON-like structure from text
            let description = "";
            let keywords = [];
            let enhancedQuery = undefined;
            // Extract description
            const descMatch = cleanedContent.match(/"description"\s*:\s*"([^"]+)"/i) ||
                cleanedContent.match(/description[:\s]+"([^"]+)"/i) ||
                cleanedContent.match(/description[:\s]+(.+?)(?:\n|,|})/i);
            if (descMatch) {
                description = descMatch[1].trim();
            }
            // Extract keywords array
            const keywordsMatch = cleanedContent.match(/"keywords"\s*:\s*\[(.*?)\]/is) ||
                cleanedContent.match(/keywords[:\s]+\[(.*?)\]/is);
            if (keywordsMatch) {
                keywords = keywordsMatch[1]
                    .split(',')
                    .map(k => k.trim().replace(/['"]/g, ''))
                    .filter(k => k.length > 0);
            }
            // Extract enhancedQuery
            const queryMatch = cleanedContent.match(/"enhancedQuery"\s*:\s*"([^"]+)"/i) ||
                cleanedContent.match(/enhancedQuery[:\s]+"([^"]+)"/i);
            if (queryMatch) {
                enhancedQuery = queryMatch[1].trim();
            }
            // Fallback: use first line as description if nothing extracted
            if (!description) {
                description = cleanedContent.split('\n')[0].trim() || cleanedContent.substring(0, 200).trim();
                // Remove any remaining markdown artifacts
                description = description.replace(/^```json\s*/i, '').replace(/\s*```$/i, '').trim();
            }
            // Fallback: generate enhanced query from description if not found
            if (!enhancedQuery && description) {
                // Use description but clean it first
                let cleanDescription = description
                    .replace(/^```json\s*/i, '')
                    .replace(/\s*```$/i, '')
                    .replace(/```/g, '')
                    .trim();
                enhancedQuery = cleanDescription.substring(0, 100); // Use first 100 chars as query
            }
            // ✅ Clean enhanced query before returning
            if (enhancedQuery) {
                enhancedQuery = enhancedQuery
                    .replace(/^```json\s*/i, '')
                    .replace(/\s*```$/i, '')
                    .replace(/```/g, '')
                    .trim();
            }
            console.log(`📝 Extracted from text - Description: ${description.substring(0, 60)}..., Keywords: ${keywords.length}, Query: ${enhancedQuery?.substring(0, 40)}`);
            return {
                description: description || "Image analyzed",
                keywords: keywords.length > 0 ? keywords : ["visual search"],
                enhancedQuery: enhancedQuery,
            };
        }
    }
    catch (error) {
        console.error('❌ Image analysis error:', error.message);
        console.error('❌ Error stack:', error.stack);
        // Return fallback response - don't throw, just return safe defaults
        return {
            description: "Image uploaded for visual search",
            keywords: ["visual search"],
            enhancedQuery: undefined,
        };
    }
}
/**
 * Enhances a text query with image analysis results
 */
export async function enhanceQueryWithImage(textQuery, imageUrl) {
    try {
        const analysis = await analyzeImage(imageUrl);
        // Combine text query with image analysis
        if (analysis.enhancedQuery) {
            // If user provided text, combine it with image analysis
            if (textQuery.trim().length > 0) {
                return `${textQuery} ${analysis.enhancedQuery}`;
            }
            // If no text, use enhanced query from image
            return analysis.enhancedQuery;
        }
        // Fallback: combine text with keywords
        if (textQuery.trim().length > 0) {
            const keywords = analysis.keywords.join(' ');
            return `${textQuery} ${keywords}`;
        }
        return analysis.description || "Find similar items";
    }
    catch (error) {
        console.error('❌ Error enhancing query with image:', error.message);
        // Return original query if image analysis fails
        return textQuery.trim().length > 0 ? textQuery : "Find similar items";
    }
}
