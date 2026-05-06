#!/usr/bin/env ruby
# frozen_string_literal: true

ROOT = File.expand_path("..", __dir__)

SOURCE_GLOBS = [
  "App/Sources/**/*.swift",
  "Modules/UI/Sources/**/*.swift"
].freeze

EXCLUDED_FILE_PATTERNS = [
  %r{\AModules/UI/Sources/Cosign.*Copy\.swift\z}
].freeze

SOURCE_FILE_PATTERNS = [
  %r{\AApp/Sources/.*\.swift\z},
  %r{\AModules/UI/Sources/.*\.swift\z}
].freeze

COPY_PATTERNS = [
  /\b(?:Text|Button|Label|TextField|SecureField)\s*\(\s*"[[:alpha:]]/,
  /\.accessibilityLabel\s*\(\s*"/,
  /\.(?:navigationTitle)\s*\(\s*"[[:alpha:]]/,
  /\b(?:title|subtitle|message|label|accessibilityLabel|cancelTitle|alertMessage):\s*"[[:alpha:]]/,
  /\bvalue:\s*"[[:alpha:]]/
].freeze

def relative_path(path)
  absolute = File.expand_path(path, ROOT)
  absolute.delete_prefix("#{ROOT}/")
end

def guarded_file?(path)
  SOURCE_FILE_PATTERNS.any? { |pattern| path.match?(pattern) } &&
    EXCLUDED_FILE_PATTERNS.none? { |pattern| path.match?(pattern) }
end

def guarded_files
  SOURCE_GLOBS.flat_map { |glob| Dir.glob(File.join(ROOT, glob)) }
              .map { |path| relative_path(path) }
              .select { |path| guarded_file?(path) }
              .sort
end

files = if ARGV.empty?
          guarded_files
        else
          ARGV.map { |path| relative_path(path) }.select { |path| guarded_file?(path) }
        end

violations = files.flat_map do |path|
  absolute = File.join(ROOT, path)
  next [] unless File.file?(absolute)

  File.readlines(absolute).each_with_index.map do |line, index|
    stripped = line.lstrip
    next if stripped.start_with?("//")
    next unless COPY_PATTERNS.any? { |pattern| line.match?(pattern) }

    "#{path}:#{index + 1}: route product copy through CosignCopy"
  end.compact
end

if violations.any?
  warn "Inline product copy found in copy-guarded UI files."
  warn "Add the string to the appropriate CosignCopy namespace and reference it from the view."
  warn violations.join("\n")
  exit 1
end
