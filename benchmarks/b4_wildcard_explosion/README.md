# B4: Wildcard Subscription Explosion Benchmark

## Description

Stress-tests topic matching engine with complex, overlapping wildcard patterns.

Validates ProtoMQ's wildcard subscription performance with patterns like `sensor/+/temp`, `sensor/1/#`, and `sensor/+/+`.

## Metrics Measured

- **topic_matching_latency_us**: Average topic matching latency in microseconds
- **total_fanout_time_s**: Time for all publishes to complete with fan-out
- **peak_memory_mb**: Peak server memory for wildcard subscriptions
- **avg_cpu_percent**: Average CPU during publishing
- **correctness_percent**: Percentage of correct message deliveries

## Thresholds

See `thresholds.json` for pass/warn/fail criteria.

## Usage

```bash
# Start server
zig build run-server

# Run benchmark (from benchmarks/ directory)
source .venv/bin/activate
protomq-bench-b4
```

**Duration**: ~5 minutes

## Implementation Details

- 100 publishers on topics `sensor/{0-99}/temp`
- 1,000 wildcard subscribers:
  - 500 subscribe to `sensor/+/temp` (matches all)
  - 250 subscribe to `sensor/1/#` (matches sensor 1)
  - 250 subscribe to `sensor/+/+` (matches all 3-level topics)
- Each publisher sends 100 messages (10,000 total messages)
- Measures topic matching latency per publish
- Validates correctness of wildcard matching

## Interpretation

- **PASS**: Fast topic matching (< 100µs), correct fan-out
- **WARN**: Moderate memory or CPU usage
- **FAIL**: Slow matching, high resource usage, or incorrect deliveries

This benchmark validates the efficiency of ProtoMQ's topic routing algorithm under complex subscription patterns.
