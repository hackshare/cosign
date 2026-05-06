#!/usr/bin/env ruby
# frozen_string_literal: true

USAGE = "Usage: ruby scripts/stop-localnet-fixtures.rb [--dry-run]"
ProcessInfo = Struct.new(:pid, :ppid, :command, keyword_init: true)

dry_run = false
ARGV.each do |arg|
  case arg
  when "--dry-run"
    dry_run = true
  when "--help", "-h"
    puts USAGE
    exit 0
  else
    warn USAGE
    exit 1
  end
end

def redact(command)
  command.gsub(/([?&](?:api-key|apikey|key|token)=)[^\s&]+/i, "\\1REDACTED")
end

def processes
  output = IO.popen(["ps", "axww", "-o", "pid=,ppid=,command="], &:read)
  output.each_line.filter_map do |line|
    match = line.chomp.match(/\A\s*(\d+)\s+(\d+)\s+(.+)\z/)
    next unless match

    ProcessInfo.new(
      pid: Integer(match[1]),
      ppid: Integer(match[2]),
      command: match[3]
    )
  end
end

def alive?(pid)
  Process.kill(0, pid)
  true
rescue Errno::ESRCH
  false
rescue Errno::EPERM
  true
end

def signal(pid, name)
  Process.kill(name, pid)
rescue Errno::ESRCH
  nil
end

all_processes = processes
fixture_processes = all_processes.select do |process|
  process.pid != Process.pid && process.command.include?("localnet_fixture")
end
validator_processes = all_processes.select do |process|
  process.command.include?("solana-test-validator") &&
    process.command.include?("cosign-local-validator-")
end
relay_processes = all_processes.select do |process|
  process.command.include?("--bin relay-server") ||
    process.command.include?("core/target/debug/relay-server")
end
targets = (fixture_processes + validator_processes + relay_processes).uniq(&:pid)

if targets.empty?
  puts "No Cosign localnet fixture processes found."
  exit 0
end

targets.sort_by(&:pid).each do |process|
  puts "Found pid #{process.pid}: #{redact(process.command)}"
end

if dry_run
  puts "Dry run only. Re-run without --dry-run to stop these processes."
  exit 0
end

targets.each { |process| signal(process.pid, "TERM") }

deadline = Time.now + 5
while Time.now < deadline && targets.any? { |process| alive?(process.pid) }
  sleep 0.2
end

remaining = targets.select { |process| alive?(process.pid) }
remaining.each { |process| signal(process.pid, "KILL") }

puts "Stopped #{targets.length} Cosign localnet fixture process#{"es" unless targets.length == 1}."
