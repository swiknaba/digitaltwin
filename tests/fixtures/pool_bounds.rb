# Hold every connection in the actual configured backend pool, then release it.
db = Kirei::App.raw_db_connection
ready = Queue.new
release = Queue.new
threads = []
begin
  5.times do
    threads << Thread.new do
      db.synchronize do
        ready << true
        release.pop
      end
    rescue StandardError
      ready << false
      raise
    end
  end
  5.times { abort 'pool checkout failed' unless ready.pop }
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  begin
    db.get(1)
    abort 'pool was unbounded'
  rescue Sequel::PoolTimeout
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    abort 'pool timeout outside bounds' unless elapsed.between?(1.5, 6)
  end
ensure
  5.times { release << true }
  threads.each(&:value)
end
abort 'pool did not recover' unless db.get(1) == 1
