#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "optparse"
require "shellwords"
require "time"

$stdout.sync = true
$stderr.sync = true

ROOT = File.expand_path("..", __dir__)
TIMESTAMP = Time.now.strftime("%Y%m%d-%H%M%S")

options = {
  destination: ENV.fetch("COSIGN_SCREENSHOT_DESTINATION", "platform=iOS Simulator,name=iPhone 17"),
  derived_data: File.join(ROOT, "DerivedData", "Screenshots"),
  output: File.join(ROOT, "Derived", "Screenshots", TIMESTAMP),
  profiles: nil,
  replace: false,
  scheme: "CosignDemo",
  test: "CosignDemoUITests/CosignDemoDesignWalkthroughUITests",
  workspace: File.join(ROOT, "Cosign.xcworkspace")
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: ruby scripts/capture-demo-screenshots.rb [options]"
  opts.on("--destination DESTINATION", "xcodebuild destination") { |value| options[:destination] = value }
  opts.on("--device ID", "Use an iOS Simulator device ID") do |value|
    options[:destination] = "platform=iOS Simulator,id=#{value}"
  end
  opts.on("--derived-data PATH", "DerivedData path") { |value| options[:derived_data] = File.expand_path(value, Dir.pwd) }
  opts.on("--exported-attachments PATH", "Attachment export directory") do |value|
    options[:exported_attachments] = File.expand_path(value, Dir.pwd)
  end
  opts.on("--output PATH", "Screenshot output directory") { |value| options[:output] = File.expand_path(value, Dir.pwd) }
  opts.on("--profiles LIST", "Comma-separated screenshot profiles to export, e.g. appstore,nullstates") do |value|
    options[:profiles] = value.split(",").map { |profile| profile.strip.downcase }.reject(&:empty?)
  end
  opts.on("--replace", "Replace an existing output or result bundle") { options[:replace] = true }
  opts.on("--result-bundle PATH", "Export screenshots from an existing xcresult bundle") do |value|
    options[:result_bundle] = File.expand_path(value, Dir.pwd)
  end
  opts.on("--scheme NAME", "Xcode scheme") { |value| options[:scheme] = value }
  opts.on("--test IDENTIFIER", "only-testing identifier") { |value| options[:test] = value }
  opts.on("--workspace PATH", "Xcode workspace") { |value| options[:workspace] = File.expand_path(value, Dir.pwd) }
  opts.on("-h", "--help", "Show this help") do
    puts opts
    exit 0
  end
end
parser.parse!(ARGV)

def run!(command)
  puts command.shelljoin
  return if system(*command)

  warn "Command failed: #{command.shelljoin}"
  exit 1
end

def capture_json(command)
  output, status = Open3.capture2e(*command)
  return JSON.parse(output) if status.success?

  warn "Command failed: #{command.shelljoin}"
  warn output
  nil
rescue JSON::ParserError => e
  warn "Invalid JSON from #{command.shelljoin}: #{e.message}"
  nil
end

def normalize_attachment_name(name)
  basename = File.basename(name.to_s)
  extension = File.extname(basename)
  extension = ".png" if extension.empty?
  stem = basename.delete_suffix(extension)
  stem = stem.sub(/_\d+_[0-9A-Fa-f-]{36}\z/, "")
  stem = stem.gsub(/[^0-9A-Za-z_.-]+/, "-")
  "#{stem}#{extension.downcase}"
end

def profile_name(test_identifier, normalized_name)
  return "nullstates" if test_identifier.include?("NullStates") || normalized_name.include?("-null-")

  "appstore"
end

def unique_destination(path)
  return path unless File.exist?(path)

  extension = File.extname(path)
  stem = path.delete_suffix(extension)
  index = 2
  loop do
    candidate = "#{stem}-#{index}#{extension}"
    return candidate unless File.exist?(candidate)

    index += 1
  end
end

def destination_component(destination, key)
  destination
    .to_s
    .split(",")
    .map(&:strip)
    .find { |part| part.start_with?("#{key}=") }
    &.split("=", 2)
    &.last
end

def simulator_udid(destination)
  destination_component(destination, "id")
end

def simulator_name(destination)
  destination_component(destination, "name")
end

def resolve_simulator(destination)
  existing_id = simulator_udid(destination)
  return { "udid" => existing_id, "state" => nil } if existing_id

  name = simulator_name(destination)
  return nil unless name

  devices = capture_json(["xcrun", "simctl", "list", "devices", "available", "--json"])
    &.fetch("devices", {})
    &.values
    &.flatten || []
  matches = devices.select { |device| device["name"] == name && device.fetch("isAvailable", true) }
  matches.find { |device| device["state"] == "Booted" } || matches.first
end

def boot_simulator(simulator)
  device_id = simulator&.fetch("udid", nil)
  return unless device_id

  system("xcrun", "simctl", "boot", device_id) unless simulator["state"] == "Booted"
  run!(["xcrun", "simctl", "bootstatus", device_id, "-b"])
end

def override_status_bar(device_id)
  return unless device_id

  run!([
    "xcrun",
    "simctl",
    "status_bar",
    device_id,
    "override",
    "--time",
    "9:41",
    "--cellularMode",
    "active",
    "--cellularBars",
    "4",
    "--wifiMode",
    "active",
    "--wifiBars",
    "3",
    "--batteryState",
    "charged",
    "--batteryLevel",
    "100"
  ])
  at_exit do
    system("xcrun", "simctl", "status_bar", device_id, "clear")
  end
end

output = options.fetch(:output)
if File.exist?(output)
  if options[:replace]
    FileUtils.rm_rf(output)
  else
    warn "Output already exists: #{output}"
    warn "Pass --replace or choose a different --output path."
    exit 1
  end
end
FileUtils.mkdir_p(output)

result_bundle = options[:result_bundle] || File.join(ROOT, "Derived", "ScreenshotResults", "#{TIMESTAMP}.xcresult")

unless options[:result_bundle]
  simulator = resolve_simulator(options.fetch(:destination))
  device_id = simulator&.fetch("udid", nil)
  if device_id
    options[:destination] = "platform=iOS Simulator,id=#{device_id}"
    boot_simulator(simulator)
    override_status_bar(device_id)
  end

  if File.exist?(result_bundle)
    if options[:replace]
      FileUtils.rm_rf(result_bundle)
    else
      warn "Result bundle already exists: #{result_bundle}"
      warn "Pass --replace or choose a different --result-bundle path."
      exit 1
    end
  end

  FileUtils.mkdir_p(File.dirname(result_bundle))
  run!([
    "xcodebuild",
    "-workspace",
    options.fetch(:workspace),
    "-scheme",
    options.fetch(:scheme),
    "-destination",
    options.fetch(:destination),
    "-derivedDataPath",
    options.fetch(:derived_data),
    "-resultBundlePath",
    result_bundle,
    "-only-testing:#{options.fetch(:test)}",
    "test"
  ])
end

attachments_dir = options[:exported_attachments] ||
                  File.join(File.dirname(result_bundle), "#{File.basename(result_bundle, ".xcresult")}-attachments")

if File.exist?(attachments_dir)
  if options[:replace]
    FileUtils.rm_rf(attachments_dir)
  else
    warn "Attachment export already exists: #{attachments_dir}"
    warn "Pass --replace or choose a different --exported-attachments path."
    exit 1
  end
end
FileUtils.mkdir_p(attachments_dir)

run!([
  "xcrun",
  "xcresulttool",
  "export",
  "attachments",
  "--path",
  result_bundle,
  "--output-path",
  attachments_dir
])

manifest_path = File.join(attachments_dir, "manifest.json")
unless File.file?(manifest_path)
  warn "Missing attachment manifest: #{manifest_path}"
  exit 1
end

copied = []
allowed_profiles = options[:profiles]
JSON.parse(File.read(manifest_path)).each do |test_result|
  test_identifier = test_result.fetch("testIdentifier", "")
  attachments = test_result.fetch("attachments", []).sort_by { |attachment| attachment.fetch("timestamp", 0.0) }

  attachments.each do |attachment|
    exported_name = attachment.fetch("exportedFileName")
    source = File.join(attachments_dir, exported_name)
    next unless File.file?(source)

    normalized_name = normalize_attachment_name(
      attachment["suggestedHumanReadableName"] || exported_name
    )
    profile = profile_name(test_identifier, normalized_name)
    next if allowed_profiles && !allowed_profiles.include?(profile)

    profile_dir = File.join(output, profile)
    FileUtils.mkdir_p(profile_dir)

    destination = unique_destination(File.join(profile_dir, normalized_name))
    FileUtils.cp(source, destination)
    copied << {
      "profile" => profile,
      "name" => File.basename(destination),
      "source" => exported_name,
      "testIdentifier" => test_identifier
    }
  end
end

if copied.empty?
  warn "No screenshot attachments were exported."
  exit 1
end

File.write(
  File.join(output, "manifest.json"),
  JSON.pretty_generate(
    "generatedAt" => Time.now.utc.iso8601,
    "scheme" => options.fetch(:scheme),
    "destination" => options.fetch(:destination),
    "profiles" => options[:profiles] || copied.map { |entry| entry.fetch("profile") }.uniq.sort,
    "resultBundle" => result_bundle,
    "attachmentsExport" => attachments_dir,
    "screenshots" => copied
  )
)

puts "Screenshots written to #{output}:"
copied.group_by { |entry| entry.fetch("profile") }.sort.each do |profile, entries|
  puts "  #{profile}/"
  entries.sort_by { |entry| entry.fetch("name") }.each do |entry|
    puts "    #{entry.fetch("name")}"
  end
end
