require_relative "../spec_helper"
RSpec.describe "Repository workspace and enrollment" do
  let(:db) { Kirei::App.raw_db_connection }
  around do |example|
    Dir.mktmpdir("digitaltwin-workspace") do |dir|
      @dir = dir
      @root = "#{dir}/repos"
      @trees = "#{dir}/worktrees"
      FileUtils.mkdir_p([@root, @trees])
      @workspace = Domains::Projects::Workspace.new(root: @root, worktrees_root: @trees)
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
    expect(@workspace.resolve(slug: "owner/repo")).to eq(repo)
    %w[../repo owner/../repo /owner/repo owner/repo.git owner/repo;echo owner/repo/extra].each do |slug|
      expect { @workspace.resolve(slug: slug) }.to raise_error(ArgumentError)
    end
    git("-C", repo, "remote", "set-url", "origin", "https://github.com/other/repo.git")
    expect { @workspace.resolve(slug: "owner/repo") }.to raise_error(ArgumentError, /remote/i)
  end
  it "rejects symlinks outside either workspace root" do
    FileUtils.mkdir_p("#{@root}/owner")
    File.symlink(@dir, "#{@root}/owner/repo")
    expect { @workspace.resolve(slug: "owner/repo") }.to raise_error(ArgumentError)
    File.symlink(@dir, "#{@trees}/12345678-1234-4234-8234-123456789abc")
    expect {
      @workspace.for_workflow(slug: "owner/repo", workflow_id: "12345678-1234-4234-8234-123456789abc",
                              branch: "digitaltwin/12345678-1234-4234-8234-123456789abc")
    }.to raise_error(ArgumentError)
  end
  it "keeps two same-repository threads in independent branches and revalidates after restart" do
    repo = repository
    ids = [SecureRandom.uuid, SecureRandom.uuid]
    paths = ids.map { |id| @workspace.for_workflow(slug: "owner/repo", workflow_id: id, branch: "digitaltwin/#{id}") }
    File.write("#{paths.first}/only-first", "one")
    expect(File.exist?("#{paths.last}/only-first")).to be(false)
    expect(git("-C", repo, "branch", "--show-current")).to eq("main")
    expect(@workspace.for_workflow(slug: "owner/repo", workflow_id: ids.first,
                                   branch: "digitaltwin/#{ids.first}")).to eq(paths.first)
    git("-C", paths.first, "checkout", "--detach")
    expect {
      @workspace.for_workflow(slug: "owner/repo", workflow_id: ids.first,
                              branch: "digitaltwin/#{ids.first}")
    }.to raise_error(ArgumentError)
  end
  it "stores channel-id mapping and rejects nonmembers and bots" do
    db[:projects].delete
    repository
    service = Domains::Projects::Enroll.new(db, workspace: @workspace)
    actor = Domains::Workflows::Entities::Actor.new(user_id: "human", channel_id: "channel", member: true, bot: false)
    expect(service.call(actor: actor, channel_id: "channel", slug: "owner/repo",
                        choice: "stop").status).to eq("accepted")
    expect(db[:projects][channel_id: "channel"][:slug]).to eq("owner/repo")
    expect(service.call(actor: actor, channel_id: "another", slug: "owner/repo",
                        choice: "stop").status).to eq("rejected")
  end
end
