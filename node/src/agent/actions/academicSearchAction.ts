

import { randomUUID } from 'crypto';
import z from 'zod';
import { ResearchAction, Chunk, ActionOutput, SearchActionOutput } from '../types';
import { searchSearxng } from '../../services/searxngService';

const schema = z.object({
  queries: z.array(z.string()).describe('List of academic search queries'),
});

const academicSearchDescription = `
Use this tool to perform academic searches for scholarly articles, papers, and research studies relevant to the user's query. Provide a list of concise search queries that will help gather comprehensive academic information on the topic at hand.
You can provide up to 3 queries at a time. Make sure the queries are specific and relevant to the user's needs.

For example, if the user is interested in recent advancements in renewable energy, your queries could be:
1. "Recent advancements in renewable energy 2024"
2. "Cutting-edge research on solar power technologies"
3. "Innovations in wind energy systems"

If this tool is present and no other tools are more relevant, you MUST use this tool to get the needed academic information.
`;

const academicSearchAction: ResearchAction<typeof schema> = {
  name: 'academic_search',
  schema: schema,
  getDescription: (config) => academicSearchDescription,
  getToolDescription: (config) =>
    "Use this tool to perform academic searches for scholarly articles, papers, and research studies relevant to the user's query. Provide a list of concise search queries that will help gather comprehensive academic information on the topic at hand.",
  enabled: (config) => {
    return (
      config.sources.includes('academic') &&
      config.classification.classification.skipSearch === false &&
      config.classification.classification.academicSearch === true
    );
  },
  execute: async (input, additionalConfig) => {
    
    input.queries = input.queries.slice(0, 3);

    
    if (additionalConfig.abortSignal?.aborted) {
      throw new Error('Academic search aborted');
    }

    let results: Chunk[] = [];

    const search = async (q: string) => {
     
      if (additionalConfig.abortSignal?.aborted) {
        throw new Error('Academic search aborted');
      }

      const res = await searchSearxng(q, {
        engines: ['arxiv', 'google scholar', 'pubmed'],
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

   
    await Promise.all(input.queries.map(search));

    
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

   
    const output: SearchActionOutput = {
      type: 'search_results',
      results,
    };

    return output;
  },
};

export default academicSearchAction;

