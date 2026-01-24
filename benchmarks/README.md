# ProtoMQ Benchmarks

This directory contains the ProtoMQ benchmark suite for measuring performance across various scenarios.

## Directory Structure

```
benchmarks/
├── common/protomq_benchmarks/   # Shared benchmark library
│   ├── environment.py           # System environment detection
│   ├── thresholds.py            # Threshold validation
│   ├── metrics.py               # Measurement utilities
│   └── runner.py                # BenchmarkRunner
├── b1-baseline-concurrency/     # B1: Baseline concurrency test
│   ├── benchmark.py
│   ├── thresholds.json
│   └── README.md
├── results/                     # All benchmark outputs (JSON)
└── benchmarks.md                # Detailed benchmark plans (B1-B7)
```

## Running Benchmarks

### Setup

**One-time setup** (from benchmarks/ directory):
```bash
cd benchmarks
uv venv                    # Create virtual environment
uv pip install -e common/  # Install protomq_benchmarks library
uv pip install -e .        # Install benchmarks package (creates console scripts)
```

This creates console scripts:
- `protomq-bench-b1` - Baseline concurrency benchmark
- `protomq-bench-b2` - Thundering herd benchmark

### Running Benchmarks

```bash
# Start server first
zig build run-server

# Run benchmarks (from benchmarks/ directory with activated venv)
cd benchmarks
source .venv/bin/activate
protomq-bench-b1
protomq-bench-b2
```

Results are saved to `benchmarks/results/{commit_id}_{benchmark_name}.json`

## Benchmark Library (`protomq_benchmarks`)

### BenchmarkRunner

Main interface for running benchmarks with automatic environment collection and threshold validation.

```python
from protomq_benchmarks import BenchmarkRunner

runner = BenchmarkRunner(
    name="b1-baseline-concurrency",
    version="1.0.0",
    timeout_seconds=300
)

runner.register_thresholds_from_file("thresholds.json")

@runner.benchmark
async def run_test():
    # Your benchmark logic
    return {"metric1": value1, "metric2": value2}

if __name__ == "__main__":
    runner.run(output_dir="../results")
```

### Environment Detection

Automatically collects:
- CPU model, architecture (normalized: aarch64 → arm64), cores, frequency
- RAM capacity
- Storage type and model (via `diskutil` on macOS, `/sys/block` on Linux)
- OS, kernel, Zig version, Python version
- Build mode (Release/Debug)
- ProtoMQ version and git commit hash
- Network backend (kqueue/epoll)

### Threshold Management

Define pass/warn/fail criteria with directional indicators:

```json
{
  "p99_latency_ms": {
    "direction": "lower",
    "max": 5.0,
    "warn": 1.0,
    "description": "p99 latency threshold"
  },
  "concurrent_connections": {
    "direction": "higher",
    "min": 100,
    "description": "Must connect at least 100 clients"
  }
}
```

- **`direction: "lower"`**: For metrics where lower is better (latency, memory)
- **`direction: "higher"`**: For metrics where higher is better (throughput, connections)

### Metrics Utilities

```python
from protomq_benchmarks import Timer, measure_memory
from protomq_benchmarks.metrics import LatencyStats

# Measure time
with Timer() as t:
    await some_operation()
print(f"Elapsed: {t.elapsed_ms()}ms")

# Measure memory
memory_mb = measure_memory(server_pid)

# Calculate latency statistics
stats = LatencyStats.from_measurements(latencies)
print(f"p99: {stats.p99:.3f}ms")
```

## Result Format

Each benchmark produces a JSON file: `{commit_id}_{benchmark_name}.json`

```json
{
  "benchmark": {
    "name": "b1-baseline-concurrency",
    "version": "1.0.0",
    "timestamp": "2026-01-24T13:45:00Z",
    "duration_s": 1.07
  },
  "environment": {
    "hardware": {...},
    "software": {...},
    "protomq": {"commit_hash": "72144c15", ...}
  },
  "metrics": {
    "concurrent_connections": 100,
    "p99_latency_ms": 0.432,
    ...
  },
  "thresholds": {
    "passed": true,
    "warnings": [],
    "failures": []
  }
}
```

## Creating New Benchmarks

1. Create directory: `benchmarks/bN-benchmark-name/`
2. Create `benchmark.py`:
   ```python
   from pathlib import Path
   from protomq_benchmarks import BenchmarkRunner
   
   runner = BenchmarkRunner(name="bN-benchmark-name", timeout_seconds=600)
   runner.register_thresholds_from_file(Path(__file__).parent / "thresholds.json")
   
   @runner.benchmark
   async def run_test():
       # Your test logic
       return {"metric": value}
   
   if __name__ == "__main__":
       runner.run(output_dir=Path(__file__).parent.parent / "results")
   ```
3. Create `thresholds.json` with metric criteria
4. Create `README.md` documenting the benchmark

## Code Quality

The benchmark suite uses `ruff` for linting and formatting (configured at project root):

```bash
# Check code
ruff check benchmarks/

# Format code
ruff format benchmarks/

# Install pre-commit hooks
pre-commit install
```

All benchmarks must be PEP-8 compliant with:
- Module-level imports only (no `sys.path` hacks)
- Type hints where applicable
- Proper error handling
- No emojis in output (professional appearance)

## Planned Benchmarks

See `benchmarks.md` for detailed plans:

- **B1**: Baseline Concurrency & Latency ✅ (implemented)
- **B2**: Thundering Herd (10k concurrent clients)
- **B3**: Sustained Throughput (10-minute stress test)
- **B4**: Wildcard Subscription Explosion
- **B5**: Protobuf Decoding Under Load
- **B6**: Connection Churn (rapid connect/disconnect)
- **B7**: Message Size Variations

## CI/CD Integration

Benchmarks can be integrated into CI/CD pipelines:

```bash
# Run benchmark and check exit code
uv run b1-baseline-concurrency/benchmark.py
if [ $? -ne 0 ]; then
    echo "Benchmark failed thresholds"
    exit 1
fi
```

Exit codes:
- `0`: All thresholds passed
- `1`: One or more thresholds failed or benchmark errored
