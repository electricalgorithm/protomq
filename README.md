
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

Verified metrics with 100 concurrent clients on Apple M2 (macOS):

- **Concurrency**: 100+ concurrent connections verified.
- **Latency (p99)**: < 0.3ms (Measured 0.24ms).
- **Memory Footprint**: ~2.4 MB for 100 clients.

For detailed methodology and full results, see [RESULTS.md](benchmarks/RESULTS.md).

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
