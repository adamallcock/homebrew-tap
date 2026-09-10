# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "pathname"
require_relative "../scripts/update-cask"

class UpdateCaskTest < Minitest::Test
  ROOT = Pathname(__dir__).join("..").cleanpath
  ARM = "a" * 64
  INTEL = "b" * 64

  def source
    # Stable version fixture: future legitimate cask bumps must not turn these
    # same-version and downgrade regressions into accidental downgrade tests.
    ROOT.join("Casks/tibotattle.rb").binread.sub(TiboTattleCaskUpdater::VERSION_STANZA, '  version "0.1.18"')
  end

  def legacy
    source.sub("#{TiboTattleCaskUpdater::ARCH_STANZA}\n\n", "")
      .sub(TiboTattleCaskUpdater::DUAL_SHA_STANZA, %(  sha256 "#{ARM}"))
      .sub(TiboTattleCaskUpdater::DUAL_URL, TiboTattleCaskUpdater::LEGACY_URL)
      .sub("  depends_on macos:", "  depends_on arch: :arm64\n  depends_on macos:")
  end

  def with_cask(content = source)
    Dir.mktmpdir("tibotattle-cask-test-") do |directory|
      path = Pathname(directory).join("tibotattle.rb")
      path.binwrite(content)
      yield path
    end
  end

  def test_updates_both_hashes_and_preserves_unrelated_install_and_data_contract
    updated = TiboTattleCaskUpdater.render(source, "0.1.19", ARM, INTEL)
    assert_includes updated, '  version "0.1.19"'
    assert_includes updated, %(  sha256 arm:   "#{ARM}",\n         intel: "#{INTEL}")
    assert_equal source.split("  name ", 2).last, updated.split("  name ", 2).last
  end

  def test_same_version_legacy_layout_is_upgraded_without_losing_uninstall_scope
    expected = TiboTattleCaskUpdater.render(source, "0.1.18", ARM, INTEL)
    assert_equal expected, TiboTattleCaskUpdater.render(legacy, "0.1.18", ARM, INTEL)
    refute_includes expected, "depends_on arch:"
  end

  def test_check_detects_same_version_checksum_changes_without_writing
    with_cask do |path|
      original = path.binread
      assert_equal 1, TiboTattleCaskUpdater.update(path, "0.1.18", ARM, INTEL, check_only: true)
      assert_equal original, path.binread
      assert_equal 0, TiboTattleCaskUpdater.update(path, "0.1.18", ARM, INTEL)
      assert_equal 0, TiboTattleCaskUpdater.update(path, "0.1.18", ARM, INTEL, check_only: true)
      assert_equal 1, TiboTattleCaskUpdater.update(path, "0.1.18", ARM, "c" * 64, check_only: true)
    end
  end

  def test_check_identifies_legacy_same_version_layout_without_writing
    with_cask(legacy) do |path|
      original = path.binread
      assert_equal 1, TiboTattleCaskUpdater.update(path, "0.1.18", ARM, INTEL, check_only: true)
      assert_equal original, path.binread
    end
  end

  def test_idempotent_update_does_not_replace_inode
    with_cask(TiboTattleCaskUpdater.render(source, "0.1.19", ARM, INTEL)) do |path|
      before = path.stat
      assert_equal 0, TiboTattleCaskUpdater.update(path, "0.1.19", ARM, INTEL)
      assert_equal before.ino, path.stat.ino
      assert_equal before.mtime, path.stat.mtime
    end
  end

  def test_validates_all_arguments_before_writing
    [["0.1.17", ARM, INTEL], ["0.1.19-rc1", ARM, INTEL], ["0.1.19\ninject", ARM, INTEL],
     ["0.1.19", ARM.upcase, INTEL], ["0.1.19", ARM, "bad"], ["0.1.19", ARM, ""]].each do |arguments|
      with_cask do |path|
        original = path.binread
        assert_raises(ArgumentError) { TiboTattleCaskUpdater.update(path, *arguments) }
        assert_equal original, path.binread
      end
    end
  end

  def test_rejects_ambiguous_or_malformed_layout_without_writing
    variants = [
      source.sub('  version "0.1.18"', "  version \"0.1.18\"\n  version \"0.1.19\""),
      source.sub("  auto_updates true", "  sha256 \"#{ARM}\"\n  auto_updates true"),
      source.sub('intel: "x64"', 'intel: "arm64"'),
      source.sub("macOS-\#{arch}.dmg", "macOS-arm64.dmg"),
      source.sub("  auto_updates true", "  depends_on arch: :arm64\n  auto_updates true"),
      source.sub(/         intel: "[a-f0-9]{64}"/, '         intel: "unknown"'),
    ]
    variants.each do |invalid|
      with_cask(invalid) do |path|
        assert_raises(ArgumentError) { TiboTattleCaskUpdater.update(path, "0.1.19", ARM, INTEL) }
        assert_equal invalid, path.binread
      end
    end
  end

  def test_supports_four_part_versions_with_numeric_ordering
    assert_includes TiboTattleCaskUpdater.render(source, "0.1.18.1", ARM, INTEL), 'version "0.1.18.1"'
    newer = TiboTattleCaskUpdater.render(source, "0.1.19", ARM, INTEL)
    assert_raises(ArgumentError) { TiboTattleCaskUpdater.render(newer, "0.1.18.9", ARM, INTEL) }
  end

  def test_rejects_noncanonical_related_declarations_before_any_write
    [source, legacy].each do |original|
      declarations = [
        '  self.version("0.1.18")',
        "  auto_updates true; sha256(\"#{ARM}\")",
        '  self.arch(arm: "arm64", intel: "x64")',
        "  depends_on(arch: :arm64)",
        "  self.depends_on(arch: :arm64)",
        "    depends_on arch: :arm64",
        "  depends_on(\n    arch: :arm64\n  )",
        "  auto_updates true; depends_on arch: :arm64",
        '    url "https://example.invalid/duplicate.dmg"',
        'url "https://example.invalid/duplicate.dmg"',
        "\turl \"https://example.invalid/duplicate.dmg\"",
        '  url("https://example.invalid/duplicate.dmg")',
        '  self.url "https://example.invalid/duplicate.dmg"',
        '  auto_updates true; url "https://example.invalid/duplicate.dmg"',
        '    url :url',
      ]
      variants = declarations.map do |declaration|
        original.sub("  auto_updates true", "#{declaration}\n  auto_updates true")
      end
      variants.concat([
        original.sub("  depends_on macos: :sonoma", "  depends_on(macos: :sonoma)"),
        original.sub("  depends_on macos: :sonoma", "  depends_on macos: :sonoma, arch: :arm64"),
        original.sub("  livecheck do", "  livecheck do\n    url :url"),
        original.sub("    skip ", "    url :url; skip "),
        original.sub("  livecheck do", "  livecheck do\n    strategy :github_latest\n    url :url\n  end\n\n  livecheck do"),
        original.sub("  depends_on macos: :sonoma", "  depends_on macos: :sonoma\n  if"),
      ])
      variants.each do |invalid|
        [true, false].each do |check_only|
          with_cask(invalid) do |path|
            before = [path.binread, path.stat.ino, path.stat.mtime, path.dirname.children.sort]
            assert_raises(ArgumentError) do
              TiboTattleCaskUpdater.update(path, "0.1.18", ARM, INTEL, check_only: check_only)
            end
            assert_equal before, [path.binread, path.stat.ino, path.stat.mtime, path.dirname.children.sort]
          end
        end
      end
    end
  end

  def test_preserves_unrelated_literal_fields_and_comments
    original = source.sub('  name "TiboTattle"', "  # depends_on(arch: :arm64), url, version, sha256\n  name \"TiboTattle\"")
      .sub('  desc "Local-first monitor for Codex allowance usage"', '  desc "Keywords: depends_on, arch, url, version, sha256"')
    updated = TiboTattleCaskUpdater.render(original, "0.1.19", ARM, INTEL)
    assert_equal original.split("  name ", 2).last, updated.split("  name ", 2).last
    assert_includes updated, "  # depends_on(arch: :arm64), url, version, sha256\n"
  end

  def test_rejects_symlinks_and_preserves_existing_temporary_file
    with_cask do |path|
      link = Pathname("#{path}.link")
      File.symlink(path, link)
      assert_raises(ArgumentError) { TiboTattleCaskUpdater.update(link, "0.1.19", ARM, INTEL) }
      original = path.binread
      temporary = Pathname("#{path}.tmp.#{$$}")
      temporary.binwrite("preserve this unrelated file")
      assert_raises(Errno::EEXIST) { TiboTattleCaskUpdater.update(path, "0.1.19", ARM, INTEL) }
      assert_equal "preserve this unrelated file", temporary.binread
      assert_equal original, path.binread
    end
  end

  def test_cli_rejects_missing_intel_checksum
    assert_equal 2, TiboTattleCaskUpdater.run(["0.1.18", ARM])
  end

  def test_cli_check_accepts_the_actual_cask_version_and_both_hashes_without_writing
    actual = ROOT.join("Casks/tibotattle.rb").binread
    version = actual.match(TiboTattleCaskUpdater::VERSION_STANZA)[1]
    hashes = actual.match(TiboTattleCaskUpdater::DUAL_SHA_STANZA).captures
    assert_equal 0, TiboTattleCaskUpdater.run(["--check", version, *hashes])
    assert_equal actual, ROOT.join("Casks/tibotattle.rb").binread
  end
end
