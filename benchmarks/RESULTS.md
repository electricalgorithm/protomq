# Benchmark Results

This document records the verified performance metrics of the ProtoMQ Server.

## Environment

Mac OS:
- **CPU**: Apple M2 Pro
- **OS**: macOS 26.2 Darwin Kernel 25.2.0 (Using kqueue)
- **Zig Version**: 0.15.2
- **Test Date**: 2026-01-23

Linux:
- **CPU**: ARM Cortex-A76 (Raspberry Pi 5)
- **OS**: Debian 1:6.6.62-1+rpt1 (2024-11-25) aarch64 6.6.62+rpt-rpi-2712 
- **Zig Version**: 0.15.2
- **Test Date**: 2026-01-23

## Methodology
Benchmarks were performed using the Python script provided in `benchmarks/mqtt_bench.py` within a virtual environment. The script uses raw async TCP sockets to simulate MQTT clients.

1. **Concurrency Test**: 100 clients connect simultaneously to the server. Connectivity is verified via CONNACK.
2. **Latency Test**: 100 PUBLISH messages are sent on a subscribed topic. Latency is measured from the moment of publication to the moment of receipt by the subscriber (round-trip through the server).
3. **Memory Measurement**: Server RSS (Resident Set Size) is measured using `psutil` while 100 clients are connected.

## Verified Results

### Mac OS
| Metric | Result |
|--------|--------|
| Concurrent Connections | **100** |
| p50 Latency | **0.16ms** |
| p99 Latency | **0.24ms** |
| Memory Usage (100 Clients) | **2.41 MB** |

### Linux
| Metric | Result |
|--------|--------|
| Concurrent Connections | **100** |
| p50 Latency | **0.12ms** |
| p99 Latency | **0.17ms** |
| Memory Usage (100 Clients) | **2.00 MB** |

## Reproducing the Results
1. Start the server:
   ```bash
   zig build && ./zig-out/bin/protomq-server
   ```
2. Create a virtual environment and install dependencies:
   ```bash
   python3 -m venv benchmarks/venv
   pip install -r benchmarks/requirements.txt
   ```
3. In a separate terminal, run the benchmark:
   ```bash
   source benchmarks/venv/bin/activate && python benchmarks/mqtt_bench.py
   ```
