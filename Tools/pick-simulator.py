#!/usr/bin/env python3
"""Print the UDID of the newest available iPhone simulator.

CI runner images add and drop simulator models between updates, so the
workflow asks for whatever is actually installed rather than naming a model
that may have gone away.
"""
import json
import re
import subprocess
import sys


def main() -> int:
    raw = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "-j"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout

    candidates = []
    for runtime, devices in json.loads(raw)["devices"].items():
        match = re.search(r"iOS-(\d+)-(\d+)", runtime)
        if not match:
            continue
        version = (int(match.group(1)), int(match.group(2)))
        for device in devices:
            if device.get("isAvailable") and device["name"].startswith("iPhone"):
                candidates.append((version, device["name"], device["udid"]))

    if not candidates:
        print("No available iPhone simulator found", file=sys.stderr)
        return 1

    candidates.sort()
    version, name, udid = candidates[-1]
    print(f"Selected {name} on iOS {version[0]}.{version[1]} ({udid})", file=sys.stderr)
    print(udid)
    return 0


if __name__ == "__main__":
    sys.exit(main())
