#!/usr/bin/env python3
"""Gate package builds on their own files and generated source entries."""

import json
import os
from pathlib import Path
import re
import subprocess
import sys


def git(*args):
    return subprocess.check_output(["git", *args]).decode()


def nix_sources(text, sources):
    # nvfetcher emits each source as a two-space-indented attribute block.
    # Keep the surrounding text too, so changes to shared code still build.
    pattern = re.compile(r"^  ([\w-]+) = \{\n.*?^  \};\n", re.M | re.S)
    blocks = {match[1]: match[0] for match in pattern.finditer(text)}
    if not all(source in blocks for source in sources):
        raise ValueError("Unrecognized generated Nix layout or missing source")
    return pattern.sub("", text), [blocks[source] for source in sources]


def package_changed(package, sources, base, head):
    paths = git("diff", "--name-only", "--no-renames", "-z", base, head).split("\0")
    shared = {
        "flake.nix", "flake.lock", "nvfetcher.toml",
        ".github/scripts/package-changed.py",
        f".github/workflows/{package}.yaml",
    }
    if any(path in shared or path.startswith(f"packages/{package}/") for path in paths):
        return True

    for path in ("_sources/generated.json", "_sources/generated.nix"):
        if path not in paths:
            continue
        before = git("show", f"{base}:{path}")
        after = git("show", f"{head}:{path}")
        if path.endswith(".json"):
            old, new = json.loads(before), json.loads(after)
            if any(old[source] != new[source] for source in sources):
                return True
        elif nix_sources(before, sources) != nix_sources(after, sources):
            return True
    return False


def main():
    package, *extra_sources = sys.argv[1:]
    event_name = os.environ["GITHUB_EVENT_NAME"]
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    changed = True
    try:
        if event_name == "push":
            base, head = event["before"], event["after"]
        elif event_name == "pull_request":
            head = event["pull_request"]["head"]["sha"]
            base = git("merge-base", event["pull_request"]["base"]["sha"], head).strip()
        else:
            base = None  # Manual runs always build.
        if base and base != "0" * 40:
            changed = package_changed(package, [package, *extra_sources], base, head)
    except (subprocess.CalledProcessError, KeyError, ValueError) as error:
        # Missing history or unfamiliar metadata must not suppress a build.
        print(f"Unable to compare sources; building conservatively: {error}", file=sys.stderr)
    value = str(changed).lower()
    print(f"{package}: changed={value}")
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write(f"changed={value}\n")


if __name__ == "__main__":
    main()
