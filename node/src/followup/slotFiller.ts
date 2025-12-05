// src/followup/slotFiller.ts

/**
 * 🟦 C10.2 — DYNAMIC SLOT FILLING (Perplexity behavior)
 * Fills templates with real data from session memory
 */
export interface SlotValues {
  brand?: string | null;
  category?: string | null;
  price?: string | number | null;
  purpose?: string | null;
  city?: string | null;
  gender?: string | null;
}

export function fillSlots(template: string, slots: SlotValues): string {
  let filled = template;

  // Replace brand (support both {brand} and {{brand}} formats)
  if (slots.brand) {
    filled = filled.replace(/{{\s*brand\s*}}/g, slots.brand);
    filled = filled.replace(/{brand}/g, slots.brand);
  } else {
    filled = filled.replace(/{{\s*brand\s*}}/g, "");
    filled = filled.replace(/{brand}/g, "");
  }

  // Replace category
  if (slots.category) {
    filled = filled.replace(/{{\s*category\s*}}/g, slots.category);
    filled = filled.replace(/{category}/g, slots.category);
  } else {
    filled = filled.replace(/{{\s*category\s*}}/g, "");
    filled = filled.replace(/{category}/g, "");
  }

  // Replace price
  if (slots.price) {
    const priceStr = typeof slots.price === "number" 
      ? `$${slots.price}` 
      : slots.price.toString();
    filled = filled.replace(/{{\s*price\s*}}/g, priceStr);
    filled = filled.replace(/{price}/g, priceStr);
  } else {
    filled = filled.replace(/{{\s*price\s*}}/g, "");
    filled = filled.replace(/{price}/g, "");
  }

  // Replace purpose
  if (slots.purpose) {
    filled = filled.replace(/{{\s*purpose\s*}}/g, slots.purpose);
    filled = filled.replace(/{purpose}/g, slots.purpose);
  } else {
    filled = filled.replace(/{{\s*purpose\s*}}/g, "");
    filled = filled.replace(/{purpose}/g, "");
  }

  // Replace city
  if (slots.city) {
    filled = filled.replace(/{{\s*city\s*}}/g, slots.city);
    filled = filled.replace(/{city}/g, slots.city);
  } else {
    filled = filled.replace(/{{\s*city\s*}}/g, "");
    filled = filled.replace(/{city}/g, "");
  }

  // Replace gender
  if (slots.gender) {
    filled = filled.replace(/{{\s*gender\s*}}/g, slots.gender);
    filled = filled.replace(/{gender}/g, slots.gender);
  } else {
    filled = filled.replace(/{{\s*gender\s*}}/g, "");
    filled = filled.replace(/{gender}/g, "");
  }

  // Clean up any double spaces or leading/trailing spaces
  filled = filled.replace(/\s+/g, " ").trim();
  
  // Remove any remaining empty slots (both formats)
  filled = filled.replace(/{{\s*[^}]+\s*}}/g, "").trim();
  filled = filled.replace(/{\s*[^}]+\s*}/g, "").trim();
  
  // Remove question marks if template became empty
  if (filled === "?" || filled.length < 3) {
    return "";
  }

  return filled;
}

