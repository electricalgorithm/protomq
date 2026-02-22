---
description: How to deploy ProtoMQ to a remote server and validate it
---

# ProtoMQ Remote Deployment Guide

This workflow guides agents on how to deploy the ProtoMQ server to a remote machine, specifically configuring it to run as a systemd service, and how to validate that the deployment is working correctly.

> [!IMPORTANT]
> Do not assume any prior knowledge of the target environment.

## Prerequisites
- Ask the user which SSH connection string to use (e.g., `<ssh_user>@<remote_host>`).

## Deployment Steps

1. **Verify Zig Dependency**:
   Search for the `zig` binary on the remote machine (e.g., `ssh <ssh_target> "which zig"` or `ssh <ssh_target> "find / -name zig 2>/dev/null | grep bin/zig"`).
   If `zig` is not found, **STOP** and tell the user to install Zig on the remote machine before proceeding.

2. **Clone Repository to `/opt/protomq`**:
   Connect via the provided SSH connection and create the `/opt/protomq` directory, ensuring appropriate permissions, then clone the repository there.
   ```bash
   ssh <ssh_target> "sudo mkdir -p /opt/protomq && sudo chown \$USER /opt/protomq && git clone https://github.com/electricalgorithm/protomq /opt/protomq || (cd /opt/protomq && git fetch --all)"
   ```

3. **Checkout and Pull**:
   Checkout the correct branch and pull the latest changes.
   ```bash
   ssh <ssh_target> "cd /opt/protomq && git checkout <branch_name> && git pull"
   ```

4. **Build the Application**:
   Build the Zig application on the remote server using the located `zig` binary. Ensure you build with the `-Dadmin_server=true` flag to enable the Admin Server API.
   ```bash
   ssh <ssh_target> "cd /opt/protomq && <path_to_zig_binary> build -Doptimize=ReleaseSafe -Dadmin_server=true"
   ```

5. **Configure systemd Service**:
   The `protomq.service` file is included in the root of the repository. Copy it to the systemd directory and enable it.
   ```bash
   ssh <ssh_target> "sudo cp /opt/protomq/protomq.service /etc/systemd/system/protomq.service && sudo systemctl daemon-reload && sudo systemctl enable --now protomq && sudo systemctl restart protomq"
   ```

6. **Verify Service Status**:
   Ensure the service is actively running.
   ```bash
   ssh <ssh_target> "systemctl status protomq"
   ```
   It should say `Active: active (running)`.

## Validation Steps

### 1. Local MQTT Client Validation
Send a ProtoMQ request from the **host machine** (the machine you are running on) to the remote machine to verify basic functionality using the `protomq-cli` tool.
First, build the project locally if necessary, then run the CLI (ensure you use the correct IP/host of the remote machine).
```bash
./zig-out/bin/protomq-cli --host <remote_host>
```
*(Provide the correct arguments for publishing/subscribing to test the connection).*

### 2. Admin Server Validation
If the Admin Server is enabled, it will listen on `127.0.0.1:8080` on the remote server. Validate the endpoints directly on the remote machine over SSH using the default authorization token (`admin_secret` or check `ADMIN_TOKEN`):

- **Metrics Endpoint**:
   ```bash
   ssh <ssh_target> 'curl -s -H "Authorization: Bearer admin_secret" http://127.0.0.1:8080/metrics'
   ```
   *Expected Output*: JSON with connections, messages, schemas, etc. `{"connections":0,"messages_routed":0,"schemas":1,"memory_mb":0}`

- **Schemas Endpoint**:
   ```bash
   ssh <ssh_target> 'curl -s -H "Authorization: Bearer admin_secret" http://127.0.0.1:8080/api/v1/schemas'
   ```
   *Expected Output*: Topic-schema mapping JSON. e.g., `{"sensor/data":"SensorData"}`

If all responses match expectations and the remote CLI connection succeeds, the server is healthy and successfully deployed.
