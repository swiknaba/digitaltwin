require_relative "../spec_helper"
RSpec.describe Domains::Reviews::GitEvidence do
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
      w = { worktree_path: path, branch: "workflow", artifacts: { "spec" => { "commit" => target, "path" => "docs/spec.md" } } }
      evidence = described_class.new(revision: Domains::Controller::GitRevision.new(root: root))
      record = { gate: "spec", target_commit: target, review_path: "docs/review.md" }
      config = { "provider" => "fixture", "model" => "fixture", "family" => "fixture" }
      evidence.artifact(w, target, "docs/spec.md")
      File.write(File.join(path, "docs/review.md"), "Target: #{target}\nProvider: fixture\nModel: fixture\nFamily: fixture\nVerdict: approve\nReviewed-at: 2026-10-02T00:00:00Z\n")
      run.call("add", ".")
      run.call("-c", "commit.gpgsign=false", "commit", "-qm", "review")
      reviewed = run.call("rev-parse", "HEAD")
      expect(evidence.review(w, record, reviewed, "approve", config)).to eq(true)
      expect(evidence.approval(w, record.merge(review_commit: reviewed))).to eq(true)
      approval = { kind: "spec", target_commit: target }
      expect(evidence.approved_artifact(w, approval)).to eq(true)
      File.write(File.join(path, "docs/spec.md"), "Changed spec\n")
      run.call("add", ".")
      run.call("-c", "commit.gpgsign=false", "commit", "-qm", "changed")
      expect { evidence.approved_artifact(w, approval) }.to raise_error(ArgumentError, "Previously approved artifact changed")
      expect { evidence.review(w, record, run.call("rev-parse", "HEAD"), "approve", config) }.to raise_error(ArgumentError, "Reviewer modified another file")
    end
  end
end
