#!/usr/bin/env ruby
# frozen_string_literal: true

require "pathname"
require "ripper"

module TiboTattleCaskUpdater
  VERSION_PATTERN = /\A[0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?\z/
  SHA256_PATTERN = /\A[a-f0-9]{64}\z/
  VERSION_STANZA = /^  version "([^"]+)"$/
  SINGLE_SHA_STANZA = /^  sha256 "([a-f0-9]{64})"$/
  DUAL_SHA_STANZA = /^  sha256 arm:   "([a-f0-9]{64})",\n         intel: "([a-f0-9]{64})"$/
  ARCH_STANZA = '  arch arm: "arm64", intel: "x64"'
  LEGACY_URL = '  url "https://github.com/adamallcock/tibotattle/releases/download/v#{version}/TiboTattle-#{version}-macOS-arm64.dmg"'
  DUAL_URL = '  url "https://github.com/adamallcock/tibotattle/releases/download/v#{version}/TiboTattle-#{version}-macOS-#{arch}.dmg"'
  LIVECHECK_STANZA = "  livecheck do\n    skip \"Native channel stays on 0.1.18; use tibotattle.com for guided Electron migration\"\n  end\n"
  OWNED_DECLARATIONS = %w[version sha256 arch url depends_on livecheck].freeze

  # Only the reviewed declaration spellings are supported. Ruby's lexer also
  # finds parenthesized, receiver-qualified and inline calls without treating
  # comments or unrelated literal strings as declarations. No Ruby is evaluated.
  def self.validate_declarations(source)
    raise ArgumentError, "Cask must contain valid Ruby syntax" unless Ripper.sexp(source)

    # Exclude only the reviewed native-channel livecheck block. A duplicate
    # or modified block remains visible and is refused.
    declarations = source.sub(LIVECHECK_STANZA, "")
    lines = declarations.lines.map(&:chomp)
    canonical_lines = [ARCH_STANZA, LEGACY_URL, DUAL_URL,
                       "  depends_on arch: :arm64", "  depends_on macos: :sonoma"]
    Ripper.lex(declarations).each do |position, kind, token|
      next unless kind == :on_ident && OWNED_DECLARATIONS.include?(token)

      line = lines.fetch(position.first - 1)
      next if canonical_lines.include?(line) || line.match?(VERSION_STANZA) ||
              line.match?(SINGLE_SHA_STANZA) || line.match?(/^  sha256 arm:   "[a-f0-9]{64}",$/)

      raise ArgumentError, "Cask must use canonical owned declarations"
    end
  end
  private_class_method :validate_declarations

  def self.render(source, version, arm_sha256, intel_sha256)
    raise ArgumentError, "Version must be a numeric three- or four-part version" unless VERSION_PATTERN.match?(version)
    unless [arm_sha256, intel_sha256].all? { |sha| SHA256_PATTERN.match?(sha) }
      raise ArgumentError, "Both SHA-256 values must be 64 lowercase hexadecimal characters"
    end
    raise ArgumentError, "Unexpected cask header" unless source.start_with?("cask \"tibotattle\" do\n")
    validate_declarations(source)
    versions = source.scan(VERSION_STANZA).flatten
    unless versions.length == 1 && source.scan(/^\s*version\b/).length == 1 && VERSION_PATTERN.match?(versions.first)
      raise ArgumentError, "Cask must contain exactly one numeric version stanza"
    end
    current_parts = versions.first.split(".").map(&:to_i).fill(0, versions.first.split(".").length...4)
    target_parts = version.split(".").map(&:to_i).fill(0, version.split(".").length...4)
    raise ArgumentError, "Refusing a version downgrade" if (target_parts <=> current_parts) == -1
    unless source.scan(/^\s*sha256\b/).length == 1 && source.scan(/^  url /).length == 1
      raise ArgumentError, "Cask must contain exactly one checksum and download stanza"
    end

    legacy = source.match?(SINGLE_SHA_STANZA)
    if legacy
      unless source.lines.count { |line| line.chomp == LEGACY_URL } == 1 &&
             source.scan(/^\s*arch\b/).empty? &&
             source.scan(/^\s*depends_on arch:/).length == 1 &&
             source.lines.count { |line| line.chomp == "  depends_on arch: :arm64" } == 1
        raise ArgumentError, "Unsupported legacy architecture layout"
      end
    else
      unless source.match?(DUAL_SHA_STANZA) &&
             source.lines.count { |line| line.chomp == ARCH_STANZA } == 1 &&
             source.scan(/^\s*arch\b/).length == 1 &&
             source.scan(/^\s*depends_on arch:/).empty? &&
             source.lines.count { |line| line.chomp == DUAL_URL } == 1
        raise ArgumentError, "Cask must contain the exact dual-architecture layout"
      end
    end

    hashes = %(  sha256 arm:   "#{arm_sha256}",\n         intel: "#{intel_sha256}")
    updated = source.sub(VERSION_STANZA, %(  version "#{version}"))
    if legacy
      updated = updated.sub("cask \"tibotattle\" do\n", "cask \"tibotattle\" do\n#{ARCH_STANZA}\n\n")
        .sub(SINGLE_SHA_STANZA, hashes).sub(LEGACY_URL, DUAL_URL)
        .sub("  depends_on arch: :arm64\n", "")
    else
      updated = updated.sub(DUAL_SHA_STANZA, hashes)
    end
    updated
  end

  # Validate everything before the sole atomic replacement. --check never
  # writes, and reports layout/hash changes even when the version is unchanged.
  def self.update(cask_path, version, arm_sha256, intel_sha256, check_only: false)
    cask_path = Pathname(cask_path)
    raise ArgumentError, "Cask must be a regular file" unless cask_path.file? && !cask_path.symlink?
    source = cask_path.binread
    updated = render(source, version, arm_sha256, intel_sha256)
    return updated == source ? 0 : 1 if check_only
    return 0 if updated == source

    temporary_path = Pathname("#{cask_path}.tmp.#{$$}")
    created = false
    begin
      File.open(temporary_path, File::WRONLY | File::CREAT | File::EXCL, 0o644) do |file|
        created = true
        file.write(updated)
        file.flush
        file.fsync
      end
      unless cask_path.file? && !cask_path.symlink? && cask_path.binread == source
        raise ArgumentError, "Cask changed during update; refusing replacement"
      end
      File.rename(temporary_path, cask_path)
    ensure
      temporary_path.delete if created && temporary_path.exist?
    end
    0
  end

  def self.run(arguments)
    args = arguments.dup
    check_only = args.first == "--check"
    args.shift if check_only
    unless args.length == 3
      warn "Usage: ruby scripts/update-cask.rb [--check] VERSION ARM_SHA256 INTEL_SHA256"
      return 2
    end
    cask_path = Pathname(__dir__).join("..", "Casks", "tibotattle.rb").cleanpath
    result = update(cask_path, *args, check_only: check_only)
    puts(check_only ? (result.zero? ? "Cask is current for both architectures" : "Cask update required") : "Cask records both architecture checksums")
    result
  rescue ArgumentError, SystemCallError => error
    warn error.message
    2
  end
end

exit TiboTattleCaskUpdater.run(ARGV) if $PROGRAM_NAME == __FILE__
