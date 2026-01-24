"""
BenchmarkRunner - Main interface for running benchmarks.
"""

import asyncio
import json
import signal
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Any
from functools import wraps

from .environment import collect_environment, Environment
from .thresholds import ThresholdChecker


class BenchmarkTimeout(Exception):
    """Raised when benchmark exceeds timeout"""
    pass


class BenchmarkRunner:
    """
    Main benchmark execution framework.
    
    Provides:
    - Automatic environment collection
    - Threshold validation
    - Result serialization
    - Timeout watchdog
    """
    
    def __init__(
        self,
        name: str,
        version: str = "1.0.0",
        description: str = "",
        timeout_seconds: int = 300  # 5 minute default
    ):
        self.name = name
        self.version = version
        self.description = description
        self.timeout_seconds = timeout_seconds
        
        self.threshold_checker = ThresholdChecker()
        self.benchmark_func: Callable | None = None
        self.environment: Environment | None = None
    
    def register_thresholds(self, thresholds: dict):
        """Register thresholds from dictionary"""
        for metric, config in thresholds.items():
            self.threshold_checker.add_threshold(
                metric=metric,
                direction=config.get("direction", "lower"),
                min_value=config.get("min"),
                max_value=config.get("max"),
                warn_value=config.get("warn"),
                description=config.get("description")
            )
    
    def register_thresholds_from_file(self, path: str | Path):
        """Load thresholds from JSON file"""
        self.threshold_checker.load_from_file(path)
    
    def benchmark(self, func: Callable) -> Callable:
        """
        Decorator to mark the main benchmark function.
        
        Usage:
            @runner.benchmark
            async def run_test():
                # benchmark logic
                return {"metric1": value1, "metric2": value2}
        """
        self.benchmark_func = func
        
        @wraps(func)
        async def wrapper(*args, **kwargs):
            return await func(*args, **kwargs)
        
        return wrapper
    
    async def _run_with_timeout(self, coro):
        """Run coroutine with timeout watchdog"""
        try:
            return await asyncio.wait_for(coro, timeout=self.timeout_seconds)
        except asyncio.TimeoutError:
            raise BenchmarkTimeout(
                f"Benchmark exceeded timeout of {self.timeout_seconds}s"
            )
    
    def run(self, output_dir: str | Path = "results"):
        """
        Execute the benchmark and save results.
        
        Steps:
        1. Collect environment information
        2. Run benchmark function (with timeout)
        3. Validate results against thresholds
        4. Save JSON output to {commit_id}_{benchmark_name}.json
        """
        if self.benchmark_func is None:
            raise RuntimeError("No benchmark function registered. Use @runner.benchmark decorator.")
        
        print(f"\n{'='*60}")
        print(f"Starting Benchmark: {self.name}")
        print(f"{'='*60}\n")
        
        # Collect environment
        print("Collecting environment information...")
        self.environment = collect_environment()
        commit_id = self.environment.protomq.commit_hash
        
        # Run benchmark
        print(f"Running benchmark (timeout: {self.timeout_seconds}s)...")
        start_time = datetime.now(timezone.utc)
        
        try:
            if asyncio.iscoroutinefunction(self.benchmark_func):
                results = asyncio.run(
                    self._run_with_timeout(self.benchmark_func())
                )
            else:
                # Synchronous benchmark
                results = self.benchmark_func()
        except BenchmarkTimeout as e:
            print(f"\nTIMEOUT: {e}")
            return False
        except Exception as e:
            print(f"\nBENCHMARK FAILED: {e}")
            raise
        
        end_time = datetime.now(timezone.utc)
        duration = (end_time - start_time).total_seconds()
        
        print(f"Benchmark completed in {duration:.2f}s\n")
        
        # Validate thresholds
        print("Validating thresholds...")
        threshold_status = self.threshold_checker.check(results)
        self.threshold_checker.print_summary(threshold_status)
        
        # Save results
        output_path = Path(output_dir)
        output_path.mkdir(parents=True, exist_ok=True)
        
        # Use commit_id instead of timestamp for filename
        result_file = output_path / f"{commit_id}_{self.name}.json"
        
        output = {
            "benchmark": {
                "name": self.name,
                "version": self.version,
                "description": self.description,
                "timestamp": start_time.isoformat(),
                "duration_s": round(duration, 3)
            },
            "environment": self.environment.to_dict(),
            "metrics": results,
            "thresholds": threshold_status
        }
        
        with open(result_file, "w") as f:
            json.dump(output, f, indent=2, default=str)
        
        print(f"Results saved to: {result_file}\n")
        
        # Create/update latest symlink
        latest_link = output_path / "latest.json"
        if latest_link.exists() or latest_link.is_symlink():
            latest_link.unlink()
        latest_link.symlink_to(result_file.name)
        
        return threshold_status["passed"]
