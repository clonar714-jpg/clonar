/**
 * ✅ PERPLEXICA-STYLE: Social Search Action
 * Performs social media searches for posts, discussions, and trends
 */

import { randomUUID } from 'crypto';
import z from 'zod';
import { ResearchAction, Chunk, SearchActionOutput } from '../types';
import { searchSearxng } from '../../services/searxngService';

const schema = z.object({
  queries: z.array(z.string()).describe('List of social search queries'),
});

const socialSearchDescription = `
Use this tool to perform social media searches for relevant posts, discussions, and trends related to the user's query. Provide a list of concise search queries that will help gather comprehensive social media information on the topic at hand.
You can provide up to 3 queries at a time. Make sure the queries are specific and relevant to the user's needs.

For example, if the user is interested in public opinion on electric vehicles, your queries could be:
1. "Electric vehicles public opinion 2024"
2. "Social media discussions on EV adoption"
3. "Trends in electric vehicle usage"

If this tool is present and no other tools are more relevant, you MUST use this tool to get the needed social media information.
`;

const socialSearchAction: ResearchAction<typeof schema> = {
  name: 'social_search',
  schema: schema,
  getDescription: (config) => socialSearchDescription,
  getToolDescription: (config) =>
    "Use this tool to perform social media searches for relevant posts, discussions, and trends related to the user's query. Provide a list of concise search queries that will help gather comprehensive social media information on the topic at hand.",
  enabled: (config) => {
    return (
      config.sources.includes('discussions') &&
      config.classification.classification.skipSearch === false &&
      config.classification.classification.discussionSearch === true
    );
  },
  execute: async (input, additionalConfig) => {
    // Limit to 3 queries
    input.queries = input.queries.slice(0, 3);

    // ✅ Check for abort signal
    if (additionalConfig.abortSignal?.aborted) {
      throw new Error('Social search aborted');
    }

    let results: Chunk[] = [];

    const search = async (q: string) => {
      // ✅ Check for abort signal before each search
      if (additionalConfig.abortSignal?.aborted) {
        throw new Error('Social search aborted');
      }

      const res = await searchSearxng(q, {
        engines: ['reddit'],
      });

      const resultChunks: Chunk[] = res.results.map((r) => ({
        content: r.content || r.title,
        metadata: {
          title: r.title,
          url: r.url,
          author: r.author,
          thumbnail: r.thumbnail || r.thumbnail_src,
        },
      }));

      results.push(...resultChunks);
    };

    // Execute all searches in parallel
    await Promise.all(input.queries.map(search));

    // ✅ Emit source block for social results (matches current codebase pattern)
    if (results.length > 0) {
      additionalConfig.session.emitBlock({
        id: randomUUID(),
        type: 'source',
        data: results.map((chunk) => ({
          title: chunk.metadata.title,
          url: chunk.metadata.url,
          ...chunk.metadata,
        })),
      });
    }

    // Return search results as ActionOutput
    const output: SearchActionOutput = {
      type: 'search_results',
      results,
    };

    return output;
  },
};

export default socialSearchAction;

