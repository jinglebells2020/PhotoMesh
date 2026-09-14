#!/usr/bin/env bash
# Writes (or clears / checks) the OpenRouter key baked into tester builds.
#
#   tools/embed-key.sh sk-or-v1-...   embed this key (XOR-obfuscated) into BuiltinKey.swift
#   tools/embed-key.sh --clear        put the empty placeholder back
#   tools/embed-key.sh --check        exit 1 if a key is currently embedded (used by CI and pre-commit)
#
# The embedded file must never be committed with a key in it. Typical local flow:
#   tools/embed-key.sh "$KEY" && <archive in Xcode> && tools/embed-key.sh --clear
set -euo pipefail

FILE="$(cd "$(dirname "$0")/.." && pwd)/PhotoMesh/Support/BuiltinKey.swift"
MODE="${1:-}"

if [ -z "$MODE" ]; then
  echo "usage: $0 <key> | --clear | --check" >&2
  exit 2
fi

python3 - "$FILE" "$MODE" <<'PY'
import os, re, sys
path, mode = sys.argv[1], sys.argv[2]
source = open(path, encoding="utf-8").read()
pattern = re.compile(r"(private static let salt: \[UInt8\] = )\[[^\]]*\](\s+private static let bytes: \[UInt8\] = )\[[^\]]*\]")
match = pattern.search(source)
if not match:
    sys.exit("BuiltinKey.swift: could not find the salt/bytes arrays")

if mode == "--check":
    salt = re.search(r"salt: \[UInt8\] = \[([^\]]*)\]", source).group(1).strip()
    data = re.search(r"bytes: \[UInt8\] = \[([^\]]*)\]", source).group(1).strip()
    if salt or data:
        sys.exit("BuiltinKey.swift contains an embedded key. Run tools/embed-key.sh --clear before committing.")
    print("BuiltinKey.swift is clean")
    sys.exit(0)

if mode == "--clear":
    salt_literal, bytes_literal = "[]", "[]"
else:
    key = mode.strip()
    if not key.startswith("sk-or-"):
        sys.exit("that does not look like an OpenRouter key (expected sk-or-...)")
    salt = os.urandom(16)
    raw = key.encode("utf-8")
    encoded = bytes(b ^ salt[i % len(salt)] for i, b in enumerate(raw))
    fmt = lambda bs: "[" + ", ".join(str(b) for b in bs) + "]"
    salt_literal, bytes_literal = fmt(salt), fmt(encoded)

updated = pattern.sub(lambda m: m.group(1) + salt_literal + m.group(2) + bytes_literal, source, count=1)
open(path, "w", encoding="utf-8").write(updated)
print("BuiltinKey.swift: " + ("cleared" if mode == "--clear" else "key embedded (%d bytes)" % len(bytes_literal)))
PY
