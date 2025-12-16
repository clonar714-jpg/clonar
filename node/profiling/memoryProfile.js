// ✅ PHASE 11: Memory Profiler - Tracks Heap Growth for 10k Requests
// Usage: node profiling/memoryProfile.js

const v8 = require('v8');
const fs = require('fs');
const path = require('path');

const heapSnapshots = [];
const maxRequests = 10000;
let requestCount = 0;

console.log('💾 Starting memory profiling...');
console.log(`📊 Tracking heap growth for ${maxRequests} requests`);

// Take initial snapshot
const initialSnapshot = v8.writeHeapSnapshot(path.join(__dirname, `heap-${Date.now()}.heapsnapshot`));
console.log('✅ Initial heap snapshot:', initialSnapshot);

// Monitor heap usage
setInterval(() => {
  const heapStats = v8.getHeapStatistics();
  const heapUsedMB = (heapStats.used_heap_size / 1024 / 1024).toFixed(2);
  const heapTotalMB = (heapStats.total_heap_size / 1024 / 1024).toFixed(2);
  
  console.log(`📊 Request ${requestCount}/${maxRequests} - Heap: ${heapUsedMB}MB / ${heapTotalMB}MB`);
  
  // Take snapshot every 1000 requests
  if (requestCount > 0 && requestCount % 1000 === 0) {
    const snapshot = v8.writeHeapSnapshot(path.join(__dirname, `heap-${Date.now()}-req${requestCount}.heapsnapshot`));
    console.log(`📸 Snapshot at request ${requestCount}: ${snapshot}`);
  }
}, 5000);

// Track memory offenders
const memoryOffenders = new Map();

function trackMemoryAllocation(functionName, size) {
  const current = memoryOffenders.get(functionName) || 0;
  memoryOffenders.set(functionName, current + size);
}

// Export tracking function
module.exports = {
  trackMemoryAllocation,
  incrementRequest: () => {
    requestCount++;
    if (requestCount >= maxRequests) {
      // Final snapshot
      const finalSnapshot = v8.writeHeapSnapshot(path.join(__dirname, `heap-final-${Date.now()}.heapsnapshot`));
      console.log('✅ Final heap snapshot:', finalSnapshot);
      
      // Report top memory offenders
      const sorted = Array.from(memoryOffenders.entries())
        .sort((a, b) => b[1] - a[1])
        .slice(0, 10);
      
      console.log('\n💾 Top 10 Memory Offenders:');
      sorted.forEach(([name, size], index) => {
        const sizeMB = (size / 1024 / 1024).toFixed(2);
        console.log(`${index + 1}. ${name}: ${sizeMB}MB`);
      });
      
      process.exit(0);
    }
  },
};

