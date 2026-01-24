# B2: Thundering Herd

Stress-tests ProtoMQ's message fan-out with 10,000 concurrent clients publishing to a single topic simultaneously.

## Metrics

- **Concurrent Connections**: Number of successfully established connections (target: 10,000)
- **Connection Time**: Time to establish all connections
- **Fan-out Time**: Time from first publish to last message received
- **Peak Memory**: Maximum server memory during test
- **Peak CPU**: Maximum CPU usage during burst
- **Message Loss**: Number of messages not received
- **Connection Failures**: Number of failed connection attempts

## Thresholds

See `thresholds.json` for pass/warn/fail criteria.

## Running

```bash
# Start the server first (important: may need to increase ulimit)
ulimit -n 20000  # Increase file descriptor limit
cd ../../
zig build -Doptimize=ReleaseSafe
zig-out/bin/protomq-server

# In another terminal, run the benchmark
cd benchmarks
uv run b2-thundering-herd/benchmark.py
```

## Implementation Details

### Barrier Synchronization

1. All 10k clients connect and subscribe to `trigger/start`
2. Coordinator publishes `GO` to `trigger/start`
3. All clients receive trigger and publish to `test/herd`
4. Dedicated subscriber counts messages on `test/herd`

### Batched Connection

Clients connect in batches of 100 to avoid overwhelming the connection handler.

### Resource Monitoring

- Baseline memory measured before burst
- Peak memory and CPU measured during message fan-out
- Message loss calculated as (expected - received)

## Expected Results

On Apple M2 Pro with 10 cores:
- Connection time: ~5-10 seconds
- Fan-out time: ~2-5 seconds
- Peak memory: ~30-50 MB
- Peak CPU: ~60-80%
- Message loss: 0-10 messages (<0.1%)

## Notes

- Requires sufficient file descriptors: `ulimit -n 20000`
- May stress-test OS network stack (kqueue/epoll)
- Connection failures >5% indicate system limits reached
