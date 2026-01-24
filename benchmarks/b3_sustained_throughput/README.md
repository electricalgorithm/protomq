# B3: Sustained Throughput Benchmark

## Description

Validates ProtoMQ can maintain low latency under continuous high message rate for extended periods (10 minutes).

Tests long-term stability, memory leaks, and performance degradation under sustained load.

## Metrics Measured

- **publishers**: Number of publisher clients connected
- **subscribers**: Number of subscriber clients connected  
- **sustained_throughput_msg_per_s**: Messages per second sustained over 10 minutes
- **p99_latency_at_10min_ms**: p99 latency at end of test (degradation check)
- **memory_growth_mb**: Memory growth from start to end
- **avg_cpu_percent**: Average CPU usage over test duration
- **message_loss_percent**: Percentage of lost messages

## Thresholds

See `thresholds.json` for pass/warn/fail criteria.

## Usage

```bash
# Start server
zig build run-server

# Run benchmark (from benchmarks/ directory)
source .venv/bin/activate
protomq-bench-b3
```

**Duration**: ~10 minutes

## Implementation Details

- 1,000 publishers, each publishing 10 messages/second
- 1,000 subscribers listening to their respective topics
- Total target: 10,000 messages/second sustained
- Monitors CPU, memory, and latency every 10 seconds
- Detects memory leaks and performance degradation
- Measures latency at regular intervals to detect degradation

## Interpretation

- **PASS**: Server maintains throughput and latency for full 10 minutes
- **WARN**: Minor memory growth or occasional latency spikes
- **FAIL**: Significant degradation, memory leaks, or message loss

This benchmark validates long-term stability crucial for production deployments.
