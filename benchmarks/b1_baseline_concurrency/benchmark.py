"""
B1: Baseline Concurrency & Latency Benchmark

Validates 100+ concurrent connections with sub-millisecond latency.

This benchmark measures:
- Concurrent connection handling
- Message routing latency (p50, p99)
- Memory footprint under load
"""

import asyncio
import sys
from pathlib import Path

import psutil

from protomq_benchmarks import BenchmarkRunner, SimpleMQTTClient, Timer, measure_memory
from protomq_benchmarks.metrics import LatencyStats


# Initialize benchmark runner
runner = BenchmarkRunner(
    name="b1-baseline-concurrency",
    version="1.0.0",
    description="Baseline concurrency and latency test",
    timeout_seconds=300,
)

# Load thresholds from file
runner.register_thresholds_from_file(Path(__file__).parent / "thresholds.json")


@runner.benchmark
async def run_baseline():
    """Main benchmark implementation"""

    print("Phase 1: Concurrent Connection Test")
    clients = []

    with Timer() as connection_timer:
        for i in range(100):
            client = SimpleMQTTClient(client_id=f"bench-{i}")
            try:
                await client.connect()
                clients.append(client)
                if (i + 1) % 25 == 0:
                    print(f"   Connected {i + 1} clients...")
            except Exception as e:
                print(f"   Failed to connect client {i}: {e}")
                break

    print(f"Connected {len(clients)} clients in {connection_timer.elapsed_s():.3f}s")

    # Find server process for memory measurement
    server_pid = None
    for proc in psutil.process_iter(["name"]):
        if proc.info["name"] == "protomq-server":
            server_pid = proc.pid
            break

    if not server_pid:
        raise RuntimeError(
            "Could not find protomq-server process. Is the server running?"
        )

    # Small delay to let connections stabilize
    await asyncio.sleep(1)

    print("\nPhase 2: Latency Measurement")

    # Set up pub/sub for latency test
    subscriber = SimpleMQTTClient(client_id="bench-sub")
    publisher = SimpleMQTTClient(client_id="bench-pub")

    await subscriber.connect()
    await publisher.connect()
    await subscriber.subscribe("bench/latency")

    # Warmup
    for _ in range(5):
        await publisher.publish("bench/latency", "warmup")
        await subscriber.wait_for_message()

    # Latency trials
    latencies = []
    trials = 100

    for i in range(trials):
        msg = f"ping-{i}"
        with Timer() as lat_timer:
            await publisher.publish("bench/latency", msg)
            received = await subscriber.wait_for_message()
            if received != msg:
                print(f"   Unexpected message: {received}")

        latencies.append(lat_timer.elapsed_ms())

        if (i + 1) % 25 == 0:
            print(f"   Completed {i + 1}/{trials} trials...")

    # Calculate statistics
    stats = LatencyStats.from_measurements(latencies)
    print(
        f"Latency: p50={stats.p50:.3f}ms, p99={stats.p99:.3f}ms, avg={stats.mean:.3f}ms"
    )

    # Measure memory
    memory_mb = measure_memory(server_pid)
    print(f"\nServer Memory: {memory_mb:.2f} MB")

    # Cleanup
    print("\nCleaning up...")
    await subscriber.disconnect()
    await publisher.disconnect()

    for client in clients:
        await client.disconnect()

    # Return metrics
    return {
        "concurrent_connections": len(clients),
        "connection_time_s": round(connection_timer.elapsed_s(), 3),
        "p50_latency_ms": round(stats.p50, 3),
        "p99_latency_ms": round(stats.p99, 3),
        "memory_mb": round(memory_mb, 2),
    }


def main():
    """Entry point for console script"""
    # Run the benchmark
    success = runner.run(output_dir=Path(__file__).parent.parent / "results")
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
