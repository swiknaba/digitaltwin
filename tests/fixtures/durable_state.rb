# Synthetic fixture only, on a uniquely named disposable Compose database.
db = Kirei::App.raw_db_connection
store = Domains::Jobs::Store.new(db)
now = Time.now
id = store.enqueue(kind: 'fixture', payload: { 'value' => 1 }, key: 'integration:dedup')
abort 'dedup' unless store.enqueue(kind: 'fixture', payload: { 'value' => 1 }, key: 'integration:dedup') == id
begin
  store.enqueue(kind: 'fixture', payload: { 'value' => 2 }, key: 'integration:dedup')
  abort 'changed body accepted'
rescue ArgumentError
end
job = store.claim(worker_id: 'fixture', now: now + 1)
abort 'stale token' if store.complete(id: id, lease_token: 'wrong', now: now + 2)
recovered = store.claim(worker_id: 'recovery', now: now + 32)
abort 'lease recovery' unless recovered[:id] == id && recovered[:lease_token] != job[:lease_token]
abort 'complete' unless store.complete(id: id, lease_token: recovered[:lease_token], now: now + 33)
uncertain = store.enqueue(kind: 'fixture', payload: {}, key: 'integration:uncertain')
job = store.claim(worker_id: 'fixture', now: now + 34)
abort 'effect marker' unless store.begin_effect(id: uncertain, lease_token: job[:lease_token], now: now + 35)
store.claim(worker_id: 'recovery', now: now + 65)
abort 'unsafe retry' unless db[:jobs][id: uncertain][:status] == 'uncertain'
store.enqueue(kind: 'workflow.dispatch', payload: {}, key: 'integration:blocked')
