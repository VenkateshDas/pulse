"""
PulseToolkit — Agno Toolkit exposing Pulse CLI commands and operations.
Provides typed, structured interfaces to macOS kernel metrics, storage,
diagnostics, clean catalog, app uninstaller, displays, and keep-awake assertions.
"""

import json
import os
import shutil
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Optional

from agno.tools import Toolkit, tool


def find_pulse_cli() -> str:
    """Locate the Pulse CLI binary."""
    configured_cli = os.environ.get("PULSE_CLI_PATH")
    if configured_cli and Path(configured_cli).is_file() and os.access(configured_cli, os.X_OK):
        return configured_cli

    # Check repo dist first
    repo_root = Path(__file__).resolve().parent.parent
    dist_cli = repo_root / "pulse" / "dist" / "cli" / "pulse"
    if dist_cli.is_file() and os.access(dist_cli, os.X_OK):
        return str(dist_cli)

    # Check PATH
    which_cli = shutil.which("pulse")
    if which_cli:
        return which_cli

    # Fallback to local build path
    built_cli = repo_root / "pulse" / ".build" / "release" / "pulse"
    if built_cli.is_file() and os.access(built_cli, os.X_OK):
        return str(built_cli)

    return str(dist_cli)


class PulseToolkit(Toolkit):
    def __init__(self, cli_path: Optional[str] = None, **kwargs):
        self.cli_path = cli_path or find_pulse_cli()
        # Preview is a real safety precondition, not a prompt suggestion.
        # State is intentionally process-local: a restarted sidecar requires a
        # fresh scan, avoiding stale-path commits after the filesystem changed.
        self.previewed_clean_targets: set[str] = set()
        self.previewed_apps: set[str] = set()
        self.previewed_quits: set[tuple[int, str]] = set()

        tools = [
            self.observe_performance,
            self.inspect_process,
            self.inspect_network,
            self.get_diagnostic_history,
            self.get_startup_inventory,
            self.preview_application_quit,
            self.quit_application,
            self.diagnose,
            self.get_top_processes,
            self.get_process_tree,
            self.get_anomalies,
            self.get_vitals,
            self.get_sensors,
            self.get_attention,
            self.inspect_storage_growth,
            self.get_folder_verdict,
            self.find_duplicates,
            self.scan_clean_targets,
            self.clean_target,
            self.list_installed_apps,
            self.uninstall_app,
            self.list_undo_history,
            self.restore_undo_item,
            self.get_displays,
            self.set_display_brightness,
            self.get_sleep_status,
            self.set_keep_awake,
            self.get_cached_speedtest,
        ]

        super().__init__(
            name="pulse_toolkit",
            tools=tools,
            # Server-enforced HITL. Prompt instructions are not an authority
            # boundary; all mutations pause before the tool receives control.
            requires_confirmation_tools=[
                "quit_application",
                "clean_target",
                "uninstall_app",
                "restore_undo_item",
                "set_display_brightness",
                "set_keep_awake",
            ],
            **kwargs,
        )

    def _run_cmd(self, args: List[str], timeout: int = 30) -> Dict[str, Any]:
        """Execute a pulse CLI command with --json output and return parsed result."""
        cmd = [self.cli_path] + args + ["--json"]
        try:
            res = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=timeout,
                check=False,
            )
            stdout = res.stdout.strip()
            if not stdout:
                if res.stderr:
                    return {"error": res.stderr.strip(), "exitCode": res.returncode}
                return {"error": "Pulse returned no JSON", "exitCode": res.returncode}
            try:
                data = json.loads(stdout)
                if res.returncode:
                    if isinstance(data, dict):
                        data["exitCode"] = res.returncode
                        data.setdefault("error", "Pulse reported failure or partial completion")
                        return data
                    return {"result": data, "exitCode": res.returncode, "error": "Pulse reported failure or partial completion"}
                return data
            except json.JSONDecodeError:
                return {
                    "rawOutput": stdout,
                    "stderr": res.stderr.strip(),
                    "exitCode": res.returncode,
                }
        except subprocess.TimeoutExpired:
            return {"error": f"Command timed out after {timeout}s", "args": args}
        except Exception as e:
            return {"error": str(e), "args": args}

    def observe_performance(self, seconds: int = 30) -> Dict[str, Any]:
        """Observe synchronized CPU, pressure, swapping, disk activity and app contributors.
        2...600 seconds; no background monitoring. Repeat after a targeted change."""
        if not 2 <= seconds <= 600:
            return {"error": "seconds must be 2...600"}
        return self._run_cmd(["observe", "--seconds", str(seconds)], timeout=seconds + 20)

    def inspect_process(self, pid: int) -> Dict[str, Any]:
        """Inspect native executable, parent PID, exact startToken, browser role and memory footprint.
        Never treat a PID in an old anomaly as current process identity."""
        return self._run_cmd(["process", str(pid)])

    def inspect_network(self, url: Optional[str] = None) -> Dict[str, Any]:
        """Read Wi-Fi/proxy/primary-interface context. Optional selected URL sends one
        bounded HTTP(S) HEAD request without browser cookies or redirects, not a speed test."""
        args = ["network"]
        if url is not None:
            args += ["--url", url]
        return self._run_cmd(args)

    def get_diagnostic_history(self, hours: int = 24) -> Dict[str, Any]:
        """Read anomalies, observed minute metrics, battery sessions and storage snapshots.
        Empty/unobserved history is not evidence of a healthy interval. Returns latest
        60 observed points per metric, 20 anomalies and 10 sessions with availability counts;
        the native history CLI retains complete evidence for export."""
        result = self._run_cmd(["history", "--hours", str(hours)])
        if not isinstance(result, dict) or result.get("error"):
            return result
        coverage = {}
        for name, entries in result.get("metrics", {}).items():
            coverage[name] = {"observedMinutes": len(entries), "returnedMinutes": min(60, len(entries))}
            result["metrics"][name] = entries[-60:]
        result["agentOutputLimits"] = {"metrics": coverage,
            "anomaliesAvailable": len(result.get("anomalies", [])),
            "batterySessionsAvailable": len(result.get("batterySessions", []))}
        result["anomalies"] = result.get("anomalies", [])[:20]
        result["batterySessions"] = result.get("batterySessions", [])[-10:]
        return result

    def get_startup_inventory(self) -> Dict[str, Any]:
        """Read configured launch agents/daemons and missing executable clues.
        Read-only plist inventory; not proof of loaded jobs or a full login-item inventory."""
        return self._run_cmd(["startup"])

    def preview_application_quit(self, pid: int, start_token: str) -> Dict[str, Any]:
        """Preview graceful application quit using the exact startToken from inspection.
        This is read only. Save prompts may need user attention; helpers/system apps refused."""
        result = self._run_cmd(["quit", str(pid), "--started-at", start_token, "--dry-run"])
        if not result.get("error"):
            self.previewed_quits.add((pid, start_token))
        return result

    def quit_application(self, pid: int, start_token: str) -> Dict[str, Any]:
        """After preview and human approval, ask this exact application to quit normally.
        Never force quits; inspect terminated status and re-observe to verify improvement."""
        key = (pid, start_token)
        if key not in self.previewed_quits:
            return {"error": "Preview this exact application identity before quitting"}
        self.previewed_quits.discard(key)
        return self._run_cmd(["quit", str(pid), "--started-at", start_token, "--yes"])

    def diagnose(self) -> Dict[str, Any]:
        """
        Run system health diagnosis.
        Returns score (0-100), verdict, severity, band (excellent/good/fair/poor/critical),
        culprit process (if any), and penalty deductions.
        """
        return self._run_cmd(["diagnose"])

    def get_top_processes(self, by: str = "cpu", limit: int = 5, grouped: bool = False) -> Any:
        """
        Fetch top resource-consuming processes.
        Args:
            by: Sort criteria, either 'cpu' or 'mem'. Defaults to 'cpu'.
            limit: Maximum number of processes to return (1-20). Defaults to 5.
        """
        valid_by = "mem" if by.lower().startswith("mem") else "cpu"
        clamped_limit = max(1, min(20, limit))
        return self._run_cmd(["procs", "--by", valid_by, "--limit", str(clamped_limit)] + (["--grouped"] if grouped else []))

    def get_process_tree(self) -> Dict[str, Any]:
        """Inspect the readable parent-child process tree and collection coverage."""
        return self._run_cmd(["procs", "--tree"])

    def get_anomalies(self, hours: int = 24) -> Any:
        """
        Retrieve historical sustained-CPU anomaly records observed by Pulse.
        Args:
            hours: Lookback window in hours (default 24).
        """
        return self._run_cmd(["anomalies", "--hours", str(hours)])

    def get_vitals(self, lite: bool = True) -> Dict[str, Any]:
        """
        Sample current real-time system vitals:
        CPU (efficiency, performance, load averages), memory pressure and usage,
        disk usage and growth, network rates, battery level, thermal state, and GPU utilization.
        Args:
            lite: If True, skips process enumeration for faster, lighter sampling.
        """
        args = ["vitals"]
        if lite:
            args.append("--lite")
        return self._run_cmd(args)

    def get_sensors(self) -> Dict[str, Any]:
        """
        Report hardware sensors: temperatures (CPU/GPU/enclosure), fan speeds (RPM),
        and battery health (cycle count, health percentage, charging state).
        """
        return self._run_cmd(["sensors"])

    def get_attention(self) -> Any:
        """
        Return prioritized, actionable attention alerts detected on the Mac.
        """
        return self._run_cmd(["attention"])

    def inspect_storage_growth(self, days: int = 1, limit: int = 5) -> Any:
        """
        Inspect recent storage growth and modified files on the disk.
        Args:
            days: Days of recent growth to examine (1-30). Default is 1.
            limit: Top entries to list. Default is 5.
        """
        return self._run_cmd(["growth", "--days", str(days), "--limit", str(limit)], timeout=60)

    def get_folder_verdict(self, path: str) -> Dict[str, Any]:
        """
        Analyze a specific directory to provide storage composition, file breakdown,
        and safe reclaimability guidance.
        Args:
            path: Absolute path to the folder to analyze.
        """
        return self._run_cmd(["verdict", path], timeout=45)

    def find_duplicates(self, directory: str, min_size_mb: int = 1) -> Any:
        """
        Find exact duplicate files grouped by BLAKE3 hash without deleting anything.
        Args:
            directory: Absolute path to search for duplicates.
            min_size_mb: Minimum file size in megabytes to inspect (default 1).
        """
        return self._run_cmd(["duplicates", directory, "--min-size-mb", str(min_size_mb)], timeout=60)

    def scan_clean_targets(self) -> Any:
        """
        Scan safe and caution cleanup targets (caches, logs, dev caches, AI tool caches).
        Returns list of targets with target ID, grade (safe/caution), sizeBytes, and refusals.
        """
        return self._run_cmd(["clean", "--scan"])

    def clean_target(self, target_id: str, dry_run: bool = True) -> Dict[str, Any]:
        """
        Preview or perform safe cleanup of a specific target from scan_clean_targets.
        Items are moved to system Trash with undo journal entries.
        NOTE: Mutating cleanup (dry_run=False) requires human confirmation.

        Args:
            target_id: Exact target ID or path from scan_clean_targets.
            dry_run: If True (default), previews paths and bytes without deleting.
                     Set to False ONLY after explicit user confirmation.
        """
        if not dry_run and target_id not in self.previewed_clean_targets:
            return {"error": "Preview this cleanup target before committing it."}
        flag = "--dry-run" if dry_run else "--yes"
        result = self._run_cmd(["clean", "--target", target_id, flag])
        if dry_run and not result.get("error") and not result.get("failures"):
            self.previewed_clean_targets.add(target_id)
        return result

    def list_installed_apps(self) -> Any:
        """
        List all installed applications eligible for inspection and uninstallation.
        """
        return self._run_cmd(["uninstall", "--list"])

    def uninstall_app(self, app_path_or_name: str, dry_run: bool = True) -> Dict[str, Any]:
        """
        Preview or perform uninstallation of an application bundle and its leftovers.
        Protected apps are refused. Moves bundle and leftovers to Trash/Vault with undo journal.
        NOTE: Mutating uninstall (dry_run=False) requires human confirmation.

        Args:
            app_path_or_name: Exact app name, bundle ID, or path (e.g. '/Applications/Slack.app').
            dry_run: If True (default), previews bundle and leftovers without deleting.
                     Set to False ONLY after explicit user confirmation.
        """
        if not dry_run and app_path_or_name not in self.previewed_apps:
            return {"error": "Preview this app removal before committing it."}
        flag = "--dry-run" if dry_run else "--yes"
        result = self._run_cmd(["uninstall", app_path_or_name, flag])
        if dry_run and not result.get("error") and not result.get("failures"):
            self.previewed_apps.add(app_path_or_name)
        return result

    def list_undo_history(self) -> Any:
        """
        List recent destructive clean/uninstall operations logged in the UndoJournal.
        Each entry has a UUID, timestamp, action type, affected paths, and restore status.
        """
        return self._run_cmd(["undo", "list"])

    def restore_undo_item(self, uuid: str) -> Dict[str, Any]:
        """
        Restore trashed files from a previous clean or uninstall operation using its UUID.
        Args:
            uuid: Full UUID from list_undo_history.
        """
        return self._run_cmd(["undo", "restore", uuid])

    def get_displays(self) -> Dict[str, Any]:
        """
        Get connected displays, their display IDs, built-in status, and current brightness (-1.0 to 1.0).
        """
        return self._run_cmd(["display", "get"])

    def set_display_brightness(self, brightness: float, display_id: Optional[int] = None) -> Dict[str, Any]:
        """
        Adjust monitor brightness. Values from 0.0 to 1.0 control hardware brightness.
        Negative values down to -1.0 activate Pulse's sub-zero software dimmer.
        Args:
            brightness: Target brightness between -1.0 and 1.0.
            display_id: Optional display ID from get_displays(). Omit to target all displays.
        """
        clamped = max(-1.0, min(1.0, float(brightness)))
        args = ["display", "set", str(clamped)]
        if display_id is not None:
            args.extend(["--display", str(display_id)])
        return self._run_cmd(args)

    def get_sleep_status(self) -> Dict[str, Any]:
        """
        Check whether keep-awake assertion is currently active and its expiration deadline.
        """
        return self._run_cmd(["sleep", "status"])

    def set_keep_awake(self, until_seconds: Optional[int] = 900, allow: bool = False) -> Dict[str, Any]:
        """
        Manage system sleep prevention.
        Args:
            until_seconds: Duration in seconds to prevent sleep (e.g. 900 for 15m, 3600 for 1h).
            allow: If True, cancels sleep prevention and allows the Mac to sleep normally.
        """
        if allow:
            return self._run_cmd(["sleep", "allow"])
        duration = until_seconds if until_seconds is not None else 900
        return self._run_cmd(["sleep", "prevent", "--until", str(duration)])

    def get_cached_speedtest(self) -> Dict[str, Any]:
        """
        Retrieve latest network speed test results (download, upload, ping) recorded by Pulse.
        """
        return self._run_cmd(["speedtest", "--cached"])
