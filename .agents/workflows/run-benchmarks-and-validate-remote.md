---
description: Run all benchmarks on a remote device via SSH, validate against previous results, and inform user of regressions
---

# Run Benchmarks and Validate on Remote Device

This workflow guides the agent to copy the project to a remote device via SSH, start the MQTT server, execute the full benchmark suite via `uv`, copy the results back to the local repository, compare them with previous ones and defined thresholds, and generate a summarized report.

**Prerequisites:** Ensure the user provides the remote SSH connection string (e.g., `user@remote_host`) and the remote target directory.

## Step 1: Copy Project to Remote Device
Sync the current project to the remote device, excluding unnecessarily large directories.

1. Ask the user for the `<SSH_TARGET>` (e.g., `user@hostname`) and `<REMOTE_DIR>` if not already provided.
2. Use the `run_command` tool to execute:
   `rsync -avz --exclude='.git' --exclude='.zig-cache' --exclude='zig-out' --exclude='benchmarks/.venv' ./ <SSH_TARGET>:<REMOTE_DIR>`

## Step 2: Start the ProtoMQ Server on Remote
Start the MQTT server in `ReleaseSafe` optimization mode and run it in the background on the remote device.

1. Execute:
   `ssh <SSH_TARGET> "cd <REMOTE_DIR> && zig build -Doptimize=ReleaseSafe run-server > server.log 2>&1 &"`

## Step 3: Setup and Run the Benchmarks on Remote
Execute the benchmark suite sequentially on the remote device.

1. Execute:
   `ssh <SSH_TARGET> "cd <REMOTE_DIR>/benchmarks && uv sync && uv run protomq-bench-b1 && uv run protomq-bench-b2 && uv run protomq-bench-b3 && uv run protomq-bench-b4 && uv run protomq-bench-b5 && uv run protomq-bench-b6 && uv run protomq-bench-b7"`

## Step 4: Stop the Server on Remote
Ensure the server is stopped after benchmarks finish to avoid port conflicts and dangling processes.

1. Terminate the server process:
   `ssh <SSH_TARGET> 'pkill -f "zig-out/bin/server" || pkill -f "zig build.*run"'`

## Step 5: Copy Results Back to Local Repository
Retrieve the newly generated benchmark results from the remote device.

1. Execute:
   `rsync -avz <SSH_TARGET>:<REMOTE_DIR>/benchmarks/results/ ./benchmarks/results/`

## Step 6: Analyze and Compare the Results
Read the newly synchronized results and compare them against past ones.

1. Use `list_dir` on `benchmarks/results/` to locate the latest hardware directory and its `latest/` contents.
2. Read the new JSON outputs for each benchmark using `view_file`.
3. Locate older result JSON files to use as a baseline.
4. Perform an analysis of crucial metrics such as `p99 latency`, `Throughput (msg/s)`, and `Memory usage`.

## Step 7: Inform the User
Present a concise report directly to the user containing:
- Confirmation of which benchmarks completed successfully.
- The vital performance metrics extracted from the JSON results.
- A clear indication of any **regressions** or **improvements** compared to earlier runs.
