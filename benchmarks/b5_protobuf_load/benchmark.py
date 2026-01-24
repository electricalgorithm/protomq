"""
B5: Protobuf Decoding Under Load Benchmark

Note: This is a simplified version that measures payload size and latency.
For true protocol decoding benchmarks, ProtoMQ would need to expose protobuf
decoding in MQTT payloads.

This benchmark compares raw payload sizes and processing times.
"""

import asyncio
import sys
import time
from pathlib import Path

import psutil

from protomq_benchmarks import BenchmarkRunner, SimpleMQTTClient, Timer, measure_cpu, measure_memory
from protomq_benchmarks.metrics import LatencyStats




runner = BenchmarkRunner(
    name="b5-protobuf-load",
    version="1.0.0",
    description="Protobuf payload size and processing comparison",
    timeout_seconds=300,
)

runner.register_thresholds_from_file(Path(__file__).parent / "thresholds.json")


@runner.benchmark
async def run_protobuf_load():
    """Main benchmark implementation"""

    NUM_PUBLISHERS = 100
    MESSAGES_PER_PUBLISHER = 100

    # Simulate protobuf-like compact binary payload (30 bytes)
    protobuf_payload = b"\x08\x01\x12\x04test\x1d\x00\x00\x80?\x25\x00\x00\x00@\x30\x01" * 2  # ~32 bytes
    
    # Equivalent JSON payload (50 bytes)
    json_payload = b'{"id":1,"name":"test","temp":1.0,"hum":2.0,"ts":1}'

    print("Phase 1: Connecting clients")
    
    publishers = []
    for i in range(NUM_PUBLISHERS):
        pub = SimpleMQTTClient(client_id=f"pub-{i}")
        if await pub.connect():
            publishers.append(pub)
    
    subscriber = SimpleMQTTClient(client_id="sub")
    await subscriber.connect()
    await subscriber.subscribe("sensor/+/data")
    
    # Find server process
    server_pid = None
    for proc in psutil.process_iter(["name"]):
        if proc.info["name"] == "protomq-server":
            server_pid = proc.pid
            break
    
    if not server_pid:
        raise RuntimeError("Could not find protomq-server process")
    
    print("\nPhase 2: Sending compact binary payloads")
    
    latencies = []
    start_time = time.time()
    cpu_start = measure_cpu(server_pid, interval=0.1)
    
    for i in range(MESSAGES_PER_PUBLISHER):
        for pub_id, pub in enumerate(publishers):
            with Timer() as t:
                await pub.publish(f"sensor/{pub_id}/data", protobuf_payload)
            latencies.append(t.elapsed_ms())
    
    end_time = time.time()
    cpu_end = measure_cpu(server_pid, interval=0.1)
    
    # Calculate statistics
    stats = LatencyStats.from_measurements(latencies)
    
    # Calculate metrics
    payload_size = len(protobuf_payload)
    decoding_latency_us = stats.mean * 1000  # Convert ms to us
    cpu_overhead = abs(cpu_end - cpu_start)
    bandwidth_savings = ((len(json_payload) - len(protobuf_payload)) / len(json_payload)) * 100
    
    print(f"\nPayload size: {payload_size} bytes (JSON: {len(json_payload)} bytes)")
    print(f"Bandwidth savings: {bandwidth_savings:.1f}%")
    print(f"p99 latency: {stats.p99:.3f}ms")
    print(f"Decoding latency: {decoding_latency_us:.2f}us")
    print(f"CPU overhead: {cpu_overhead:.1f}%")
    
    # Cleanup
    print("\nCleaning up...")
    for pub in publishers:
        await pub.disconnect()
    await subscriber.disconnect()
    
    return {
        "payload_size_bytes": payload_size,
        "decoding_latency_us": round(decoding_latency_us, 2),
        "p99_latency_ms": round(stats.p99, 3),
        "cpu_overhead_percent": round(cpu_overhead, 1),
        "bandwidth_savings_percent": round(bandwidth_savings, 1),
        "json_size_bytes": len(json_payload),
    }


def main():
    """Entry point for console script"""
    success = runner.run(output_dir=Path(__file__).parent.parent / "results")
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
