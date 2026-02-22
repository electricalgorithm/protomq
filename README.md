
<h1 align="center">ProtoMQ</h1>

<p align="center">
  <img src="assets/mascot.png" alt="ProtoMQ Mascot" width="300px" />
  <br />
  <b>Type-safe, bandwidth-efficient MQTT for the rest of us.</b>
  <br />
  <i>Stop sending bloated JSON over the wire.</i>
</p>

---
- MQTT v3.1.1 packet parsing (CONNECT, PUBLISH, SUBSCRIBE, etc.)
- Thread-safe Topic Broker with wildcard support (`+`, `#`)
- Custom Protobuf Engine with runtime `.proto` schema parsing
- Topic-based Protobuf schema routing
- Service Discovery & Schema Registry
- CLI with automatic JSON-to-Protobuf encoding
- Structured diagnostic output for Protobuf payloads

### Building

One have to have Zig 0.15.2 or later installed. Please download it from [here](https://ziglang.org/download/).

```bash
# Build server and client
zig build

# Build and run server
zig build run-server

# Build and run client
zig build run-client

# Run tests
zig build test

# Run all integration tests
./tests/run_all.sh
```

### Limitations

For the initial release, we support:
- QoS 0 only (at most once delivery)
- No persistent sessions
- No retained messages
- Single-node deployment

### Service Discovery

ProtoMQ includes a built-in Service Discovery mechanism. Clients can discover available topics and their associated Protobuf schemas (including the full source code) by querying the `$SYS/discovery/request` topic.

**Using the CLI for discovery:**
```bash
# Verify schemas are loaded and available
protomq-cli discover --proto-dir schemas
```
This allows clients to "bootstrap" themselves without needing pre-shared `.proto` files.

### Admin Server

ProtoMQ includes an optional HTTP Admin Server for runtime observability and dynamic schema management without polluting the core MQTT hot-paths.

- **Dynamic Schema Registration**: Register `.proto` files at runtime via `POST /api/v1/schemas`.
- **Telemetry**: Monitor active connections, message throughput, and schemas via `GET /metrics`.
- **Zero Overhead Footprint**: The Admin Server is disabled by default to preserve the absolute minimum memory footprint for embedded devices. It is strictly conditionally compiled via the `zig build -Dadmin_server=true` flag. Enabling it moderately increases the initial static memory baseline (e.g., from ~2.6 MB to ~4.0 MB) by safely running a parallel HTTP listener, but it executes cooperatively on the same event loop ensuring zero degradation to per-message MQTT performance. When the flag is deactivated, it incurs **zero overhead footprint**.

### Performance Results

ProtoMQ delivers high performance across both high-end and edge hardware:

| Scenario | Apple M2 Pro | Raspberry Pi 5 |
|----------|--------------|----------------|
| Latency (p99, 100 clients) | 0.44 ms | 0.13 ms |
| Concurrent clients | 10,000 | 10,000 |
| Sustained throughput | 9k msg/s | 9k msg/s |
| Message throughput (small) | 208k msg/s | 147k msg/s |
| Memory (100 clients) | 2.6 MB | 2.5 MB |

Handles 100,000 connection cycles with zero memory leaks and sub-millisecond latency.

For detailed methodology and full results, see [ProtoMQ Benchmarking Suite](benchmarks/README.md).

### Contributing

This is currently a learning/development project. Contributions will be welcome after the MVP is complete.

### License

The project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

### Resources

- [Zig Documentation](https://ziglang.org/documentation/master/)
- [MQTT v3.1.1 Specification](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/mqtt-v3.1.1.html)
- [Protocol Buffers](https://protobuf.dev/)

---

**Note**: This project is under active development. The API and architecture may change significantly.
