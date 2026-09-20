"""
Context Provider & System Vitals Injection for Pulse AI Agent.
Injects real-time hardware status into the Agent's context prefix so the model
understands the local machine environment without wasting tool calls.
"""

import json
import os
import platform
import subprocess
from typing import Any, Dict, Optional

from pulse_toolkit import find_pulse_cli


def get_system_vitals_summary() -> Dict[str, Any]:
    """Retrieve quick system vitals and diagnosis for prompt augmentation."""
    cli = find_pulse_cli()
    summary = {
        "os": f"macOS {platform.mac_ver()[0]} ({platform.machine()})",
        "hostname": platform.node(),
    }

    # Try quick vitals
    try:
        res = subprocess.run(
            [cli, "vitals", "--lite", "--json"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
        if res.returncode == 0 and res.stdout.strip():
            vitals = json.loads(res.stdout.strip())
            summary["cpu_usage_pct"] = vitals.get("cpu", {}).get("totalPercent")
            summary["memory_used_fraction"] = vitals.get("memory", {}).get("usedFraction")
            summary["memory_pressure"] = vitals.get("memory", {}).get("pressure")
            summary["disk_used_fraction"] = vitals.get("disk", {}).get("usedFraction")
            summary["battery_pct"] = vitals.get("battery", {}).get("levelPercent")
            summary["battery_charging"] = vitals.get("battery", {}).get("isCharging")
            summary["thermal_state"] = vitals.get("thermal")
    except Exception:
        pass

    # Try quick diagnosis
    try:
        res = subprocess.run(
            [cli, "diagnose", "--json"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
        if res.returncode == 0 and res.stdout.strip():
            diag = json.loads(res.stdout.strip())
            summary["health_score"] = diag.get("score")
            summary["health_verdict"] = diag.get("verdict")
            summary["health_severity"] = diag.get("severity")
            summary["health_culprit"] = diag.get("culprit")
    except Exception:
        pass

    return summary


def build_system_instructions(vitals: Optional[Dict[str, Any]] = None) -> str:
    """Build high-signal system instructions with live hardware context."""
    vitals_data = vitals or get_system_vitals_summary()
    vitals_block = "\n".join(f"  - {k}: {v}" for k, v in vitals_data.items() if v is not None)

    return f"""You are Pulse AI, the intelligent command center assistant for macOS.
You operate directly on the user's Mac, with access to real-time kernel telemetry, storage diagnostics, process management, clean catalog, and display/sleep controls via the Pulse Skill and PulseToolkit.

CURRENT SYSTEM CONTEXT:
{vitals_block}

CORE PRINCIPLES & CONSTRAINTS:
1. ACCURACY OVER GUESSWORK: Always inspect real kernel metrics using your tools. Do not invent process names, disk sizes, or health scores.
2. SAFETY-FIRST MUTATIONS:
   - For cleanup (`clean_target`) and app uninstallation (`uninstall_app`): ALWAYS call with `dry_run=True` first to preview affected paths, bytes, and refusals.
   - Present the dry-run findings clearly to the user before requesting execution confirmation.
   - Destructive operations require explicit human confirmation.
3. CLEAR FORMATTING:
   - Format storage sizes using human-readable units (MB, GB).
   - Use Markdown tables or bullet points for process and storage breakdowns.
   - When diagnosing issues, highlight the culprit process and give concrete remediation advice.
4. DISPLAY & SLEEP CONTROLS:
   - Brightness ranges from -1.0 (sub-zero software dimmer) to 1.0 (maximum hardware brightness).
   - Sleep prevention default is 900 seconds (15 minutes). Always state the active duration.
5. CONVERSATION CONTEXT:
   - The session summary contains verified earlier findings and decisions.
   - Use get_chat_history only when a specific older detail is required. Do not retrieve history for ordinary follow-ups.
"""
