require_relative "../spec_helper"
RSpec.describe "Repository workspace and enrollment" do
  let(:db) { Kirei::App.raw_db_connection }
  around do |example|
    Dir.mktmpdir("digitaltwin-workspace") do |dir|
      @dir = dir
      @root = "#{dir}/repos"
      @trees = "#{dir}/worktrees"
      FileUtils.mkdir_p([@root, @trees])
      @paths = Domains::Projects::WorkspacePaths.new(root: @root, worktrees_root: @trees)
      example.run
    end
  end
  def git(*args)
    out, status = Open3.capture2e("git", *args)
    raise out unless status.success?

    out.strip
  end

  def repository
    path = "#{@root}/owner/repo"
    FileUtils.mkdir_p(path)
    git("init", "-b", "main", path)
    git("-C", path, "config", "user.email", "fixture@example.invalid")
    git("-C", path, "config", "user.name", "Fixture")
    git("-C", path, "commit", "--allow-empty", "-m", "fixture")
    git("-C", path, "remote", "add", "origin", "git@github.com:owner/repo.git")
    path
  end
  it "accepts only exact owner/repository slugs and checks remote identity" do
    repo = repository
    expect(resolve_repository.call(slug: "owner/repo").result).to eq(repo)
    %w[../repo owner/../repo /owner/repo owner/repo.git owner/repo;echo owner/repo/extra].each do |slug|
      expect(resolve_repository.call(slug: slug)).to be_failed
    end
    git("-C", repo, "remote", "set-url", "origin", "https://github.com/other/repo.git")
    failure = resolve_repository.call(slug: "owner/repo")
    expect(failure.errors.first.code).to eq("workspace_rejected")
    expect(failure.errors.first.detail).to match(/remote/i)
  end
  it "rejects symlinks outside either workspace root" do
    FileUtils.mkdir_p("#{@root}/owner")
    File.symlink(@dir, "#{@root}/owner/repo")
    expect(resolve_repository.call(slug: "owner/repo")).to be_failed
    File.symlink(@dir, "#{@trees}/12345678-1234-4234-8234-123456789abc")
    expect(
      prepare_worktree.call(slug: "owner/repo", workflow_id: "12345678-1234-4234-8234-123456789abc",
                            branch: "digitaltwin/12345678-1234-4234-8234-123456789abc")
    ).to be_failed
  end
  it "keeps two same-repository threads in independent branches and revalidates after restart" do
    repo = repository
    ids = [SecureRandom.uuid, SecureRandom.uuid]
    paths = ids.map { |id| prepare_worktree.call(slug: "owner/repo", workflow_id: id, branch: "digitaltwin/#{id}").result }
    File.write("#{paths.first}/only-first", "one")
    expect(File.exist?("#{paths.last}/only-first")).to be(false)
    expect(git("-C", repo, "branch", "--show-current")).to eq("main")
    expect(prepare_worktree.call(slug: "owner/repo", workflow_id: ids.first,
                                 branch: "digitaltwin/#{ids.first}").result).to eq(paths.first)
    git("-C", paths.first, "checkout", "--detach")
    mismatch = prepare_worktree.call(slug: "owner/repo", workflow_id: ids.first, branch: "digitaltwin/#{ids.first}")
    expect(mismatch.errors.first.detail).to eq("Worktree branch mismatch")
  end
  let(:resolve_repository) { Services::Projects::ResolveRepository.new(paths: @paths) }
  let(:prepare_worktree) { Services::Projects::PrepareWorktree.new(paths: @paths, resolve_repository: resolve_repository) }
  let(:enroll) { Services::Projects::Enroll.new(paths: @paths, resolve_repository: resolve_repository) }
  let(:actor) { Domains::Messaging::Dto::VerifiedActor.new(user_id: "human", channel_id: "channel", member: true, bot: false) }
  let(:choice) { Domains::Projects::Dto::EnrollChoice }
  let(:status) { Domains::Projects::Dto::EnrollmentStatus }

  it "stores channel-id mapping and rejects nonmembers and bots" do
    repository
    outcome = enroll.call(actor: actor, channel_id: "channel", slug: "owner/repo", choice: choice::Stop)
    expect(outcome.result).to eq(Domains::Projects::Dto::Enrollment.new(status: status::Enrolled, detail: "Repository enrolled"))
    expect(Domains::Projects::Directory.new.for_channel(channel_id: "channel")&.slug).to eq("owner/repo")
    rejected = enroll.call(actor: actor, channel_id: "another", slug: "owner/repo", choice: choice::Stop)
    expect(rejected.errors.first.code).to eq("membership_required")
    expect(rejected.errors.first.detail).to eq("Verified human channel membership required")
    bot = Domains::Messaging::Dto::VerifiedActor.new(user_id: "bot", channel_id: "another", member: true, bot: true)
    expect(enroll.call(actor: bot, channel_id: "another", slug: "owner/repo", choice: choice::Stop)).to be_failed
  end

  it "retains an existing mapping and rejects a different repository for the channel" do
    repository
    enroll.call(actor: actor, channel_id: "channel", slug: "owner/repo", choice: choice::Stop)
    retained = enroll.call(actor: actor, channel_id: "channel", slug: "owner/repo", choice: choice::Stop)
    expect(retained.result).to eq(Domains::Projects::Dto::Enrollment.new(status: status::Retained, detail: "Channel mapping retained"))
    other = enroll.call(actor: actor, channel_id: "channel", slug: "owner/other", choice: choice::Stop)
    expect([other.errors.first.code, other.errors.first.detail]).to eq(["channel_enrolled_elsewhere", "Channel already enrolled to another repository"])
  end

  it "blocks when the repository is missing and the human chose stop" do
    outcome = enroll.call(actor: actor, channel_id: "channel", slug: "owner/repo", choice: choice::Stop)
    expect(outcome.result).to eq(Domains::Projects::Dto::Enrollment.new(status: status::Blocked, detail: "Choose clone/create_private/stop"))
    expect(Domains::Projects::Directory.new.all).to be_empty
  end

  it "rejects an invalid slug with the slug rule detail" do
    outcome = enroll.call(actor: actor, channel_id: "channel", slug: "owner/repo.git", choice: choice::Stop)
    expect([outcome.errors.first.code, outcome.errors.first.detail]).to eq(["invalid_slug", "Expected owner/repository slug"])
  end

  it "register rejects duplicate channel/slug as a failure result" do
    register = Domains::Projects::Register.new
    first = register.call(channel_id: "channel", slug: "owner/repo", remote_identity: "github.com/owner/repo", workspace: "/tmp/repo")
    expect(first.result.slug).to eq("owner/repo")
    duplicate = register.call(channel_id: "channel", slug: "owner/repo", remote_identity: "github.com/owner/repo", workspace: "/tmp/repo")
    expect([duplicate.errors.first.code, duplicate.errors.first.detail]).to eq(["already_enrolled", "Repository/channel already enrolled"])
    expect(Domains::Projects::Directory.new.all.map(&:slug)).to eq(["owner/repo"])
  end

  it "looks projects up by id and channel" do
    project = Domains::Projects::Register.new.call(channel_id: "c", slug: "owner/repo", remote_identity: "github.com/owner/repo", workspace: "/tmp/r").result
    directory = Domains::Projects::Directory.new
    expect(directory.find(id: project.id)).to eq(project)
    expect(directory.for_channel(channel_id: "c")).to eq(project)
    expect(directory.find(id: "missing")).to be_nil
    expect(directory.for_channel(channel_id: "missing")).to be_nil
  end

  it "keeps workspace paths inside their roots" do
    expect(@paths.worktree(slug: "owner/repo", workflow_id: "12345678-1234-4234-8234-123456789abc")).to eq("#{File.realpath(@trees)}/12345678-1234-4234-8234-123456789abc")
    expect { @paths.contained!(root: File.realpath(@root), path: "#{@root}/../escape") }.to raise_error(ArgumentError, "Workspace escape")
    expect { @paths.worktree(slug: "owner/repo", workflow_id: "not-a-uuid") }.to raise_error(ArgumentError, "Invalid workflow UUID/branch")
  end
end
