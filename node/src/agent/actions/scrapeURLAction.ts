

import { randomUUID } from 'crypto';
import z from 'zod';
import TurnDown from 'turndown';
import { ResearchAction, Chunk, SearchActionOutput } from '../types';

const schema = z.object({
  urls: z.array(z.string()).describe('A list of URLs to scrape content from.'),
});

const actionDescription = `
Use this tool to scrape and extract content from the provided URLs. This is useful when you the user has asked you to extract or summarize information from specific web pages. You can provide up to 3 URLs at a time. NEVER CALL THIS TOOL EXPLICITLY YOURSELF UNLESS INSTRUCTED TO DO SO BY THE USER.
You should only call this tool when the user has specifically requested information from certain web pages, never call this yourself to get extra information without user instruction.

For example, if the user says "Please summarize the content of https://example.com/article", you can call this tool with that URL to get the content and then provide the summary or "What does X mean according to https://example.com/page", you can call this tool with that URL to get the content and provide the explanation.
`;


const turndownService = new TurnDown();

const scrapeURLAction: ResearchAction<typeof schema> = {
  name: 'scrape_url',
  schema: schema,
  getToolDescription: (config) =>
    'Use this tool to scrape and extract content from the provided URLs. This is useful when you the user has asked you to extract or summarize information from specific web pages. You can provide up to 3 URLs at a time. NEVER CALL THIS TOOL EXPLICITLY YOURSELF UNLESS INSTRUCTED TO DO SO BY THE USER.',
  getDescription: (config) => actionDescription,
  enabled: (_) => true,
  execute: async (params, additionalConfig) => {
    
    params.urls = params.urls.slice(0, 3);

   
    if (additionalConfig.abortSignal?.aborted) {
      throw new Error('Scrape URL action aborted');
    }

    const results: Chunk[] = [];

    await Promise.all(
      params.urls.map(async (url) => {
       
        if (additionalConfig.abortSignal?.aborted) {
          results.push({
            content: `Scraping aborted for ${url}`,
            metadata: {
              url,
              title: `Aborted: ${url}`,
            },
          });
          return;
        }

        try {
          const res = await fetch(url, {
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            },
          });
          
          if (!res.ok) {
            throw new Error(`HTTP ${res.status}: ${res.statusText}`);
          }

          const text = await res.text();

          
          const titleMatch = text.match(/<title>(.*?)<\/title>/i);
          const title = titleMatch?.[1]?.trim() || `Content from ${url}`;

          
          const markdown = turndownService.turndown(text);

          results.push({
            content: markdown,
            metadata: {
              url,
              title: title,
            },
          });
        } catch (error: any) {
          console.error(`❌ Failed to scrape ${url}:`, error.message);
          results.push({
            content: `Failed to fetch content from ${url}: ${error.message}`,
            metadata: {
              url,
              title: `Error fetching ${url}`,
            },
          });
        }
      }),
    );

    
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

export default scrapeURLAction;

