#!/usr/bin/env python3

import json
import sys
from pathlib import Path
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


def is_special_version(version: str) -> bool:
    """Detect prerelease or dry-run versions."""
    return bool(re.search(r"-(test|alpha|beta|rc)", version, re.IGNORECASE))


def normalize_version(version: str):
    """Return both tag and plain forms for a version string."""
    value = version.strip()
    plain = value[1:] if value.lower().startswith("v") else value
    tagged = f"v{plain}"
    return tagged, plain


def find_release_file(version: str):
    """Locate release markdown file."""
    tagged, plain = normalize_version(version)
    candidate_names = []

    for name in (f"{version}.md", f"{plain}.md", f"{tagged}.md"):
        if name not in candidate_names:
            candidate_names.append(name)

    for base_dir in (RELEASES_DIR, ARCHIVE_DIR):
        for candidate in candidate_names:
            candidate_path = base_dir / candidate
            if candidate_path.exists():
                return candidate_path

    return None


def load_changelog():
    if not CHANGELOG_FILE.exists():
        return {}

    return json.loads(CHANGELOG_FILE.read_text(encoding="utf-8"))


def find_changelog_entry(version: str):
    tagged, plain = normalize_version(version)
    data = load_changelog()

    for entry in data.get("versions", []):
        entry_version = str(entry.get("version", "")).strip()
        if entry_version in (plain, tagged):
            return entry

    return None


def build_release_notes(version: str, date: str, changes):
    tagged, _ = normalize_version(version)

    content = [
        f"# AutoDoctor {tagged}",
        "",
        f"Release date: {date}",
        "",
        "## Changes",
        "",
    ]

    content += [f"- {change}" for change in changes]
    return "\n".join(content)


def build_special_release_notes(version: str):
    tagged, _ = normalize_version(version)

    return "\n".join(
        [
            f"# AutoDoctor {tagged}",
            "",
            "⚠ Pre-release / test version",
            "",
            "## Changes",
            "",
            "- This is a dry-run or pre-release",
            "- Workflow validation successful",
            "- No production release changes",
        ]
    )


def build_default_release_notes(version: str):
    tagged, _ = normalize_version(version)
    return f"# AutoDoctor {tagged}\n\nNo release notes available."


def write_release_notes(path: Path, content: str):
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(content)


# --------------------------------------------------
# MAIN
# --------------------------------------------------


def main():

    if len(sys.argv) < 2:
        print("Usage: prepare_release_notes.py <version>")
        sys.exit(1)

    version = sys.argv[1]  # example: v1.1.0 or v1.1.0-test
    content = None
    source = None

    try:
        release_file = find_release_file(version)

        if release_file:
            content = release_file.read_text(encoding="utf-8")
            source = str(release_file)
        else:
            changelog_entry = find_changelog_entry(version)
            if changelog_entry:
                content = build_release_notes(
                    version=version,
                    date=changelog_entry["date"],
                    changes=changelog_entry.get("changes", []),
                )
                source = "docs/data/changelog.json"
            elif is_special_version(version):
                content = build_special_release_notes(version)
                source = "special prerelease fallback"
            else:
                content = build_default_release_notes(version)
                source = "default fallback"

    except Exception as e:
        print(f"ERROR: {e}")
        content = f"# AutoDoctor {version}\n\nFailed to generate release notes."
        source = "error fallback"

    write_release_notes(NOTES_FILE, content)
    print(f"INFO: Wrote {NOTES_FILE} from {source}")


if __name__ == "__main__":
    main()
