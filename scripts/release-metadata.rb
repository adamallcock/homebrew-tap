#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

abort "Usage: ruby scripts/release-metadata.rb RELEASE_JSON" unless ARGV.length == 1

begin
  release = JSON.parse(File.binread(ARGV.fetch(0)))
  raise "Expected a public immutable stable release" unless release.is_a?(Hash) &&
    release["draft"] == false && release["prerelease"] == false && release["immutable"] == true
  tag = release.fetch("tag_name")
  raise "Invalid release tag" unless tag.is_a?(String) && /\Av[0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?\z/.match?(tag)
  version = tag.delete_prefix("v")
  raise "Electron automatic replacement requires version 0.1.20 or later" if (version.split(".").map(&:to_i) <=> [0, 1, 20]) == -1
  assets = release.fetch("assets")
  raise "Invalid assets" unless assets.is_a?(Array)
  output = { "version" => version }
  { "arm64" => "arm64", "intel" => "x64" }.each do |key, suffix|
    name = "TiboTattle-#{version}-mac-#{suffix}.dmg"
    matches = assets.select { |asset| asset.is_a?(Hash) && asset["name"] == name }
    raise "Expected exactly one #{suffix} installer" unless matches.length == 1
    asset = matches.fetch(0)
    url = "https://github.com/adamallcock/tibotattle/releases/download/#{tag}/#{name}"
    raise "Installer URL is not the exact official asset" unless asset["browser_download_url"] == url
    size = asset["size"]
    raise "Invalid installer size" unless size.is_a?(Integer) && size.positive? && size <= 9_007_199_254_740_991
    digest = asset["digest"]
    raise "Missing or invalid GitHub SHA-256 digest" unless digest.is_a?(String) && /\Asha256:[a-f0-9]{64}\z/.match?(digest)
    output["#{key}_url"] = url
    output["#{key}_size"] = size
    output["#{key}_sha256"] = digest.delete_prefix("sha256:")
  end
  # Validate the entire pair before emitting anything consumed by GITHUB_OUTPUT.
  puts output.map { |key, value| "#{key}=#{value}" }
rescue JSON::ParserError, KeyError, TypeError, RuntimeError, SystemCallError => error
  warn "Release metadata rejected: #{error.message}"
  exit 2
end
