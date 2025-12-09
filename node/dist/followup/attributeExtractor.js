// src/followup/attributeExtractor.ts
export function extractAttributes(answer) {
    if (!answer)
        return {};
    const lower = answer.toLowerCase();
    const attrs = {};
    // Purpose detection
    if (lower.includes("running") || lower.includes("distance") || lower.includes("marathon")) {
        attrs.purpose = "running";
    }
    else if (lower.includes("hiking") || lower.includes("trail") || lower.includes("outdoor")) {
        attrs.purpose = "hiking";
    }
    else if (lower.includes("walking") || lower.includes("casual")) {
        attrs.purpose = "walking";
    }
    else if (lower.includes("basketball") || lower.includes("sports")) {
        attrs.purpose = "sports";
    }
    else if (lower.includes("long distance") || lower.includes("endurance")) {
        attrs.purpose = "long-distance";
    }
    // Attribute detection
    if (lower.includes("wide") || lower.includes("wide fit") || lower.includes("wide toe box")) {
        attrs.attribute = "wide fit";
    }
    else if (lower.includes("narrow") || lower.includes("slim fit")) {
        attrs.attribute = "narrow fit";
    }
    else if (lower.includes("polarized") || lower.includes("polarization")) {
        attrs.attribute = "polarized";
    }
    else if (lower.includes("waterproof") || lower.includes("water resistant")) {
        attrs.attribute = "waterproof";
    }
    else if (lower.includes("lightweight") || lower.includes("light weight")) {
        attrs.attribute = "lightweight";
    }
    else if (lower.includes("durable") || lower.includes("durability") || lower.includes("sturdy")) {
        attrs.attribute = "durability";
    }
    else if (lower.includes("cushioning") || lower.includes("cushion")) {
        attrs.attribute = "cushioning";
    }
    else if (lower.includes("stability") || lower.includes("stable")) {
        attrs.attribute = "stability";
    }
    // Style detection
    if (lower.includes("budget") || lower.includes("affordable") || lower.includes("cheap")) {
        attrs.style = "budget";
    }
    else if (lower.includes("premium") || lower.includes("luxury") || lower.includes("high-end")) {
        attrs.style = "premium";
    }
    else if (lower.includes("value") || lower.includes("best value")) {
        attrs.style = "value";
    }
    // Target audience
    if (lower.includes("men") || lower.includes("male") || lower.includes("mens")) {
        attrs.target = "men";
    }
    else if (lower.includes("women") || lower.includes("female") || lower.includes("womens")) {
        attrs.target = "women";
    }
    else if (lower.includes("family") || lower.includes("families")) {
        attrs.target = "family";
    }
    return attrs;
}
