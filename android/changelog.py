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
    changes = [unescape(c[1]) for c in re.finditer(r"Change\(text: " + STR + r", apps: (\w+)\)", m[5])
               if "android" in sets.get(c[2], set())]
    if changes:
        out.append({"version": m[1], "date": m[2], "time": m[3], "title": unescape(m[4]), "changes": changes})
json.dump(out, sys.stdout, ensure_ascii=False, indent=1)
