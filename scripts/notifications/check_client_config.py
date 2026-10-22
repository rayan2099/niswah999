#!/usr/bin/env python3
"""Validate public Flutter push configuration without echoing any value."""
import argparse
import json
import re
from pathlib import Path

def validate(data, platform="both"):
    if not isinstance(data, dict):
        raise ValueError("Configuration must be a JSON object")
    if any(any(word in key.upper() for word in ("PRIVATE_KEY", "SERVICE_ACCOUNT", "SERVICE_ROLE", "SECRET", "PASSWORD")) for key in data):
        raise ValueError("Server credentials must never be included in Flutter configuration")
    if data.get("NISWAH_PUSH_ENABLED") is not True:
        raise ValueError("NISWAH_PUSH_ENABLED must be true for a push-enabled release")
    for field in ("FIREBASE_PROJECT_ID", "FIREBASE_MESSAGING_SENDER_ID", "FIREBASE_API_KEY"):
        if not isinstance(data.get(field), str) or not data[field].strip():
            raise ValueError(f"Missing or invalid {field}")
    if not re.fullmatch(r"[a-z][a-z0-9-]{4,61}[a-z0-9]", data["FIREBASE_PROJECT_ID"]):
        raise ValueError("Invalid FIREBASE_PROJECT_ID")
    sender = data["FIREBASE_MESSAGING_SENDER_ID"]
    if not sender.isdigit():
        raise ValueError("Invalid FIREBASE_MESSAGING_SENDER_ID")
    platforms = ("android", "ios") if platform == "both" else (platform,)
    for item in platforms:
        field = f"FIREBASE_{item.upper()}_APP_ID"
        if not re.fullmatch(rf"1:{re.escape(sender)}:{item}:[A-Za-z0-9]+", str(data.get(field, ""))):
            raise ValueError(f"Invalid {field}; use the registered mobile app, not a web app")

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("config", type=Path)
    parser.add_argument("--platform", choices=("android", "ios", "both"), default="both")
    args = parser.parse_args()
    try:
        validate(json.loads(args.config.read_text()), args.platform)
    except (ValueError, OSError):
        # Never print parse exceptions: they can contain a copied credential.
        parser.exit(1, "Push client configuration is invalid. Check the documented public fields; keep server credentials out.\n")
    print("Public push configuration passed structural checks; provider delivery still requires verification.")

if __name__ == "__main__":
    main()
