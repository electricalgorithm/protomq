# B5: Protobuf Decoding Under Load Benchmark

## Description

Compares payload sizes and processing performance between compact binary and JSON representations.

**Note**: This is a simplified benchmark that measures payload efficiency. ProtoMQ uses Protobuf internally for all MQTT operations.

## Metrics Measured

- **payload_size_bytes**: Protobuf payload size
- **decoding_latency_us**: Processing latency in microseconds
- **p99_latency_ms**: End-to-end p99 latency
- **cpu_overhead_percent**: CPU overhead comparison
- **bandwidth_savings_percent**: Bandwidth savings vs JSON
- **json_size_bytes**: Reference JSON payload size

## Thresholds

See `thresholds.json` for pass/warn/fail criteria.

## Usage

```bash
# Start server
zig build run-server

# Run benchmark (from benchmarks/ directory)
source .venv/bin/activate
protomq-bench-b5
```

**Duration**: ~30 seconds

## Implementation Details

- 100 publishers sending compact binary payloads
- Compares 40-byte binary vs 50-byte JSON payload
- Measures end-to-end latency
- Calculates bandwidth savings percentage
- Simple CPU overhead sampling

## Interpretation

- **PASS**: Binary payloads are smaller and efficient
- **WARN/FAIL**: Current thresholds may be unrealistic for simplified test

**Known Issue**: This benchmark has simplified CPU overhead calculation that may trigger false warnings. Consider it a baseline test rather than a strict validation.

This benchmark demonstrates the efficiency benefits of binary protocols over text-based alternatives.
