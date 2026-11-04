#!/bin/bash
# Fails when a UI string has no English translation. The compiler lists every localizable string
# (SwiftUI LocalizedStringKey literals and String(localized:)), with the exact %@/%lld format keys.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
swift build --scratch-path .build-l10n -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$OUT" >/dev/null
plutil -convert json -o "$OUT/en.json" Resources/en.lproj/Localizable.strings
python3 - "$OUT" <<'PY'
import glob, json, sys
out = sys.argv[1]
en = json.load(open(f"{out}/en.json"))
missing = set()
for f in glob.glob(f"{out}/*.stringsdata"):
    if f.endswith("Snapshots.stringsdata"):   # debug-only renders
        continue
    for entries in json.load(open(f)).get("tables", {}).values():
        missing |= {e["key"] for e in entries if e["key"] not in en}
if missing:
    print("Missing English strings (Resources/en.lproj/Localizable.strings):")
    for k in sorted(missing): print("  " + json.dumps(k, ensure_ascii=False))
    sys.exit(1)
print(f"✓ strings: {len(en)} English translations cover every UI string")
PY
