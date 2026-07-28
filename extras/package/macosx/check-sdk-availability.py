#!/usr/bin/env python3
"""Flag the selectors a plug-in sends that the SDK marks as too recent.

check-jaguar-selectors.m answers "does this system know this selector at
all", which misses every method whose name another class happens to share:
-[NSCell setLineBreakMode:] is 10.4, but NSParagraphStyle has had a selector
by that name since 10.0, so the runtime check calls it known and the
interface still dies on it.

The SDK headers carry the answer, in two forms: the 10.4u headers mostly
wrap the newer declarations in

    #if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_4
    ...
    #endif

and annotate a few with AVAILABLE_MAC_OS_X_VERSION_10_x_AND_LATER. This
reads both, builds selector -> earliest version, and reports every selector
the binary sends that the SDK says arrived after the deployment target.

It over-reports by design: a selector declared 10.4 on one class may be 10.0
on the class actually receiving it, and a call already wrapped in a
-respondsToSelector: check is listed just the same. It is a list to review,
not a list of defects.

Usage:
  check-sdk-availability.py <sdk-path> <min-version> <selector-list-file>

  e.g. check-sdk-availability.py /path/MacOSX10.4u.sdk 10.2 needed.txt
"""

import os
import re
import sys

AVAILABILITY = re.compile(
    r"AVAILABLE_MAC_OS_X_VERSION_10_(\d+)(?:_\d+)?_AND_LATER")
VERSION_GUARD = re.compile(
    r"^\s*#\s*if.*MAC_OS_X_VERSION_MAX_ALLOWED\s*>=\s*"
    r"MAC_OS_X_VERSION_10_(\d+)")
ANY_IF = re.compile(r"^\s*#\s*if")
ENDIF = re.compile(r"^\s*#\s*endif")
PARENS = re.compile(r"\([^()]*\)")


def selector_of(declaration):
    """Rebuild the selector from an Objective-C method declaration."""
    body = declaration.strip()
    if not body.startswith(("-", "+")):
        return None
    body = body[1:]

    # Drop the types, which are the only parenthesised parts of a
    # declaration; nested ones (function pointers) need several passes.
    previous = None
    while previous != body:
        previous = body
        body = PARENS.sub(" ", body)

    parts = re.findall(r"(\w+)\s*:", body)
    if parts:
        return "".join(part + ":" for part in parts)

    words = body.split()
    return words[0] if words and words[0].isidentifier() else None


def sdk_versions(sdk):
    """selector -> earliest 10.x minor version the SDK announces for it."""
    versions = {}
    roots = [
        os.path.join(sdk, "System/Library/Frameworks"),
        os.path.join(sdk, "usr/include"),
    ]

    for root in roots:
        for path, _, names in os.walk(root):
            for name in names:
                if not name.endswith(".h"):
                    continue
                try:
                    with open(os.path.join(path, name),
                              encoding="utf-8", errors="replace") as handle:
                        text = handle.read()
                except OSError:
                    continue

                note(versions, text)
    return versions


def note(versions, text):
    """Record every declaration and the version guard it sits inside."""
    def remember(selector, minor):
        if selector and versions.get(selector, 99) > minor:
            versions[selector] = minor

    # Stack of guards: the innermost MAC_OS_X_VERSION_MAX_ALLOWED one wins,
    # and any other #if pushes a "no opinion" entry so #endif stays paired.
    stack = []
    declaration = ""

    for line in text.split("\n"):
        if ENDIF.match(line):
            if stack:
                stack.pop()
            continue
        if ANY_IF.match(line):
            guard = VERSION_GUARD.match(line)
            stack.append(int(guard.group(1)) if guard else None)
            continue

        declaration = (declaration + " " + line).strip()
        if not declaration.startswith(("-", "+")):
            declaration = "" if line.strip().endswith(";") else declaration
            continue
        if ";" not in declaration:
            continue                      # a declaration split over lines

        selector = selector_of(declaration.split(";")[0])
        declaration = ""
        if selector is None:
            continue

        annotated = AVAILABILITY.search(line)
        if annotated:
            remember(selector, int(annotated.group(1)))
            continue

        guarded = [minor for minor in stack if minor is not None]
        if guarded:
            remember(selector, max(guarded))


def main():
    if len(sys.argv) != 4:
        print(__doc__, file=sys.stderr)
        return 2

    sdk, target, listing = sys.argv[1], sys.argv[2], sys.argv[3]
    target_minor = int(target.split(".")[1])

    versions = sdk_versions(sdk)
    with open(listing) as handle:
        wanted = [line.strip() for line in handle if line.strip()]

    late = [(versions[s], s) for s in wanted
            if s in versions and versions[s] > target_minor]

    for minor, selector in sorted(late):
        print("10.%d\t%s" % (minor, selector))

    print("%d of %d selectors are newer than %s"
          % (len(late), len(wanted), target), file=sys.stderr)
    return 1 if late else 0


if __name__ == "__main__":
    sys.exit(main())
