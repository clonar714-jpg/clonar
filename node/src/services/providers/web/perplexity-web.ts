// src/services/providers/web/perplexity-web.ts
import axios from 'axios';

const PPLX_API_URL = 'https://api.perplexity.ai/chat/completions';

/** One citation from Perplexity (search_results item or derived). */
export interface PerplexityCitation {
  id: string;
  url: string;
  title?: string;
  snippet?: string;
  date?: string;
  last_updated?: string;
}

/** Result of overview call: summary + citations when API returns them. */
export interface PerplexityOverviewResult {
  summary: string;
  citations?: PerplexityCitation[];
}

/** Overview-style answer with citations when the API returns search_results/citations. */
export async function perplexityOverview(query: string): Promise<PerplexityOverviewResult> {
  try {
    const { data } = await axios.post(
      PPLX_API_URL,
      {
        model: 'sonar',
        messages: [
          {
            role: 'system',
            content:
              'You are a concise search assistant. Provide a factual, well-structured overview answer with citations inline.',
          },
          { role: 'user', content: query },
        ],
        max_tokens: 1024,
        temperature: 0,
      },
      {
        headers: {
          Authorization: `Bearer ${process.env.PERPLEXITY_API_KEY}`,
          'Content-Type': 'application/json',
        },
      },
    );
    const content: string = data.choices?.[0]?.message?.content ?? '';
    const summary = content.trim();

    // Use API search_results when present so we can show references (Perplexity flow: citation-first).
    const rawResults = data.search_results ?? [];
    const citations: PerplexityCitation[] = Array.isArray(rawResults)
      ? rawResults.map((r: any, i: number) => ({
          id: r.url ?? `pplx-${i}`,
          url: typeof r.url === 'string' ? r.url : '',
          title: typeof r.title === 'string' ? r.title : undefined,
          snippet: typeof r.snippet === 'string' ? r.snippet : undefined,
          date: typeof r.date === 'string' ? r.date : undefined,
          last_updated: typeof r.last_updated === 'string' ? r.last_updated : undefined,
        }))
      : [];

    return { summary, citations: citations.length > 0 ? citations : undefined };
  } catch (err: any) {
    const status = err.response?.status;
    const body = err.response?.data;
    console.error('Perplexity overview error:', status, body ?? err.message);
    throw err;
  }
}

export async function perplexitySearch(query: string): Promise<any> {
  const { data } = await axios.post(
    PPLX_API_URL,
    {
      model: 'sonar',
      messages: [{ role: 'user', content: query }],
      max_tokens: 1024,
    },
    {
      headers: {
        Authorization: `Bearer ${process.env.PERPLEXITY_API_KEY}`,
        'Content-Type': 'application/json',
      },
    },
  );
  return data; // you can shape this into your own snippet structure
}
