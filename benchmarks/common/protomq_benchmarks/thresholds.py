"""
Threshold management and validation.
"""

from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path
import json


class ThresholdDirection(StrEnum):
    """Indicator for threshold direction"""
    LOWER_IS_BETTER = "lower"  # e.g., latency, memory
    HIGHER_IS_BETTER = "higher"  # e.g., throughput, connections
    

@dataclass
class Threshold:
    """Single metric threshold configuration"""
    metric: str
    direction: ThresholdDirection
    min_value: float | None = None
    max_value: float | None = None
    warn_value: float | None = None
    description: str | None = None
    
    def check(self, value: float) -> tuple[str, str | None]:
        """
        Check value against threshold.
        Returns (status, message) where status is "OK", "WARN", or "FAIL"
        """
        if self.direction == ThresholdDirection.LOWER_IS_BETTER:
            # For "lower is better" metrics (latency, memory)
            if self.max_value is not None and value > self.max_value:
                return ("FAIL", f"{self.metric}={value} exceeds max={self.max_value}")
            if self.warn_value is not None and value > self.warn_value:
                return ("WARN", f"{self.metric}={value} exceeds warn={self.warn_value}")
            if self.min_value is not None and value < self.min_value:
                return ("FAIL", f"{self.metric}={value} below min={self.min_value}")
        else:
            # For "higher is better" metrics (throughput, connections)
            if self.min_value is not None and value < self.min_value:
                return ("FAIL", f"{self.metric}={value} below min={self.min_value}")
            if self.warn_value is not None and value < self.warn_value:
                return ("WARN", f"{self.metric}={value} below warn={self.warn_value}")
            if self.max_value is not None and value > self.max_value:
                return ("FAIL", f"{self.metric}={value} exceeds max={self.max_value}")
        
        return ("OK", None)


class ThresholdChecker:
    """Manages and validates benchmark thresholds"""
    
    def __init__(self):
        self.thresholds: dict[str, Threshold] = {}
    
    def add_threshold(
        self,
        metric: str,
        direction: ThresholdDirection,
        min_value: float | None = None,
        max_value: float | None = None,
        warn_value: float | None = None,
        description: str | None = None
    ):
        """Add a threshold for a metric"""
        self.thresholds[metric] = Threshold(
            metric=metric,
            direction=direction,
            min_value=min_value,
            max_value=max_value,
            warn_value=warn_value,
            description=description
        )
    
    def load_from_file(self, path: str | Path):
        """
        Load thresholds from JSON file.
        
        Format:
        {
            "metric_name": {
                "direction": "lower",  # or "higher"
                "min": 100,
                "max": 1000,
                "warn": 500,
                "description": "..."
            }
        }
        """
        with open(path) as f:
            data = json.load(f)
        
        for metric, config in data.items():
            direction = ThresholdDirection(config.get("direction", "lower"))
            self.add_threshold(
                metric=metric,
                direction=direction,
                min_value=config.get("min"),
                max_value=config.get("max"),
                warn_value=config.get("warn"),
                description=config.get("description")
            )
    
    def check(self, results: dict[str, float]) -> dict:
        """
        Validate results against thresholds.
        
        Returns:
        {
            "passed": bool,
            "warnings": [str],
            "failures": [str],
            "details": {metric: {status, value, threshold}}
        }
        """
        warnings = []
        failures = []
        details = {}
        
        for metric, value in results.items():
            if metric not in self.thresholds:
                # No threshold defined, skip
                details[metric] = {
                    "status": "SKIP",
                    "value": value,
                    "threshold": None
                }
                continue
            
            threshold = self.thresholds[metric]
            status, message = threshold.check(value)
            
            details[metric] = {
                "status": status,
                "value": value,
                "threshold": {
                    "direction": threshold.direction,
                    "min": threshold.min_value,
                    "max": threshold.max_value,
                    "warn": threshold.warn_value
                }
            }
            
            if status == "FAIL":
                failures.append(message)
            elif status == "WARN":
                warnings.append(message)
        
        return {
            "passed": len(failures) == 0,
            "warnings": warnings,
            "failures": failures,
            "details": details
        }
    
    def print_summary(self, status: dict):
        """Pretty-print threshold check results"""
        print("\n" + "="*60)
        print("THRESHOLD CHECK RESULTS")
        print("="*60)
        
        for metric, detail in status["details"].items():
            status_symbol = {
                "OK": "[PASS]",
                "WARN": "[WARN]",
                "FAIL": "[FAIL]",
                "SKIP": "[SKIP]"
            }[detail["status"]]
            
            print(f"{status_symbol} {metric}: {detail['value']}")
            
            if detail["threshold"]:
                th = detail["threshold"]
                print(f"   Direction: {th['direction']}")
                if th["min"] is not None:
                    print(f"   Min: {th['min']}")
                if th["max"] is not None:
                    print(f"   Max: {th['max']}")
                if th["warn"] is not None:
                    print(f"   Warn: {th['warn']}")
        
        print("\n" + "-"*60)
        if status["failures"]:
            print("FAILURES:")
            for failure in status["failures"]:
                print(f"   - {failure}")
        
        if status["warnings"]:
            print("WARNINGS:")
            for warning in status["warnings"]:
                print(f"   - {warning}")
        
        if status["passed"] and not status["warnings"]:
            print("ALL THRESHOLDS PASSED")
        elif status["passed"]:
            print("PASSED (with warnings)")
        else:
            print("FAILED")
        
        print("="*60 + "\n")
