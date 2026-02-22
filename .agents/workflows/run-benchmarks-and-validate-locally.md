---
description: Run all benchmarks locally, validate against previous results, and inform user of regressions
---

# Run Benchmarks and Validate

This workflow guides the agent to start the MQTT server, execute the full benchmark suite via `uv`, collect the new results, compare them with previous ones and defined thresholds, and generate a summarized report.

## Step 1: Start the ProtoMQ Server in the Background
Start the MQTT server in `ReleaseSafe` optimization mode and run it in the background.

// turbo
1. Use the `run_command` tool from the root directory to execute:
   `zig build -Doptimize=ReleaseSafe run-server &`
2. Wait a few seconds to ensure the server is successfully running and accepting connections.

## Step 2: Setup and Run the Benchmarks
Use `uv` within the `benchmarks` directory to execute the benchmarks sequentially.

// turbo
1. Change to the `benchmarks` directory and sync dependencies:
   `cd benchmarks && uv sync`
2. Execute the benchmark suite sequentially (using `run_command`):
   - `uv run protomq-bench-b1`
   - `uv run protomq-bench-b2`
   - `uv run protomq-bench-b3`
   - `uv run protomq-bench-b4`
   - `uv run protomq-bench-b5`
   - `uv run protomq-bench-b6`
   - `uv run protomq-bench-b7`

## Step 3: Stop the Server
Ensure the server is stopped after benchmarks finish to avoid port conflicts and dangling processes.

// turbo
1. Terminate the server process:
   `pkill -f "zig-out/bin/server" || pkill -f "zig build.*run"`

## Step 4: Analyze and Compare the Results
Read the newly generated results and compare them against past ones.

1. Use `list_dir` on `benchmarks/results/` to locate the latest hardware directory and its `latest/` contents.
2. Read the new JSON outputs for each benchmark using `view_file`.
3. Locate older result JSON files to use as a baseline (or refer to established thresholds in past summaries).
4. Perform an analysis of crucial metrics such as `p99 latency`, `Throughput (msg/s)`, and `Memory usage`.

## Step 5: Inform the User
Present a concise report directly to the user containing:
- Confirmation of which benchmarks completed successfully.
- The vital performance metrics extracted from the JSON results.
- A clear indication of any **regressions** or **improvements** compared to earlier runs.
- Conclude with a recommendation if a performance regression requires troubleshooting.
