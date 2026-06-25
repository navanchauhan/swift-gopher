#!/usr/bin/env python3
import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[2]
FILES = [
    ROOT / "Sources" / "swift-gopher" / "helpers.swift",
    ROOT / "Tests" / "SwiftGopherServerTests" / "ServerHelpersTests.swift",
    ROOT / "Tests" / "SwiftGopherServerTests" / "WindowsGopherRequestProcessorTests.swift",
]
VERSION_RE = re.compile(r"swift-gopher/(\d+)\.(\d+)\.(\d+)")


def main() -> int:
    source = FILES[0].read_text(encoding="utf-8")
    match = VERSION_RE.search(source)
    if not match:
        print("Could not find swift-gopher version string", file=sys.stderr)
        return 1

    major, minor, patch = map(int, match.groups())
    old_version = f"{major}.{minor}.{patch}"
    new_version = f"{major}.{minor}.{patch + 1}"

    for path in FILES:
        text = path.read_text(encoding="utf-8")
        updated = text.replace(f"swift-gopher/{old_version}", f"swift-gopher/{new_version}")
        if updated == text:
            print(f"Version string not found in {path}", file=sys.stderr)
            return 1
        path.write_text(updated, encoding="utf-8", newline="\n")

    github_output = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else None
    if github_output:
        with github_output.open("a", encoding="utf-8") as output:
            output.write(f"old_version={old_version}\n")
            output.write(f"new_version={new_version}\n")
            output.write(f"tag=v{new_version}\n")

    print(new_version)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
