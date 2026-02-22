---
description: How to deploy ProtoMQ to a remote server and validate it
---

# ProtoMQ Remote Deployment Guide

This workflow guides agents on how to deploy the ProtoMQ server to a remote machine, specifically configuring it to run as a systemd service, and how to validate that the deployment is working correctly, particularly for the Admin Server.

## Prerequisites
- SSH access to the remote machine (e.g., `user@localserver`).
- The `protomq` repository should already be cloned on the remote machine in the user's home directory (`~/protomq`).

## Deployment Steps

1. **Update Repository**:
   Fetch the latest changes and checkout the target branch (e.g., `feat/admin-server` or `main`), then pull.
   ```bash
   ssh user@localserver "cd protomq && git fetch --all && git checkout <branch_name> && git pull"
   ```

2. **Build the Application**:
   Build the Zig application on the remote server. Ensure you build with the `-Dadmin_server=true` flag if you need the Admin Server API enabled.
   ```bash
   ssh user@localserver "cd protomq && ./zig-aarch64-linux-0.15.2/zig build -Doptimize=ReleaseSafe -Dadmin_server=true"
   ```

3. **Configure systemd Service**:
   The `protomq.service` file is included in the root of the repository. Copy it to the systemd directory and enable it.
   ```bash
   ssh user@localserver "sudo cp /home/user/protomq/protomq.service /etc/systemd/system/protomq.service && sudo systemctl daemon-reload && sudo systemctl enable --now protomq && sudo systemctl restart protomq"
   ```

4. **Verify Service Status**:
   Ensure the service is actively running.
   ```bash
   ssh user@localserver "systemctl status protomq"
   ```
   It should say `Active: active (running)`.

## Admin Server Validation Steps

If the Admin Server is enabled, it will listen on `127.0.0.1:8080`.
By default, requests require an authorization token (default: `admin_secret` or overriden via the `ADMIN_TOKEN` environment variable).

Validate the endpoints directly on the remote machine over SSH:

1. **Test Metrics Endpoint**
   ```bash
   ssh user@localserver 'curl -s -H "Authorization: Bearer admin_secret" http://127.0.0.1:8080/metrics'
   ```
   *Expected Output*: JSON with connections, messages, schemas, etc. `{"connections":0,"messages_routed":0,"schemas":1,"memory_mb":0}`

2. **Test Schemas Endpoint**
   ```bash
   ssh user@localserver 'curl -s -H "Authorization: Bearer admin_secret" http://127.0.0.1:8080/api/v1/schemas'
   ```
   *Expected Output*: Expected topic-schema matching JSON. e.g., `{"sensor/data":"SensorData"}`

If the outputs match expectations, the server is healthy and successfully deployed.
