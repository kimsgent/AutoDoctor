#!/usr/bin/env python3

import json
import re
from pathlib import Path
from datetime import datetime

# --------------------------------------------------
# PATH CONFIGURATION
# --------------------------------------------------

# --------------------------------------------------
# PATH CONFIGURATION
# --------------------------------------------------

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent

BASE_DIR = PROJECT_ROOT / "docs"

DATA_FILE = BASE_DIR / "data" / "changelog.json"
RELEASES_DIR = BASE_DIR / "content" / "releases"
ARCHIVE_DIR = BASE_DIR / "content" / "archive"

PROJECT_NAME = "AutoDoctor"

PRERELEASE_PATTERNS = [r"alpha", r"beta", r"rc", r"test", r"-test"]

# --------------------------------------------------
# HELPERS
# --------------------------------------------------


def is_prerelease(version: str) -> bool:
    v = version.lower()
    return any(re.search(p, v) for p in PRERELEASE_PATTERNS)


def load_changelog():
    if not DATA_FILE.exists():
        raise FileNotFoundError(f"Missing changelog file: {DATA_FILE}")

    with open(DATA_FILE, "r", encoding="utf-8") as f:
        return json.load(f)


def sort_versions(versions):
    return sorted(
        versions, key=lambda x: datetime.strptime(x["date"], "%Y-%m-%d"), reverse=True
    )


def format_release(version, date, changes, prerelease=False):
    lines = []

    lines.append(f"# {PROJECT_NAME} {version}")
    lines.append("")
    lines.append(f"Release date: {date}")
    lines.append("")

    if prerelease:
        lines.append("⚠ Pre-release / test version")
        lines.append("")

    lines.append("## Changes")
    lines.append("")

    for c in changes:
        lines.append(f"- {c}")

    lines.append("")

    return "\n".join(lines)


def write_release(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)

    with open(path, "w", encoding="utf-8") as f:
        f.write(content)


# --------------------------------------------------
# MAIN
# --------------------------------------------------


def main():

    data = load_changelog()

    versions = data.get("versions", [])
    if not versions:
        print("No versions found in changelog.")
        return

    versions = sort_versions(versions)

    latest = None

    for v in versions:
        if not is_prerelease(v["version"]):
            latest = v
            break

    if latest is None:
        latest = versions[0]

    for entry in versions:

        version = entry["version"]
        date = entry["date"]
        changes = entry.get("changes", [])

        prerelease = is_prerelease(version)

        filename = f"{version}.md"

        content = format_release(version, date, changes, prerelease)

        if entry == latest:
            path = RELEASES_DIR / filename
        else:
            path = ARCHIVE_DIR / filename

        write_release(path, content)

        print(f"Generated {path}")


if __name__ == "__main__":
    main()
