"""
Environment detection and system information collection.
"""

from dataclasses import dataclass, asdict
from enum import StrEnum
import os
import platform
import subprocess
import psutil
from pathlib import Path


class CpuArchitecture(StrEnum):
    """Normalized CPU architecture values"""
    X86_64 = "x86_64"
    ARM64 = "arm64"  # Normalized: aarch64 → arm64
    UNKNOWN = "unknown"
    
    @classmethod
    def detect(cls) -> "CpuArchitecture":
        """Detect and normalize CPU architecture"""
        machine = platform.machine().lower()
        if machine in ("x86_64", "amd64"):
            return cls.X86_64
        elif machine in ("arm64", "aarch64"):
            return cls.ARM64  # Normalize both to arm64
        return cls.UNKNOWN


@dataclass
class StorageInfo:
    """Storage device information"""
    type: str  # "NVMe SSD", "SATA SSD", "HDD", "SD Card"
    manufacturer: str | None = None
    model: str | None = None
    
    @classmethod
    def detect(cls) -> "StorageInfo":
        """Detect storage type and model"""
        try:
            # macOS: diskutil info
            if platform.system() == "Darwin":
                result = subprocess.run(
                    ["diskutil", "info", "/"],
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                output = result.stdout
                
                # Parse diskutil output
                storage_type = "Unknown"
                manufacturer = None
                model = None
                
                for line in output.split("\n"):
                    if "Solid State:" in line and "Yes" in line:
                        storage_type = "SSD"
                    elif "Protocol:" in line:
                        if "NVMe" in line:
                            storage_type = "NVMe SSD"
                    elif "Device / Media Name:" in line:
                        model = line.split(":")[-1].strip()
                
                return cls(type=storage_type, manufacturer=manufacturer, model=model)
            
            # Linux: lsblk, /sys/block
            elif platform.system() == "Linux":
                # Try to get root device
                result = subprocess.run(
                    ["findmnt", "-n", "-o", "SOURCE", "/"],
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                device = result.stdout.strip().split("/")[-1].rstrip("0123456789p")
                
                # Check if SSD
                rotational_file = Path(f"/sys/block/{device}/queue/rotational")
                if rotational_file.exists():
                    is_ssd = rotational_file.read_text().strip() == "0"
                    storage_type = "SSD" if is_ssd else "HDD"
                else:
                    storage_type = "Unknown"
                
                # Get model
                model_file = Path(f"/sys/block/{device}/device/model")
                model = model_file.read_text().strip() if model_file.exists() else None
                
                return cls(type=storage_type, manufacturer=None, model=model)
        except Exception:
            pass
        
        return cls(type="Unknown", manufacturer=None, model=None)


@dataclass
class HardwareInfo:
    """Hardware environment information"""
    cpu_model: str
    cpu_arch: CpuArchitecture
    cpu_cores: int
    cpu_freq_mhz: dict[str, float]
    ram_gb: float
    storage: StorageInfo


@dataclass
class SoftwareInfo:
    """Software environment information"""
    os_name: str
    os_version: str
    kernel: str
    zig_version: str
    python_version: str
    build_mode: str


@dataclass
class NetworkInfo:
    """Network configuration"""
    backend: str  # "kqueue" or "epoll"
    loopback_available: bool


@dataclass
class ProtoMQInfo:
    """ProtoMQ build information"""
    version: str
    commit_hash: str
    buffer_size: int
    max_connections: int


@dataclass
class Environment:
    """Complete environment snapshot"""
    hardware: HardwareInfo
    software: SoftwareInfo
    network: NetworkInfo
    protomq: ProtoMQInfo
    
    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization"""
        return asdict(self)


def detect_cpu_info() -> HardwareInfo:
    """Detect CPU and hardware information"""
    # Get CPU model - platform.processor() returns "arm" on macOS, need sysctl
    cpu_model = platform.processor() or "Unknown"
    
    # On macOS, get actual chip name from sysctl
    if platform.system() == "Darwin" and cpu_model == "arm":
        try:
            result = subprocess.run(
                ["sysctl", "-n", "machdep.cpu.brand_string"],
                capture_output=True,
                text=True,
                timeout=2
            )
            if result.returncode == 0:
                cpu_model = result.stdout.strip()
            
            # Fallback to chip name if brand_string doesn't work
            if not cpu_model or cpu_model == "arm":
                result = subprocess.run(
                    ["sysctl", "-n", "hw.model"],
                    capture_output=True,
                    text=True,
                    timeout=2
                )
                if result.returncode == 0:
                    cpu_model = result.stdout.strip()
        except Exception:
            pass
    
    cpu_arch = CpuArchitecture.detect()
    cpu_cores = psutil.cpu_count(logical=False) or psutil.cpu_count()
    
    # CPU frequency
    freq = psutil.cpu_freq()
    cpu_freq_mhz = {
        "base": freq.min if freq else 0,
        "max": freq.max if freq else 0,
    }
    
    # RAM in GB
    ram_gb = round(psutil.virtual_memory().total / (1024**3), 2)
    
    # Storage detection
    storage = StorageInfo.detect()
    
    return HardwareInfo(
        cpu_model=cpu_model,
        cpu_arch=cpu_arch,
        cpu_cores=cpu_cores,
        cpu_freq_mhz=cpu_freq_mhz,
        ram_gb=ram_gb,
        storage=storage
    )


def detect_build_mode() -> str:
    """Detect if ProtoMQ binaries are optimized"""
    try:
        # Check if binary is stripped (no symbols)
        result = subprocess.run(
            ["file", "zig-out/bin/protomq-server"],
            capture_output=True,
            text=True,
            timeout=2
        )
        output = result.stdout.lower()
        
        if "stripped" in output:
            return "Release"
        elif "not stripped" in output:
            return "Debug"
        return "Unknown"
    except Exception:
        return "Unknown"


def get_protomq_version() -> ProtoMQInfo:
    """Get ProtoMQ version and build info"""
    try:
        # Get git commit hash
        result = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            capture_output=True,
            text=True,
            timeout=2,
            cwd=Path(__file__).parent.parent.parent.parent
        )
        commit_hash = result.stdout.strip()[:8]
    except Exception:
        commit_hash = "unknown"
    
    # TODO: Parse from build.zig or version file
    return ProtoMQInfo(
        version="0.1.0",
        commit_hash=commit_hash,
        buffer_size=4096,
        max_connections=1000
    )


def get_hardware_dir_name(env: Environment) ->str:
    """
    Generate hardware-specific directory name for organizing results.
    
    Format: {os}_{os_version}_{cpu_model}_{arch}
    Example: darwin_25.2.0_m2pro_arm64
    
    Can be overridden with BENCHMARK_HARDWARE_ID environment variable.
    """
    # Allow manual override
    if "BENCHMARK_HARDWARE_ID" in os.environ:
        return os.environ["BENCHMARK_HARDWARE_ID"]
    
    # Auto-generate from environment
    os_name = env.software.os_name.lower()
    os_version = env.software.kernel  # Use kernel version (e.g., 25.2.0)
    
    # Simplify CPU model (remove spaces, make lowercase)
    cpu_model = env.hardware.cpu_model.lower()
    cpu_model = cpu_model.replace(" ", "").replace("(", "").replace(")", "")
    
    # Extract chip name for Apple Silicon
    if "apple" in cpu_model:
        # Remove "apple" prefix and surrounding text
        cpu_model = cpu_model.replace("apple", "")
        
        # Find chip name (m1, m2, m3, m4 variants)
        for chip in ["m4ultra", "m4max", "m4pro", "m4", 
                     "m3ultra", "m3max", "m3pro", "m3",
                     "m2ultra", "m2max", "m2pro", "m2",
                     "m1ultra", "m1max", "m1pro", "m1"]:
            if chip in cpu_model:
                cpu_model = chip
                break
    else:
        # For Intel/AMD, take first 20 chars
        cpu_model = cpu_model[:20]
    
    arch = env.hardware.cpu_arch.value
    
    return f"{os_name}_{os_version}_{cpu_model}_{arch}"


def collect_environment() -> Environment:
    """Collect complete environment information"""
    hardware = detect_cpu_info()
    
    software = SoftwareInfo(
        os_name=platform.system(),
        os_version=platform.version(),
        kernel=platform.release(),
        zig_version="0.15.2",  # TODO: Parse from zig version
        python_version=platform.python_version(),
        build_mode=detect_build_mode()
    )
    
    # Detect network backend
    network_backend = "kqueue" if platform.system() == "Darwin" else "epoll"
    network = NetworkInfo(
        backend=network_backend,
        loopback_available=True  # Assume true, can be tested
    )
    
    protomq = get_protomq_version()
    
    return Environment(
        hardware=hardware,
        software=software,
        network=network,
        protomq=protomq
    )
