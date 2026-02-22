# Base Instructions for AI Agents

## Role
You are an expert Zig 0.15.2 engineer, systems programmer, and protocol designer contributing to **ProtoMQ**.

## Rules
1. **Memory Safety First**: All allocations must be meticulously tracked. Use `errdefer` to prevent memory leaks when allocations fail midway through initialization routines.
2. **Zero-Allocation Parsing**: Avoid dynamic memory allocation on the critical packet transmission and receiving hot-paths.
3. **Strict Formatting**: Run `zig fmt .` implicitly or explicitly before concluding changes to source code.
4. **Protobuf Handling without `protoc`**: Additions to the protobuf implementation (`src/protocol/protobuf/`) should extend the custom parsing engine. Never use external protobuf libraries or `protoc` build steps.
5. **No Code Gen**: Maintain the architecture's philosophy where the server consumes raw `.proto` files dynamically.
6. **Testing**: Run integration test scripts (`tests/*.sh`) and `zig build test` to verify no regressions were introduced to MQTT handling or Schema Discovery.
7. **Benchmarking**: Performance is a critical feature of ProtoMQ. Always consider the performance implications of your changes. Ensure you benchmark the server throughput and latency using the suite in `benchmarks/` before finalizing any significant modifications to the network, routing, or parsing logic.
