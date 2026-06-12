"""Data collection layer — sudoless system scans for live TUI polling.

Ported from the mac-audit skill's generate_report.py and reshaped for
incremental polling: cheap snapshots (process list, memory) refresh often,
expensive ones (battery health, storage scans) refresh on demand.
"""
from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import sys
import threading
import time
from datetime import datetime
from pathlib import Path

import psutil

HOME = str(Path.home())


class _TTLCache:
    """Tiny per-key TTL cache for expensive, slow-changing scans."""

    def __init__(self):
        self._data: dict[str, tuple[float, object]] = {}
        self._lock = threading.Lock()

    def get(self, key: str, ttl: float, compute):
        now = time.monotonic()
        with self._lock:
            hit = self._data.get(key)
            if hit and now - hit[0] < ttl:
                return hit[1]
        val = compute()
        with self._lock:
            self._data[key] = (now, val)
        return val

    def invalidate(self, key: str) -> None:
        with self._lock:
            self._data.pop(key, None)


_cache = _TTLCache()


class MacmonStream:
    """Persistent `macmon pipe` subprocess + reader thread.

    Re-spawning macmon per tick costs ~2s (it must sample before printing).
    Keeping one long-lived process streaming a sample every second means
    `latest()` is a dict read — effectively free."""

    def __init__(self, interval_ms: int = 1000):
        self._interval = interval_ms
        self._latest: dict = {}
        self._proc: subprocess.Popen | None = None
        self._lock = threading.Lock()
        self._started = False

    def start(self) -> None:
        with self._lock:
            if self._started:
                return
            self._started = True
        threading.Thread(target=self._run, daemon=True, name="macmon-stream").start()

    def _run(self) -> None:
        while True:
            try:
                self._proc = subprocess.Popen(
                    ["macmon", "pipe", "-i", str(self._interval)],
                    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
                for line in self._proc.stdout:
                    line = line.strip()
                    if line.startswith("{"):
                        try:
                            self._latest = json.loads(line)
                        except ValueError:
                            pass
            except FileNotFoundError:
                return  # macmon not installed — latest() stays empty
            except Exception:
                pass
            time.sleep(2)  # macmon died — back off, respawn

    def latest(self) -> dict:
        return self._latest


_macmon = MacmonStream()


def run(cmd: str, timeout: int = 30) -> str:
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return r.stdout.strip()
    except Exception:
        return ""


def parse_size(s: str) -> float:
    """Convert '1.2G', '500M', '3.4K' to MB float."""
    s = (s or "").strip()
    if not s or s in ("0B", "0"):
        return 0.0
    m = re.match(r"([\d.]+)\s*([BKMGTP]?)", s, re.I)
    if not m:
        return 0.0
    try:
        v, u = float(m.group(1)), m.group(2).upper()
        return v * {"B": 1 / 1024 / 1024, "K": 1 / 1024, "M": 1, "G": 1024,
                    "T": 1024 * 1024, "P": 1024 ** 3, "": 1 / 1024 / 1024}.get(u, 1)
    except Exception:
        return 0.0


def fmt_mb(mb: float) -> str:
    if mb >= 1024:
        return f"{mb / 1024:.1f} GB"
    return f"{mb:.0f} MB"


# ===================== PROCESS ROLE TAXONOMY =====================
def classify_proc(comm: str, args: str):
    """Classify a process into a behavioral role.
    Returns (role_label, category, alarm_cpu, expected_max_cpu, fix_hint).
      alarm_cpu    = CPU% that flags a confirmed anomaly (None = informational only)
      expected_max = CPU% considered "elevated but possible"
    """
    ext = "--extension-process" in args
    gpu = "--type=gpu-process" in args or "gpu-process" in args

    if comm == "kernel_task":
        return ("Thermal Throttle", "system", 15, 5,
                "macOS caps CPU to protect thermals — find the hottest process and reduce its load")
    if comm == "WindowServer":
        return ("Display Compositor", "system", 30, 10,
                "Reduce open windows, animations, or lower display refresh rate")
    if comm == "coreaudiod":
        return ("Audio Server", "system", 15, 5,
                "Check for looping audio, virtual audio devices, or misbehaving audio plugins")
    if "VTDecoderXPCService" in comm:
        return ("HW Video Decoder", "system", None, 50,
                "Near-zero while browser renderer is hot = software video decode (codec mismatch)")
    if re.match(r"^mds$|^mdworker|^mds_stores$", comm):
        return ("Spotlight Indexer", "system", 250, 60,
                "Sustained high: add folder to Spotlight exclusions in System Settings")
    if comm in ("airportd", "WiFiAgent", "wifid", "wifi_scan", "airport"):
        return ("Wi-Fi Daemon", "system", 15, 5,
                "Poor signal or interference — move closer to router")
    if comm == "bluetoothd":
        return ("Bluetooth Daemon", "system", 10, 3,
                "Chatty BT device — unpair unused devices or toggle BT off/on")
    if comm in ("bird", "cloudd", "cloudpaird") or "CloudDocs" in comm:
        return ("iCloud Sync", "system", 40, 10,
                "Large sync in progress — pause via System Settings › Apple ID › iCloud")
    if comm == "backupd":
        return ("Time Machine", "system", None, 200,
                "Backup in progress — will subside when done")
    if comm == "caffeinate":
        return ("Sleep Preventer", "system", None, 1,
                "Actively preventing sleep — kill with: pkill caffeinate")
    if comm in ("duetexpertd", "coreduetd"):
        return ("Perf Manager", "system", 30, 10,
                "Apple performance prediction daemon — occasional spikes are normal")
    if comm in ("logd", "syslogd", "notifyd", "opendirectoryd"):
        return ("System Core", "system", 10, 2,
                "High rate may indicate crash loop or verbose logging — check Console.app")
    if comm in ("trustd", "securityd", "secd", "keybagd"):
        return ("Security Daemon", "system", 20, 5,
                "Spikes during cert validation, keychain unlock, or first app launch")
    if comm in ("sharingd", "rapportd"):
        return ("Sharing / Handoff", "system", 15, 3,
                "AirDrop/Handoff overhead — disable if unused: System Settings › General › AirDrop")
    if comm in ("symptomsd", "healthd", "diagnosticd"):
        return ("Health Reporter", "system", 10, 2, "Should be near-zero")
    if comm == "launchd":
        return ("Process Manager", "system", 5, 1, "Root process manager — should be near-zero")
    if comm in ("locationd",):
        return ("Location Daemon", "system", 10, 3,
                "Check which apps have location access: System Settings › Privacy › Location")

    BROWSERS = ("Brave Browser", "Google Chrome", "Chromium", "Firefox",
                "Safari", "Arc", "Microsoft Edge", "Opera", "Vivaldi")
    is_browser = (any(b in comm or b in args for b in BROWSERS)
                  or "Helper (Renderer)" in comm
                  or ("Helper" in comm and any(b in args for b in BROWSERS)))
    if is_browser:
        if gpu:
            return ("Browser GPU", "browser", 35, 15,
                    "Verify hardware acceleration is on in browser settings (brave://gpu)")
        if ext:
            return ("Browser Extension", "browser", 12, 5,
                    "All extensions share this process — disable one by one to find the CPU hog")
        if "--type=renderer" in args or "Renderer" in comm:
            return ("Browser Tab Renderer", "browser", 60, 25,
                    "High CPU: software video decode (install h264ify), heavy JS, or crypto miner")
        return ("Browser Main", "browser", 40, 10,
                "High: background tasks, pre-rendering — reduce tab count or check extensions")

    if "Electron" in args or "electron" in args.lower():
        return ("Electron App", "user", 60, 20,
                "Background sync or update cycle — check app's background activity settings")

    DEV_RT = {"node", "python3", "python", "ruby", "java", "go", "deno", "bun", "tsx", "php"}
    DEV_CC = {"clang", "clang++", "swift", "swiftc", "xcodebuild", "make", "cmake", "ld", "gcc", "g++", "Xcode"}
    if comm in DEV_RT:
        return ("Script / Runtime", "dev", None, 200,
                "Active script or dev server — expected if you started one")
    if comm in DEV_CC:
        return ("Compiler / Build", "dev", None, 400,
                "Active compilation — CPU-intensive by design")

    MENUBAR = ("Stats", "iStatMenus", "iStat", "Alfred", "Raycast", "Lungo", "Amphetamine", "Bartender")
    if any(m in comm for m in MENUBAR):
        return ("Menu Bar App", "user", 10, 3,
                "Reduce polling interval in app preferences")

    SYNC = ("Dropbox", "dbxd", "OneDrive", "Box", "Maestral", "rclone", "syncthing")
    if any(s in comm or s in args for s in SYNC):
        return ("Cloud Sync Agent", "user", 40, 15,
                "Large upload in progress — pause sync or check what's being uploaded")

    return ("User App", "user", 90, 30,
            "Investigate if consistently high with no obvious active task")


# ===================== DISK ACTIVITY (sudoless proxies) =====================
# psutil has no per-process io_counters() on macOS (kernel doesn't expose it
# without root — confirmed: AttributeError on psutil.Process). The closest
# sudoless proxy is `top`'s per-process PAGEINS counter (pages faulted in from
# disk) — a real signal for "this process is driving disk activity", just not
# byte-accurate I/O. System-wide throughput IS available via psutil.disk_io_counters().
_pageins_prev: dict[int, tuple[int, float]] = {}
_disk_io_prev: tuple[object, float] | None = None


def _proc_pageins_rate() -> dict[int, float]:
    """Per-pid pages-faulted-in-from-disk per second since last sample (proxy for disk read activity)."""
    out = run("top -l 1 -n 400 -stats pid,pageins -o pageins 2>/dev/null", timeout=6)
    now = time.time()
    rates = {}
    for line in out.splitlines():
        m = re.match(r"\s*(\d+)\s+(\d+)\s*$", line)
        if not m:
            continue
        pid, pageins = int(m.group(1)), int(m.group(2))
        prev = _pageins_prev.get(pid)
        if prev:
            prev_val, prev_t = prev
            dt = now - prev_t
            if dt > 0 and pageins >= prev_val:
                rates[pid] = round((pageins - prev_val) / dt, 1)
        _pageins_prev[pid] = (pageins, now)
    return rates


_net_io_prev: tuple[object, float] | None = None
_net_proc_prev: dict[int, tuple[int, int, float]] = {}
_NETTOP_RE = re.compile(r"^(.+)\.(\d+)\s+(\d+)\s+(\d+)\s*$")


def collect_network():
    """System throughput (psutil, sudoless) + per-process top talkers
    (nettop -P, sudoless — gives cumulative bytes_in/out, we derive rates)."""
    global _net_io_prev
    N = {}

    cur = psutil.net_io_counters()
    now = time.time()
    if _net_io_prev is None:
        sent_kb_s = recv_kb_s = 0.0
    else:
        prev, prev_t = _net_io_prev
        dt = now - prev_t
        sent_kb_s = max(0.0, (cur.bytes_sent - prev.bytes_sent) / dt / 1024) if dt > 0 else 0.0
        recv_kb_s = max(0.0, (cur.bytes_recv - prev.bytes_recv) / dt / 1024) if dt > 0 else 0.0
    _net_io_prev = (cur, now)
    N["sent_kb_s"] = round(sent_kb_s, 1)
    N["recv_kb_s"] = round(recv_kb_s, 1)
    N["total_sent_mb"] = round(cur.bytes_sent / 1e6)
    N["total_recv_mb"] = round(cur.bytes_recv / 1e6)

    out = run("nettop -P -x -l 1 -J bytes_in,bytes_out 2>/dev/null", timeout=15)
    talkers = []
    for line in out.splitlines():
        m = _NETTOP_RE.match(line.strip())
        if not m:
            continue
        name, pid_s, bytes_in, bytes_out = m.group(1).strip(), m.group(2), int(m.group(3)), int(m.group(4))
        pid = int(pid_s)
        if bytes_in == 0 and bytes_out == 0:
            continue
        prev = _net_proc_prev.get(pid)
        in_rate = out_rate = 0.0
        if prev:
            p_in, p_out, p_t = prev
            dt = now - p_t
            if dt > 0:
                in_rate = max(0.0, (bytes_in - p_in) / dt / 1024)
                out_rate = max(0.0, (bytes_out - p_out) / dt / 1024)
        _net_proc_prev[pid] = (bytes_in, bytes_out, now)
        talkers.append({"pid": pid, "name": name,
                        "in_kb_s": round(in_rate, 1), "out_kb_s": round(out_rate, 1),
                        "total_in_mb": round(bytes_in / 1e6, 1), "total_out_mb": round(bytes_out / 1e6, 1)})
    talkers.sort(key=lambda t: -(t["in_kb_s"] + t["out_kb_s"]))
    N["talkers"] = talkers[:30]

    # Active outbound connections per top talker (sudoless for owned processes)
    conn_counts = {}
    for t in N["talkers"][:15]:
        try:
            p = psutil.Process(t["pid"])
            conns = p.net_connections(kind="inet")
            conn_counts[t["pid"]] = sum(1 for c in conns if c.status == "ESTABLISHED")
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
            conn_counts[t["pid"]] = 0
    for t in N["talkers"]:
        t["connections"] = conn_counts.get(t["pid"], 0)

    return N


def disk_throughput_mb_s() -> tuple[float, float]:
    """System-wide (read_mb_s, write_mb_s) since the last call, via psutil (sudoless)."""
    global _disk_io_prev
    cur = psutil.disk_io_counters()
    now = time.time()
    if not cur:
        return 0.0, 0.0
    if _disk_io_prev is None:
        _disk_io_prev = (cur, now)
        return 0.0, 0.0
    prev, prev_t = _disk_io_prev
    dt = now - prev_t
    _disk_io_prev = (cur, now)
    if dt <= 0:
        return 0.0, 0.0
    read_mb_s = max(0.0, (cur.read_bytes - prev.read_bytes) / dt / 1e6)
    write_mb_s = max(0.0, (cur.write_bytes - prev.write_bytes) / dt / 1e6)
    return round(read_mb_s, 2), round(write_mb_s, 2)


# ===================== LIVE PROCESS SNAPSHOT (psutil, cheap) =====================
def snapshot_processes(limit: int = 200):
    """Fast process snapshot for the live table. Uses psutil (no subprocess spawn).
    Returns list of dicts sorted by CPU desc, each classified into a role.
    The pageins `top` sample (~0.3s subprocess) is throttled to every 10s —
    disk-activity rates barely move tick-to-tick."""
    pageins_rate = _cache.get("pageins", 10.0, _proc_pageins_rate)
    procs = []
    for p in psutil.process_iter(["pid", "ppid", "name", "cpu_percent", "memory_percent",
                                   "memory_info", "username", "cmdline"]):
        try:
            info = p.info
            cmdline = info.get("cmdline") or []
            args = " ".join(cmdline) if cmdline else (info.get("name") or "")
            comm = info.get("name") or (cmdline[0] if cmdline else "")
            role, cat, alarm, exp_max, fix = classify_proc(comm, args)
            procs.append({
                "pid": info["pid"],
                "ppid": info.get("ppid") or 0,
                "comm": comm,
                "args": args,
                "cpu": round(info.get("cpu_percent") or 0.0, 1),
                "mem_pct": round(info.get("memory_percent") or 0.0, 1),
                "rss_mb": round((info.get("memory_info").rss if info.get("memory_info") else 0) / 1024 / 1024),
                "user": info.get("username") or "",
                "disk_activity": pageins_rate.get(info["pid"], 0.0),
                "role": role, "cat": cat, "alarm": alarm, "exp_max": exp_max, "fix": fix,
            })
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
            continue
    procs.sort(key=lambda p: -p["cpu"])
    return procs[:limit]


def build_process_tree(procs: list[dict], sort_key: str = "cpu") -> list[tuple[dict, int]]:
    """Order processes as a parent->child hierarchy for display.
    Returns a depth-first list of (proc, depth) — roots are processes whose
    ppid isn't present in the snapshot, children are sorted by `sort_key`
    desc within each parent (mirrors the active flat-view sort)."""
    by_pid = {p["pid"]: p for p in procs}
    children: dict[int, list[dict]] = {}
    roots = []
    for p in procs:
        ppid = p["ppid"]
        if ppid in by_pid and ppid != p["pid"]:
            children.setdefault(ppid, []).append(p)
        else:
            roots.append(p)

    def _key(node: dict) -> float:
        return -(node.get(sort_key) or 0)

    for kids in children.values():
        kids.sort(key=_key)
    roots.sort(key=_key)

    ordered: list[tuple[dict, int]] = []

    def walk(node: dict, depth: int, seen: set[int]) -> None:
        if node["pid"] in seen:
            return
        seen.add(node["pid"])
        ordered.append((node, depth))
        for child in children.get(node["pid"], []):
            walk(child, depth + 1, seen)

    seen: set[int] = set()
    for r in roots:
        walk(r, 0, seen)
    return ordered


def kill_process(pid: int) -> tuple[bool, str]:
    """Kill a user-owned process. Returns (ok, message)."""
    try:
        p = psutil.Process(pid)
        if p.username() != psutil.Process(os.getpid()).username():
            return False, f"PID {pid} is not owned by you — refusing to kill"
        name = p.name()
        p.terminate()
        try:
            p.wait(timeout=3)
        except psutil.TimeoutExpired:
            p.kill()
        return True, f"Killed {name} (pid {pid})"
    except psutil.NoSuchProcess:
        return True, f"PID {pid} already gone"
    except psutil.AccessDenied:
        return False, f"Access denied killing pid {pid} (not owned by you)"
    except Exception as e:
        return False, str(e)


# ===================== SYSTEM VITALS (cheap) =====================
def _static_machine_info() -> dict:
    """Chip label + architecture never change — one subprocess, ever."""
    out = run("sysctl -n machdep.cpu.brand_string hw.optional.arm64 2>/dev/null", timeout=3)
    lines = out.splitlines()
    return {
        "chip_label": (lines[0].strip() if lines else "") or "Unknown",
        "is_apple_silicon": len(lines) > 1 and lines[1].strip() == "1",
    }


def collect_vitals():
    """Zero-subprocess on the hot path: boot time + load avg come from
    psutil/os natives; chip identity is computed once and cached forever."""
    V = {}
    boot_epoch = int(psutil.boot_time())
    up_s = max(0, int(datetime.now().timestamp()) - boot_epoch)
    d, rem = divmod(up_s, 86400)
    h, rem = divmod(rem, 3600)
    mins = rem // 60
    V["uptime"] = (f"{d}d {h}h" if d else f"{h}h {mins}m" if h else f"{mins}m")
    V["uptime_days"] = d

    V.update(_cache.get("machine_info", 86400.0, _static_machine_info))

    try:
        V["load_avg"] = list(os.getloadavg())
    except OSError:
        V["load_avg"] = [0.0, 0.0, 0.0]

    # Per-logical-core utilization for the btop-style core grid. psutil keeps
    # its own delta state between calls, so this reflects the interval since
    # the previous dashboard tick (first call after launch reads 0s).
    try:
        V["per_core"] = psutil.cpu_percent(percpu=True)
        V["cpu_overall"] = round(sum(V["per_core"]) / len(V["per_core"]), 1) if V["per_core"] else 0.0
        V["core_count"] = len(V["per_core"])
    except Exception:
        V["per_core"] = []
        V["cpu_overall"] = 0.0
        V["core_count"] = 0
    return V


# ===================== PERFORMANCE SNAPSHOT (macmon + thermals, ~moderate cost) =====================
def collect_perf_light():
    """Power/thermal/memory snapshot without the slow battery-history scans.
    Suitable for polling every few seconds."""
    R = {}
    _macmon.start()
    macmon_data = _macmon.latest()

    batt = psutil.sensors_battery()
    on_ac = batt.power_plugged if batt else True

    if macmon_data:
        watts = round(macmon_data.get("sys_power", 0), 1)
        cpu_power = round(macmon_data.get("cpu_power", 0), 2)
        gpu_power = round(macmon_data.get("gpu_power", 0), 2)
    else:
        watts = cpu_power = gpu_power = 0
    R["watts"] = watts
    R["on_ac"] = on_ac
    R["cpu_power"] = cpu_power
    R["gpu_power"] = gpu_power

    if macmon_data and "temp" in macmon_data:
        R["cpu_temp"] = round(macmon_data["temp"].get("cpu_temp_avg", 0), 1)
        R["gpu_temp"] = round(macmon_data["temp"].get("gpu_temp_avg", 0), 1)
    else:
        R["cpu_temp"] = R["gpu_temp"] = 0
    R["temp_elevated"] = R["cpu_temp"] > 75 and R["cpu_temp"] > 0
    R["temp_critical"] = R["cpu_temp"] > 88 and R["cpu_temp"] > 0

    if macmon_data and "gpu_usage" in macmon_data:
        gu = macmon_data.get("gpu_usage", [0, 0])
        R["gpu_util"] = round(gu[1] * 100) if len(gu) > 1 else 0
    else:
        R["gpu_util"] = 0

    # Apple Silicon E-core/P-core cluster breakdown + ANE power (sudoless via macmon's
    # private-API wrapper — no fan RPM available this way; that needs SMC access).
    ecpu = macmon_data.get("ecpu_usage") if macmon_data else None
    pcpu = macmon_data.get("pcpu_usage") if macmon_data else None
    R["ecpu_freq"] = round(ecpu[0]) if ecpu and len(ecpu) > 1 else 0
    R["ecpu_util"] = round(ecpu[1] * 100) if ecpu and len(ecpu) > 1 else 0
    R["pcpu_freq"] = round(pcpu[0]) if pcpu and len(pcpu) > 1 else 0
    R["pcpu_util"] = round(pcpu[1] * 100) if pcpu and len(pcpu) > 1 else 0
    R["ane_power"] = round(macmon_data.get("ane_power", 0), 2) if macmon_data else 0
    R["has_core_split"] = bool(ecpu and pcpu)

    # Memory pressure
    page_size = _cache.get("page_size", 86400.0,
                           lambda: int(run("pagesize 2>/dev/null", timeout=3) or 4096))
    vmstat = run("vm_stat 2>/dev/null", timeout=5)
    vm_v = {}
    for line in vmstat.splitlines():
        m = re.match(r'^(.+?):\s+([\d.]+)', line)
        if m:
            k = m.group(1).strip().lower().replace(" ", "_").replace("-", "_")
            try:
                vm_v[k] = int(float(m.group(2)))
            except Exception:
                pass
    comp_gb = vm_v.get("pages_occupied_by_compressor", 0) * page_size / 1e9
    pageouts = vm_v.get("pageouts", 0)
    if macmon_data and "memory" in macmon_data:
        swap_gb = round(macmon_data["memory"].get("swap_usage", 0) / 1e9, 2)
    else:
        swap_raw = run("sysctl vm.swapusage 2>/dev/null", timeout=3)
        swap_gb = 0.0
        swm = re.search(r'swapused\s*=\s*([\d.]+)M', swap_raw)
        if swm:
            swap_gb = float(swm.group(1)) / 1024
    pressure = ("critical" if comp_gb > 2 or swap_gb > 3
                else "warning" if comp_gb > 0.5 or swap_gb > 0.5 or pageouts > 2000
                else "normal")
    R["mem"] = {"comp_gb": round(comp_gb, 1), "swap_gb": round(swap_gb, 2),
                "pageouts": pageouts, "pressure": pressure}

    vm = psutil.virtual_memory()
    R["mem_total_gb"] = round(vm.total / 1e9, 1)
    R["mem_used_pct"] = vm.percent
    R["mem_free_pct"] = round(100 - vm.percent, 1)
    return R


# ===================== BATTERY (slow — poll infrequently) =====================
def collect_battery():
    """Battery health changes over weeks and sessions over hours — cache the
    two expensive scans (system_profiler ~3s, pmset log ~2s) for 5 minutes."""
    return _cache.get("battery", 300.0, _collect_battery_uncached)


def _collect_battery_uncached():
    B = {}
    batt_health = {"cycle_count": None, "max_capacity_pct": None, "condition": "Unknown"}
    sp_power = run("system_profiler SPPowerDataType 2>/dev/null", timeout=10)
    for line in sp_power.splitlines():
        m = re.search(r'Cycle Count:\s*(\d+)', line)
        if m:
            batt_health["cycle_count"] = int(m.group(1))
        m = re.search(r'Maximum Capacity:\s*(\d+)\s*%', line)
        if m:
            batt_health["max_capacity_pct"] = int(m.group(1))
        m = re.search(r'Condition:\s*(\w+)', line)
        if m:
            batt_health["condition"] = m.group(1)
    B["health"] = batt_health

    pmlog = run("pmset -g log 2>/dev/null | grep -E 'Using AC|Using Batt' | tail -n 2000", timeout=12)
    sessions = []
    current_session = None

    for line in pmlog.splitlines():
        dtm = re.match(r'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', line)
        if not dtm:
            continue
        time_str = dtm.group(1)
        
        chm = re.search(r'Charge:\s*(\d+)', line)
        charge = int(chm.group(1)) if chm else None
        
        is_batt = "Using Batt" in line
        is_ac = "Using AC" in line
        
        if not is_batt and not is_ac:
            continue
        
        etype = "batt" if is_batt else "ac"
        
        if charge is None:
            continue

        if current_session is None:
            if etype == "batt":
                current_session = {"start": time_str, "s_pct": charge, "last_time": time_str, "last_charge": charge}
        else:
            if etype == "batt":
                current_session["last_time"] = time_str
                current_session["last_charge"] = charge
            elif etype == "ac":
                # Session ended
                try:
                    t0 = datetime.strptime(current_session["start"], "%Y-%m-%d %H:%M:%S")
                    t1 = datetime.strptime(current_session["last_time"], "%Y-%m-%d %H:%M:%S")
                    dur_h = (t1 - t0).total_seconds() / 3600
                    drop = current_session["s_pct"] - current_session["last_charge"]
                    if dur_h > 0 and drop > 0:
                        rate = round(drop / dur_h, 1)
                        sessions.append({
                            "start": current_session["start"][5:16], 
                            "end": current_session["last_time"][5:16],
                            "s_pct": current_session["s_pct"],
                            "e_pct": current_session["last_charge"],
                            "dur_h": round(dur_h, 1),
                            "drop": drop,
                            "rate": rate
                        })
                except Exception:
                    pass
                current_session = None

    B["sessions"] = sessions[-15:] if sessions else []
    return B


# ===================== ASSERTIONS / ROSETTA (moderate) =====================
def collect_assertions():
    assert_raw = run("pmset -g assertions 2>/dev/null", timeout=6)
    assertions = []
    for line in assert_raw.splitlines():
        m = re.search(r'pid\s+(\d+)\((.+?)\)[^"]*"([^"]+)"', line)
        if m and any(kw in line for kw in ("PreventUserIdle", "PreventSystem", "PreventDisplay")):
            atype = ("Prevent System Sleep" if "PreventSystem" in line
                     else "Prevent Display Sleep" if "PreventDisplay" in line
                     else "Prevent Sleep")
            assertions.append({"pid": int(m.group(1)), "app": m.group(2),
                               "reason": m.group(3), "type": atype})
    return assertions


# ===================== STARTUP / LOGIN ITEMS =====================
def collect_startup():
    """Login items / LaunchAgents change rarely — cache for 2 minutes
    (the osascript call alone can take several seconds)."""
    return _cache.get("startup", 120.0, _collect_startup_uncached)


def _collect_startup_uncached():
    S = {}
    li_raw = run('osascript -e \'tell application "System Events" to get the name of every login item\' 2>/dev/null', timeout=8)
    login_items = [x.strip() for x in li_raw.split(",") if x.strip()] if li_raw else []
    S["login_items"] = login_items
    la_dir = os.path.join(HOME, "Library/LaunchAgents")
    agents = []
    if os.path.isdir(la_dir):
        for f in sorted(os.listdir(la_dir)):
            if f.endswith(".plist"):
                noisy = any(k in f.lower() for k in ("update", "keystone", "wake"))
                agents.append({"label": f[:-6], "noisy": noisy})
    S["launch_agents"] = agents
    svc = run("launchctl list 2>/dev/null | wc -l", timeout=6)
    try:
        S["service_count"] = int(svc.strip()) - 1
    except Exception:
        S["service_count"] = 0
    bloat = len(login_items) * 4 + sum(2 if a["noisy"] else 1 for a in agents) + max(S["service_count"] - 400, 0) // 50
    S["bloat_score"] = bloat
    S["bloat_level"] = "high" if bloat > 28 else "moderate" if bloat > 16 else "low"
    return S


# ===================== STORAGE =====================
def collect_disk_usage():
    """df ground truth for the data volume."""
    out = run("df -h /System/Volumes/Data 2>/dev/null", timeout=8)
    lines = out.splitlines()
    if len(lines) < 2:
        return {}
    parts = lines[1].split()
    if len(parts) < 5:
        return {}
    return {"size": parts[1], "used": parts[2], "avail": parts[3],
            "pct": int(parts[4].rstrip("%")) if parts[4].rstrip("%").isdigit() else 0,
            "mount": parts[-1]}


def collect_storage_extra():
    X = {}
    lf_raw = run(f"find {HOME} -type f -size +500M -not -path '*/vm_bundles/*' 2>/dev/null | head -40", timeout=30)
    files = []
    for p in lf_raw.splitlines():
        s = run(f"du -h {shlex.quote(p)} 2>/dev/null | cut -f1", timeout=6)
        if s:
            files.append({"path": p, "size_str": s, "size_mb": parse_size(s),
                          "name": os.path.basename(p),
                          "protected": "vm_bundles" in p or "claudevm" in p})
    files.sort(key=lambda x: -x["size_mb"])
    X["large_files"] = files[:15]

    trash_s = run(f"du -sh {HOME}/.Trash 2>/dev/null | cut -f1", timeout=12)
    X["trash"] = {"size_str": trash_s or "0B", "size_mb": parse_size(trash_s)}

    bo = run("brew outdated 2>/dev/null | wc -l", timeout=20)
    try:
        X["brew_outdated"] = int(bo.strip())
    except Exception:
        X["brew_outdated"] = 0
    return X


def list_dir(path: str):
    """List a directory's entries with sizes, sorted largest first.
    Single `du -d 1` call covers directories; files are stat'd directly —
    far faster than spawning `du` per entry."""
    entries = []
    try:
        with os.scandir(path) as it:
            names = [e.name for e in it if e.name != ".DS_Store"]
    except Exception:
        return entries

    dir_sizes = {}
    du_out = run(f"du -h -d 1 '{path}' 2>/dev/null", timeout=45)
    for line in du_out.splitlines():
        parts = line.split("\t", 1)
        if len(parts) == 2:
            size, full = parts
            name = os.path.basename(full.rstrip("/"))
            dir_sizes[name] = size

    for name in names:
        full = os.path.join(path, name)
        try:
            is_dir = os.path.isdir(full) and not os.path.islink(full)
            if is_dir:
                size_str = dir_sizes.get(name, "")
                size_mb = parse_size(size_str)
            else:
                size_bytes = os.path.getsize(full)
                size_mb = size_bytes / 1024 / 1024
                size_str = fmt_mb(size_mb) if size_mb >= 1 else f"{size_bytes} B"
        except OSError:
            size_str, size_mb = "—", 0.0
        entries.append({"name": name, "path": full, "is_dir": is_dir,
                        "size_str": size_str or "—", "size_mb": size_mb})
    entries.sort(key=lambda e: (-e["size_mb"], e["name"].lower()))
    return entries


def fmt_size(n: int | None) -> str:
    """Relative-unit byte formatter for the storage tree (B/KB/MB/GB/TB…)."""
    if n is None:
        return "…"
    n = float(n)
    for unit in ("B", "KB", "MB", "GB", "TB", "PB"):
        if n < 1024 or unit == "PB":
            if unit in ("B", "KB"):
                return f"{n:.0f} {unit}"
            return f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} PB"


def list_children_fast(path: str) -> list[dict]:
    """One directory level via os.scandir only — no subprocess, effectively
    instant. File sizes are exact; directory sizes are left as None (filled in
    later by `dir_sizes_depth1`). Sorted directories-first then files
    largest-first so the tree is useful before the `du` pass returns."""
    out = []
    try:
        with os.scandir(path) as it:
            for e in it:
                if e.name == ".DS_Store":
                    continue
                try:
                    is_dir = e.is_dir(follow_symlinks=False)
                    st = e.stat(follow_symlinks=False)
                    out.append({
                        "name": e.name,
                        "path": os.path.join(path, e.name),
                        "is_dir": is_dir,
                        "size": None if is_dir else st.st_size,
                        "mtime": st.st_mtime,
                        "loaded": False,
                    })
                except OSError:
                    continue
    except (PermissionError, FileNotFoundError, NotADirectoryError, OSError):
        pass
    out.sort(key=lambda e: (e["size"] is not None, -(e["size"] or 0), e["name"].lower()))
    return out


def du_size_bytes(path: str) -> int | None:
    """Recursive size of a single directory in bytes via `du -sk` (sudoless;
    permission-denied descendants are skipped). Returns None on failure."""
    import shlex
    out = run(f"du -sk {shlex.quote(path)} 2>/dev/null", timeout=120)
    if not out:
        return None
    first = out.split("\n", 1)[0].split("\t", 1)
    try:
        return int(first[0]) * 1024
    except (ValueError, IndexError):
        return None


def dir_sizes_depth1(path: str) -> dict[str, int]:
    """Fallback for directories with very many children: one `du -k -d 1` pass
    (blocking) instead of a per-child process storm. Keyed by normalized path."""
    import shlex
    sizes = {}
    out = run(f"du -k -d 1 {shlex.quote(path)} 2>/dev/null", timeout=180)
    for line in out.splitlines():
        parts = line.split("\t", 1)
        if len(parts) == 2:
            kb, full = parts
            try:
                sizes[os.path.normpath(full.strip())] = int(kb) * 1024
            except ValueError:
                pass
    return sizes


# ===================== CLEANUP CENTER =====================
# (label, relative-to-HOME path, hint). Only entries that exist are reported.
# These are well-known regenerable cache/log/build-artifact locations — safe
# to trash (apps rebuild caches on demand; nothing here is source data).
CLEANUP_TARGETS = [
    ("User Caches", "Library/Caches",
     "Per-app caches — regenerated automatically; safe to clear individual subfolders"),
    ("User Logs", "Library/Logs",
     "App/system logs — safe to clear, only useful for active debugging"),
    ("Xcode DerivedData", "Library/Developer/Xcode/DerivedData",
     "Build artifacts — Xcode regenerates on next build"),
    ("Xcode Archives", "Library/Developer/Xcode/Archives",
     "Old app archives — keep only if you need to re-submit/re-symbolicate a past build"),
    ("iOS Simulators", "Library/Developer/CoreSimulator/Devices",
     "Simulator device images — `xcrun simctl delete unavailable` trims unused ones"),
    ("Homebrew Cache", "Library/Caches/Homebrew",
     "Downloaded package archives — `brew cleanup` territory, safe to clear"),
    ("npm Cache", ".npm",
     "Package download cache — `npm cache clean` territory, safe to clear"),
    ("pip/general Cache", ".cache",
     "pip wheels, other CLI tool caches — regenerated on next install"),
    ("iOS Device Backups", "Library/Application Support/MobileSync/Backup",
     "Full iPhone/iPad backups — only delete if you have a current backup elsewhere"),
    ("Trash", ".Trash",
     "Already-deleted files awaiting permanent removal — emptying frees this immediately"),
]


def scan_cleanup_targets():
    """Sizes for known regenerable cache/log/build locations (sudoless `du`,
    parallel). Only locations that exist are returned, sorted largest first."""
    import concurrent.futures
    existing = [(label, os.path.join(HOME, rel), rel, hint)
                for label, rel, hint in CLEANUP_TARGETS
                if os.path.exists(os.path.join(HOME, rel))]

    def _size(item):
        label, full, rel, hint = item
        size_str = run(f"du -sh {shlex.quote(full)} 2>/dev/null | cut -f1", timeout=30)
        size_mb = parse_size(size_str)
        if size_mb < 1:
            return None
        return {"label": label, "path": full, "rel": rel,
                "size_str": size_str or "—", "size_mb": size_mb, "hint": hint}

    with concurrent.futures.ThreadPoolExecutor(max_workers=min(8, os.cpu_count() or 4)) as ex:
        found = [r for r in ex.map(_size, existing) if r]
    found.sort(key=lambda x: -x["size_mb"])
    return found


# ===================== SMART STORAGE SCAN =====================
# Paid-cleaner-style analysis (CleanMyMac/DaisyDisk territory), sudoless.
# Safety levels: "safe" = regenerable, delete freely; "careful" = almost
# certainly unwanted but glance first; "review" = real data, human decision.

_INSTALLER_EXTS = (".dmg", ".pkg", ".iso", ".xip")
_DEV_JUNK_DIRS = ("node_modules", ".venv", "venv", ".tox", "target", ".gradle")
_STALE_PROJECT_DAYS = 60
_OLD_INSTALLER_DAYS = 30
_LARGE_OLD_DAYS = 180


def _expand_cache_dir(parent: str, category: str, hint: str,
                      min_mb: float = 10.0, top_n: int = 12) -> list[dict]:
    """Per-app subfolders of a cache/log dir as individual suggestions.
    Finder refuses to trash ~/Library/Caches itself (system-required dir),
    and granular rows tell you *which app* is hoarding space anyway."""
    import concurrent.futures
    try:
        with os.scandir(parent) as it:
            subdirs = [e.path for e in it if e.is_dir(follow_symlinks=False)]
    except OSError:
        return []

    def _size(p):
        sz = du_size_bytes(p)
        if not sz or sz / 1024 / 1024 < min_mb:
            return None
        mb = sz / 1024 / 1024
        return {"category": category, "label": os.path.basename(p),
                "path": p, "size_mb": mb, "size_str": fmt_mb(mb),
                "safety": "safe", "hint": hint}

    with concurrent.futures.ThreadPoolExecutor(max_workers=min(8, os.cpu_count() or 4)) as ex:
        out = [r for r in ex.map(_size, subdirs) if r]
    out.sort(key=lambda x: -x["size_mb"])
    return out[:top_n]


def _scan_regenerable() -> list[dict]:
    """Known cache/log/build locations (the old Cleanup tab targets).
    User Caches/Logs are expanded into per-app subfolders — the parent
    folders themselves can't be trashed (Finder: system-required dirs)."""
    review_labels = {"iOS Device Backups"}
    expand = {
        "User Caches": ("app caches",
                        "Per-app cache — regenerated automatically on next launch"),
        "User Logs": ("app logs",
                      "App log folder — only useful for active debugging"),
    }
    out = []
    for t in scan_cleanup_targets():
        if t["label"] in expand:
            category, hint = expand[t["label"]]
            out.extend(_expand_cache_dir(t["path"], category, hint))
            continue
        safety = "review" if t["label"] in review_labels else "safe"
        out.append({"category": "system junk",
                    "label": t["label"], "path": t["path"], "size_mb": t["size_mb"],
                    "size_str": t["size_str"], "safety": safety, "hint": t["hint"]})

    # Trash needs special handling: TCC hides ~/.Trash from du without Full
    # Disk Access, so the generic size scan drops it. Finder always knows the
    # item count — surface it so `e` (empty trash) is discoverable.
    if not any(r["label"] == "Trash" for r in out):
        t_size, t_count = trash_info()
        if t_count > 0 or (t_size or 0) >= 1:
            mb = t_size or 0.0
            out.append({"category": "system junk", "label": "Trash",
                        "path": os.path.join(HOME, ".Trash"), "size_mb": mb,
                        "size_str": fmt_mb(mb) if t_size else f"{t_count} items",
                        "safety": "safe",
                        "hint": "Press e to empty — only this actually frees disk space"})
    return out


def _scan_old_installers() -> list[dict]:
    """Installers in ~/Downloads older than a month — done with, almost always."""
    dl = os.path.join(HOME, "Downloads")
    out = []
    cutoff = time.time() - _OLD_INSTALLER_DAYS * 86400
    try:
        with os.scandir(dl) as it:
            for e in it:
                if not e.name.lower().endswith(_INSTALLER_EXTS):
                    continue
                try:
                    st = e.stat()
                except OSError:
                    continue
                if st.st_mtime > cutoff or st.st_size < 5 * 1024 * 1024:
                    continue
                mb = st.st_size / 1024 / 1024
                age_d = int((time.time() - st.st_mtime) / 86400)
                out.append({"category": "old installers", "label": e.name,
                            "path": e.path, "size_mb": mb, "size_str": fmt_mb(mb),
                            "safety": "careful",
                            "hint": f"Installer untouched {age_d}d — app already installed, image not needed"})
    except OSError:
        pass
    out.sort(key=lambda x: -x["size_mb"])
    return out[:12]


def _scan_dev_junk() -> list[dict]:
    """node_modules/.venv/target/... belonging to projects untouched for
    months — fully regenerable via npm install / pip install / build."""
    import concurrent.futures
    names = " -o ".join(f"-name {shlex.quote(n)}" for n in _DEV_JUNK_DIRS)
    cmd = (f"find {shlex.quote(HOME)} -maxdepth 6 "
           f"\\( -path {shlex.quote(HOME + '/Library')} -o -path {shlex.quote(HOME + '/.Trash')} "
           f"-o \\( -name '.*' ! -name '.venv' ! -name '.tox' \\) "
           f"-o -name miniforge -o -name miniconda3 -o -name anaconda3 \\) -prune "
           f"-o -type d \\( {names} \\) -print -prune 2>/dev/null")
    paths = [p for p in run(cmd, timeout=60).splitlines() if p.strip()]
    now = time.time()
    candidates = []
    for p in paths:
        project = os.path.dirname(p)
        try:
            # newest mtime among project-root entries = last real activity
            newest = max((os.lstat(os.path.join(project, n)).st_mtime
                          for n in os.listdir(project)
                          if n not in _DEV_JUNK_DIRS), default=0)
        except OSError:
            continue
        idle_d = int((now - newest) / 86400)
        if idle_d >= _STALE_PROJECT_DAYS:
            candidates.append((p, project, idle_d))
    candidates = candidates[:20]

    def _build(item):
        p, project, idle_d = item
        sz = du_size_bytes(p)
        if not sz or sz < 20 * 1024 * 1024:
            return None
        mb = sz / 1024 / 1024
        rel = os.path.relpath(p, HOME)
        return {"category": "stale dev junk", "label": rel,
                "path": p, "size_mb": mb, "size_str": fmt_mb(mb), "safety": "careful",
                "hint": f"Project idle {idle_d}d — regenerate with install/build when needed"}

    with concurrent.futures.ThreadPoolExecutor(max_workers=min(8, os.cpu_count() or 4)) as ex:
        out = [r for r in ex.map(_build, candidates) if r]
    out.sort(key=lambda x: -x["size_mb"])
    return out[:15]


def _scan_large_old() -> list[dict]:
    """Files >500MB not modified in 6 months — the forgotten disk hogs."""
    cmd = (f"find {shlex.quote(HOME)} -type f -size +500M -mtime +{_LARGE_OLD_DAYS} "
           f"-not -path '*/vm_bundles/*' -not -path '*/.Trash/*' "
           f"-not -path '*/Library/*' 2>/dev/null | head -25")
    out = []
    now = time.time()
    for p in run(cmd, timeout=45).splitlines():
        try:
            st = os.stat(p)
        except OSError:
            continue
        mb = st.st_size / 1024 / 1024
        age_d = int((now - st.st_mtime) / 86400)
        out.append({"category": "large & old", "label": os.path.basename(p),
                    "path": p, "size_mb": mb, "size_str": fmt_mb(mb),
                    "safety": "review",
                    "hint": f"{age_d}d since modified — archive or delete if no longer needed"})
    out.sort(key=lambda x: -x["size_mb"])
    return out[:12]


def smart_scan(force: bool = False) -> list[dict]:
    """Full smart-storage analysis — all category scanners in parallel,
    cached 5 min (the dev-junk find walk is the slow part).
    Returns suggestion rows sorted safe-first then largest-first."""
    if force:
        _cache.invalidate("smart_scan")
    return _cache.get("smart_scan", 300.0, _smart_scan_uncached)


def _smart_scan_uncached() -> list[dict]:
    import concurrent.futures
    scanners = [_scan_regenerable, _scan_old_installers, _scan_dev_junk, _scan_large_old]
    results: list[dict] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(scanners)) as ex:
        for fut in concurrent.futures.as_completed([ex.submit(s) for s in scanners]):
            try:
                results.extend(fut.result())
            except Exception:
                pass
    order = {"safe": 0, "careful": 1, "review": 2}
    results.sort(key=lambda x: (order.get(x["safety"], 3), -x["size_mb"]))
    return results


# ===================== APP UNINSTALLER =====================
APP_DIRS = ["/Applications", os.path.join(HOME, "Applications")]

# Standard per-user locations apps scatter files into, keyed by a format
# string taking either the bundle id or the app's display name.
LEFTOVER_GLOBS = [
    "Library/Application Support/{name}",
    "Library/Application Support/{bundle}",
    "Library/Caches/{bundle}",
    "Library/Caches/{name}",
    "Library/Preferences/{bundle}.plist",
    "Library/Saved Application State/{bundle}.savedState",
    "Library/Containers/{bundle}",
    "Library/HTTPStorages/{bundle}",
    "Library/WebKit/{bundle}",
    "Library/Logs/{name}",
    "Library/LaunchAgents/{bundle}.plist",
]


def list_apps():
    """Apps in /Applications and ~/Applications with sizes. The per-app `du`
    calls run in a bounded thread pool — sequential scanning took tens of
    seconds with 50+ apps."""
    import concurrent.futures
    paths = []
    for d in APP_DIRS:
        if not os.path.isdir(d):
            continue
        for name in sorted(os.listdir(d)):
            if name.endswith(".app"):
                paths.append((name[:-4], os.path.join(d, name)))

    def _size(item):
        name, full = item
        size_str = run(f"du -sh {shlex.quote(full)} 2>/dev/null | cut -f1", timeout=20)
        return {"name": name, "path": full,
                "size_str": size_str or "—", "size_mb": parse_size(size_str)}

    with concurrent.futures.ThreadPoolExecutor(max_workers=min(8, os.cpu_count() or 4)) as ex:
        apps = list(ex.map(_size, paths))
    apps.sort(key=lambda a: -a["size_mb"])
    return apps


def app_bundle_id(app_path: str) -> str:
    info_plist = os.path.join(app_path, "Contents", "Info")
    bid = run(f"defaults read '{info_plist}' CFBundleIdentifier 2>/dev/null", timeout=6)
    return bid.strip()


def find_app_leftovers(app_path: str, app_name: str):
    """Find per-user files an app likely scattered around — Application Support,
    Caches, Preferences, Containers, LaunchAgents, etc. — keyed by bundle id
    and display name. Sudoless (only scans the user's own ~/Library)."""
    bundle = app_bundle_id(app_path)
    leftovers = []
    seen = set()
    candidates = set()
    for tmpl in LEFTOVER_GLOBS:
        if "{bundle}" in tmpl and not bundle:
            continue
        candidates.add(tmpl.format(name=app_name, bundle=bundle))

    for rel in candidates:
        full = os.path.join(HOME, rel)
        if full in seen or not os.path.exists(full):
            continue
        seen.add(full)
        if os.path.isdir(full):
            size_str = run(f"du -sh {shlex.quote(full)} 2>/dev/null | cut -f1", timeout=15)
        else:
            try:
                size_str = fmt_mb(os.path.getsize(full) / 1024 / 1024)
            except OSError:
                size_str = "—"
        leftovers.append({"path": full, "rel": rel,
                          "size_str": size_str or "—", "size_mb": parse_size(size_str)})
    leftovers.sort(key=lambda x: -x["size_mb"])
    return {"bundle_id": bundle or "(unknown)", "leftovers": leftovers}


def delete_path(path: str) -> tuple[bool, str]:
    """Move a path to Trash (safe delete) — never hard-delete."""
    path = os.path.abspath(path)
    protected = ("vm_bundles" in path or "claudevm" in path
                 or path in (HOME, "/", os.path.join(HOME, "Library"),
                             os.path.join(HOME, ".Trash")))
    if protected:
        return False, f"Refusing to delete protected path: {path}"
    if not os.path.exists(path):
        return False, f"Path does not exist: {path}"
    # argv form (no shell) so paths with quotes/spaces can't break the script
    script = f'tell application "Finder" to delete POSIX file "{path}"'
    try:
        r = subprocess.run(["osascript", "-e", script],
                           capture_output=True, text=True, timeout=30)
        if r.returncode == 0 and "error" not in (r.stderr or "").lower():
            return True, f"Moved to Trash: {path}"
        finder_err = r.stderr.strip() or r.stdout.strip() or "Finder delete failed"
    except Exception as e:
        finder_err = str(e)

    # Fallback: Finder refuses some Library paths ("operation can't be
    # performed") even though the user owns them. Same-volume rename into
    # ~/.Trash is an instant, equally-recoverable move.
    trash = os.path.join(HOME, ".Trash")
    base = os.path.basename(path.rstrip("/")) or "item"
    dest = os.path.join(trash, base)
    if os.path.exists(dest):
        dest = os.path.join(trash, f"{base} {datetime.now().strftime('%H.%M.%S')}")
    try:
        os.rename(path, dest)
        return True, f"Moved to Trash: {path}"
    except OSError as e:
        return False, f"{finder_err} (fallback rename failed: {e.strerror})"


def trash_info() -> tuple[float | None, int]:
    """(size_mb or None, item_count) for ~/.Trash. macOS TCC blocks du/ls on
    .Trash unless the terminal has Full Disk Access, so size may be unknown —
    item count comes from Finder, which always has access to its own Trash."""
    size_mb = None
    out = run(f"du -sk {shlex.quote(os.path.join(HOME, '.Trash'))} 2>/dev/null", timeout=30)
    try:
        size_mb = int(out.split("\t", 1)[0]) / 1024
    except (ValueError, IndexError):
        pass
    cnt_out = run("osascript -e 'tell application \"Finder\" to count items of trash' 2>/dev/null",
                  timeout=15)
    try:
        count = int(cnt_out.strip())
    except ValueError:
        count = 0
    return size_mb, count


def empty_trash() -> tuple[bool, str]:
    """Permanently empty the Trash via Finder — this is the step that
    actually returns disk space to the volume."""
    size_mb, count = trash_info()
    try:
        r = subprocess.run(["osascript", "-e",
                            'tell application "Finder" to empty trash'],
                           capture_output=True, text=True, timeout=120)
    except Exception as e:
        return False, str(e)
    if r.returncode != 0:
        return False, (r.stderr.strip() or "Empty Trash failed")
    what = fmt_mb(size_mb) if size_mb else f"{count} item(s)"
    return True, f"Trash emptied — {what} returned to disk"


def reveal_in_finder(path: str) -> tuple[bool, str]:
    """Reveal (select) a path in Finder via `open -R` — sudoless, no delete."""
    import shlex
    if not os.path.exists(path):
        return False, f"Path does not exist: {path}"
    r = subprocess.run(f"open -R {shlex.quote(path)}", shell=True,
                       capture_output=True, text=True)
    if r.returncode != 0:
        return False, (r.stderr.strip() or "Could not reveal in Finder")
    return True, f"Revealed in Finder: {os.path.basename(path) or path}"

def get_process_details(pid: int) -> dict:
    """Fetch deep inspection details for a single process."""
    try:
        p = psutil.Process(pid)
        info = p.as_dict(attrs=[
            "pid", "ppid", "name", "cmdline", "status", "create_time", 
            "num_threads", "cpu_times", "num_ctx_switches", "memory_info", "username"
        ])
        
        cmdline = info.get("cmdline") or []
        args = " ".join(cmdline) if cmdline else (info.get("name") or "")
        comm = info.get("name") or (cmdline[0] if cmdline else "")
        role, cat, alarm, exp_max, fix = classify_proc(comm, args)
        
        # Format times
        import datetime
        try:
            created = datetime.datetime.fromtimestamp(info.get("create_time", 0)).strftime("%Y-%m-%d %H:%M:%S")
        except Exception:
            created = "Unknown"
            
        mem = info.get("memory_info")
        rss_mb = round((mem.rss if mem else 0) / 1024 / 1024, 1)
        vms_mb = round((mem.vms if mem else 0) / 1024 / 1024, 1)
        pfaults = getattr(mem, "pfaults", 0) if mem else 0
        
        cput = info.get("cpu_times")
        user_t = round(cput.user, 2) if cput else 0.0
        sys_t = round(cput.system, 2) if cput else 0.0
        
        ctx = info.get("num_ctx_switches")
        ctx_vol = ctx.voluntary if ctx else 0
        ctx_invol = ctx.involuntary if ctx else 0
        
        return {
            "pid": info.get("pid"),
            "ppid": info.get("ppid"),
            "user": info.get("username", "Unknown"),
            "comm": comm,
            "args": args,
            "status": info.get("status", "Unknown"),
            "created": created,
            "threads": info.get("num_threads", 0),
            "cpu_user_t": user_t,
            "cpu_sys_t": sys_t,
            "ctx_vol": ctx_vol,
            "ctx_invol": ctx_invol,
            "rss_mb": rss_mb,
            "vms_mb": vms_mb,
            "pfaults": pfaults,
            "role": role,
            "cat": cat,
            "fix": fix
        }
    except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
        return None

def get_network_details(pid: int) -> dict:
    """Fetch active connection sockets for a specific PID using nettop."""
    out = run(f"nettop -l 1 -x -J state,rtt_avg -p {pid} 2>/dev/null", timeout=5)
    
    connections = []
    for line in out.splitlines():
        if not line.startswith("   "):
            continue
        parts = line.strip().split()
        if len(parts) < 2:
            continue
            
        proto = parts[0]
        
        # Address parsing
        addrs = parts[1].split("<->")
        local = addrs[0]
        remote = addrs[1] if len(addrs) > 1 else ""
        
        state = ""
        latency = ""
        
        rest = parts[2:]
        if rest:
            # If the first item of rest is alphabetic, it's state (e.g. Established)
            if rest[0].isalpha():
                state = rest[0]
            
            # If the last item is 'ms', then the last two form latency
            if rest[-1] == "ms" and len(rest) >= 2:
                latency = f"{rest[-2]} ms"
                
        connections.append({
            "proto": proto.upper(),
            "local": local,
            "remote": remote,
            "state": state.upper(),
            "latency": latency
        })
        
    return {"connections": connections}


# ===================== LIGHTWEIGHT DASHBOARD HELPERS =====================
_net_light_prev: tuple[object, float] | None = None


def collect_network_light() -> dict:
    """System-wide throughput only — psutil, no subprocess, ~instant.
    Returns sent_kb_s, recv_kb_s, total_sent_mb, total_recv_mb."""
    global _net_light_prev
    cur = psutil.net_io_counters()
    now = time.time()
    if _net_light_prev is None:
        sent_kb_s = recv_kb_s = 0.0
    else:
        prev, prev_t = _net_light_prev
        dt = now - prev_t
        sent_kb_s = max(0.0, (cur.bytes_sent - prev.bytes_sent) / dt / 1024) if dt > 0 else 0.0
        recv_kb_s = max(0.0, (cur.bytes_recv - prev.bytes_recv) / dt / 1024) if dt > 0 else 0.0
    _net_light_prev = (cur, now)
    return {
        "sent_kb_s": round(sent_kb_s, 1),
        "recv_kb_s": round(recv_kb_s, 1),
        "total_sent_mb": round(cur.bytes_sent / 1e6),
        "total_recv_mb": round(cur.bytes_recv / 1e6),
    }


def top_processes_fast(n: int = 20) -> list[dict]:
    """Top N processes by CPU — minimal psutil attrs, no subprocess, ~50ms."""
    procs = []
    for p in psutil.process_iter(["pid", "name", "username", "cpu_percent", "memory_info"]):
        try:
            info = p.info
            cpu = info.get("cpu_percent") or 0.0
            mem = info.get("memory_info")
            rss_mb = round((mem.rss if mem else 0) / 1024 / 1024)
            procs.append({
                "pid": info["pid"],
                "name": (info.get("name") or "?")[:25],
                "user": (info.get("username") or "?")[:10],
                "cpu": round(cpu, 1),
                "rss_mb": rss_mb,
            })
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
            continue
    procs.sort(key=lambda p: -p["cpu"])
    return procs[:n]

