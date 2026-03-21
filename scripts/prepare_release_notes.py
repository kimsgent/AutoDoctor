#!/usr/bin/env python3

import json
import sys
from pathlib import Path
import subprocess
import shutil
import re


# --------------------------------------------------
# PATH CONFIGURATION
# --------------------------------------------------

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent

DOCS_DIR = PROJECT_ROOT / "docs"

RELEASES_DIR = DOCS_DIR / "content" / "releases"
ARCHIVE_DIR = DOCS_DIR / "content" / "archive"
CHANGELOG_FILE = DOCS_DIR / "data" / "changelog.json"

NOTES_FILE = PROJECT_ROOT / "RELEASE_NOTES.md"


# --------------------------------------------------
# HELPERS
# --------------------------------------------------


def release_exists(version: str) -> bool:
    """Check if a GitHub release already exists."""
    if shutil.which("gh") is None:
        return False

    result = subprocess.run(
        ["gh", "release", "view", version],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    return result.returncode == 0


def is_special_version(version: str) -> bool:
    """Detect prerelease or dry-run versions."""
    return bool(re.search(r"-(test|alpha|beta|rc)", version, re.IGNORECASE))


def find_release_file(version: str):
    """Locate release markdown file."""
    release_path = RELEASES_DIR / f"{version}.md"
    archive_path = ARCHIVE_DIR / f"{version}.md"

    if release_path.exists():
        return release_path

    if archive_path.exists():
        return archive_path

    return None


# --------------------------------------------------
# MAIN
# --------------------------------------------------


def main():

    if len(sys.argv) < 2:
        print("Usage: prepare_release_notes.py <version>")
        sys.exit(1)

    version = sys.argv[1]  # example: v1.1.0 or v1.1.0-test

    # ---------------------------------------------
    # ALWAYS generate release notes
    # ---------------------------------------------

    try:
        release_file = find_release_file(version)

        if release_file:
            print(f"INFO: Using {release_file} for release notes")
            content = release_file.read_text(encoding="utf-8")
            NOTES_FILE.write_text(content, encoding="utf-8")
            return

        print("WARNING: Release markdown not found, falling back to changelog.json")

        if CHANGELOG_FILE.exists():
            data = json.loads(CHANGELOG_FILE.read_text(encoding="utf-8"))

            for v in data.get("versions", []):
                if "v" + v["version"] == version:
                    content = [
                        f"# AutoDoctor {version}",
                        "",
                        f"Release date: {v['date']}",
                        "",
                        "## Changes",
                        "",
                    ]
                    content += [f"- {c}" for c in v["changes"]]

                    NOTES_FILE.write_text("\n".join(content), encoding="utf-8")
                    return

        # fallback of last resort
        NOTES_FILE.write_text(
            f"# AutoDoctor {version}\n\nNo release notes available.", encoding="utf-8"
        )

    except Exception as e:
        print(f"ERROR: {e}")
        NOTES_FILE.write_text(
            f"# AutoDoctor {version}\n\nFailed to generate release notes.",
            encoding="utf-8",
        )

    # ---------------------------------------------
    # Try using generated release markdown
    # ---------------------------------------------

    release_file = find_release_file(version)

    if release_file:
        print(f"INFO: Using {release_file} for release notes")

        content = release_file.read_text(encoding="utf-8")
        NOTES_FILE.write_text(content, encoding="utf-8")
        return

    # ---------------------------------------------
    # Fallback to changelog.json
    # ---------------------------------------------

    print("WARNING: Release markdown not found, falling back to changelog.json")

    if not CHANGELOG_FILE.exists():
        print("ERROR: changelog.json missing")
        sys.exit(1)

    data = json.loads(CHANGELOG_FILE.read_text(encoding="utf-8"))

    for v in data.get("versions", []):

        if "v" + v["version"] == version:

            content = [
                f"# AutoDoctor {version}",
                "",
                f"Release date: {v['date']}",
                "",
                "## Changes",
                "",
            ]

            content += [f"- {c}" for c in v["changes"]]

            NOTES_FILE.write_text("\n".join(content), encoding="utf-8")

            print(f"INFO: Release notes generated from changelog.json for {version}")
            return

    # ---------------------------------------------
    # Special versions (test / alpha / beta)
    # ---------------------------------------------

    if is_special_version(version):

        dummy_content = [
            f"# AutoDoctor {version}",
            "",
            "⚠ Pre-release / test version",
            "",
            "## Changes",
            "",
            "- This is a dry-run or pre-release",
            "- Workflow validation successful",
            "- No production release changes",
        ]

        NOTES_FILE.write_text("\n".join(dummy_content), encoding="utf-8")

        print(f"INFO: Dummy release notes created for {version}")

    else:

        NOTES_FILE.write_text(
            f"# AutoDoctor {version}\n\nNo release notes available.",
            encoding="utf-8",
        )

        print(f"WARNING: No release notes found for {version}")


if __name__ == "__main__":
    main()
