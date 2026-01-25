
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
- MQTT CLI client with automatic JSON-to-Protobuf encoding
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

# Run integration tests
zig build && \
./tests/cli_test.sh && \
./tests/integration_test.sh && \
./tests/run_pubsub_test.sh
```

### Limitations

For the initial release, we support:
- QoS 0 only (at most once delivery)
- No persistent sessions
- No retained messages
- Single-node deployment

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
