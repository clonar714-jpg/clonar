// src/embeddings/embeddingClient.ts
import OpenAI from "openai";
import { LRUCache } from "lru-cache";
// Lazy-load OpenAI client to ensure environment variables are loaded
let client = null;
function getClient() {
    if (!client) {
        const apiKey = process.env.OPENAI_API_KEY;
        if (!apiKey) {
            throw new Error("❌ Missing OPENAI_API_KEY in .env");
        }
        client = new OpenAI({ apiKey });
    }
    return client;
}
// LRU cache to avoid recomputing embeddings
const cache = new LRUCache({
    max: 5000,
    ttl: 1000 * 60 * 60 * 24, // 24 hours
});
// -----------------------------
// Cosine Similarity
// -----------------------------
export function cosine(a, b) {
    let dot = 0, na = 0, nb = 0;
    for (let i = 0; i < a.length; i++) {
        dot += a[i] * b[i];
        na += a[i] * a[i];
        nb += b[i] * b[i];
    }
    const denom = Math.sqrt(na) * Math.sqrt(nb);
    return denom === 0 ? 0 : dot / denom;
}
// -----------------------------
// Single text embedding
// -----------------------------
export async function getEmbedding(text) {
    if (!text || !text.trim())
        return [];
    const input = text.trim().slice(0, 8000);
    const key = `emb:${input}`;
    const cached = cache.get(key);
    if (cached)
        return cached;
    const res = await getClient().embeddings.create({
        model: "text-embedding-3-small",
        input,
    });
    const emb = res.data[0].embedding;
    cache.set(key, emb);
    return emb;
}
// -----------------------------
// Batch embedding (array of strings)
// -----------------------------
export async function getEmbeddings(texts) {
    const results = [];
    const uncached = [];
    const mapping = {};
    texts.forEach((t, i) => {
        if (!t || !t.trim()) {
            results[i] = [];
            return;
        }
        const input = t.trim().slice(0, 8000);
        const key = `emb:${input}`;
        const cached = cache.get(key);
        if (cached) {
            results[i] = cached;
        }
        else {
            mapping[input] = i;
            uncached.push(input);
        }
    });
    if (uncached.length > 0) {
        const res = await getClient().embeddings.create({
            model: "text-embedding-3-small",
            input: uncached,
        });
        res.data.forEach((d, idx) => {
            const text = uncached[idx];
            const emb = d.embedding;
            cache.set(`emb:${text}`, emb);
            results[mapping[text]] = emb;
        });
    }
    return results;
}
// -----------------------------
// Similarity search helper
// -----------------------------
export async function similaritySearch(query, items) {
    if (!items.length)
        return [];
    const [qEmb, ...itemEmbeds] = await getEmbeddings([query, ...items]);
    return items
        .map((item, i) => ({
        item,
        score: cosine(qEmb, itemEmbeds[i]),
    }))
        .sort((a, b) => b.score - a.score);
}
