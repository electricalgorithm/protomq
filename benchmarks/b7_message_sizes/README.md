# B7: Message Size Variations Benchmark

## Description

Validates performance across message sizes from tiny (10 bytes - IoT sensors) to large (64KB - images, logs).

Tests ProtoMQ's ability to handle diverse payload sizes efficiently.

## Metrics Measured

Per message size (10B, 100B, 1KB, 10KB, 64KB):
- **p99_latency_XXX_ms**: p99 latency for each size
- **throughput_XXX_msg_per_s**: Throughput (messages/second)
- **memory_XXX_mb**: Memory usage during test

## Thresholds

See `thresholds.json` for pass/warn/fail criteria.

## Usage

```bash
# Start server
zig build run-server

# Run benchmark (from benchmarks/ directory)
source .venv/bin/activate
protomq-bench-b7
```

**Duration**: ~2 minutes

## Implementation Details

- 100 publishers per size test
- 100 messages per size from each publisher (10,000 total per size)
- Tests 5 payload sizes:
  - **10 bytes**: IoT sensor data
  - **100 bytes**: Small telemetry
  - **1 KB**: JSON documents
  - **10 KB**: Detailed logs
  - **64 KB**: Max MQTT payload, images/files
- Measures latency and throughput for each size
- Monitors memory usage

## Interpretation

- **PASS**: Consistent performance across all sizes
- **Expected**: Throughput decreases with larger messages
- **Expected**: Latency increases slightly with larger messages

**Known Issue**: Some socket exceptions may occur with 64KB messages due to client buffering limitations. This is a client implementation detail, not a server issue.

This benchmark validates ProtoMQ's versatility in handling diverse payload requirements.
