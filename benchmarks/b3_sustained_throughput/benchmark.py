"""
B3: Sustained Throughput Benchmark

Validates ProtoMQ can maintain low latency under continuous high message
rate for extended periods (10 minutes).

This benchmark measures:
- Sustained throughput (messages/second)
- Latency degradation over time
- Memory growth over duration
- Average CPU usage
- Message loss under sustained load
"""

import asyncio
import sys
import time
from pathlib import Path

import psutil

from protomq_benchmarks import BenchmarkRunner, SimpleMQTTClient, Timer, measure_cpu, measure_memory
from protomq_benchmarks.metrics import LatencyStats


# Initialize benchmark runner
runner = BenchmarkRunner(
    name="b3-sustained-throughput",
    version="1.0.0",
    description="Sustained throughput: 10 minutes of continuous load",
    timeout_seconds=720,
)

# Load thresholds from file
runner.register_thresholds_from_file(Path(__file__).parent / "thresholds.json")


@runner.benchmark
async def run_sustained_throughput():
    """Main benchmark implementation"""

    NUM_PUBLISHERS = 1000
    NUM_SUBSCRIBERS = 1000
    MESSAGES_PER_SECOND = 10
    DURATION_SECONDS = 600  # 10 minutes
    
    print(f"Phase 1: Connecting {NUM_PUBLISHERS} publishers and {NUM_SUBSCRIBERS} subscribers")
    
    publishers = []
    subscribers = []
    
    # Connect publishers
    for i in range(NUM_PUBLISHERS):
        pub = SimpleMQTTClient(client_id=f"pub-{i}")
        if await pub.connect():
            publishers.append(pub)
        
        if (i + 1) % 200 == 0:
            print(f"   Connected {i + 1} publishers...")
    
    # Connect subscribers
    for i in range(NUM_SUBSCRIBERS):
        sub = SimpleMQTTClient(client_id=f"sub-{i}")
        if await sub.connect():
            await sub.subscribe(f"client/{i}/data")
            subscribers.append(sub)
        
        if (i + 1) % 200 == 0:
            print(f"   Connected {i + 1} subscribers...")
    
    print(f"Connected {len(publishers)} publishers, {len(subscribers)} subscribers")
    
    # Find server process
    server_pid = None
    for proc in psutil.process_iter(["name"]):
        if proc.info["name"] == "protomq-server":
            server_pid = proc.pid
            break
    
    if not server_pid:
        raise RuntimeError("Could not find protomq-server process")
    
    # Measure baseline
    start_memory = measure_memory(server_pid)
    cpu_samples = []
    latency_samples = []
    
    print(f"\nPhase 2: Running sustained load for {DURATION_SECONDS}s")
    print(f"   Target: {NUM_PUBLISHERS * MESSAGES_PER_SECOND} msg/s")
    
    start_time = time.time()
    messages_sent = 0
    messages_expected = NUM_PUBLISHERS * MESSAGES_PER_SECOND * DURATION_SECONDS
    
    # Publisher task: each publishes 10 msg/s
    async def publisher_task(pub, pub_id):
        nonlocal messages_sent
        interval = 1.0 / MESSAGES_PER_SECOND
        
        for seq in range(DURATION_SECONDS * MESSAGES_PER_SECOND):
            await pub.publish(f"client/{pub_id}/data", f"{pub_id}:{seq}")
            messages_sent += 1
            await asyncio.sleep(interval)
    
    # Monitor task: sample metrics every 10 seconds
    async def monitor_task():
        for _ in range(DURATION_SECONDS // 10):
            await asyncio.sleep(10)
            
            # Sample CPU
            cpu = measure_cpu(server_pid)
            cpu_samples.append(cpu)
            
            # Sample latency
            test_pub = publishers[0] if publishers else None
            if test_pub:
                with Timer() as t:
                    await test_pub.publish("test/latency", "ping")
                latency_samples.append(t.elapsed_ms())
            
            elapsed = time.time() - start_time
            throughput = messages_sent / elapsed if elapsed > 0 else 0
            print(f"   {int(elapsed)}s: {throughput:.0f} msg/s, CPU: {cpu:.1f}%")
    
    # Run all publishers and monitor concurrently
    tasks = [publisher_task(pub, i) for i, pub in enumerate(publishers)]
    tasks.append(monitor_task())
    
    await asyncio.gather(*tasks, return_exceptions=True)
    
    duration = time.time() - start_time
    
    # Final measurements
    end_memory = measure_memory(server_pid)
    memory_growth = end_memory - start_memory
    avg_cpu = sum(cpu_samples) / len(cpu_samples) if cpu_samples else 0
    
    # Calculate final latency
    if latency_samples:
        stats = LatencyStats.from_measurements(latency_samples)
        final_p99 = stats.p99
    else:
        final_p99 = 0
    
    # Calculate throughput
    sustained_throughput = messages_sent / duration
    message_loss_percent = ((messages_expected - messages_sent) / messages_expected * 100) if messages_expected > 0 else 0
    
    print(f"\nSustained throughput: {sustained_throughput:.0f} msg/s")
    print(f"Memory growth: {memory_growth:.2f} MB")
    print(f"Average CPU: {avg_cpu:.1f}%")
    print(f"Final p99 latency: {final_p99:.3f}ms")
    
    # Cleanup
    print("\nCleaning up...")
    for pub in publishers:
        await pub.disconnect()
    for sub in subscribers:
        await sub.disconnect()
    
    return {
        "publishers": len(publishers),
        "subscribers": len(subscribers),
        "sustained_throughput_msg_per_s": round(sustained_throughput, 0),
        "p99_latency_at_10min_ms": round(final_p99, 3),
        "memory_growth_mb": round(memory_growth, 2),
        "avg_cpu_percent": round(avg_cpu, 1),
        "message_loss_percent": round(message_loss_percent, 3),
        "total_messages_sent": messages_sent,
        "duration_s": round(duration, 1),
    }


def main():
    """Entry point for console script"""
    success = runner.run(output_dir=Path(__file__).parent.parent / "results")
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
