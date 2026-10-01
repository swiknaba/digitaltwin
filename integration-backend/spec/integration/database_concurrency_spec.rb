require_relative "../spec_helper"
RSpec.describe "Exclusive PostgreSQL checkout" do
  it "isolates overlapping fiber transactions and rolls back only the failing transaction" do
    db = Kirei::App.raw_db_connection
    db[:audit].delete
    ids = []
    Async do |task|
      a = task.async do
        begin
          db.transaction do
            ids << db.get(Sequel.function(:pg_backend_pid))
            db[:audit].insert(event_key: "rolled-back", action: "test", details: Sequel.pg_jsonb({}))
            task.sleep(0.1)
            raise "rollback"
          end
        rescue RuntimeError
        end
      end
      b = task.async do
        db.transaction do
          ids << db.get(Sequel.function(:pg_backend_pid))
          db[:audit].insert(event_key: "committed", action: "test", details: Sequel.pg_jsonb({}))
          task.sleep(0.1)
        end
      end
      [a, b].each(&:wait)
    end.wait
    expect(ids.uniq.size).to eq(2)
    expect(db[:audit].select_map(:event_key)).to eq(["committed"])
    expect(db.get(Sequel.function(:pg_backend_pid))).to be_a(Integer)
  end
  it "bounds exhaustion and releases connections after exceptions" do
    db = Sequel.connect(ENV.fetch("DATABASE_URL"), max_connections: 1, pool_timeout: 0.05)
    Async do |task|
      a = task.async { db.synchronize { task.sleep(0.15) } }
      b = task.async { expect { db.synchronize {} }.to raise_error(Sequel::PoolTimeout) }
      [a, b].each(&:wait)
    end.wait
    expect { db.transaction { raise "abort" } }.to raise_error("abort")
    expect(db.get(1)).to eq(1)
  ensure
    db&.disconnect
  end
end
