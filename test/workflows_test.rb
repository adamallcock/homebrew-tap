# frozen_string_literal: true

require "minitest/autorun"
require "pathname"

class WorkflowsTest < Minitest::Test
  ROOT = Pathname(__dir__).join("..").cleanpath
  UPDATE_WORKFLOW = ".github/workflows/update-tibotattle.yml"
  WORKFLOWS_WITH_ONLINE_AUDIT = [
    ".github/workflows/ci.yml",
    UPDATE_WORKFLOW,
  ].freeze

  def test_every_online_homebrew_audit_uses_the_github_actions_token
    WORKFLOWS_WITH_ONLINE_AUDIT.each do |relative_path|
      source = ROOT.join(relative_path).read
      audit_indexes = source.enum_for(:scan, /brew audit --cask --online/).map do
        Regexp.last_match.begin(0)
      end

      assert_equal 1, audit_indexes.length, "expected one online audit in #{relative_path}"

      step_start = source.rindex("      - name:", audit_indexes.fetch(0))
      refute_nil step_start, "could not find the audit step in #{relative_path}"
      run_start = source.index("        run:", step_start)
      refute_nil run_start, "could not find the audit command block in #{relative_path}"

      step_header = source[step_start...run_start]
      assert_match(
        /\n        env:\n          HOMEBREW_GITHUB_API_TOKEN: \$\{\{ github\.token \}\}\n/,
        step_header,
        "online audit must authenticate GitHub API requests in #{relative_path}",
      )
    end
  end

  def test_scheduled_updater_skips_expensive_steps_when_the_cask_is_current
    source = ROOT.join(UPDATE_WORKFLOW).read

    assert_match(/current_version=.*Casks\/tibotattle\.rb/m, source)
    assert_match(/\[\[ "\$current_version" == "\$version" \]\]/, source)
    assert_match(/TIBOTATTLE_UPDATE_NEEDED=false/, source)

    [
      "Update Homebrew",
      "Verify the latest release and update the cask",
      "Audit, install, and uninstall the candidate cask",
      "Commit a changed cask",
    ].each do |name|
      step_start = source.index("      - name: #{name}")
      refute_nil step_start, "missing updater step #{name}"
      run_start = source.index("        run:", step_start)
      refute_nil run_start, "missing command block for #{name}"
      step_header = source[step_start...run_start]
      assert_match(
        /\n        if: env\.TIBOTATTLE_UPDATE_NEEDED == 'true'\n/,
        step_header,
        "#{name} must be skipped when the cask already matches the release",
      )
    end

    resolve_index = source.index("      - name: Resolve the latest release")
    update_index = source.index("      - name: Update Homebrew")
    refute_nil resolve_index
    refute_nil update_index
    assert_operator resolve_index, :<, update_index
  end
end
