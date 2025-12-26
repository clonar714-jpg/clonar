// ✅ PHASE 11: Streaming Batch Chunk Size Optimizer

interface StreamingMetrics {
  chunkSize: number;
  latency: number;
  throughput: number;
  timestamp: number;
}

class StreamingOptimizer {
  private metrics: StreamingMetrics[] = [];
  private currentChunkSize: number = 50; // Initial chunk size (characters)
  private readonly minChunkSize = 10;
  private readonly maxChunkSize = 200;
  private readonly targetLatency = 100; // Target latency per chunk (ms)

  /**
   * Record streaming metrics
   */
  recordMetrics(chunkSize: number, latency: number, throughput: number): void {
    this.metrics.push({
      chunkSize,
      latency,
      throughput,
      timestamp: Date.now(),
    });

    // Keep only last 100 metrics
    if (this.metrics.length > 100) {
      this.metrics.shift();
    }

    // Optimize chunk size based on recent performance
    this.optimizeChunkSize();
  }

  /**
   * Optimize chunk size based on latency
   */
  private optimizeChunkSize(): void {
    if (this.metrics.length < 5) return;

    // Get average latency for current chunk size
    const recentMetrics = this.metrics.slice(-10);
    const avgLatency = recentMetrics.reduce((sum, m) => sum + m.latency, 0) / recentMetrics.length;

    // If latency is too high, reduce chunk size
    if (avgLatency > this.targetLatency * 1.5) {
      this.currentChunkSize = Math.max(
        this.minChunkSize,
        Math.floor(this.currentChunkSize * 0.9)
      );
      console.log(`📉 Reduced chunk size to ${this.currentChunkSize} (latency: ${avgLatency.toFixed(0)}ms)`);
    }
    // If latency is low, increase chunk size for better throughput
    else if (avgLatency < this.targetLatency * 0.7) {
      this.currentChunkSize = Math.min(
        this.maxChunkSize,
        Math.floor(this.currentChunkSize * 1.1)
      );
      console.log(`📈 Increased chunk size to ${this.currentChunkSize} (latency: ${avgLatency.toFixed(0)}ms)`);
    }
  }

  /**
   * Get optimal chunk size
   */
  getOptimalChunkSize(): number {
    return this.currentChunkSize;
  }

  /**
   * Get metrics summary
   */
  getMetricsSummary(): {
    avgLatency: number;
    avgThroughput: number;
    currentChunkSize: number;
  } {
    if (this.metrics.length === 0) {
      return {
        avgLatency: 0,
        avgThroughput: 0,
        currentChunkSize: this.currentChunkSize,
      };
    }

    return {
      avgLatency: this.metrics.reduce((sum, m) => sum + m.latency, 0) / this.metrics.length,
      avgThroughput: this.metrics.reduce((sum, m) => sum + m.throughput, 0) / this.metrics.length,
      currentChunkSize: this.currentChunkSize,
    };
  }
}

// ✅ PHASE 11: Global streaming optimizer
export const streamingOptimizer = new StreamingOptimizer();

