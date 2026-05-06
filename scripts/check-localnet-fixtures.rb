#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "optparse"
require "rbconfig"
require "uri"

$stdout.sync = true
$stderr.sync = true

repo_root = File.expand_path("..", __dir__)
options = {
  manifest: File.join(repo_root, ".cosign-local", "localnet-fixture.json"),
  check_browser_proxy: true,
  relay_url: ENV["COSIGN_RELAY_URL"]
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: ruby scripts/check-localnet-fixtures.rb [options]"
  opts.on("--manifest PATH", "JSON fixture manifest") { |value| options[:manifest] = File.expand_path(value, Dir.pwd) }
  opts.on("--rpc-url URL", "Override manifest local validator RPC URL") { |value| options[:rpc_url] = value }
  opts.on("--relay-url URL", "Check the local relay indexed reads") { |value| options[:relay_url] = value }
  opts.on("--no-browser-proxy", "Skip browser-safe proxy health check") { options[:check_browser_proxy] = false }
  opts.on("-h", "--help", "Show this help") do
    puts opts
    exit 0
  end
end
parser.parse!(ARGV)

def relay_endpoint(base_url, path)
  uri = URI(base_url)
  base_path = uri.path.to_s.sub(%r{/\z}, "")
  child_path, child_query = path.split("?", 2)
  child_path = child_path.sub(%r{\A/+}, "")
  endpoint_path = [base_path, child_path].reject(&:empty?).join("/")
  uri.path = endpoint_path.start_with?("/") ? endpoint_path : "/#{endpoint_path}"
  uri.query = [uri.query, child_query].compact.reject(&:empty?).join("&")
  uri
end

def get_json(uri)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == "https"
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE if loopback?(uri)

  response = http.request(Net::HTTP::Get.new(uri.request_uri))
  raise "GET #{uri} failed with HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

  JSON.parse(response.body)
end

def check_rpc_health(rpc_url)
  uri = URI(rpc_url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == "https"
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE if loopback?(uri)

  request = Net::HTTP::Post.new(uri.request_uri.empty? ? "/" : uri.request_uri)
  request["Content-Type"] = "application/json"
  request.body = JSON.generate(
    jsonrpc: "2.0",
    id: 1,
    method: "getHealth"
  )

  response = http.request(request)
  raise "RPC health check failed with HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

  body = JSON.parse(response.body)
  raise "RPC health check failed: #{body}" unless body["result"] == "ok"
end

def check_relay_indexed_squads(relay_url, manifest)
  capabilities = get_json(relay_endpoint(relay_url, "/cosign/v1/capabilities"))
  unless capabilities.fetch("capabilities", []).include?("squads_indexing")
    raise "Relay at #{relay_url} does not advertise squads_indexing"
  end
  unless capabilities.fetch("capabilities", []).include?("squad_detail")
    raise "Relay at #{relay_url} does not advertise squad_detail"
  end
  [
    "squad_proposals",
    "proposal_detail",
    "account_activity",
    "transaction_status",
    "proposal_inspection",
    "executed_transaction_inspection",
    "known_program_decoding",
    "action_effects",
    "rpc_method_filtering",
    "transaction_attribution"
  ].each do |capability|
    unless capabilities.fetch("capabilities", []).include?(capability)
      raise "Relay at #{relay_url} does not advertise #{capability}"
    end
  end
  if manifest["browser_safe_rpc_url"] && capabilities["explorerRPCURL"] != manifest["browser_safe_rpc_url"]
    raise "Relay explorerRPCURL does not match browser-safe RPC URL"
  end

  member = manifest.fetch("browser_member")
  indexed = get_json(relay_endpoint(relay_url, "/cosign/v1/members/#{member}/squads"))
  indexed_addresses = indexed.fetch("squads").map { |squad| squad.fetch("address") }
  missing = manifest.fetch("squads").filter_map do |squad|
    squad.fetch("multisig") unless indexed_addresses.include?(squad.fetch("multisig"))
  end
  raise "Relay indexed squads missing manifest Squads: #{missing.join(", ")}" unless missing.empty?

  manifest.fetch("squads").each do |squad|
    detail = get_json(relay_endpoint(relay_url, "/cosign/v1/squads/#{squad.fetch("multisig")}"))
    indexed_detail = detail.fetch("squad")
    unless indexed_detail.fetch("address") == squad.fetch("multisig")
      raise "Relay detail returned wrong Squad: #{indexed_detail.fetch("address")}"
    end
    unless indexed_detail.fetch("vaults").length == squad.fetch("vaults").length
      raise "Relay detail returned wrong vault count for #{squad.fetch("multisig")}"
    end

    expected_proposals = squad.fetch("proposals")
    proposals = get_json(relay_endpoint(
      relay_url,
      "/cosign/v1/squads/#{squad.fetch("multisig")}/proposals?from=1&to=#{expected_proposals.length}"
    ))
    unless proposals.fetch("proposals").length == expected_proposals.length
      raise "Relay proposals returned wrong count for #{squad.fetch("multisig")}"
    end

    expected_proposals.each do |proposal|
      detail = get_json(relay_endpoint(
        relay_url,
        "/cosign/v1/squads/#{squad.fetch("multisig")}/proposals/#{proposal.fetch("transaction_index")}"
      ))
      unless detail.fetch("proposal").fetch("transactionAddress") == proposal.fetch("transaction_account")
        raise "Relay proposal detail returned wrong transaction account for #{squad.fetch("multisig")}"
      end

      inspection = get_json(relay_endpoint(
        relay_url,
        "/cosign/v1/squads/#{squad.fetch("multisig")}/transactions/#{proposal.fetch("transaction_index")}/inspection?format=json"
      ))
      unless inspection.fetch("proposal").fetch("transactionIndex") == proposal.fetch("transaction_index")
        raise "Relay proposal inspection returned wrong transaction index for #{squad.fetch("multisig")}"
      end
      if inspection.fetch("action").fetch("summary").empty?
        raise "Relay proposal inspection returned an empty action summary for #{squad.fetch("multisig")}"
      end

      next unless proposal["execution_signature"]

      status = get_json(relay_endpoint(
        relay_url,
        "/cosign/v1/transactions/#{proposal.fetch("execution_signature")}/status"
      ))
      status.fetch("status").fetch("status")

      executed_inspection = get_json(relay_endpoint(
        relay_url,
        "/cosign/v1/transactions/#{proposal.fetch("execution_signature")}/inspection?format=json"
      ))
      unless executed_inspection.fetch("signature") == proposal.fetch("execution_signature")
        raise "Relay executed inspection returned wrong signature for #{proposal.fetch("execution_signature")}"
      end
      if executed_inspection.fetch("action").fetch("summary").empty?
        raise "Relay executed inspection returned an empty action summary for #{proposal.fetch("execution_signature")}"
      end
    end

    activity = get_json(relay_endpoint(
      relay_url,
      "/cosign/v1/accounts/#{squad.fetch("multisig")}/activity?limit=5"
    ))
    activity.fetch("activity")
  end

  puts "Relay indexed Squads OK: #{relay_url}"
end

def loopback?(uri)
  ["localhost", "127.0.0.1", "::1"].include?(uri.host)
end

unless File.file?(options[:manifest])
  warn "Missing localnet fixture manifest: #{options[:manifest]}"
  warn "Start one with: ruby scripts/start-localnet-fixtures.rb --member <pubkey>"
  exit 1
end

manifest = JSON.parse(File.read(options[:manifest]))

if options[:check_browser_proxy] && manifest["browser_safe_rpc_url"]
  check_rpc_health(manifest["browser_safe_rpc_url"])
  puts "Browser-safe RPC health OK: #{manifest["browser_safe_rpc_url"]}"
end

check_relay_indexed_squads(options[:relay_url], manifest) if options[:relay_url]

command = [
  "cargo",
  "run",
  "--manifest-path",
  File.join(repo_root, "core", "Cargo.toml"),
  "--example",
  "check_localnet_fixture",
  "--",
  "--manifest",
  options[:manifest]
]
command.concat(["--rpc-url", options[:rpc_url]]) if options[:rpc_url]

exit 1 unless system(*command)
