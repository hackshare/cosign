#!/usr/bin/env python3
"""Assemble the decode-registry bundle from per-spec JSON sources, byte-exact.

Emits {"schema":1,"keyId":<KEY_ID>,"specs":[...]} with compact separators and NO
trailing newline, so the served bytes, signed bytes, and hashed bytes are identical.
"""
import json, sys, pathlib

KEY_ID = "cosign-registry-2026"

def main(specs_dir: str, out_path: str) -> None:
    specs = [json.loads(p.read_text()) for p in sorted(pathlib.Path(specs_dir).glob("*.json"))]
    bundle = {"schema": 1, "keyId": KEY_ID, "specs": specs}
    body = json.dumps(bundle, separators=(",", ":"), ensure_ascii=False)
    pathlib.Path(out_path).write_text(body)  # no trailing newline

if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Usage: assemble-decode-registry.py <specs-dir> <out.json>")
    main(sys.argv[1], sys.argv[2])
