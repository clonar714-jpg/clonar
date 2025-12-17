// ==================================================================
// ANSWER COVERAGE DETECTION (Gap analysis for follow-ups)
// ==================================================================
/**
 * Detects what dimensions the answer already covers
 * Used to suppress redundant follow-up suggestions
 */
export function detectAnswerCoverage(answer) {
    if (!answer) {
        return {
            price: false,
            comparison: false,
            durability: false,
            useCase: false,
        };
    }
    const lower = answer.toLowerCase();
    return {
        price: /\$|price|cost|budget|cheap|affordable|expensive|pricing/i.test(lower),
        comparison: /compare|vs|versus|better than|alternative|options|versus/i.test(lower),
        durability: /durable|long-term|last|quality|sturdy|robust|reliable/i.test(lower),
        useCase: /for running|for travel|for work|use case|purpose|suitable for|ideal for/i.test(lower),
    };
}
