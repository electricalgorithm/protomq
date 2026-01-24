"""
B6: Connection Churn Benchmark

Tests ProtoMQ's resilience to rapid connect/disconnect cycles
(simulates mobile/edge devices).

This benchmark measures:
- Total connections handled
- Connection rate (connections/second)
- Memory leaks
- File descriptor leaks
- Error rate
"""

import asyncio
import sys
import time
from pathlib import Path

import psutil

from protomq_benchmarks import BenchmarkRunner, SimpleMQTTClient, Timer, measure_memory
from protomq_benchmarks.metrics import LatencyStats


runner = BenchmarkRunner(
    name="b6-connection-churn",
    version="1.0.0",
    description="Connection churn stability test (rapid connect/disconnect)",
    timeout_seconds=600,
)

runner.register_thresholds_from_file(Path(__file__).parent / "thresholds.json")


@runner.benchmark
async def run_connection_churn():
    """Main benchmark implementation"""

    CLIENTS_PER_SECOND = 100
    TOTAL_CYCLES = 1000
    TOTAL_CONNECTIONS = CLIENTS_PER_SECOND * TOTAL_CYCLES

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
    start_fds = len(psutil.Process(server_pid).open_files())
    
    print(f"Phase 1: Running {TOTAL_CYCLES} churn cycles ({CLIENTS_PER_SECOND} clients/cycle)")
    
    successful_connections = 0
    failed_connections = 0
    start_time = time.time()
    
    async def churn_client(client_id):
        nonlocal successful_connections, failed_connections
        
        client = SimpleMQTTClient(client_id=f"churn-{client_id}")
        
        try:
            # Connect
            if await client.connect():
                # Subscribe
                await client.subscribe("test/topic")
                # Publish
                await client.publish("test/topic", f"msg-{client_id}")
                # Disconnect
                await client.disconnect()
                successful_connections += 1
            else:
                failed_connections += 1
        except Exception:
            failed_connections += 1
    
    # Run churn cycles
    for cycle in range(TOTAL_CYCLES):
        tasks = []
        for i in range(CLIENTS_PER_SECOND):
            client_id = cycle * CLIENTS_PER_SECOND + i
            tasks.append(churn_client(client_id))
        
        await asyncio.gather(*tasks, return_exceptions=True)
        
        if (cycle + 1) % 200 == 0:
            print(f"   Completed {cycle + 1} cycles ({successful_connections} successful)...")
    
    end_time = time.time()
    duration = end_time - start_time
    
    # Measure final state
    end_memory = measure_memory(server_pid)
    end_fds = len(psutil.Process(server_pid).open_files())
    
    # Calculate metrics
    connection_rate = successful_connections / duration
    memory_leak = end_memory - start_memory
    fd_leak = end_fds - start_fds
    error_rate = (failed_connections / TOTAL_CONNECTIONS) * 100
    
    print(f"\nTotal connections: {successful_connections}/{TOTAL_CONNECTIONS}")
    print(f"Connection rate: {connection_rate:.1f} conn/s")
    print(f"Memory leak: {memory_leak:.2f} MB")
    print(f"FD leak: {fd_leak} descriptors")
    print(f"Error rate: {error_rate:.2f}%")
    
    return {
        "total_connections": successful_connections,
        "connection_rate_per_s": round(connection_rate, 1),
        "memory_leak_mb": round(memory_leak, 2),
        "fd_leak_count": fd_leak,
        "error_rate_percent": round(error_rate, 2),
        "failed_connections": failed_connections,
    }


def main():
    """Entry point for console script"""
    success = runner.run(output_dir=Path(__file__).parent.parent / "results")
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
