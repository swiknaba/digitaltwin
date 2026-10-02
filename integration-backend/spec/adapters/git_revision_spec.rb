require_relative "../spec_helper"
RSpec.describe Adapters::Git::Revision do
  it "requires the bound clean worktree and reports its exact revision" do
    Dir.mktmpdir do |root|
      path = File.join(root, "workflow")
      FileUtils.mkdir_p(path)
      run = ->(*args) { output, status = Open3.capture2e("git", "-C", path, *args); raise output unless status.success?; output.strip }
      run.call("init", "-q", "-b", "workflow-branch")
      run.call("config", "user.name", "Fixture")
      run.call("config", "user.email", "fixture@example.invalid")
      File.write(File.join(path, "artifact"), "reviewed")
      run.call("add", "artifact")
      run.call("-c", "commit.gpgsign=false", "commit", "-qm", "fixture")
      read = described_class.new(root: root)
      expect(read.call(worktree_path: path, branch: "workflow-branch")).to eq(run.call("rev-parse", "HEAD"))
      expect { read.call(worktree_path: path, branch: "different") }.to raise_error(ArgumentError, "Worktree branch mismatch")
      expect { read.call(worktree_path: File.join(root, "missing"), branch: "workflow-branch") }.to raise_error(ArgumentError, "Invalid worktree path")
      File.write(File.join(path, "artifact"), "unreviewed")
      expect { read.call(worktree_path: path, branch: "workflow-branch") }.to raise_error(ArgumentError, "Worktree has uncommitted changes")
    end
  end
end
