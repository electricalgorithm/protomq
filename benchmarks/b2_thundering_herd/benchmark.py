"""
B2: Thundering Herd Benchmark

Stress-tests message fan-out with 10,000 concurrent clients publishing
to a single topic simultaneously.

This benchmark measures:
- High concurrency connection handling (10k clients)
- Message fan-out performance under burst load
- Peak memory and CPU usage
- Message loss and connection stability
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
    name="b2-thundering-herd",
    version="1.0.0",
    description="Thundering herd: 10k concurrent clients burst publish",
    timeout_seconds=600,
)

# Load thresholds from file
runner.register_thresholds_from_file(Path(__file__).parent / "thresholds.json")


@runner.benchmark
async def run_thundering_herd():
    """Main benchmark implementation"""

    TARGET_CLIENTS = 10000
    BATCH_SIZE = 100  # Connect clients in batches to avoid overwhelming the system

    print(f"Phase 1: Connecting {TARGET_CLIENTS} clients")
    clients = []
    failed_connections = 0

    with Timer() as connection_timer:
        # Connect clients in batches
        for batch_start in range(0, TARGET_CLIENTS, BATCH_SIZE):
            batch_end = min(batch_start + BATCH_SIZE, TARGET_CLIENTS)
            batch_tasks = []

            for i in range(batch_start, batch_end):
                client = SimpleMQTTClient(client_id=f"herd-{i}")
                clients.append(client)
                batch_tasks.append(client.connect())

            # Connect batch concurrently
            results = await asyncio.gather(*batch_tasks, return_exceptions=True)

            # Count failures
            for result in results:
                if not result or isinstance(result, Exception):
                    failed_connections += 1

            if (batch_end) % 1000 == 0:
                successful = batch_end - failed_connections
                print(f"   Connected {successful}/{batch_end} clients...")

    successful_connections = len(clients) - failed_connections
    print(
        f"Connected {successful_connections}/{TARGET_CLIENTS} clients "
        f"in {connection_timer.elapsed_s():.2f}s"
    )
    print(f"Failed connections: {failed_connections}")

    # Find server process for monitoring
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
    await asyncio.sleep(2)

    print("\nPhase 2: Setting up barrier synchronization")

    # Subscribe all clients to trigger topic
    trigger_topic = "trigger/start"
    herd_topic = "test/herd"

    subscribe_tasks = []
    for client in clients:
        if client.connected:
            subscribe_tasks.append(client.subscribe(trigger_topic))

    await asyncio.gather(*subscribe_tasks, return_exceptions=True)
    print(f"   Subscribed {len(subscribe_tasks)} clients to trigger")

    # Set up dedicated subscriber to count messages
    counter = SimpleMQTTClient(client_id="herd-counter")
    await counter.connect()
    await counter.subscribe(herd_topic)

    # Create receiver task
    received_messages = []

    async def count_messages():
        start_time = None
        while True:
            msg = await counter.wait_for_message(timeout=10.0)
            if msg is None:
                break
            if start_time is None:
                start_time = time.perf_counter()
            received_messages.append(time.perf_counter())

    counter_task = asyncio.create_task(count_messages())

    print("\nPhase 3: Thundering herd (barrier-synchronized burst)")

    # Coordinator client publishes trigger
    coordinator = SimpleMQTTClient(client_id="coordinator")
    await coordinator.connect()

    # Wait for clients to be ready to receive trigger
    await asyncio.sleep(1)

    # Measure baseline memory before burst
    baseline_memory_mb = measure_memory(server_pid)
    
    # Start CPU measurement (initial call to reset counter)
    process = psutil.Process(server_pid)
    process.cpu_percent()

    # Publish trigger - this causes all clients to see "GO"
    trigger_time = time.perf_counter()
    await coordinator.publish(trigger_topic, "GO")

    # Small delay for trigger to propagate
    await asyncio.sleep(0.5)

    # All clients publish simultaneously
    print("   Initiating burst publish...")

    publish_start = time.perf_counter()
    publish_tasks = []
    for i, client in enumerate(clients):
        if client.connected:
            publish_tasks.append(client.publish(herd_topic, f"msg-{i}"))

    await asyncio.gather(*publish_tasks, return_exceptions=True)
    publish_end = time.perf_counter()

    print(f"   All clients published in {publish_end - publish_start:.2f}s")

    # Wait for messages to be received
    print("   Waiting for message fan-out...")
    await asyncio.sleep(5)  # Allow time for all messages to be delivered
    
    # Measure CPU now (during/after the load)
    peak_cpu_percent = process.cpu_percent()  # Get CPU usage over the burst period

    # Stop counting
    await counter.disconnect()
    try:
        await asyncio.wait_for(counter_task, timeout=1.0)
    except asyncio.TimeoutError:
        counter_task.cancel()

    # Calculate fan-out time
    if received_messages:
        fan_out_start = received_messages[0]
        fan_out_end = received_messages[-1]
        fan_out_time_s = fan_out_end - fan_out_start
    else:
        fan_out_time_s = 0.0

    messages_received = len(received_messages)
    message_loss = successful_connections - messages_received

    print(
        f"   Received {messages_received}/{successful_connections} messages "
        f"in {fan_out_time_s:.2f}s"
    )
    print(f"   Message loss: {message_loss}")

    # Measure peak memory
    peak_memory_mb = measure_memory(server_pid)

    print(f"\nPeak Memory: {peak_memory_mb:.2f} MB (baseline: {baseline_memory_mb:.2f} MB)")
    print(f"Peak CPU: {peak_cpu_percent:.1f}%")

    # Cleanup
    print("\nCleaning up...")
    disconnect_tasks = []
    for client in clients:
        if client.connected:
            disconnect_tasks.append(client.disconnect())

    await asyncio.gather(*disconnect_tasks, return_exceptions=True)
    await coordinator.disconnect()

    # Return metrics
    return {
        "concurrent_connections": successful_connections,
        "connection_time_s": round(connection_timer.elapsed_s(), 2),
        "fan_out_time_s": round(fan_out_time_s, 2),
        "peak_memory_mb": round(peak_memory_mb, 2),
        "peak_cpu_percent": round(peak_cpu_percent, 1),
        "message_loss_count": message_loss,
        "connection_failures": failed_connections,
        "messages_received": messages_received,
    }


def main():
    """Entry point for console script"""
    # Run the benchmark
    success = runner.run(output_dir=Path(__file__).parent.parent / "results")
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
