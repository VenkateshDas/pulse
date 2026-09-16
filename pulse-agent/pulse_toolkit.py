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

        tools = [
            self.diagnose,
            self.get_top_processes,
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
                return {"success": res.returncode == 0, "exitCode": res.returncode}
            try:
                data = json.loads(stdout)
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

    def diagnose(self) -> Dict[str, Any]:
        """
        Run system health diagnosis.
        Returns score (0-100), verdict, severity, band (excellent/good/fair/poor/critical),
        culprit process (if any), and penalty deductions.
        """
        return self._run_cmd(["diagnose"])

    def get_top_processes(self, by: str = "cpu", limit: int = 5) -> Any:
        """
        Fetch top resource-consuming processes.
        Args:
            by: Sort criteria, either 'cpu' or 'mem'. Defaults to 'cpu'.
            limit: Maximum number of processes to return (1-20). Defaults to 5.
        """
        valid_by = "mem" if by.lower().startswith("mem") else "cpu"
        clamped_limit = max(1, min(20, limit))
        return self._run_cmd(["procs", "--by", valid_by, "--limit", str(clamped_limit)])

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
        flag = "--dry-run" if dry_run else "--yes"
        return self._run_cmd(["clean", "--target", target_id, flag])

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
        flag = "--dry-run" if dry_run else "--yes"
        return self._run_cmd(["uninstall", app_path_or_name, flag])

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
