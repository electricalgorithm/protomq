"""
Metric collection utilities for benchmarks.
"""

import time
import psutil
import asyncio
from dataclasses import dataclass
from statistics import quantiles


class Timer:
    """Context manager for measuring elapsed time"""
    
    def __init__(self):
        self.start_time = None
        self.end_time = None
    
    def __enter__(self):
        self.start_time = time.perf_counter()
        return self
    
    def __exit__(self, *args):
        self.end_time = time.perf_counter()
    
    def elapsed_s(self) -> float:
        """Get elapsed time in seconds"""
        if self.end_time is None:
            return time.perf_counter() - self.start_time
        return self.end_time - self.start_time
    
    def elapsed_ms(self) -> float:
        """Get elapsed time in milliseconds"""
        return self.elapsed_s() * 1000


def measure_memory(pid: int | None = None) -> float:
    """
    Measure memory usage in MB.
    
    Args:
        pid: Process ID to measure (defaults to current process)
    
    Returns:
        RSS memory in MB
    """
    process = psutil.Process(pid) if pid else psutil.Process()
    return process.memory_info().rss / (1024 * 1024)


def measure_cpu(pid: int | None = None, interval: float = 1.0) -> float:
    """
    Measure CPU usage percentage.
    
    Args:
        pid: Process ID to measure (defaults to current process)
        interval: Measurement interval in seconds
    
    Returns:
        CPU percentage (0-100 per core, can exceed 100 on multi-core)
    """
    process = psutil.Process(pid) if pid else psutil.Process()
    return process.cpu_percent(interval=interval)


def calculate_percentile(values: list[float], p: int) -> float:
    """
    Calculate the p-th percentile of a list of values.
    
    Uses the nearest-rank method (standard definition).
    For p99 with 100 values, this returns the 99th value when sorted.
    
    Args:
        values: List of numeric values
        p: Percentile (0-100)
    
    Returns:
        The p-th percentile value
    """
    if not values:
        return 0.0
    
    sorted_values = sorted(values)
    n = len(sorted_values)
    
    # Nearest-rank method
    rank = int((p / 100) * n)
    
    # Clamp to valid index
    if rank >= n:
        return sorted_values[-1]
    if rank == 0:
        return sorted_values[0]
    
    return sorted_values[rank]


@dataclass
class LatencyStats:
    """Statistical summary of latency measurements"""
    min: float
    max: float
    mean: float
    median: float
    p50: float
    p95: float
    p99: float
    p999: float | None = None
    
    @classmethod
    def from_measurements(cls, latencies: list[float]) -> "LatencyStats":
        """Calculate statistics from raw latency measurements"""
        if not latencies:
            return cls(0, 0, 0, 0, 0, 0, 0)
        
        sorted_lat = sorted(latencies)
        n = len(sorted_lat)
        
        return cls(
            min=sorted_lat[0],
            max=sorted_lat[-1],
            mean=sum(sorted_lat) / n,
            median=sorted_lat[n // 2],
            p50=calculate_percentile(latencies, 50),
            p95=calculate_percentile(latencies, 95),
            p99=calculate_percentile(latencies, 99),
            p999=calculate_percentile(latencies, 99.9) if n >= 1000 else None
        )


class ConnectionTracker:
    """Helper for tracking MQTT connections in benchmarks"""
    
    def __init__(self, host: str = "127.0.0.1", port: int = 1883):
        self.host = host
        self.port = port
        self.successful = 0
        self.failed = 0
        self.lost_messages = 0
        self.server_pid: int | None = None
        self.connections: list = []
    
    async def connect_clients(self, count: int):
        """Connect multiple clients concurrently"""
        # TODO: Implement actual MQTT connection logic
        # For now, this is a placeholder
        self.successful = count
    
    async def publish_and_receive(self, topic: str, message: str) -> float:
        """
        Publish a message and measure round-trip latency.
        
        Returns:
            Latency in milliseconds
        """
        # TODO: Implement actual pub/sub logic
        # For now, simulate with small delay
        await asyncio.sleep(0.001)
        return 1.0
    
    async def disconnect_all(self):
        """Disconnect all clients"""
        # TODO: Implement cleanup
        pass
