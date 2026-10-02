require_relative "../spec_helper"
RSpec.describe "Durable jobs and outbox" do
  let(:db) { Kirei::App.raw_db_connection }
  let(:store) { Domains::Jobs::Store.new }
  before { %i[audit outbox inbox jobs].each { |table| db[table].delete } }
  def enqueue(key = "one") = store.enqueue(kind: "test", payload: { "x" => 1 }, key: key)
  it "returns one durable job for a unique dispatch key" do
    expect(enqueue).to eq(enqueue)
    expect(db[:jobs].count).to eq(1)
  end
  it "rejects reuse with different payloads" do
    enqueue
    expect { store.enqueue(kind: "test", payload: { "x" => 2 }, key: "one") }.to raise_error(ArgumentError)
  end
  it "claims exclusively with concurrent workers" do
    enqueue
    jobs = 2.times.map { |i| Thread.new { store.claim(worker_id: i.to_s, now: Time.now) } }.map(&:value).compact
    expect(jobs.size).to eq(1)
  end
  it "reclaims expired uneffected leases but rejects old completion tokens" do
    id = enqueue
    now = Time.now
    a = store.claim(worker_id: "a", now: now)
    b = store.claim(worker_id: "b", now: now + 31)
    expect(b.id).to eq(id)
    expect(store.complete(id: id, lease_token: T.must(a.lease_token))).to be(false)
    expect(store.complete(id: id, lease_token: T.must(b.lease_token))).to be(true)
  end
  it "blocks on the fifth failure" do
    id = enqueue
    now = Time.now
    5.times do |i|
      job = store.claim(worker_id: "a", now: now + (i * 100))
      store.retry(id: id, lease_token: T.must(job.lease_token), error: "fixture", now: now + (i * 100))
    end
    expect(db[:jobs][id: id][:status]).to eq("blocked")
  end
  it "blocks a crash after beginning an external effect, without retrying it" do
    enqueue
    now = Time.now
    job = store.claim(worker_id: "a", now: now)
    expect(store.begin_effect(id: job.id, lease_token: T.must(job.lease_token))).to be(true)
    expect(store.claim(worker_id: "b", now: now + 31)).to be_nil
    expect(db[:jobs][id: job.id][:status]).to eq("uncertain")
  end
  it "heartbeats only the current lease" do
    enqueue
    job = store.claim(worker_id: "a", now: Time.now)
    expect(store.heartbeat(id: job.id, lease_token: "wrong")).to be(false)
    expect(store.heartbeat(id: job.id, lease_token: T.must(job.lease_token))).to be(true)
  end
  it "rolls back state and outbox together" do
    expect {
      db.transaction {
        enqueue;
        Domains::Mattermost::Outbox.new.enqueue(channel_id: "c", thread_id: "r", bot: "worker", role: "writer",
                                                    body: "hello", key: "response");
        raise "abort"
      }
    }.to raise_error("abort")
    expect(db[:jobs].count).to eq(0)
    expect(db[:outbox].count).to eq(0)
  end
  it "deduplicates responses and rejects changed bodies" do
    outbox = Domains::Mattermost::Outbox.new
    args = { channel_id: "c", thread_id: "r", bot: "worker", role: "writer", body: "hello", key: "response" }
    expect(outbox.enqueue(**args)).to eq(outbox.enqueue(**args))
    expect { outbox.enqueue(**args.merge(body: "changed")) }.to raise_error(ArgumentError)
    expect(db[:jobs].count).to eq(1)
  end
end
