"""
PulseToolkit — Agno Toolkit exposing Pulse CLI commands and operations.
Provides typed, structured interfaces to macOS kernel metrics, storage,
diagnostics, clean catalog, app uninstaller, displays, and keep-awake assertions.
"""

import json
import os
import asyncio
import time
import uuid
from pathlib import Path
from typing import Any, Dict, List, Optional



class PulseToolkit:
    def __init__(self, run_id: str, session_id: str, **kwargs):
        self.run_id = run_id
        self.session_id = session_id
        self.evidence = {}
        self.previews = {}
        self.quit_previews = {}
        # Preview is a real safety precondition, not a prompt suggestion.
        # State is intentionally process-local: a restarted sidecar requires a
        # fresh scan, avoiding stale-path commits after the filesystem changed.
        self.previewed_clean_targets: set[str] = set()
        self.previewed_apps: set[str] = set()
        self.previewed_quits: set[tuple[int, str]] = set()

        tools = [
            self.read_current_context,
            self.observe_performance,
            self.inspect_process,
            self.inspect_network,
            self.get_diagnostic_history,
            self.get_startup_inventory,
            self.preview_application_quit,
            self.quit_application,
            self.check_performance,
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
            self.preview_cleanup,
            self.clean_target,
            self.list_installed_apps,
            self.preview_uninstall,
            self.uninstall_app,
            self.list_undo_history,
            self.preview_undo_item,
            self.restore_undo_item,
            self.get_displays,
            self.set_display_brightness,
            self.get_sleep_status,
            self.set_keep_awake,
            self.get_cached_speedtest,
            self.list_automations,
            self.create_automation,
            self.set_automation_enabled,
        ]

        self.tools = tools
        self.mutations = frozenset([
                "quit_application",
                "clean_target",
                "uninstall_app",
                "restore_undo_item",
                "set_display_brightness",
                "set_keep_awake",
                "create_automation",
                "set_automation_enabled",
            ])

    async def _run_cmd(self, args: List[str], timeout: int = 30) -> Any:
        """Closed native RPC. Never launches an executable or retries a mutation."""
        key = tuple(args)
        is_read = args[0] in {"vitals", "procs", "diagnose", "sensors", "attention", "startup"}
        cached = self.evidence.get(key)
        if is_read and cached and time.monotonic() - cached[0] < 2:
            return cached[1]
        try:
            response = await native_request(self.run_id, self.session_id, args, timeout)
            result = json.loads(response["json"])
            if response["exit_code"]:
                if not isinstance(result, dict): result = {"result": result}
                result["exitCode"] = response["exit_code"]
                result.setdefault("error", "Pulse reported failure or partial completion")
            if is_read: self.evidence[key] = (time.monotonic(), result)
            return result
        except (OSError, ValueError, asyncio.TimeoutError, KeyError):
            return {"error": "Native tool unavailable or timed out. Inspect state before retrying an action."}

    async def read_current_context(self) -> Any:
        """Read Pulse's latest timestamped snapshot without collecting or scanning again.
        Missing/stale samples are unknown. For sustained evidence use observation."""
        return await self._run_cmd(["context"])

    async def observe_performance(self, seconds: int = 30) -> Dict[str, Any]:
        """Observe synchronized CPU, pressure, swapping, disk activity and app contributors.
        2...600 seconds; no background monitoring. Repeat after a targeted change."""
        if not 2 <= seconds <= 600:
            return {"error": "seconds must be 2...600"}
        return await self._run_cmd(["observe", "--seconds", str(seconds)], timeout=seconds + 20)

    async def inspect_process(self, pid: int) -> Dict[str, Any]:
        """Inspect native executable, parent PID, exact startToken, browser role and memory footprint.
        Never treat a PID in an old anomaly as current process identity."""
        return await self._run_cmd(["process", str(pid)])

    async def inspect_network(self, url: Optional[str] = None) -> Dict[str, Any]:
        """Read Wi-Fi/proxy/primary-interface context. Optional selected URL sends one
        bounded HTTP(S) HEAD request without browser cookies or redirects, not a speed test."""
        args = ["network"]
        if url is not None:
            args += ["--url", url]
        return await self._run_cmd(args)

    async def get_diagnostic_history(self, hours: int = 24) -> Dict[str, Any]:
        """Read anomalies, observed minute metrics, battery sessions and storage snapshots.
        Empty/unobserved history is not evidence of a healthy interval. Returns latest
        60 observed points per metric, 20 anomalies and 10 sessions with availability counts;
        the native history CLI retains complete evidence for export."""
        result = await self._run_cmd(["history", "--hours", str(hours)])
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

    async def get_startup_inventory(self) -> Dict[str, Any]:
        """Read configured launch agents/daemons and missing executable clues.
        Read-only plist inventory; not proof of loaded jobs or a full login-item inventory."""
        return await self._run_cmd(["startup"])

    async def preview_application_quit(self, pid: int, start_token: str) -> Dict[str, Any]:
        """Preview graceful application quit using the exact startToken from inspection.
        This is read only. Save prompts may need user attention; helpers/system apps refused."""
        result = await self._run_cmd(["quit", str(pid), "--started-at", start_token, "--dry-run"])
        if not result.get("error"):
            self.previewed_quits.add((pid, start_token))
            self.quit_previews[(pid, start_token)] = (time.monotonic(), result)
        return result

    async def quit_application(self, pid: int, start_token: str) -> Dict[str, Any]:
        """After preview and human approval, ask this exact application to quit normally.
        Never force quits; inspect terminated status and re-observe to verify improvement."""
        key = (pid, start_token)
        if key not in self.previewed_quits:
            return {"error": "Preview this exact application identity before quitting"}
        self.previewed_quits.discard(key)
        preview = self.quit_previews.pop(key, None)
        if not preview or time.monotonic() - preview[0] > 300:
            return {"error": "Quit preview expired. Preview again."}
        return await self._run_cmd(["quit", str(pid), "--started-at", start_token, "--yes"])

    async def check_performance(self) -> dict:
        """Batch independent cheap health, vitals and busy-app reads concurrently.
        Use for general slowness; no sustained observation, storage scan or mutation."""
        diagnosis, vitals, processes = await asyncio.gather(self.diagnose(), self.get_vitals(), self.get_top_processes())
        return {"diagnosis": diagnosis, "vitals": vitals, "busy_apps": processes}

    async def diagnose(self) -> Dict[str, Any]:
        """
        Run system health diagnosis.
        Returns score (0-100), verdict, severity, band (excellent/good/fair/poor/critical),
        culprit process (if any), and penalty deductions.
        """
        return await self._run_cmd(["diagnose"])

    async def get_top_processes(self, by: str = "cpu", limit: int = 5, grouped: bool = False) -> Any:
        """
        Fetch top resource-consuming processes.
        Args:
            by: Sort criteria, either 'cpu' or 'mem'. Defaults to 'cpu'.
            limit: Maximum number of processes to return (1-20). Defaults to 5.
        """
        valid_by = "mem" if by.lower().startswith("mem") else "cpu"
        clamped_limit = max(1, min(20, limit))
        return await self._run_cmd(["procs", "--by", valid_by, "--limit", str(clamped_limit)] + (["--grouped"] if grouped else []))

    async def get_process_tree(self) -> Dict[str, Any]:
        """Inspect the readable parent-child process tree and collection coverage."""
        return await self._run_cmd(["procs", "--tree"])

    async def get_anomalies(self, hours: int = 24) -> Any:
        """
        Retrieve historical sustained-CPU anomaly records observed by Pulse.
        Args:
            hours: Lookback window in hours (default 24).
        """
        return await self._run_cmd(["anomalies", "--hours", str(hours)])

    async def get_vitals(self, lite: bool = True) -> Dict[str, Any]:
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
        return await self._run_cmd(args)

    async def get_sensors(self) -> Dict[str, Any]:
        """
        Report hardware sensors: temperatures (CPU/GPU/enclosure), fan speeds (RPM),
        and battery health (cycle count, health percentage, charging state).
        """
        return await self._run_cmd(["sensors"])

    async def get_attention(self) -> Any:
        """
        Return prioritized, actionable attention alerts detected on the Mac.
        """
        return await self._run_cmd(["attention"])

    async def inspect_storage_growth(self, days: int = 1, limit: int = 5) -> Any:
        """
        Inspect recent storage growth and modified files on the disk.
        Args:
            days: Days of recent growth to examine (1-30). Default is 1.
            limit: Top entries to list. Default is 5.
        """
        return await self._run_cmd(["growth", "--days", str(days), "--limit", str(limit)], timeout=60)

    async def get_folder_verdict(self, path: str) -> Dict[str, Any]:
        """
        Analyze a specific directory to provide storage composition, file breakdown,
        and safe reclaimability guidance.
        Args:
            path: Absolute path to the folder to analyze.
        """
        return await self._run_cmd(["verdict", path], timeout=45)

    async def find_duplicates(self, directory: str, min_size_mb: int = 1) -> Any:
        """
        Find exact duplicate files grouped by BLAKE3 hash without deleting anything.
        Args:
            directory: Absolute path to search for duplicates.
            min_size_mb: Minimum file size in megabytes to inspect (default 1).
        """
        return await self._run_cmd(["duplicates", directory, "--min-size-mb", str(min_size_mb)], timeout=60)

    async def scan_clean_targets(self) -> Any:
        """
        Scan safe and caution cleanup targets (caches, logs, dev caches, AI tool caches).
        Returns list of targets with target ID, grade (safe/caution), sizeBytes, and refusals.
        """
        return await self._run_cmd(["clean", "--scan"])

    async def clean_target(self, target_id: str) -> Dict[str, Any]:
        """
        Perform previously previewed cleanup of a specific target from scan_clean_targets.
        Items are moved to system Trash with undo journal entries.
        Requires a read-only preview and application-enforced human confirmation.

        Args:
            target_id: Exact target ID or path from scan_clean_targets.
        """
        if target_id not in self.previewed_clean_targets:
            return {"error": "Preview this cleanup target before committing it."}
        self.previewed_clean_targets.discard(target_id)
        return await self._commit_preview(["clean", "--target", target_id])

    async def preview_cleanup(self, target_id: str) -> Any:
        """Read-only preview of exact cleanup paths, bytes and refusals; never needs approval."""
        args = ["clean", "--target", target_id]
        result = await self._run_cmd(args + ["--dry-run"])
        if len(json.dumps(result)) > 32000:
            return {"error": "Preview too large to review. Select a narrower target."}
        if not result.get("error") and not result.get("failures"):
            self.previewed_clean_targets.add(target_id)
            self.previews[tuple(args)] = (time.monotonic(), result)
        return result

    async def list_installed_apps(self) -> Any:
        """
        List all installed applications eligible for inspection and uninstallation.
        """
        return await self._run_cmd(["uninstall", "--list"])

    async def uninstall_app(self, app_path_or_name: str) -> Dict[str, Any]:
        """
        Perform previously previewed uninstallation of an application bundle and its leftovers.
        Protected apps are refused. Moves bundle and leftovers to Trash with undo journal.
        Requires a read-only preview and application-enforced human confirmation.

        Args:
            app_path_or_name: Exact app name, bundle ID, or path (e.g. '/Applications/Slack.app').
        """
        if app_path_or_name not in self.previewed_apps:
            return {"error": "Preview this app removal before committing it."}
        self.previewed_apps.discard(app_path_or_name)
        return await self._commit_preview(["uninstall", app_path_or_name])

    async def preview_uninstall(self, app_path_or_name: str) -> Any:
        """Read-only preview of this exact app and eligible leftovers; never needs approval."""
        args = ["uninstall", app_path_or_name]
        result = await self._run_cmd(args + ["--dry-run"])
        if len(json.dumps(result)) > 32000:
            return {"error": "Preview too large to review. Select a narrower target."}
        if not result.get("error") and not result.get("failures"):
            self.previewed_apps.add(app_path_or_name)
            self.previews[tuple(args)] = (time.monotonic(), result)
        return result

    def approval_evidence(self, name: str, arguments: dict) -> dict:
        if name in {"create_automation", "set_automation_enabled"}:
            return {"arguments": arguments, "notice": "Automations run while Pulse is open, catch up a missed schedule once, and never wake a sleeping Mac. Future runs send requests to your selected provider and may incur charges. Scheduled investigations are read-only; changes need a fresh interactive review and approval."}
        key = None
        if name == "clean_target": key = ("clean", "--target", arguments.get("target_id", ""))
        if name == "uninstall_app": key = ("uninstall", arguments.get("app_path_or_name", ""))
        if name == "restore_undo_item": key = ("undo", arguments.get("uuid", ""))
        if key:
            preview = self.previews.get(key)
            return {"arguments": arguments, "preview": preview[1] if preview and time.monotonic()-preview[0] <= 300 else "Preview unavailable or expired. Execution will be refused."}
        if name == "quit_application":
            preview = self.quit_previews.get((arguments.get("pid"), arguments.get("start_token")))
            return {"arguments": arguments, "preview": preview[1] if preview else "Preview unavailable. Execution will be refused."}
        return {"arguments": arguments}

    async def _commit_preview(self, args: List[str]) -> Any:
        preview = self.previews.pop(tuple(args), None)
        if not preview or time.monotonic() - preview[0] > 300:
            return {"error": "Preview expired. Preview again before approving."}
        current = await self._run_cmd(args + ["--dry-run"])
        if current != preview[1]:
            return {"error": "Affected items changed since preview. Review a fresh preview."}
        return await self._run_cmd(args + ["--yes"])

    async def list_undo_history(self) -> Any:
        """
        List recent destructive clean/uninstall operations logged in the UndoJournal.
        Each entry has a UUID, timestamp, action type, affected paths, and restore status.
        """
        return await self._run_cmd(["undo", "list"])

    async def preview_undo_item(self, uuid: str) -> Any:
        """Preview exact original paths for one full undo UUID before approval."""
        entries = await self.list_undo_history()
        row = next((e for e in entries if e.get("id", "").lower() == uuid.lower()), None) if isinstance(entries, list) else None
        if not row or len(json.dumps(row)) > 32000:
            return {"error": "Undo entry unavailable or too large. Choose one full UUID."}
        self.previews[("undo", uuid)] = (time.monotonic(), row)
        return row

    async def restore_undo_item(self, uuid: str) -> Any:
        """Restore one previously previewed UUID after human approval; no retries."""
        preview = self.previews.pop(("undo", uuid), None)
        if not preview or time.monotonic()-preview[0] > 300:
            return {"error": "Preview this exact undo entry before restoring."}
        entries = await self.list_undo_history()
        row = next((e for e in entries if e.get("id", "").lower() == uuid.lower()), None) if isinstance(entries, list) else None
        if row != preview[1]: return {"error": "Undo entry changed. Review a fresh preview."}
        return await self._run_cmd(["undo", "restore", uuid])

    async def get_displays(self) -> Dict[str, Any]:
        """
        Get connected displays, their display IDs, built-in status, and current brightness (-1.0 to 1.0).
        """
        return await self._run_cmd(["display", "get"])

    async def set_display_brightness(self, brightness: float, display_id: Optional[int] = None) -> Dict[str, Any]:
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
        return await self._run_cmd(args)

    async def get_sleep_status(self) -> Dict[str, Any]:
        """
        Check whether keep-awake assertion is currently active and its expiration deadline.
        """
        return await self._run_cmd(["sleep", "status"])

    async def set_keep_awake(self, until_seconds: Optional[int] = 900, allow: bool = False) -> Dict[str, Any]:
        """
        Manage system sleep prevention.
        Args:
            until_seconds: Duration in seconds to prevent sleep (e.g. 900 for 15m, 3600 for 1h).
            allow: If True, cancels sleep prevention and allows the Mac to sleep normally.
        """
        if allow:
            return await self._run_cmd(["sleep", "allow"])
        duration = until_seconds if until_seconds is not None else 900
        return await self._run_cmd(["sleep", "prevent", "--until", str(duration)])

    async def get_cached_speedtest(self) -> Dict[str, Any]:
        """
        Retrieve latest network speed test results (download, upload, ping) recorded by Pulse.
        """
        return await self._run_cmd(["speedtest", "--cached"])

    async def list_automations(self) -> Any:
        """List Pulse's saved automations and schedules without changing them."""
        return await self._run_cmd(["automation", "list"])

    async def create_automation(self, title: str, instructions: str, timezone_id: str,
                                repeat_rule: str = "daily", hour: int = 9, minute: int = 0,
                                weekday: int = 2, once_at: str = "") -> Any:
        """After human approval, schedule a read-only Mac investigation. Supply the user's
        explicit IANA timezone (never infer it); repeat once/daily/weekdays/weekly.
        Hour 0–23, minute 0–59, weekday 1=Sunday through 7=Saturday.
        For once, supply once_at as a future ISO8601 date with timezone offset.
        Pulse must remain open; future provider requests may incur charges."""
        if not all(isinstance(value, str) for value in (title, instructions, timezone_id, repeat_rule, once_at)):
            return {"error": "Supply text for automation name, instructions, timezone and schedule"}
        title, instructions, timezone_id = title.strip(), instructions.strip(), timezone_id.strip()
        if not 1 <= len(title) <= 80 or not instructions or len(instructions.encode('utf-8')) > 2500:
            return {"error": "Use a name of 1–80 characters and instructions of 1–2,500 UTF-8 bytes"}
        if not timezone_id or len(timezone_id) > 100:
            return {"error": "Supply the user's explicit timezone ID, at most 100 characters"}
        if repeat_rule not in {"once", "daily", "weekdays", "weekly"}:
            return {"error": "Repeat must be once, daily, weekdays or weekly"}
        if any(type(value) is not int for value in (hour, minute, weekday)) or not (0 <= hour <= 23 and 0 <= minute <= 59 and 1 <= weekday <= 7):
            return {"error": "Use integer hour 0–23, minute 0–59 and weekday 1–7"}
        once_at = once_at.strip()
        if len(once_at) > 100 or (repeat_rule == "once" and not once_at):
            return {"error": "A one-time schedule requires a future ISO8601 date, at most 100 characters"}
        payload = {"title": title, "instructions": instructions, "repeatRule": repeat_rule,
                   "hour": hour, "minute": minute, "weekday": weekday,
                   "timezoneID": timezone_id, "onceAt": once_at}
        encoded = json.dumps(payload, separators=(',', ':'), ensure_ascii=False)
        if len(encoded.encode('utf-8')) > 4096:
            return {"error": "Automation exceeds the 4,096-byte request limit"}
        return await self._run_cmd(["automation", "create", encoded])

    async def set_automation_enabled(self, automation_id: str, enabled: bool) -> Any:
        """After human approval, pause or resume one exact automation UUID from list_automations.
        Resuming permits future read-only provider requests, which may incur charges."""
        if not isinstance(automation_id, str) or type(enabled) is not bool:
            return {"error": "Supply an automation UUID and boolean enabled value"}
        try: identifier = str(uuid.UUID(automation_id))
        except ValueError: return {"error": "Supply an automation UUID"}
        return await self._run_cmd(["automation", "set_enabled", json.dumps({"id": identifier, "enabled": enabled}, separators=(',', ':'))])


async def native_request(run_id: str, session_id: str, arguments: list[str], timeout: int = 30, cancel: bool = False) -> dict:
    port = int(os.environ["PULSE_NATIVE_PORT"])
    payload = {"version": 1, "token": os.environ["PULSE_NATIVE_TOKEN"],
               "request_id": str(uuid.uuid4()), "run_id": run_id, "session_id": session_id,
               "arguments": arguments, "cancel": cancel}
    async with asyncio.timeout(timeout):
        reader, writer = await asyncio.open_connection("127.0.0.1", port, limit=8_000_000)
        try:
            writer.write(json.dumps(payload).encode() + b"\n")
            await writer.drain()
            raw = await reader.readline()
            response = json.loads(raw)
            if response.get("request_id") != payload["request_id"]: raise ValueError("RPC identity mismatch")
            return response
        finally:
            writer.close()
            await writer.wait_closed()
