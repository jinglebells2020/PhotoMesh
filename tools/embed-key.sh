#!/usr/bin/env bash
# Writes (or clears / checks) the secrets baked into tester builds (PhotoMesh/Support/BuiltinKey.swift).
#
#   tools/embed-key.sh sk-or-v1-...                 embed the OpenRouter key (XOR-obfuscated)
#   tools/embed-key.sh --telemetry <https-url> <key>   embed the telemetry collector URL and ingest key
#   tools/embed-key.sh --clear                      put every empty placeholder back
#   tools/embed-key.sh --check                      exit 1 if anything is currently embedded (CI and pre-commit)
#
# The file must never be committed with a value in it. Typical local flow:
#   tools/embed-key.sh "$KEY" && tools/embed-key.sh --telemetry "$URL" "$TKEY" && <archive> && tools/embed-key.sh --clear
set -euo pipefail

FILE="$(cd "$(dirname "$0")/.." && pwd)/PhotoMesh/Support/BuiltinKey.swift"
MODE="${1:-}"

if [ -z "$MODE" ]; then
  echo "usage: $0 <openrouter-key> | --telemetry <url> <key> | --clear | --check" >&2
  exit 2
fi

python3 - "$FILE" "$@" <<'PY'
import os, re, sys
path, mode = sys.argv[1], sys.argv[2]
args = sys.argv[3:]
source = open(path, encoding="utf-8").read()

ARRAYS = {"key": ("salt", "bytes"), "telemetry": ("telemetrySalt", "telemetryBytes")}

def literal_of(name):
    m = re.search(r"private static let %s: \[UInt8\] = \[([^\]]*)\]" % name, source)
    if not m:
        sys.exit("BuiltinKey.swift: could not find the %s array" % name)
    return m.group(1).strip()

def set_array(src, name, literal):
    pattern = re.compile(r"(private static let %s: \[UInt8\] = )\[[^\]]*\]" % name)
    if not pattern.search(src):
        sys.exit("BuiltinKey.swift: could not find the %s array" % name)
    return pattern.sub(lambda m: m.group(1) + literal, src, count=1)

def obfuscate(text):
    salt = os.urandom(16)
    raw = text.encode("utf-8")
    encoded = bytes(b ^ salt[i % len(salt)] for i, b in enumerate(raw))
    fmt = lambda bs: "[" + ", ".join(str(b) for b in bs) + "]"
    return fmt(salt), fmt(encoded)

if mode == "--check":
    filled = [name for pair in ARRAYS.values() for name in pair if literal_of(name)]
    if filled:
        sys.exit("BuiltinKey.swift contains embedded values (%s). Run tools/embed-key.sh --clear before committing." % ", ".join(filled))
    print("BuiltinKey.swift is clean")
    sys.exit(0)

if mode == "--clear":
    for pair in ARRAYS.values():
        for name in pair:
            source = set_array(source, name, "[]")
    open(path, "w", encoding="utf-8").write(source)
    print("BuiltinKey.swift: cleared")
    sys.exit(0)

if mode == "--telemetry":
    if len(args) != 2:
        sys.exit("usage: --telemetry <https-url> <ingest-key>")
    url, key = args[0].strip(), args[1].strip()
    if not url.startswith("https://"):
        sys.exit("the telemetry endpoint must be an https:// URL")
    if not key:
        sys.exit("the telemetry ingest key is empty")
    salt_l, bytes_l = obfuscate(url + "\n" + key)
    source = set_array(set_array(source, "telemetrySalt", salt_l), "telemetryBytes", bytes_l)
    open(path, "w", encoding="utf-8").write(source)
    print("BuiltinKey.swift: telemetry endpoint embedded")
    sys.exit(0)

key = mode.strip()
if not key.startswith("sk-or-"):
    sys.exit("that does not look like an OpenRouter key (expected sk-or-...)")
salt_l, bytes_l = obfuscate(key)
source = set_array(set_array(source, "salt", salt_l), "bytes", bytes_l)
open(path, "w", encoding="utf-8").write(source)
print("BuiltinKey.swift: key embedded (%d bytes)" % len(bytes_l))
PY
