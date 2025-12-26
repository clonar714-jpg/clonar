/**
 * ✅ PERPLEXITY-STYLE ANSWER PARSER
 *
 * Parses LLM-generated structured answers and extracts:
 * 1. Structured sections with headings
 * 2. UI element requirements (images, maps, cards)
 * 3. Metadata for response building
 */
/**
 * Parse LLM answer from Perplexica-style prompt
 *
 * Expected format (Perplexica-style):
 * [Introduction paragraph]
 *
 * Section Heading 1
 * [Content for section 1]
 *
 * Section Heading 2
 * [Content for section 2]
 *
 * ...
 *
 * FOLLOW_UP_SUGGESTIONS:
 * [
 *   "First follow-up question",
 *   "Second follow-up question",
 *   "Third follow-up question"
 * ]
 *
 * Notes:
 * - Uses plain text headings (title case, on their own line)
 * - Includes inline citations with [number] notation
 * - Introduction paragraph before first heading becomes the summary
 */
export function parseStructuredAnswer(llmResponse) {
    // Default values
    const defaultAnswer = {
        answer: llmResponse,
        summary: extractSummary(llmResponse),
        sections: [],
        followUpSuggestions: [],
    };
    try {
        // ✅ REMOVED: UI requirements extraction (LLM no longer decides media existence)
        // ✅ REMOVED: Follow-up suggestions extraction (now generated separately)
        // Answer text is now clean (no FOLLOW_UP_SUGGESTIONS in prompt)
        let answerText = llmResponse.trim();
        // ✅ PERPLEXICA-STYLE: Remove any <context> tags if LLM accidentally included them
        answerText = answerText
            .replace(/<context>[\s\S]*?<\/context>/gi, '')
            .trim();
        // Extract sections from answer text
        const sections = extractSections(answerText);
        // Extract metadata (pass sections to avoid re-parsing)
        const metadata = extractMetadata(answerText, sections);
        return {
            answer: answerText,
            summary: extractSummary(answerText),
            sections,
            followUpSuggestions: [], // ✅ Will be generated separately in perplexityAnswer.ts
            metadata,
        };
    }
    catch (error) {
        console.error("❌ Answer parsing failed:", error.message);
        return defaultAnswer;
    }
}
/**
 * Extract summary (first paragraph, no truncation for Perplexity-style answers)
 * The summary is the introduction paragraph before the first section heading
 */
function extractSummary(text) {
    // First, try to find the introduction before the first section heading
    // Look for plain text headings (title case, on their own line, followed by content)
    const lines = text.split('\n');
    let firstHeadingIndex = -1;
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        // Check if this line looks like a heading (title case, short, not ending with punctuation)
        if (line.length > 0 &&
            line.length < 80 &&
            /^[A-Z]/.test(line) &&
            !line.endsWith('.') &&
            !line.endsWith(',') &&
            (i === 0 || lines[i - 1].trim() === '' || lines[i - 1].trim().endsWith('.')) &&
            (i < lines.length - 1 && lines[i + 1].trim().length > 0)) {
            firstHeadingIndex = i;
            break;
        }
    }
    if (firstHeadingIndex > 0) {
        // Extract everything before the first heading as the introduction
        const intro = lines.slice(0, firstHeadingIndex).join('\n').trim();
        if (intro.length > 0) {
            return intro;
        }
    }
    // Fallback: first paragraph
    const paragraphs = text.split(/\n\n+/).filter(p => p.trim().length > 0);
    if (paragraphs.length > 0) {
        const firstPara = paragraphs[0].trim();
        // ✅ PERPLEXITY-STYLE: No truncation - use full first paragraph
        return firstPara;
    }
    // Final fallback: return first 500 chars if no paragraphs found
    if (text.length > 500) {
        return text.substring(0, 500).trim();
    }
    return text.trim();
}
/**
 * Extract sections from structured answer
 * Looks for plain text headings like "Luxury Hotels", "Running Shoes", etc.
 */
function extractSections(text) {
    const sections = [];
    // ✅ FIX: Pre-filter text to remove any FOLLOW_UP_SUGGESTIONS that might have slipped through
    // This is a safety net in case the main removal didn't catch it
    text = text.replace(/FOLLOW_UP_SUGGESTIONS[\s\S]*$/i, '').trim();
    const lines = text.split('\n');
    let currentSection = null;
    let currentContent = [];
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        // ✅ FIX: Skip entire line if it contains FOLLOW_UP_SUGGESTIONS
        if (line.toUpperCase().includes('FOLLOW_UP_SUGGESTIONS')) {
            // Stop processing - everything after this is follow-up suggestions
            break;
        }
        // Check if this line looks like a heading
        // Heading characteristics:
        // - Short line (less than 80 chars)
        // - Title case or all caps
        // - Not ending with punctuation (usually)
        // - Followed by content (not empty next line)
        // - Preceded by empty line or end of paragraph
        const isHeading = line.length > 0 &&
            line.length < 80 &&
            /^[A-Z]/.test(line) &&
            !line.endsWith('.') &&
            !line.endsWith(',') &&
            (i === 0 || lines[i - 1].trim() === '' || lines[i - 1].trim().endsWith('.')) &&
            (i < lines.length - 1 && lines[i + 1].trim().length > 0);
        if (isHeading) {
            // ✅ FIX: Skip "FOLLOW_UP_SUGGESTIONS:" section (it's metadata, not content)
            if (line.toUpperCase().includes('FOLLOW_UP_SUGGESTIONS')) {
                // Skip this heading and all content until next heading or end
                currentSection = null;
                currentContent = [];
                continue;
            }
            // Save previous section
            if (currentSection && currentContent.length > 0) {
                sections.push({
                    title: currentSection.title,
                    content: currentContent.join('\n').trim(),
                    type: inferSectionType(currentSection.title),
                });
            }
            // Start new section
            currentSection = { title: line, content: '' };
            currentContent = [];
        }
        else if (line.length > 0) {
            // Add to current section content
            if (currentSection) {
                currentContent.push(line);
            }
        }
    }
    // Save last section (but skip if it's FOLLOW_UP_SUGGESTIONS)
    if (currentSection && currentContent.length > 0) {
        // ✅ FIX: Skip "FOLLOW_UP_SUGGESTIONS:" section (it's metadata, not content)
        if (!currentSection.title.toUpperCase().includes('FOLLOW_UP_SUGGESTIONS')) {
            sections.push({
                title: currentSection.title,
                content: currentContent.join('\n').trim(),
                type: inferSectionType(currentSection.title),
            });
        }
    }
    // If no sections found or only 1 section, try harder to extract sections
    if (sections.length <= 1 && text.trim().length > 0) {
        // Try splitting by common section patterns
        const sectionPatterns = [
            /(?:^|\n\n)([A-Z][A-Za-z\s&]{3,50}?)\n(?!\n)/gm, // Title case headings
            /(?:^|\n\n)([A-Z][A-Za-z\s]+?):\s*\n/gm, // Headings with colon
        ];
        for (const pattern of sectionPatterns) {
            const matches = [...text.matchAll(pattern)];
            if (matches.length >= 2) {
                // Found multiple potential sections
                for (let i = 0; i < matches.length; i++) {
                    const match = matches[i];
                    const title = match[1].trim();
                    // ✅ FIX: Skip "FOLLOW_UP_SUGGESTIONS:" section (it's metadata, not content)
                    if (title.toUpperCase().includes('FOLLOW_UP_SUGGESTIONS')) {
                        continue;
                    }
                    const startPos = match.index + match[0].length;
                    const endPos = i < matches.length - 1 ? matches[i + 1].index : text.length;
                    const content = text.substring(startPos, endPos).trim();
                    if (content.length > 20) { // Only add if has substantial content
                        sections.push({
                            title: title,
                            content: content,
                            type: inferSectionType(title),
                        });
                    }
                }
                break; // Use first pattern that works
            }
        }
        // If still no sections, create one from the whole text
        if (sections.length === 0) {
            sections.push({
                title: "Overview",
                content: text.trim(),
                type: "overview",
            });
        }
    }
    return sections;
}
/**
 * Infer section type from title
 */
function inferSectionType(title) {
    const lower = title.toLowerCase();
    if (lower.includes('luxury') || lower.includes('premium') || lower.includes('high-end')) {
        return "luxury";
    }
    if (lower.includes('budget') || lower.includes('affordable') || lower.includes('cheap')) {
        return "budget";
    }
    if (lower.includes('mid') || lower.includes('moderate')) {
        return "midrange";
    }
    if (lower.includes('design') || lower.includes('build')) {
        return "design";
    }
    if (lower.includes('display') || lower.includes('screen')) {
        return "display";
    }
    if (lower.includes('performance') || lower.includes('speed')) {
        return "performance";
    }
    if (lower.includes('camera')) {
        return "camera";
    }
    if (lower.includes('battery')) {
        return "battery";
    }
    if (lower.includes('conclusion') || lower.includes('summary')) {
        return "conclusion";
    }
    return "general";
}
/**
 * Extract metadata from answer
 * @param text - Answer text
 * @param sections - Pre-parsed sections (optional, to avoid re-parsing)
 */
function extractMetadata(text, sections) {
    const categories = [];
    const mentionedItems = [];
    // Extract categories from section titles (use provided sections or parse if needed)
    const sectionTitles = sections ? sections.map(s => s.title) : extractSections(text).map(s => s.title);
    categories.push(...sectionTitles);
    // Extract mentioned items (hotel names, product names, etc.)
    // Look for capitalized phrases that might be proper nouns
    const properNounPattern = /\b([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)\b/g;
    const matches = text.match(properNounPattern);
    if (matches) {
        // Filter out common words and keep likely product/hotel names
        const commonWords = ['The', 'And', 'For', 'With', 'From', 'This', 'That', 'When', 'Where'];
        const items = matches
            .filter(m => !commonWords.includes(m) && m.length > 3)
            .slice(0, 10); // Limit to top 10
        mentionedItems.push(...items);
    }
    return {
        categories: categories.length > 0 ? categories : undefined,
        mentionedItems: mentionedItems.length > 0 ? mentionedItems : undefined,
    };
}
