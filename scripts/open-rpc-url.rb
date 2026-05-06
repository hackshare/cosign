#!/usr/bin/env ruby
# frozen_string_literal: true

require "uri"
require "optparse"

options = {
  scheme: ENV.fetch("COSIGN_DEV_URL_SCHEME", "cosign-dev")
}

OptionParser.new do |parser|
  parser.banner = "Usage: scripts/open-rpc-url.rb [--demo|--scheme SCHEME] ENDPOINT_URL [simulator-device]"
  parser.on("--demo", "Open the Cosign Demo app URL scheme.") do
    options[:scheme] = "cosign-demo-dev"
  end
  parser.on("--scheme SCHEME", "Open a specific Cosign developer URL scheme.") do |scheme|
    options[:scheme] = scheme
  end
end.parse!

rpc_url = ARGV.fetch(0) do
  warn "Usage: scripts/open-rpc-url.rb [--demo|--scheme SCHEME] ENDPOINT_URL [simulator-device]"
  exit 1
end
device = ARGV.fetch(1, "booted")

deep_link = "#{options.fetch(:scheme)}://network/rpc?url=#{URI.encode_www_form_component(rpc_url)}"
unless system("xcrun", "simctl", "openurl", device, deep_link)
  warn "Failed to open Cosign network endpoint settings link on simulator device #{device}."
  exit 1
end

puts "Opened Cosign network endpoint settings link with #{options.fetch(:scheme)} on simulator device #{device}."
