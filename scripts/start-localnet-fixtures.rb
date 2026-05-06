#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "rbconfig"
require "uri"

$stdout.sync = true
$stderr.sync = true

repo_root = File.expand_path("..", __dir__)

options = {
  browser_proxy_port: "65535",
  device: "booted",
  install_ca: true,
  manifest: File.join(repo_root, ".cosign-local", "localnet-fixture.json"),
  open_simulator: true,
  proposals: "8",
  relay: true,
  relay_port: "8787",
  scenario: "inspection-matrix",
  squads: "2",
  stop_existing: true
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: ruby scripts/start-localnet-fixtures.rb [options] [-- extra fixture args]"
  opts.on("--member PUBKEY", "Include this pubkey in every fixture Squad") { |value| options[:member] = value }
  opts.on("--browser-proxy-port PORT", "HTTPS proxy port (default: 65535)") { |value| options[:browser_proxy_port] = value }
  opts.on("--squads COUNT", "Number of fixture Squads (default: 2)") { |value| options[:squads] = value }
  opts.on("--proposals COUNT", "Proposals per Squad for the default scenario (default: 8)") { |value| options[:proposals] = value }
  opts.on("--scenario NAME", "Fixture scenario: default or inspection-matrix (default: inspection-matrix)") { |value| options[:scenario] = value }
  opts.on("--relay-port PORT", "Local relay port (default: 8787)") { |value| options[:relay_port] = value }
  opts.on("--manifest PATH", "Ignored JSON manifest path") { |value| options[:manifest] = File.expand_path(value, Dir.pwd) }
  opts.on("--device DEVICE", "Simulator device (default: booted)") { |value| options[:device] = value }
  opts.on("--duration-seconds N", "Stop automatically after N seconds") { |value| options[:duration_seconds] = value }
  opts.on("--no-install-ca", "Do not install the local proxy CA") { options[:install_ca] = false }
  opts.on("--no-open", "Do not open the app network endpoint settings deeplink") { options[:open_simulator] = false }
  opts.on("--no-relay", "Do not start the local relay server") { options[:relay] = false }
  opts.on("--no-stop", "Do not stop existing fixture processes first") { options[:stop_existing] = false }
  opts.on("-h", "--help", "Show this help") do
    puts opts
    exit 0
  end
end

extra_fixture_args = parser.order!(ARGV)

if options[:stop_existing]
  stop_script = File.join(repo_root, "scripts", "stop-localnet-fixtures.rb")
  unless system(RbConfig.ruby, stop_script)
    warn "Failed to stop existing localnet fixture processes."
    exit 1
  end
end

command = [
  "cargo",
  "run",
  "--manifest-path",
  File.join(repo_root, "core", "Cargo.toml"),
  "--example",
  "localnet_fixture",
  "--",
  "--browser-proxy-port",
  options[:browser_proxy_port],
  "--squads",
  options[:squads],
  "--proposals",
  options[:proposals],
  "--scenario",
  options[:scenario],
  "--manifest",
  options[:manifest]
]

command.concat(["--member", options[:member]]) if options[:member]

if options[:duration_seconds]
  command.concat(["--duration-seconds", options[:duration_seconds]])
else
  command << "--until-stopped"
end

command.concat(extra_fixture_args)

local_rpc_url = nil
browser_rpc_url = nil
ca_cert_path = nil
configured_simulator = false
child_pid = nil
relay_io = nil
relay_pid = nil
relay_reader = nil
relay_url = nil
local_websocket_url = nil
browser_websocket_url = nil

def local_validator_websocket_url(rpc_url)
  uri = URI(rpc_url)
  return nil unless uri.host && uri.port

  websocket_scheme = uri.scheme == "https" ? "wss" : "ws"
  "#{websocket_scheme}://#{uri.host}:#{uri.port + 1}"
end

stop_relay = lambda do
  if relay_pid
    begin
      Process.kill("TERM", relay_pid)
    rescue Errno::ESRCH
      nil
    end
  end
  relay_reader&.join(2)
  relay_io&.close unless relay_io&.closed?
end

start_relay = lambda do
  return if relay_pid || !options[:relay] || !local_rpc_url

  relay_url = "http://localhost:#{options[:relay_port]}"
  relay_env = {
    "COSIGN_RELAY_BIND_ADDR" => "127.0.0.1:#{options[:relay_port]}",
    "COSIGN_RELAY_RPC_URL" => local_rpc_url
  }
  advertised_websocket_url = browser_websocket_url || local_websocket_url
  relay_env["COSIGN_RELAY_WEBSOCKET_URL"] = advertised_websocket_url if advertised_websocket_url
  relay_env["COSIGN_RELAY_EXPLORER_RPC_URL"] = browser_rpc_url if browser_rpc_url

  relay_command = [
    "cargo",
    "run",
    "--manifest-path",
    File.join(repo_root, "core", "Cargo.toml"),
    "--bin",
    "relay-server"
  ]

  relay_io = IO.popen(relay_env, relay_command, err: [:child, :out])
  relay_pid = relay_io.pid
  relay_reader = Thread.new do
    relay_io.each_line { |line| print "[relay] #{line}" }
  rescue IOError
    nil
  end

  puts "Local relay: #{relay_url}"
  puts "Local relay WebSocket: #{advertised_websocket_url}" if advertised_websocket_url
end

configure_simulator = lambda do
  return if configured_simulator

  fallback_rpc_url = browser_rpc_url || local_rpc_url
  return unless fallback_rpc_url
  start_relay.call
  endpoint_url = relay_url || fallback_rpc_url

  if options[:install_ca] && ca_cert_path && browser_rpc_url&.start_with?("https://")
    if system("xcrun", "simctl", "keychain", options[:device], "add-root-cert", ca_cert_path)
      puts "Installed local RPC proxy CA into simulator #{options[:device]}."
    else
      warn "Failed to install local RPC proxy CA into simulator #{options[:device]}."
    end
  end

  if options[:open_simulator]
    open_script = File.join(repo_root, "scripts", "open-rpc-url.rb")
    if system(RbConfig.ruby, open_script, endpoint_url, options[:device])
      puts "Opened simulator network endpoint settings for #{endpoint_url} on #{options[:device]}."
    else
      warn "Failed to open network endpoint settings deeplink for #{endpoint_url}."
    end
  end

  configured_simulator = true
end

forward_signal = lambda do |signal_name|
  Process.kill(signal_name, child_pid) if child_pid
rescue Errno::ESRCH
  nil
ensure
  stop_relay.call
  exit signal_name == "INT" ? 130 : 143
end

trap("INT") { forward_signal.call("INT") }
trap("TERM") { forward_signal.call("TERM") }

io = IO.popen(command, err: [:child, :out])
child_pid = io.pid

io.each_line do |line|
  print line
  text = line.chomp

  case text
  when /\ALocal validator RPC: (.+)\z/
    local_rpc_url = Regexp.last_match(1).strip
    local_websocket_url = local_validator_websocket_url(local_rpc_url)
  when /\ALocal validator WebSocket: (.+)\z/
    local_websocket_url = Regexp.last_match(1).strip
  when /\ABrowser-safe RPC: (https:\/\/\S+)\z/
    browser_rpc_url = Regexp.last_match(1).strip
  when /\ABrowser-safe WebSocket: (wss:\/\/\S+)\z/
    browser_websocket_url = Regexp.last_match(1).strip
  when /\ATrust simulator CA once: xcrun simctl keychain booted add-root-cert '(.+)'\z/
    ca_cert_path = Regexp.last_match(1).gsub("'\\''", "'")
  when /\AFixture manifest: /
    configure_simulator.call
  when /\AThe validator will stay alive/
    configure_simulator.call
  end
end

_, status = Process.wait2(child_pid)
stop_relay.call
exit(status.exitstatus || 1) unless status.success?
