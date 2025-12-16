// ✅ PHASE 10: Load Simulation Script
// Simulates high load to test stability and performance

import axios from 'axios';

const BASE_URL = process.env.TEST_URL || 'http://localhost:4000/api';

interface TestResult {
  query: string;
  responseTime: number;
  success: boolean;
  error?: string;
}

const QUERY_TYPES = [
  { type: 'shopping', queries: ['nike shoes', 'gucci bag', 'apple phone', 'rolex watch', 'laptop under 1000'] },
  { type: 'hotels', queries: ['hotels in paris', 'resorts in bali', 'cheap hotels new york', 'luxury hotels tokyo'] },
  { type: 'flights', queries: ['flights to london', 'cheap flights paris', 'flight deals'] },
  { type: 'movies', queries: ['inception movie', 'best movies 2024', 'movie showtimes'] },
  { type: 'general', queries: ['what is ai', 'how does blockchain work', 'explain quantum computing'] },
];

const FOLLOW_UPS = [
  'show me cheaper ones',
  'what about alternatives',
  'tell me more',
  'show on map',
  'compare prices',
];

/**
 * Simulate a single query
 */
async function simulateQuery(query: string, isFollowUp: boolean = false): Promise<TestResult> {
  const startTime = Date.now();
  try {
    const response = await axios.post(
      `${BASE_URL}/agent`,
      {
        query,
        conversationHistory: isFollowUp ? [{ query: 'test', summary: 'test' }] : [],
        lastFollowUp: isFollowUp ? 'test' : undefined,
      },
      { timeout: 30000 }
    );
    
    const responseTime = Date.now() - startTime;
    return {
      query,
      responseTime,
      success: response.status === 200,
    };
  } catch (error: any) {
    const responseTime = Date.now() - startTime;
    return {
      query,
      responseTime,
      success: false,
      error: error.message || 'Unknown error',
    };
  }
}

/**
 * Run load test
 */
async function runLoadTest() {
  console.log('🚀 Starting load test...');
  console.log(`📡 Target: ${BASE_URL}`);
  console.log(`⏱️  Duration: 60 seconds`);
  console.log(`🎯 Target: 2000 queries/minute (≈33 queries/second)\n`);

  const results: TestResult[] = [];
  const startTime = Date.now();
  const duration = 60000; // 60 seconds
  const targetQPS = 33; // Queries per second
  const interval = 1000 / targetQPS; // ~30ms between queries

  let queryCount = 0;
  const promises: Promise<void>[] = [];

  // Generate queries
  const allQueries: Array<{ query: string; isFollowUp: boolean }> = [];
  
  // Generate 2000 queries (mix of types and follow-ups)
  for (let i = 0; i < 2000; i++) {
    const queryType = QUERY_TYPES[Math.floor(Math.random() * QUERY_TYPES.length)];
    const queries = queryType.queries;
    const query = queries[Math.floor(Math.random() * queries.length)];
    const isFollowUp = Math.random() < 0.2; // 20% follow-ups
    
    allQueries.push({ query, isFollowUp });
  }

  // Execute queries with rate limiting
  const executeQuery = async (queryData: { query: string; isFollowUp: boolean }) => {
    const result = await simulateQuery(queryData.query, queryData.isFollowUp);
    results.push(result);
    queryCount++;
    
    if (queryCount % 100 === 0) {
      const elapsed = (Date.now() - startTime) / 1000;
      const qps = queryCount / elapsed;
      console.log(`📊 Progress: ${queryCount} queries, ${qps.toFixed(1)} QPS, ${results.filter(r => r.success).length} successful`);
    }
  };

  // Execute queries in batches
  for (const queryData of allQueries) {
    if (Date.now() - startTime > duration) break;
    
    promises.push(executeQuery(queryData));
    
    // Rate limit
    await new Promise(resolve => setTimeout(resolve, interval));
  }

  // Wait for all queries to complete
  await Promise.allSettled(promises);

  const endTime = Date.now();
  const totalTime = (endTime - startTime) / 1000;
  const totalQueries = results.length;
  const successful = results.filter(r => r.success).length;
  const failed = results.filter(r => !r.success).length;
  
  // Calculate statistics
  const responseTimes = results.map(r => r.responseTime);
  responseTimes.sort((a, b) => a - b);
  
  const avgResponseTime = responseTimes.reduce((a, b) => a + b, 0) / responseTimes.length;
  const p95Index = Math.floor(responseTimes.length * 0.95);
  const p95Latency = responseTimes[p95Index] || 0;
  const p99Index = Math.floor(responseTimes.length * 0.99);
  const p99Latency = responseTimes[p99Index] || 0;
  
  const errorRate = (failed / totalQueries) * 100;
  const qps = totalQueries / totalTime;

  // Memory usage (approximate)
  const memoryUsage = process.memoryUsage();
  const memoryMB = memoryUsage.heapUsed / 1024 / 1024;

  // Print results
  console.log('\n' + '='.repeat(60));
  console.log('📊 LOAD TEST RESULTS');
  console.log('='.repeat(60));
  console.log(`⏱️  Total Time: ${totalTime.toFixed(2)}s`);
  console.log(`📈 Total Queries: ${totalQueries}`);
  console.log(`✅ Successful: ${successful} (${((successful / totalQueries) * 100).toFixed(1)}%)`);
  console.log(`❌ Failed: ${failed} (${errorRate.toFixed(1)}%)`);
  console.log(`🚀 QPS: ${qps.toFixed(2)}`);
  console.log(`⚡ Avg Response Time: ${avgResponseTime.toFixed(0)}ms`);
  console.log(`📊 95th Percentile: ${p95Latency.toFixed(0)}ms`);
  console.log(`📊 99th Percentile: ${p99Latency.toFixed(0)}ms`);
  console.log(`💾 Memory Usage: ${memoryMB.toFixed(2)} MB`);
  console.log('='.repeat(60));

  // Error breakdown
  if (failed > 0) {
    console.log('\n❌ Error Breakdown:');
    const errorCounts: Record<string, number> = {};
    results.filter(r => !r.success).forEach(r => {
      const error = r.error || 'Unknown';
      errorCounts[error] = (errorCounts[error] || 0) + 1;
    });
    Object.entries(errorCounts).forEach(([error, count]) => {
      console.log(`  ${error}: ${count}`);
    });
  }
}

// Run if executed directly
if (require.main === module) {
  runLoadTest().catch(console.error);
}

export { runLoadTest };

