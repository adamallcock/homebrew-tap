#!/usr/bin/env ruby
# frozen_string_literal: true

require "pathname"

VERSION_PATTERN = /\A[0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?\z/
SHA256_PATTERN = /\A[a-f0-9]{64}\z/

unless ARGV.length == 2
  abort "Usage: ruby scripts/update-cask.rb VERSION SHA256"
end

version, sha256 = ARGV
abort "Version must be a numeric three- or four-part version" unless VERSION_PATTERN.match?(version)
abort "SHA-256 must be 64 lowercase hexadecimal characters" unless SHA256_PATTERN.match?(sha256)

cask_path = Pathname(__dir__).join("..", "Casks", "tibotattle.rb").cleanpath
abort "Cask must be a regular file" unless cask_path.file? && !cask_path.symlink?

source = cask_path.binread
version_lines = source.scan(/^  version "[^"]+"$/)
sha256_lines = source.scan(/^  sha256 "[a-f0-9]+"$/)
abort "Cask must contain exactly one version stanza" unless version_lines.length == 1
abort "Cask must contain exactly one SHA-256 stanza" unless sha256_lines.length == 1

updated = source
  .sub(/^  version "[^"]+"$/, %(  version "#{version}"))
  .sub(/^  sha256 "[a-f0-9]+"$/, %(  sha256 "#{sha256}"))

if updated == source
  puts "TiboTattle cask already records version #{version} and SHA-256 #{sha256}"
  exit 0
end

temporary_path = Pathname("#{cask_path}.tmp.#{$$}")
begin
  File.open(
    temporary_path,
    File::WRONLY | File::CREAT | File::EXCL,
    0o644,
  ) do |file|
    file.write(updated)
    file.flush
    file.fsync
  end
  File.rename(temporary_path, cask_path)
ensure
  temporary_path.delete if temporary_path.exist?
end

puts "Updated TiboTattle cask to version #{version} with SHA-256 #{sha256}"
