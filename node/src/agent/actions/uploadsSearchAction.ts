

import { randomUUID } from 'crypto';
import z from 'zod';
import { ResearchAction, Chunk, SearchActionOutput } from '../types';
import { searchUserFiles } from '../../services/fileSearchService';
import { db } from '../../services/database';

const schema = z.object({
  queries: z
    .array(z.string())
    .describe(
      'A list of queries to search in user uploaded files. Can be a maximum of 3 queries.',
    ),
});

const uploadsSearchAction: ResearchAction<typeof schema> = {
  name: 'uploads_search',
  schema: schema,
  getToolDescription: (config) =>
    `Use this tool to perform searches over the user's uploaded files. This is useful when you need to gather information from the user's documents to answer their questions. You can provide up to 3 queries at a time. You will have to use this every single time if this is present and relevant.`,
  getDescription: (config) => `
  Use this tool to perform searches over the user's uploaded files. This is useful when you need to gather information from the user's documents to answer their questions. You can provide up to 3 queries at a time. You will have to use this every single time if this is present and relevant.
  Always ensure that the queries you use are directly relevant to the user's request and pertain to the content of their uploaded files.

  For example, if the user says "Please find information about X in my uploaded documents", you can call this tool with a query related to X to retrieve the relevant information from their files.
  Never use this tool to search the web or for information that is not contained within the user's uploaded files.
  `,
  enabled: (config) => {
    return (
      (config.classification.classification.personalSearch &&
        config.fileIds.length > 0) ||
      config.fileIds.length > 0
    );
  },
  execute: async (input, additionalConfig) => {
    
    input.queries = input.queries.slice(0, 3);

   
    if (additionalConfig.abortSignal?.aborted) {
      throw new Error('Uploads search aborted');
    }

    
    let userId: string | null = null;
    
    if (additionalConfig.fileIds.length > 0) {
      try {
        const { data: fileRecord, error } = await db.userFiles()
          .select('user_id')
          .eq('id', additionalConfig.fileIds[0])
          .single();
        
        if (!error && fileRecord) {
          userId = fileRecord.user_id;
        }
      } catch (error: any) {
        console.error('❌ Error getting userId from fileIds:', error.message);
      }
    }

    
    if (!userId) {
      console.warn('⚠️ No userId found for uploads search');
      return {
        type: 'search_results',
        results: [],
      };
    }

    
    if (additionalConfig.abortSignal?.aborted) {
      throw new Error('Uploads search aborted');
    }

    
    const allResults: Chunk[] = [];
    const seenUrls = new Map<string, number>();

    await Promise.all(
      input.queries.map(async (query) => {
        
        if (additionalConfig.abortSignal?.aborted) {
          return;
        }

        try {
          
          const documents = await searchUserFiles(userId, query, 10);

          
          documents.forEach((doc) => {
            const url = doc.url || '';
            
            if (url && !seenUrls.has(url)) {
              seenUrls.set(url, allResults.length);
              allResults.push({
                content: doc.content || doc.summary || '',
                metadata: {
                  title: doc.title || '',
                  url: url,
                },
              });
            } else if (url && seenUrls.has(url)) {
              
              const existingIndex = seenUrls.get(url)!;
              const existingResult = allResults[existingIndex];
              existingResult.content += `\n\n${doc.content || doc.summary || ''}`;
            } else if (!url) {
              
              allResults.push({
                content: doc.content || doc.summary || '',
                metadata: {
                  title: doc.title || '',
                },
              });
            }
          });
        } catch (error: any) {
          console.error(`❌ Error searching files for query "${query}":`, error.message);
        }
      }),
    );

    
    if (allResults.length > 0) {
      additionalConfig.session.emitBlock({
        id: randomUUID(),
        type: 'source',
        data: allResults.map((chunk) => ({
          title: chunk.metadata.title,
          url: chunk.metadata.url,
          ...chunk.metadata,
        })),
      });
    }

    
    const output: SearchActionOutput = {
      type: 'search_results',
      results: allResults,
    };

    return output;
  },
};

export default uploadsSearchAction;

