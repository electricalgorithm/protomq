# ProtoMQ Project Context

## Overview
ProtoMQ is a type-safe, bandwidth-efficient MQTT broker written in Zig. It focuses on using Protocol Buffers (Protobuf) as a first-class citizen instead of treating payloads as opaque binary or JSON.

## Core Philosophy
- **"Stop sending bloated JSON over the wire."**
- Enforce message schemas at the network layer.
- Zero-allocation parsing on the hot path where possible.
- Avoid a build step for code generation (`protoc`); parse `.proto` files dynamically at runtime to act as a Schema Registry.

## Key Features
- MQTT v3.1.1 support (QoS 0)
- Custom, runtime, Protobuf engine
- Service Discovery & Schema Registry: Clients fetch schemas and topics dynamically via `$SYS/discovery/request`
- CLI tool (`protomq-cli`) for interacting with the broker and converting JSON constraints to Protobufs.

## Tech Stack
- **Language**: Zig 0.15.2
- **Build System**: `zig build`

## Architecture Layout
- `src/main.zig`: Server entry point
- `src/server/tcp.zig`: Async TCP server & event loop handling
- `src/broker/`: Core MQTT broker logic, pub/sub, subscriptions, MQTT session handling
- `src/protocol/mqtt/`: MQTT packet parsing, decoding, and encoding
- `src/protocol/protobuf/`: Custom Protobuf engine (tokenizer, parser, decoder, encoder, AST types)
- `src/client/`: Simple MQTT client implementation used by the CLI tool
- `schemas/`: Directory for `.proto` files that the server parses on startup to register schemas
- `tests/`: End-to-end integration shell scripts

