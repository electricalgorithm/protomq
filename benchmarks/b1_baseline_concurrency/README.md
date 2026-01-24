# B1: Baseline Concurrency & Latency

Validates ProtoMQ's basic performance claims: 100+ concurrent connections with sub-millisecond latency.

## Metrics

- **Concurrent Connections**: Number of successfully established MQTT connections
- **Connection Time**: Time to establish all connections
- **p50 Latency**: Median round-trip message latency
- **p99 Latency**: 99th percentile latency
- **Memory**: Server RSS memory usage

## Thresholds

See `thresholds.json` for pass/warn/fail criteria.

## Running

```bash
# Start the server first
cd ../../
zig build run-server

# In another terminal, run the benchmark
cd benchmarks
uv run b1-baseline-concurrency/benchmark.py
```

## Results

Results are saved to `benchmarks/results/{commit_id}_b1-baseline-concurrency.json`
