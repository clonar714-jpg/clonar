// ✅ PHASE 11: CPU Profiler for Agent Pipeline
// Usage: node profiling/cpuProfile.js

const inspector = require('inspector');
const fs = require('fs');
const path = require('path');

const session = new inspector.Session();
session.connect();

const profileDuration = 60000; // 60 seconds
const outputFile = path.join(__dirname, 'cpu-profile.json');

console.log(`📊 Starting CPU profiling for ${profileDuration / 1000} seconds...`);
console.log('🎯 Profiling agent.ts flow...');

session.post('Profiler.enable', () => {
  session.post('Profiler.start', () => {
    console.log('✅ Profiler started. Make requests to /api/agent...');
    
    setTimeout(() => {
      session.post('Profiler.stop', (err, { profile }) => {
        if (err) {
          console.error('❌ Error stopping profiler:', err);
          return;
        }

        fs.writeFileSync(outputFile, JSON.stringify(profile, null, 2));
        console.log(`✅ CPU profile saved to ${outputFile}`);
        
        // Analyze top functions
        analyzeProfile(profile);
        
        session.disconnect();
      });
    }, profileDuration);
  });
});

function analyzeProfile(profile) {
  const nodes = profile.nodes || [];
  const samples = profile.samples || [];
  const timeDeltas = profile.timeDeltas || [];
  
  // Calculate time spent in each function
  const functionTimes = new Map();
  
  for (let i = 0; i < samples.length; i++) {
    const nodeId = samples[i];
    const timeDelta = timeDeltas[i] || 0;
    
    const node = nodes.find(n => n.id === nodeId);
    if (node) {
      const functionName = node.callFrame?.functionName || 'unknown';
      const currentTime = functionTimes.get(functionName) || 0;
      functionTimes.set(functionName, currentTime + timeDelta);
    }
  }
  
  // Sort by time spent
  const sorted = Array.from(functionTimes.entries())
    .sort((a, b) => b[1] - a[1])
    .slice(0, 10);
  
  console.log('\n📊 Top 10 Slow Functions:');
  sorted.forEach(([name, time], index) => {
    console.log(`${index + 1}. ${name}: ${(time / 1000).toFixed(2)}ms`);
  });
}

