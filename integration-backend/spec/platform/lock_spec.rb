# typed: strict
# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Platform::Lock do
  it "returns the block result and rejects a held key with Busy" do
    lock = described_class.new
    other = Sequel.connect(ENV.fetch("DATABASE_URL"))
    begin
      key = Sequel.function(:hashtextextended, "held", 0)
      other.get(Sequel.function(:pg_advisory_lock, key))
      expect { lock.call(key: "held") { :never } }.to raise_error(Platform::Lock::Busy, "Resource busy")
      other.get(Sequel.function(:pg_advisory_unlock, key))
      expect(lock.call(key: "held") { :ran }).to eq(:ran)
    ensure
      other.disconnect
    end
  end

  it "releases the key when the block raises" do
    lock = described_class.new
    expect { lock.call(key: "raising") { raise IOError, "boom" } }.to raise_error(IOError)
    expect(lock.call(key: "raising") { 1 }).to eq(1)
  end
end

RSpec.describe Platform::Transaction do
  it "commits the block result and rolls back on error" do
    db = Kirei::App.raw_db_connection
    insert = lambda do |id|
      db[:jobs].insert(id:, dispatch_key: id, kind: "future_task.due", payload: Sequel.pg_jsonb({}), available_at: Time.now)
    end
    expect(described_class.new.call { insert.call("kept"); 1 }).to eq(1)
    expect { described_class.new.call { insert.call("dropped"); raise IOError } }.to raise_error(IOError)
    expect(db[:jobs].select_map(:id)).to eq(["kept"])
  end
end
