"""
B7: Message Size Variations Benchmark

Validates performance across message sizes from tiny (IoT sensors)
to large (images, logs).

This benchmark measures:
- Latency per message size
- Throughput per message size
- Memory usage scaling
"""

import asyncio
import sys
import time
from pathlib import Path

import psutil

from protomq_benchmarks import BenchmarkRunner, SimpleMQTTClient, Timer, measure_memory
from protomq_benchmarks.metrics import LatencyStats




runner = BenchmarkRunner(
    name="b7-message-sizes",
    version="1.0.0",
    description="Message size variation performance test",
    timeout_seconds=300,
)

runner.register_thresholds_from_file(Path(__file__).parent / "thresholds.json")


@runner.benchmark
async def run_message_sizes():
    """Main benchmark implementation"""

    NUM_PUBLISHERS = 100
    MESSAGES_PER_SIZE = 100
    
    # Test payload sizes: 10B, 100B, 1KB, 10KB, 64KB
    sizes = [10, 100, 1024, 10 * 1024, 64 * 1024]
    
    # Find server process
    server_pid = None
    for proc in psutil.process_iter(["name"]):
        if proc.info["name"] == "protomq-server":
            server_pid = proc.pid
            break
    
    if not server_pid:
        raise RuntimeError("Could not find protomq-server process")
    
    print("Phase 1: Connecting publishers")
    
    publishers = []
    for i in range(NUM_PUBLISHERS):
        pub = SimpleMQTTClient(client_id=f"pub-{i}")
        if await pub.connect():
            publishers.append(pub)
    
    results = {}
    
    for size in sizes:
        size_label = f"{size}B" if size < 1024 else f"{size // 1024}KB"
        print(f"\nPhase 2: Testing {size_label} messages")
        
        # Create payload
        payload = b"X" * size
        
        latencies = []
        start_time = time.time()
        
        # Publish messages
        for i in range(MESSAGES_PER_SIZE):
            for pub in publishers:
                with Timer() as t:
                    await pub.publish("test/data", payload)
                latencies.append(t.elapsed_ms())
        
        end_time = time.time()
        duration = end_time - start_time
        
        # Calculate statistics
        stats = LatencyStats.from_measurements(latencies)
        throughput = (NUM_PUBLISHERS * MESSAGES_PER_SIZE) / duration
        memory = measure_memory(server_pid)
        
        print(f"   p99 latency: {stats.p99:.3f}ms")
        print(f"   Throughput: {throughput:.0f} msg/s")
        print(f"   Memory: {memory:.2f} MB")
        
        # Store results
        results[f"p99_latency_{size_label.lower()}_ms"] = round(stats.p99, 3)
        results[f"throughput_{size_label.lower()}_msg_per_s"] = round(throughput, 0)
        results[f"memory_{size_label.lower()}_mb"] = round(memory, 2)
    
    # Cleanup
    print("\nCleaning up...")
    for pub in publishers:
        await pub.disconnect()
    
    return results


def main():
    """Entry point for console script"""
    success = runner.run(output_dir=Path(__file__).parent.parent / "results")
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
