"""Writes What's new for the Android app (the changes tagged android in Shared/Changelog.swift) as JSON."""
import json, re, sys

src = open(sys.argv[1], encoding="utf-8").read()
sets = {m[1]: {x.strip().lstrip(".") for x in m[2].split(",") if x.strip()}
        for m in re.finditer(r"static let (\w+): Set<App> = \[([^\]]*)\]", src)}
STR = r'"((?:[^"\\]|\\.)*)"'

def unescape(s):
    s = re.sub(r"\\u\{([0-9a-fA-F]+)\}", lambda m: chr(int(m[1], 16)), s)
    return s.replace('\\"', '"').replace("\\\\", "\\")

out = []
for m in re.finditer(r"Release\(version: " + STR + r", date: " + STR + r", time: " + STR + r", title: " + STR +
                     r", changes: \[(.*?)\]\)", src, re.S):
    every = []
    for c in re.finditer(r"Change\(text: " + STR + r", apps: (\w+|\[[^\]]*\])\)", m[5]):
        apps = c[2]
        if apps.startswith("["):
            apps = {x.strip().lstrip(".") for x in apps[1:-1].split(",") if x.strip()}
        else:
            apps = sets.get(apps, set())
        every.append((unescape(c[1]), "android" in apps))
    changes = [text for text, mine in every if mine]
    if changes:
        # A release that also changed other apps: its title may be about them, so the app shows "2 changes".
        title = unescape(m[4]) if len(changes) == len(every) else ""
        out.append({"version": m[1], "date": m[2], "time": m[3], "title": title, "changes": changes})
json.dump(out, sys.stdout, ensure_ascii=False, indent=1)
