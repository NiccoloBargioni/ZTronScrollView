#!/bin/bash
# UIKit scope gate (SPEC S2 amendment 2026-10-20, S16; D31; design docs/design/UIKIT-touch-observer.md §5, R5).
# usage: scripts/check-uikit-scope.sh      exit 0 = clean, exit 1 = any violation (every hit is printed as file:line).
#  1. `import UIKit` / `UIKit.` / `UIViewRepresentable` appear in code only under Sources/ZTronScrollView/Gesture/UIKit/,
#     and every file there that has such a hit starts (first non-comment line) with `#if canImport(UIKit) && os(iOS)`.
#  2. `UIScrollView`, `UIHostingController`, `NSClassFromString`, `value(forKey`, `Mirror(` appear in code nowhere in
#     Sources or Packages (the MC spike under Packages/ScrollArbitration/Spike is excluded by path).
# Comments (// ... and /* ... */) are ignored: prose such as "as in UIKit." is not a use.
cd "$(dirname "$0")/.." || exit 1
python3 -I - <<'EOF'
import os, re, sys

ALLOWED = "Sources/ZTronScrollView/Gesture/UIKit/"
GUARD = "#if canImport(UIKit) && os(iOS)"
SCOPED = re.compile(r"import\s+UIKit|UIKit\.|UIViewRepresentable")
FORBIDDEN = re.compile(r"UIScrollView|UIHostingController|NSClassFromString|value\(forKey|Mirror\(")

def code_lines(path):
    """(line number, code with comments removed) for every line of the file."""
    in_block = False
    for n, raw in enumerate(open(path, encoding="utf-8"), 1):
        line, out, i = raw.rstrip("\n"), "", 0
        while i < len(line):
            if in_block:
                j = line.find("*/", i)
                if j < 0: i = len(line)
                else: in_block, i = False, j + 2
            elif line.startswith("/*", i): in_block, i = True, i + 2
            elif line.startswith("//", i): i = len(line)
            else: out, i = out + line[i], i + 1
        yield n, out

files = []
for root in ("Sources", "Packages"):
    for d, dirs, names in os.walk(root):
        dirs[:] = [x for x in dirs if x != ".build" and not (d + "/" + x).startswith("Packages/ScrollArbitration/Spike")]
        files += [os.path.join(d, n) for n in names if n.endswith(".swift")]

bad = []
for path in sorted(files):
    lines = list(code_lines(path))
    scoped = [(n, c.strip()) for n, c in lines if SCOPED.search(c)]
    if scoped and not path.startswith(ALLOWED):
        bad += [f"{path}:{n}: UIKit outside {ALLOWED}: {c}" for n, c in scoped]
    if scoped and path.startswith(ALLOWED):
        first = next((c.strip() for _, c in lines if c.strip()), "")
        if first != GUARD:
            bad.append(f"{path}:1: first code line is `{first}`, expected `{GUARD}`")
    bad += [f"{path}:{n}: forbidden API: {c.strip()}" for n, c in lines if FORBIDDEN.search(c)]

for b in bad: print(b)
print(f"check-uikit-scope: {len(files)} files scanned, {len(bad)} violation(s)")
sys.exit(1 if bad else 0)
EOF
