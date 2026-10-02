require_relative "../spec_helper"
RSpec.describe Adapters::Git::Evidence do
  it "validates real append-only review commits and rejects changed approved artifacts" do
    Dir.mktmpdir do |root|
      path = File.join(root, "workflow")
      FileUtils.mkdir_p(File.join(path, "docs"))
      run = ->(*args) { output, status = Open3.capture2e("git", "-C", path, *args); raise output unless status.success?; output.strip }
      run.call("init", "-q", "-b", "workflow")
      run.call("config", "user.name", "Fixture")
      run.call("config", "user.email", "fixture@example.invalid")
      File.write(File.join(path, "docs/spec.md"), "Approved spec\n")
      run.call("add", ".")
      run.call("-c", "commit.gpgsign=false", "commit", "-qm", "spec")
      target = run.call("rev-parse", "HEAD")
      worktree = Adapters::Git::Dto::WorktreeRef.new(worktree_path: path, branch: "workflow")
      binding = Adapters::Git::Dto::ArtifactBinding.new(commit: target, path: "docs/spec.md")
      evidence = described_class.new(revision: Adapters::Git::Revision.new(root: root))
      reviewer = Adapters::Git::Dto::ReviewerIdentity.new(provider: "fixture", model: "fixture", family: "fixture")
      review = ->(commit) { evidence.review(worktree: worktree, target_commit: target, review_path: "docs/review.md", review_commit: commit, verdict: "approve", reviewer: reviewer) }
      expect(evidence.artifact(worktree: worktree, commit: target, path: "docs/spec.md")).to eq(true)
      expect(evidence.current(worktree: worktree)).to eq(target)
      expect { evidence.artifact(worktree: worktree, commit: target, path: "../spec.md") }.to raise_error(ArgumentError, "Invalid artifact path")
      File.write(File.join(path, "docs/review.md"), "Target: #{target}\nProvider: fixture\nModel: fixture\nFamily: fixture\nVerdict: approve\nReviewed-at: 2026-10-02T00:00:00Z\n")
      run.call("add", ".")
      run.call("-c", "commit.gpgsign=false", "commit", "-qm", "review")
      reviewed = run.call("rev-parse", "HEAD")
      expect(review.call(reviewed)).to eq(true)
      expect(evidence.approval(worktree: worktree, binding: binding, target_commit: target, review_commit: reviewed, review_path: "docs/review.md")).to eq(true)
      expect { evidence.approval(worktree: worktree, binding: nil, target_commit: target, review_commit: reviewed, review_path: "docs/review.md") }.to raise_error(ArgumentError, "Artifact binding missing")
      expect(evidence.approved_artifact(worktree: worktree, binding: binding, target_commit: target)).to eq(true)
      File.write(File.join(path, "docs/spec.md"), "Changed spec\n")
      run.call("add", ".")
      run.call("-c", "commit.gpgsign=false", "commit", "-qm", "changed")
      expect { evidence.approved_artifact(worktree: worktree, binding: binding, target_commit: target) }.to raise_error(ArgumentError, "Previously approved artifact changed")
      expect { review.call(run.call("rev-parse", "HEAD")) }.to raise_error(ArgumentError, "Reviewer modified another file")
    end
  end
end
