# ProtoMQ Benchmarking

The main goal of the ProtoMQ project is to provide a high-performance MQTT server implementation using Zig with type-safety. To ensure that the server meets this goal, we perform regular benchmarking to measure its performance. It's recommended to run the "protomq-bench-b1" after each commit to detect any performance regressions, and all the benchmarks before a new release.

## Regularly Testing Environments

Mac OS:
- **CPU**: Apple M2 Pro
- **OS**: macOS 26.2 Darwin Kernel 25.2.0 (Using kqueue)
- **Backend**: kqueue
- **Zig Version**: 0.15.2

Linux:
- **CPU**: ARM Cortex-A76 (Raspberry Pi 5)
- **OS**: Debian 1:6.6.62-1+rpt1 (2024-11-25) aarch64 6.6.62+rpt-rpi-2712
- **Backend**: epoll
- **Zig Version**: 0.15.2

## Results

Whenever the benchmarks are run, they are saved under the "results" directory ("protomq/benchmarks/results") within a directory specific for the hardware. Furthermore, each results is saved as a JSON file with the name of the benchmark and the commit ID of the repository. The JSON holds the results for each metric defined and environment configuration.

Please find the most recent results in the "results" directory with the name "latest" under the hardware directory.

### Overall Summary (2026-01-25)

| Test Scenario | Metric | Apple M2 Pro | Raspberry Pi 5 |
|--------------|--------|--------------|----------------|
| **100 concurrent connections** | p99 latency | 0.44 ms | 0.13 ms |
| | Memory usage | 2.6 MB | 2.5 MB |
| **10,000 concurrent clients** | Connection time | 0.96 s | 1.76 s |
| | Message fan-out | 0.12 s | 0.21 s |
| | Message loss | 0% | 0% |
| **Sustained load (10 min)** | Throughput | 8,981 msg/s | 9,012 msg/s |
| | Memory growth | 0.16 MB | 0.09 MB |
| **Wildcard subscriptions** | Topic matching | 7.2 µs | 5.2 µs |
| | 1000 subscribers | 100% correct | 100% correct |
| **Connection churn** | Total connections | 100,000 | 100,000 |
| | Connection rate | 1,496 conn/s | 1,548 conn/s |
| | Memory leak | 0 MB | 0 MB |
| **Message throughput** | 10 byte messages | 208k msg/s | 147k msg/s |
| | 64 KB messages | 39k msg/s | 27k msg/s |

**Notes:**
- All tests run on loopback interface.
- Server built with Zig 0.15.2, ReleaseSafe mode.
- Raspberry Pi 5 shows competitive performance, especially in sustained throughput and topic matching.

## Reproducing the Results
1. Start the server:
   ```bash
   zig build -Doptimize=ReleaseSafe run-server
   ```
2. Create a virtual environment and install benchmark suite:
   ```bash
   python3 -m venv benchmarks/venv
   pip install -e ./common
   pip install -e .
   ```
3. Run any benchmark:
   ```bash
   source benchmarks/venv/bin/activate
   protomq-bench-b1
   # protomq-bench-b2
   # protomq-bench-b3
   # ...
   ```
