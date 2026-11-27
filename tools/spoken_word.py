#!/usr/bin/env python3
"""How Siri says a word: `make say WORD=Traceforce AS="Trace force"`.

Adds (or changes) the word in SpokenText.sounds (FUMailKit/Sources/FUMailKit/Client/SpokenText.swift), so
Siri's voice says it that way while the screen and shortcuts keep the spelling; bumps the patch version
(VERSION, both MARKETING_VERSION lines, the README's status line and a Versions row); runs the package
tests; and prints the commands to commit and upload. It commits nothing.

  python3 tools/spoken_word.py add WORD "SOUNDS LIKE"   [--no-bump]
  python3 tools/spoken_word.py remove WORD               [--no-bump]
  python3 tools/spoken_word.py list
"""
import datetime, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SWIFT = os.path.join(ROOT, "FUMailKit/Sources/FUMailKit/Client/SpokenText.swift")
START = "public static let sounds: [String: String] = ["
ENTRY = re.compile(r'^\s*"((?:[^"\\]|\\.)*)": "((?:[^"\\]|\\.)*)",\s*$')


def fail(message):
    sys.exit(f"spoken_word: {message}")


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return f.read()


def write(path, text):
    with open(os.path.join(ROOT, path), "w", encoding="utf-8") as f:
        f.write(text)


def sounds():
    """The list's lines: (index of `[`, index of `]`, [(word, sound)])."""
    lines = read(SWIFT).split("\n")
    start = next((i for i, line in enumerate(lines) if START in line), None)
    if start is None:
        fail(f"can't find the list in {SWIFT}")
    end = next(i for i in range(start + 1, len(lines)) if lines[i].strip() == "]")
    entries = []
    for line in lines[start + 1:end]:
        match = ENTRY.match(line)
        if match:
            entries.append((match.group(1), match.group(2)))
        elif line.strip() and not line.strip().startswith("//"):
            fail(f"don't know this line in the list: {line.strip()}")
    return lines, start, end, entries


def save(entries):
    lines, start, end, _ = sounds()
    body = [f'        "{word}": "{sound}",' for word, sound in entries]
    write(SWIFT, "\n".join(lines[:start + 1] + body + lines[end:]))


def checked(text, what):
    text = text.strip()
    if not text or any(c in text for c in '"\\\n'):
        fail(f"{what} can't be empty or contain quotes, backslashes or new lines")
    return text


def bump(what):
    old = read("VERSION").strip()
    major, minor, patch = old.split(".")
    new = f"{major}.{minor}.{int(patch) + 1}"
    write("VERSION", new + "\n")
    project = "FUMail.xcodeproj/project.pbxproj"
    text = read(project)
    if text.count(f"MARKETING_VERSION = {old};") != 2:
        fail(f"expected two MARKETING_VERSION = {old} lines in {project}")
    write(project, text.replace(f"MARKETING_VERSION = {old};", f"MARKETING_VERSION = {new};"))
    readme = read("README.md")
    if f"> **Status: {old}," not in readme or f"\n| {old} | " not in readme:
        fail(f"README.md has no status line or Versions row for {old}")
    row = f"| {new} | {datetime.date.today()} | **Siri:** {what}. |\n"
    readme = readme.replace(f"> **Status: {old},", f"> **Status: {new},", 1)
    readme = readme.replace(f"\n| {old} | ", f"\n{row}| {old} | ", 1)
    write("README.md", readme)
    return new


def main():
    args = [a for a in sys.argv[1:] if a != "--no-bump"]
    if not args or args[0] not in ("add", "remove", "list"):
        sys.exit(__doc__)
    _, _, _, entries = sounds()
    if args[0] == "list":
        for word, sound in entries:
            print(f"{word} → {sound}")
        return
    word = checked(args[1] if len(args) > 1 else "", "WORD")
    others = [(w, s) for w, s in entries if w.lower() != word.lower()]
    if args[0] == "add":
        sound = checked(args[2] if len(args) > 2 else "", "AS")
        if sound.lower() == word.lower():
            fail("AS is the same as WORD")
        save(others + [(word, sound)])
        what = f'says {word} as "{sound}"; the screen and shortcuts keep the spelling'
    else:
        if len(others) == len(entries):
            fail(f"{word} isn't in the list")
        save(others)
        what = f"says {word} as written again"
    version = None if "--no-bump" in sys.argv else bump(what)
    print(f"Siri {what}.")
    if subprocess.run(["swift", "test"], cwd=os.path.join(ROOT, "FUMailKit"), capture_output=True).returncode != 0:
        fail("the package tests failed: run `cd FUMailKit && swift test` to see why (nothing was committed)")
    print("Tests pass.")
    files = "FUMailKit/Sources/FUMailKit/Client/SpokenText.swift" + ("" if version is None else
                                                                     " VERSION README.md FUMail.xcodeproj/project.pbxproj")
    message = f"[AM] FU Mail for iOS: Siri {what}" + ("" if version is None else f" (v{version})")
    print(f"\nCommit and upload:\n  git add {files}\n  git commit -m '{message}'\n  git push\n  make testflight")


if __name__ == "__main__":
    main()
