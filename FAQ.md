# Frequently Asked Questions



## Why should I use this instead of plain MQTT with my own binary protocol?

Plain MQTT with a hand-rolled binary protocol forces every consumer to independently maintain serialisation logic, documentation, and versioning. This explodes in complexity as the number of topics and team members grows.

ProtoMQ eliminates that by making **Protobuf the contract enforced at the broker layer**:

| Concern | Plain MQTT + custom binary | ProtoMQ |
|---|---|---|
| Schema definition | Ad-hoc, lives in docs or code comments | Canonical `.proto` files, version-controlled |
| Consumer bootstrap | Pre-shared, out-of-band | Built-in Service Discovery (`$SYS/discovery/request`) |
| Type safety | Manual, silently fails on mismatch | Validated at every PUBLISH |
| CLI tooling | Write your own encoder | `protomq-cli publish --json '{"temp": 22.5}'` |
| Observability | None | Admin HTTP API: connections, throughput, active schemas |

**When it is not the right choice**: if you control all producers and consumers end-to-end and have no schema-evolution needs, plain MQTT + a single struct is simpler. ProtoMQ's value scales with the number of independently-developed clients and the pace of schema change.

---

## How do I deploy it to a remote server?

The canonical deployment target is a Linux host running systemd. The `zig build` system handles both compilation and service-file installation in one step.

**Prerequisites on the remote host**: Zig 0.15.2+, `git`.

```bash
# 1. Clone to the installation directory
sudo mkdir -p /opt/protomq && sudo chown $USER /opt/protomq
git clone https://github.com/electricalgorithm/protomq /opt/protomq

# 2. Build and install (cross-compile on the remote host itself)
#    The --prefix flag installs binaries to /opt/protomq/bin/
#    and the systemd unit to /opt/protomq/etc/systemd/system/
cd /opt/protomq
zig build -Doptimize=ReleaseSafe -Dadmin_server=true --prefix /opt/protomq

# 3. Register and start the systemd service
sudo ln -sf /opt/protomq/etc/systemd/system/protomq.service \
            /etc/systemd/system/protomq.service
sudo systemctl daemon-reload
sudo systemctl enable --now protomq

# 4. Verify
systemctl status protomq
# Expected: Active: active (running)
```

The service runs the binary at `/opt/protomq/bin/protomq-server` from the `/opt/protomq` working directory (so it resolves the `schemas/` directory correctly) and restarts automatically on failure.

**Validation** — from any machine that can reach the server:

```bash
# MQTT connectivity
./zig-out/bin/protomq-cli connect --host <remote_host>

# Admin API (runs only on loopback; tunnel or run on the host)
curl -s -H "Authorization: Bearer admin_secret" \
  http://127.0.0.1:8080/metrics
# → {"connections":0,"messages_routed":0,"schemas":1,"memory_mb":0}
```

> **Security note**: The Admin Server binds to `127.0.0.1:8080` only. Set the `ADMIN_TOKEN` environment variable in the systemd unit before exposing it via an SSH tunnel or reverse proxy.

---

## How do I add a new Protobuf schema and map it to a topic?

There are two paths depending on whether you want a rebuild or not.

### Static (requires rebuild)

1. Drop your `.proto` file into the `schemas/` directory.
2. Open `src/server/tcp.zig` and add a `mapTopicToSchema` call inside `TcpServer.init`:

```zig
// Load Schemas — already called automatically for every .proto in schemas/
try server.schema_manager.loadSchemasFromDir("schemas");

// Add your mapping:
try server.schema_manager.mapTopicToSchema("telemetry/gps", "GpsCoordinate");
```

3. Rebuild and restart:

```bash
zig build -Doptimize=ReleaseSafe --prefix /opt/protomq
sudo systemctl restart protomq
```

The schema directory is scanned on startup; **every `.proto` file found there is parsed automatically** — you only need to add the topic-to-message-type mapping line.

### Dynamic (no rebuild, requires Admin Server)

If the server was built with `-Dadmin_server=true`, you can register a schema at runtime without restarting:

```bash
curl -X POST http://127.0.0.1:8080/api/v1/schemas \
  -H "Authorization: Bearer ${ADMIN_TOKEN:-admin_secret}" \
  -H "Content-Type: application/json" \
  -d '{
    "topic": "telemetry/gps",
    "message_type": "GpsCoordinate",
    "proto_file_content": "syntax = \"proto3\";\nmessage GpsCoordinate { float lat = 1; float lon = 2; }"
  }'
# → OK
```

The schema is parsed in-process and persisted as `schemas/<MessageType>.proto` on disk. The mapping is live immediately; **no restart needed**.

---

## How do I build with the Admin Server enabled?

The Admin Server is **off by default** to keep the binary minimal for embedded targets. Enable it at compile time with a single flag:

```bash
zig build -Dadmin_server=true
```

With the flag, the server binary gains an HTTP listener on `127.0.0.1:8080`. Without the flag, the HTTP code is completely absent from the binary — zero overhead, not just disabled.

| Build | Binary size | Memory baseline | Admin API |
|---|---|---|---|
| `zig build` | smaller | ~2.6 MB | ✗ |
| `zig build -Dadmin_server=true` | slightly larger | ~4.0 MB | ✓ |

**Available endpoints** (all require `Authorization: Bearer <ADMIN_TOKEN>`):

| Method | Path | Description |
|---|---|---|
| `GET` | `/metrics` | Active connections, messages routed, loaded schemas |
| `GET` | `/api/v1/schemas` | Current topic-to-message-type mappings |
| `POST` | `/api/v1/schemas` | Register a new schema and topic mapping at runtime |

The Admin Server runs cooperatively on the same event loop as the MQTT broker, so enabling it does **not** degrade per-message MQTT performance.
