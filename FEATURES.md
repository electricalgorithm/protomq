# Features

This document covers ProtoMQ's features in more depth than the README. If you're looking for deployment guides and configuration, check [FAQ.md](FAQ.md).

---

## Service Discovery

ProtoMQ includes a built-in Service Discovery mechanism. Clients can discover available topics and their associated Protobuf schemas — including the full `.proto` source code — by querying the `$SYS/discovery/request` topic.

This lets new clients bootstrap themselves in a single round-trip without any out-of-band configuration or pre-shared schema files.

**Using the CLI:**

```bash
protomq-cli discover --proto-dir schemas
```

Under the hood, the client subscribes to `$SYS/discovery/request` and receives a `ServiceDiscoveryResponse` message containing every registered topic-schema mapping. The response includes the raw `.proto` source so clients can dynamically configure their own decoding logic.

---

## Admin Server

An optional HTTP server for runtime schema management and telemetry. Disabled by default — when the build flag is off, the HTTP code is **completely stripped from the binary** (zero overhead, not just disabled).

### Enabling it

```bash
zig build -Dadmin_server=true run-server
```

### Build comparison

| Build | Memory baseline | Admin API |
|---|---|---|
| `zig build` | ~2.6 MB | ✗ |
| `zig build -Dadmin_server=true` | ~4.0 MB | ✓ |

The Admin Server runs cooperatively on the same event loop as the MQTT broker — enabling it does **not** degrade per-message MQTT performance.

### Endpoints

All endpoints require `Authorization: Bearer <ADMIN_TOKEN>` (defaults to `admin_secret`, configurable via the `ADMIN_TOKEN` environment variable).

| Method | Path | Description |
|---|---|---|
| `GET` | `/metrics` | Active connections, message throughput, loaded schemas |
| `GET` | `/api/v1/schemas` | Current topic-to-schema mappings |
| `POST` | `/api/v1/schemas` | Register a new `.proto` schema and map it to a topic at runtime |

### Dynamic schema registration

With the Admin Server enabled, you can register schemas at runtime without restarting the broker:

```bash
curl -X POST http://127.0.0.1:8080/api/v1/schemas \
  -H "Authorization: Bearer ${ADMIN_TOKEN:-admin_secret}" \
  -H "Content-Type: application/json" \
  -d '{
    "topic": "telemetry/gps",
    "message_type": "GpsCoordinate",
    "proto_file_content": "syntax = \"proto3\";\nmessage GpsCoordinate { float lat = 1; float lon = 2; }"
  }'
```

The schema is parsed in-process and persisted to disk as `schemas/<MessageType>.proto`. The mapping is live immediately — no restart needed.

> **Security note**: The Admin Server binds to `127.0.0.1:8080` only. If you need remote access, use an SSH tunnel or reverse proxy.
