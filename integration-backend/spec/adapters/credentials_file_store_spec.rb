require_relative "../spec_helper"
RSpec.describe Adapters::Credentials::FileStore do
  around { |example| Dir.mktmpdir { |dir| @dir = dir; example.run } }

  it "creates a private root and exclusive 0600 token files" do
    store = described_class.new(root: File.join(@dir, "credentials"))
    path = store.write(name: "session.token", token: "secret")
    expect(path).to eq(File.join(@dir, "credentials", "session.token"))
    expect(File.stat(File.dirname(path)).mode & 0o777).to eq(0o700)
    expect(File.stat(path).mode & 0o777).to eq(0o600)
    expect(store.read(name: "session.token")).to eq("secret")
    expect { store.write(name: "session.token", token: "other") }.to raise_error(Errno::EEXIST)
    store.delete(name: "session.token")
    store.delete(name: "session.token")
    expect(File.exist?(path)).to be(false)
  end

  it "rejects symlinked roots and files and path-like names" do
    FileUtils.mkdir_p(File.join(@dir, "elsewhere"))
    File.symlink(File.join(@dir, "elsewhere"), File.join(@dir, "linked"))
    expect { described_class.new(root: File.join(@dir, "linked")).write(name: "a.token", token: "x") }.to raise_error(ArgumentError, "Credential root symlink")
    store = described_class.new(root: File.join(@dir, "elsewhere"))
    File.symlink("/etc/hosts", File.join(@dir, "elsewhere", "b.token"))
    expect { store.read(name: "b.token") }.to raise_error(ArgumentError, "Credential file symlink")
    expect { store.write(name: "b.token", token: "x") }.to raise_error(Errno::EEXIST)
    %w[../a.token a/b .hidden].each { |name| expect { store.path(name: name) }.to raise_error(ArgumentError, "Invalid credential name") }
  end
end
