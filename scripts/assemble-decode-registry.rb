#!/usr/bin/env ruby
# frozen_string_literal: true

# Assemble the decode-registry bundle from per-spec JSON sources, byte-exact.
#
# Pretty-printed (2-space indent) and deterministic — specs in sorted-filename
# order, each spec's keys in source order — so a GitHub diff of the bundle reads
# like the diff of the spec sources. There is NO trailing newline: the relay
# serves, signs, and hashes these exact bytes, so a trailing newline (or any
# hand-edit) would break signature verification. Regenerate via this script;
# never hand-edit the generated bundle.

require "json"

KEY_ID = "cosign-registry-2026"

def assemble(specs_dir, out_path)
  specs = Dir.glob(File.join(specs_dir, "*.json")).sort.map { |path| JSON.parse(File.read(path)) }
  bundle = { "schema" => 1, "keyId" => KEY_ID, "specs" => specs }
  File.write(out_path, JSON.pretty_generate(bundle)) # 2-space indent, no trailing newline
end

abort "Usage: assemble-decode-registry.rb <specs-dir> <out.json>" if ARGV.length != 2

assemble(ARGV[0], ARGV[1])
