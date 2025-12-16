// ✅ PHASE 11: Flamegraph Generator for Node.js Profiling
// Usage: node profiling/flamegraph.js

const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

console.log('🔥 Starting flamegraph generation...');

// Use 0x for flamegraph generation
const profiler = spawn('npx', ['0x', '--output-dir', 'profiling/flamegraphs', '--', 'node', 'dist/index.js'], {
  stdio: 'inherit',
  shell: true,
});

profiler.on('error', (err) => {
  console.error('❌ Error starting profiler:', err);
  console.log('💡 Install 0x: npm install -g 0x');
});

profiler.on('exit', (code) => {
  if (code === 0) {
    console.log('✅ Flamegraph generated in profiling/flamegraphs/');
  } else {
    console.error('❌ Profiler exited with code:', code);
  }
});

// Alternative: Use clinic.js if 0x is not available
function generateWithClinic() {
  const clinic = spawn('npx', ['clinic', 'flame', '--', 'node', 'dist/index.js'], {
    stdio: 'inherit',
    shell: true,
  });

  clinic.on('error', (err) => {
    console.error('❌ Error starting clinic:', err);
    console.log('💡 Install clinic: npm install -g clinic');
  });
}

// Check if 0x is available, fallback to clinic
setTimeout(() => {
  if (profiler.killed) {
    console.log('⚠️ 0x not available, trying clinic.js...');
    generateWithClinic();
  }
}, 2000);

