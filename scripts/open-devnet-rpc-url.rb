#!/usr/bin/env ruby
# frozen_string_literal: true

require "uri"
require "optparse"

options = {
  scheme: ENV.fetch("COSIGN_DEV_URL_SCHEME", "cosign-dev")
}

OptionParser.new do |parser|
  parser.banner = "Usage: scripts/open-devnet-rpc-url.rb [--demo|--scheme SCHEME] [simulator-device]"
  parser.on("--demo", "Open the Cosign Demo app URL scheme.") do
    options[:scheme] = "cosign-demo-dev"
  end
  parser.on("--scheme SCHEME", "Open a specific Cosign developer URL scheme.") do |scheme|
    options[:scheme] = scheme
  end
end.parse!

env_path = ENV.fetch("COSIGN_ENV_FILE", ".env.devnet")
device = ARGV.fetch(0, "booted")

unless File.exist?(env_path)
  warn "Missing #{env_path}. Copy .env.devnet.example and add COSIGN_DEVNET_RPC_URL."
  exit 1
end

rpc_url = nil
File.foreach(env_path) do |line|
  stripped = line.strip
  next if stripped.empty? || stripped.start_with?("#")

  key, value = stripped.split("=", 2)
  next unless key == "COSIGN_DEVNET_RPC_URL"

  rpc_url = value&.strip
  if rpc_url&.start_with?('"') && rpc_url.end_with?('"')
    rpc_url = rpc_url[1...-1]
  elsif rpc_url&.start_with?("'") && rpc_url.end_with?("'")
    rpc_url = rpc_url[1...-1]
  end
  break
end

if rpc_url.nil? || rpc_url.empty?
  warn "COSIGN_DEVNET_RPC_URL is not set in #{env_path}."
  exit 1
end

deep_link = "#{options.fetch(:scheme)}://network/rpc?url=#{URI.encode_www_form_component(rpc_url)}"
unless system("xcrun", "simctl", "openurl", device, deep_link)
  warn "Failed to open Cosign network endpoint settings link on simulator device #{device}."
  exit 1
end

puts "Opened Cosign network endpoint settings link with #{options.fetch(:scheme)} on simulator device #{device}."
