# frozen_string_literal: true

require "minitest/autorun"
require "pathname"
require "yaml"
require "json"
require "open3"
require "tmpdir"
require "fileutils"
require "rbconfig"

class WorkflowsTest < Minitest::Test
  ROOT = Pathname(__dir__).join("..").cleanpath
  UPDATE_WORKFLOW = ".github/workflows/update-tibotattle.yml"
  WORKFLOWS = [".github/workflows/ci.yml", UPDATE_WORKFLOW].freeze

  def workflow(path = UPDATE_WORKFLOW)
    YAML.load_file(ROOT.join(path))
  end

  def native_matrix(job)
    job.fetch("strategy").fetch("matrix").fetch("include")
  end

  def test_both_workflows_run_native_arm_and_intel_with_host_checks
    WORKFLOWS.each do |path|
      jobs = workflow(path).fetch("jobs")
      job = jobs.fetch(path == UPDATE_WORKFLOW ? "verify" : "validate")
      assert_equal [
        { "runner" => "macos-15", "cpu" => "arm64", "suffix" => "arm64" },
        { "runner" => "macos-15-intel", "cpu" => "x86_64", "suffix" => "x64" },
      ], native_matrix(job)
      assert_equal false, job.dig("strategy", "fail-fast")
      assert_equal "${{ matrix.runner }}", job.fetch("runs-on")
      assert job.fetch("steps").any? { |step| step["run"].to_s.include?('test "$(uname -m)" = "$EXPECTED_CPU"') }
    end
  end

  def test_every_online_audit_uses_the_actions_token_and_verifies_native_selection
    WORKFLOWS.each do |path|
      audits = workflow(path).fetch("jobs").values.flat_map { |job| job.fetch("steps") }
        .select { |step| step["run"].to_s.include?("brew audit --cask --online") }
      assert_equal 1, audits.length
      step = audits.fetch(0)
      assert_equal "${{ github.token }}", step.dig("env", "HOMEBREW_GITHUB_API_TOKEN")
      assert_includes step.fetch("run"), "brew info --cask --json=v2"
      assert_includes step.fetch("run"), ".casks[0].url"
      assert_includes step.fetch("run"), "bash scripts/verify-app.sh"
      assert_includes step.fetch("run"), 'brew install --cask --appdir="$appdir"'
      assert_includes step.fetch("run"), "brew uninstall --cask tibotattle/ci/tibotattle"
      assert_includes step.fetch("run"), "brew trust --cask tibotattle/ci/tibotattle"
      assert_operator step.fetch("run").index('cmp Casks/tibotattle.rb'), :<,
        step.fetch("run").index('brew trust --cask tibotattle/ci/tibotattle')
      assert_includes step.fetch("run"), ".casks[0].installed == null"
      refute_match(/HOMEBREW_REQUIRE_TAP_TRUST|brew (?:untap|uninstall).*--force/, step.fetch("run"))
    end
  end

  def test_temporary_tap_cleanup_revokes_exact_trust_and_removes_cask_before_untap
    WORKFLOWS.each do |path|
      step = workflow(path).fetch("jobs").values.flat_map { |job| job.fetch("steps") }
        .find { |item| item["run"].to_s.include?("cleanup_tap()") }
      cleanup = step.fetch("run")[/cleanup_tap\(\) \{.*?trap cleanup_tap EXIT/m]
      refute_nil cleanup
      [[0, 0, 0, 0], [5, 0, 0, 5], [0, 7, 0, 7], [5, 7, 0, 5], [0, 0, 9, 9]].each do |initial, cleanup_failure, remove_failure, expected|
        Dir.mktmpdir("tibotattle-tap-cleanup-") do |directory|
          FileUtils.mkdir_p(File.join(directory, "Casks"))
          File.write(File.join(directory, "Casks/tibotattle.rb"), "synthetic")
          script = <<~BASH
            set -euo pipefail
            brew() {
              printf '%s\\n' "$*" >> "$CLEANUP_LOG"
              if [[ "$1" = untap ]]; then
                test ! -e "$tap_path/Casks/tibotattle.rb" || exit 11
              fi
              if [[ "$1" = untrust ]]; then return "$CLEANUP_FAILURE"; fi
            }
            rm() {
              if [[ "$REMOVE_FAILURE" != 0 ]]; then return "$REMOVE_FAILURE"; fi
              command rm "$@"
            }
            #{cleanup}
            exit "$INITIAL_STATUS"
          BASH
          log = File.join(directory, "log")
          env = { "tap_path" => directory, "CLEANUP_LOG" => log, "INITIAL_STATUS" => initial.to_s,
            "CLEANUP_FAILURE" => cleanup_failure.to_s, "REMOVE_FAILURE" => remove_failure.to_s }
          _stdout, stderr, status = Open3.capture3(env, "bash", "-c", script)
          assert_equal expected, status.exitstatus, stderr
          expected_calls = ["untrust --cask tibotattle/ci/tibotattle"]
          expected_calls << "untap tibotattle/ci" if remove_failure.zero?
          assert_equal expected_calls, File.readlines(log, chomp: true)
          assert_equal !remove_failure.zero?, File.exist?(File.join(directory, "Casks/tibotattle.rb"))
        end
      end
    end
  end

  def test_publication_requires_main_unchanged_source_and_both_native_results
    source = workflow
    assert_equal "read", source.dig("permissions", "contents")
    source.fetch("jobs").reject { |name, _job| name == "commit" }.each_value do |job|
      refute_equal "write", job.dig("permissions", "contents")
      job.fetch("steps").each do |step|
        refute_match(/\bgit (?:push|commit)\b/, step["run"].to_s)
      end
    end
    candidate = source.fetch("jobs").fetch("commit")
    assert_equal ["resolve", "verify"], candidate.fetch("needs")
    assert_equal "github.ref == 'refs/heads/main' && needs.resolve.outputs.needed == 'true' && needs.verify.result == 'success'", candidate.fetch("if")
    assert_equal "write", candidate.dig("permissions", "contents")
    assert_equal "main", candidate.fetch("steps").first.dig("with", "ref")
    publication = candidate.fetch("steps").last.fetch("run")
    assert_includes publication, 'test "$GITHUB_REF" = refs/heads/main'
    assert_includes publication, 'test "$(git rev-parse HEAD)" = "$EXPECTED_BASE"'
    assert_includes publication, 'test "$(git diff --name-only)" = Casks/tibotattle.rb'
    assert_includes publication, "git push origin HEAD:main"
    refute_match(/--force|\s-f\b/, publication)
    verify = source.fetch("jobs").fetch("verify")
    assert_equal "needs.resolve.outputs.needed == 'true'", verify.fetch("if")
    assert_equal "${{ needs.resolve.outputs.base_commit }}", verify.fetch("steps").first.dig("with", "ref")
  end

  def test_digest_aware_skip_executes_the_checker_contract_instead_of_version_only_comparison
    step = workflow.fetch("jobs").fetch("resolve").fetch("steps").find { |item| item["id"] == "check" }
    script = step.fetch("run")
    Dir.mktmpdir("tibotattle-workflow-check-") do |directory|
      executable = File.join(directory, "ruby")
      File.write(executable, "#!#{RbConfig.ruby}\nrequire 'json'\nFile.write(ENV.fetch('CHECK_ARGS'), JSON.generate(ARGV))\nexit Integer(ENV.fetch('CHECK_STATUS'))\n")
      File.chmod(0o700, executable)
      [[0, false, "needed=false\n"], [1, false, "needed=true\n"], [0, true, "needed=true\n"], [2, true, nil]].each do |status, force, expected|
        output = File.join(directory, "output")
        File.write(output, "")
        args = File.join(directory, "args")
        env = { "PATH" => "#{directory}:#{ENV.fetch('PATH')}", "CHECK_ARGS" => args,
          "CHECK_STATUS" => status.to_s, "GITHUB_OUTPUT" => output, "VERSION" => "0.1.18",
          "ARM_SHA256" => "a" * 64, "INTEL_SHA256" => "b" * 64, "FORCE_VERIFY" => force.to_s }
        _stdout, stderr, result = Open3.capture3(env, "bash", "-c", script, chdir: ROOT.to_s)
        assert_equal expected.nil? ? 2 : 0, result.exitstatus, stderr
        assert_equal expected || "", File.read(output)
        assert_equal ["scripts/update-cask.rb", "--check", "0.1.18", "a" * 64, "b" * 64], JSON.parse(File.read(args))
      end
    end
  end

  def valid_release
    version = "0.1.21"
    { "tag_name" => "v#{version}", "draft" => false, "prerelease" => false, "immutable" => true,
      "assets" => [["arm64", "a"], ["x64", "b"]].map do |suffix, hash|
        name = "TiboTattle-#{version}-mac-#{suffix}.dmg"
        { "name" => name, "size" => 5000, "digest" => "sha256:#{hash * 64}",
          "browser_download_url" => "https://github.com/adamallcock/tibotattle/releases/download/v#{version}/#{name}" }
      end }
  end

  def run_metadata(release)
    Dir.mktmpdir("tibotattle-release-fixture-") do |directory|
      file = File.join(directory, "release.json")
      File.write(file, JSON.generate(release))
      Open3.capture3(RbConfig.ruby, ROOT.join("scripts/release-metadata.rb").to_s, file)
    end
  end

  def test_resolver_rejects_electron_before_021_before_emitting_results
    step = workflow.fetch("jobs").fetch("resolve").fetch("steps").find { |item| item["id"] == "metadata" }
    refute step.fetch("env").key?("NATIVE_RELEASE_TAG")
    assert_includes step.fetch("run"), 'gh api repos/adamallcock/tibotattle/releases/latest'
    Dir.mktmpdir("tibotattle-channel-test-") do |directory|
      gh = File.join(directory, "gh")
      File.write(gh, "#!/bin/bash\nset -euo pipefail\ntest \"$*\" = 'api repos/adamallcock/tibotattle/releases/latest'\ncat \"$LATEST_FIXTURE\"\n")
      File.chmod(0o700, gh)
      ["0.1.19", "0.1.20", "0.1.21"].each do |version|
        release = JSON.parse(JSON.generate(valid_release).gsub("0.1.21", version))
        latest = File.join(directory, "latest.json"); File.write(latest, JSON.generate(release))
        output = File.join(directory, "output"); File.write(output, "")
        env = { "PATH" => "#{directory}:#{ENV.fetch('PATH')}", "RUNNER_TEMP" => directory,
          "GITHUB_OUTPUT" => output, "LATEST_FIXTURE" => latest }
        _stdout, stderr, status = Open3.capture3(env, "bash", "-c", step.fetch("run"), chdir: ROOT.to_s)
        if version != "0.1.21"
          assert_equal 2, status.exitstatus, stderr
          assert_empty File.read(output)
        else
          assert status.success?, stderr
          values = File.readlines(output).to_h { |line| line.strip.split("=", 2) }
          assert_equal version, values.fetch("version")
          assert_equal "a" * 64, values.fetch("arm64_sha256")
          assert_equal "b" * 64, values.fetch("intel_sha256")
        end
      end
    end
  end

  def test_release_metadata_emits_both_exact_asset_digests_and_sizes
    stdout, stderr, status = run_metadata(valid_release)
    assert status.success?, stderr
    values = stdout.lines.to_h { |line| line.strip.split("=", 2) }
    assert_equal "0.1.21", values.fetch("version")
    assert_equal "a" * 64, values.fetch("arm64_sha256")
    assert_equal "b" * 64, values.fetch("intel_sha256")
    assert_equal "5000", values.fetch("intel_size")
    assert_equal valid_release.fetch("assets").last.fetch("browser_download_url"), values.fetch("intel_url")
  end

  def test_release_metadata_refuses_incomplete_ambiguous_or_mutable_release_before_any_output
    mutations = [
      ->(r) { r["assets"].pop },
      ->(r) { r["assets"].each { |asset| asset["name"] = asset["name"].sub("mac-", "macOS-") } },
      ->(r) { r["tag_name"] = "v0.1.19" },
      ->(r) { r["assets"] << r["assets"].last.dup },
      ->(r) { r["assets"].last["digest"] = nil },
      ->(r) { r["assets"].last["digest"] = "sha256:#{"A" * 64}" },
      ->(r) { r["assets"].last["browser_download_url"] = r["assets"].first["browser_download_url"] },
      ->(r) { r["assets"].last["size"] = 0 },
      ->(r) { r["assets"].last["size"] = "5000" },
      ->(r) { r["immutable"] = false },
      ->(r) { r["draft"] = true },
      ->(r) { r["prerelease"] = true },
      ->(r) { r["tag_name"] = "v0.1.18\nneeded=true" },
    ]
    mutations.each do |mutate|
      release = valid_release
      mutate.call(release)
      stdout, stderr, status = run_metadata(release)
      assert_equal 2, status.exitstatus, stderr
      assert_equal "", stdout, "No partial ARM result may escape after Intel rejection"
    end
  end

  def test_every_workflow_shell_block_parses_without_execution
    WORKFLOWS.each do |path|
      workflow(path).fetch("jobs").each_value do |job|
        job.fetch("steps").each do |step|
          next unless step["run"]
          _stdout, stderr, status = Open3.capture3("bash", "-n", stdin_data: step.fetch("run"))
          assert status.success?, "#{path}: #{step['name']}: #{stderr}"
        end
      end
    end
  end

  def test_native_app_verifier_checks_identity_version_minimum_os_main_node_arch_and_signature
    Dir.mktmpdir("tibotattle-native-fixture-") do |directory|
      app = File.join(directory, "TiboTattle.app")
      ["Contents/Info.plist", "Contents/MacOS/TiboTattle", "Contents/Resources/runtime/bin/node", "Contents/Frameworks/Fixture.framework/Fixture", "Contents/MacOS/TiboTattleNativeHandover", "Contents/Resources/native/macos-keychain.node", "Contents/Resources/app.asar", "Contents/Frameworks/Electron Framework.framework/Electron Framework"].each do |path|
        destination = File.join(app, path)
        FileUtils.mkdir_p(File.dirname(destination))
        File.write(destination, "synthetic")
        File.chmod(0o700, destination) unless path.end_with?(".plist")
      end
      bin = File.join(directory, "mock-bin")
      FileUtils.mkdir_p(bin)
      # Shell mocks avoid macOS system Ruby consulting the mocked xcrun during
      # interpreter startup (which would recursively launch the interpreter).
      body = <<~'BASH'
        command="${0##*/}"
        { printf '%s' "$command"; printf '|%s' "$@"; printf '\n'; } >> "$VERIFY_LOG"
        if [ "${FAIL_COMMAND:-}" = "$command" ]; then exit 1; fi
        case "$command" in
          plutil)
            case "$2" in
              CFBundleIdentifier) printf '%s\n' "${IDENTIFIER:-com.usagemonitor.local}";;
              CFBundleShortVersionString) printf '%s\n' "${VERSION:-0.1.18}";;
              CFBundleExecutable) printf '%s\n' TiboTattle;;
              LSMinimumSystemVersion) printf '%s\n' "${MIN_OS:-14.0}";;
              *) exit 1;;
            esac;;
          lipo)
            case "$2" in
              */TiboTattleNativeHandover) printf '%s\n' "${NODE_CPU:-$CPU}";;
              */macos-keychain.node) printf '%s\n' "${CREDENTIAL_CPU:-$CPU}";;
              */node) printf '%s\n' "${NODE_CPU:-$CPU}";;
              */Fixture.framework/Fixture) printf '%s\n' "${DEPENDENCY_CPU:-$CPU}";;
              *) printf '%s\n' "${MAIN_CPU:-$CPU}";;
            esac;;
          file)
            case "$2" in
              */Fixture.framework/Fixture) printf '%s\n' 'Mach-O shared library';;
              *) printf '%s\n' 'ASCII text';;
            esac;;
          *) :;;
        esac
      BASH
      %w[plutil lipo file codesign spctl xcrun].each do |command|
        path = File.join(bin, command)
        File.write(path, "#!/bin/bash\n#{body}")
        File.chmod(0o700, path)
      end
      %w[0.1.18 0.1.20 0.1.21].each do |version|
      %w[arm64 x86_64].each do |cpu|
        minimum_os = version == "0.1.20" ? "12.0" : "14.0"
        [
          [{}, true], [{ "IDENTIFIER" => "wrong.identifier" }, false], [{ "VERSION" => "0.1.17" }, false],
          [{ "MIN_OS" => "15.0" }, false], [{ "MIN_OS" => "13.0" }, false],
          [{ "MIN_OS" => minimum_os + ".0" }, true],
          [{ "MIN_OS" => minimum_os == "14.0" ? "12.0" : "14.0" }, false], [{ "MAIN_CPU" => "arm64 x86_64" }, false],
          [{ "NODE_CPU" => cpu == "arm64" ? "x86_64" : "arm64" }, false],
          [{ "DEPENDENCY_CPU" => "arm64 x86_64" }, true],
          [{ "DEPENDENCY_CPU" => cpu == "arm64" ? "x86_64" : "arm64" }, false],
          [{ "FAIL_COMMAND" => "codesign" }, false], [{ "FAIL_COMMAND" => "spctl" }, false],
          [{ "FAIL_COMMAND" => "xcrun" }, false], [{ "FAIL_COMMAND" => "file" }, false],
          [{ "FAIL_COMMAND" => "lipo" }, false], [{ "FAIL_COMMAND" => "plutil" }, false],
        ].each do |overrides, expected|
          log = File.join(directory, "verify-log")
          File.write(log, "")
          env = { "PATH" => "#{bin}:#{ENV.fetch('PATH')}", "CPU" => cpu, "VERSION" => version, "MIN_OS" => minimum_os, "VERIFY_LOG" => log }.merge(overrides)
          _stdout, stderr, status = Open3.capture3(env, "bash", ROOT.join("scripts/verify-app.sh").to_s, app, version, cpu)
          assert_equal expected, status.success?, "#{cpu} #{overrides}: #{stderr}"
          if expected
            calls = File.readlines(log).map { |line| fields = line.chomp.split("|"); [fields.shift, fields] }
            assert_equal version == "0.1.18" ? 3 : 4, calls.count { |command, _| command == "lipo" }
            assert_equal %w[codesign spctl xcrun], calls.last(3).map(&:first)
            assert_equal ["stapler", "validate", app], calls.last.last
          end
        end
        executable_paths = ["Contents/MacOS/TiboTattle", version == "0.1.18" ? "Contents/Resources/runtime/bin/node" : "Contents/MacOS/TiboTattleNativeHandover"]
        executable_paths.each do |relative|
          executable = File.join(app, relative)
          File.chmod(0o600, executable)
          env = { "PATH" => "#{bin}:#{ENV.fetch('PATH')}", "CPU" => cpu, "VERSION" => version, "MIN_OS" => minimum_os,
            "VERIFY_LOG" => File.join(directory, "nonexecutable-log") }
          _stdout, stderr, status = Open3.capture3(env, "bash", ROOT.join("scripts/verify-app.sh").to_s, app, version, cpu)
          refute status.success?, "Non-executable #{relative}: #{stderr}"
          File.chmod(0o700, executable)
        end
        if version != "0.1.18"
          ["Contents/Resources/native/macos-keychain.node", "Contents/Resources/app.asar", "Contents/Frameworks/Electron Framework.framework/Electron Framework"].each do |relative|
            resource = File.join(app, relative)
            File.rename(resource, resource + ".preserved")
            env = { "PATH" => "#{bin}:#{ENV.fetch('PATH')}", "CPU" => cpu, "VERSION" => version, "MIN_OS" => minimum_os,
              "VERIFY_LOG" => File.join(directory, "missing-resource-log") }
            _stdout, stderr, status = Open3.capture3(env, "bash", ROOT.join("scripts/verify-app.sh").to_s, app, version, cpu)
            refute status.success?, "Missing Electron #{relative}: #{stderr}"
            File.rename(resource + ".preserved", resource)
          end
          env = { "PATH" => "#{bin}:#{ENV.fetch('PATH')}", "CPU" => cpu, "VERSION" => version, "MIN_OS" => minimum_os,
            "CREDENTIAL_CPU" => cpu == "arm64" ? "x86_64" : "arm64", "VERIFY_LOG" => File.join(directory, "credential-log") }
          _stdout, stderr, status = Open3.capture3(env, "bash", ROOT.join("scripts/verify-app.sh").to_s, app, version, cpu)
          refute status.success?, "Opposite-architecture credential adapter: #{stderr}"
        end
      end
      end
    end
  end
end
