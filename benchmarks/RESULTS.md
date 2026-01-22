# Benchmark Results

This document records the verified performance metrics of the ProtoMQ Server.

## Environment
- **CPU**: Apple M2 (8 cores)
- **OS**: macOS 15.2 (Using kqueue)
- **Zig Version**: 0.15.2
- **Test Date**: 2026-01-23

## Methodology
Benchmarks were performed using the Python script provided in `benchmarks/mqtt_bench.py` within a virtual environment. The script uses raw async TCP sockets to simulate MQTT clients.

1. **Concurrency Test**: 100 clients connect simultaneously to the server. Connectivity is verified via CONNACK.
2. **Latency Test**: 100 PUBLISH messages are sent on a subscribed topic. Latency is measured from the moment of publication to the moment of receipt by the subscriber (round-trip through the server).
3. **Memory Measurement**: Server RSS (Resident Set Size) is measured using `psutil` while 100 clients are connected.

## Verified Results

| Metric | Goal | Result | Status |
|--------|------|--------|--------|
| Concurrent Connections | 100+ | **100** | Met |
| p50 Latency | < 10ms | **0.16ms** | Exceeded |
| p99 Latency | < 10ms | **0.24ms** | Exceeded |
| Memory Usage (100 Clients) | < 100 MB | **2.41 MB** | Exceeded |

## Reproducing the Results
1. Start the server:
   ```bash
   zig build && ./zig-out/bin/protomq-server
   ```
2. In a separate terminal, run the benchmark:
   ```bash
   benchmarks/venv/bin/python3 benchmarks/mqtt_bench.py
   ```
