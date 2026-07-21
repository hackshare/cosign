#!/usr/bin/env ruby
# frozen_string_literal: true

# Assemble the decode-registry bundle from per-spec JSON sources, byte-exact.
#
# Emits {"schema":1,"keyId":<KEY_ID>,"specs":[...]} with compact separators and NO
# trailing newline, so the served bytes, signed bytes, and hashed bytes are identical.

require "json"

KEY_ID = "cosign-registry-2026"

def assemble(specs_dir, out_path)
  specs = Dir.glob(File.join(specs_dir, "*.json")).sort.map { |path| JSON.parse(File.read(path)) }
  bundle = { "schema" => 1, "keyId" => KEY_ID, "specs" => specs }
  File.write(out_path, JSON.generate(bundle)) # compact, no trailing newline
end

abort "Usage: assemble-decode-registry.rb <specs-dir> <out.json>" if ARGV.length != 2

assemble(ARGV[0], ARGV[1])
