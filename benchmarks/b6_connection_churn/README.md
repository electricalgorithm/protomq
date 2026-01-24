# B6: Connection Churn Benchmark

## Description

Tests ProtoMQ's resilience to rapid connect/disconnect cycles simulating mobile/edge devices with intermittent connectivity.

Validates resource cleanup, memory leak detection, and connection handling under churn.

## Metrics Measured

- **total_connections**: Total successful connections (of 100,000 attempted)
- **connection_rate_per_s**: Connections per second sustained
- **memory_leak_mb**: Memory growth from start to end
- **fd_leak_count**: File descriptor leak count
- **error_rate_percent**: Connection error rate percentage

## Thresholds

See `thresholds.json` for pass/warn/fail criteria.

## Usage

```bash
# Start server
zig build run-server

# Run benchmark (from benchmarks/ directory)
source .venv/bin/activate
protomq-bench-b6
```

**Duration**: ~5 minutes

## Implementation Details

- 1,000 cycles of 100 concurrent clients each
- Total: 100,000 connection attempts
- Each client: CONNECT → SUBSCRIBE → PUBLISH → DISCONNECT
- Measures memory usage before and after
- Tracks file descriptor count for leak detection
- Monitors error rate

## Interpretation

- **PASS**: High success rate (≥95%), no leaks, fast connection rate
- **WARN**: Minor memory growth or small error rate (< 1%)
- **FAIL**: Significant leaks, high error rate, or low throughput

This benchmark is critical for IoT and mobile use cases where devices frequently connect and disconnect.
