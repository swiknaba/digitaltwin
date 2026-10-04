# typed: strict
# frozen_string_literal: true

# Synthetic fixture only, on a uniquely named disposable Compose database.
store = Platform::Jobs::Store.new
kind = Platform::Jobs::Dto::JobKind::MattermostPost
payload = Domains::Messaging::Dto::OutboxPostJob.new(outbox_id: "integration:outbox")
now = Time.now
id = store.enqueue(kind: kind, payload: payload, dispatch_key: "integration:dedup")
abort "dedup" unless store.enqueue(kind: kind, payload: payload, dispatch_key: "integration:dedup") == id
begin
  store.enqueue(kind: kind, payload: Domains::Messaging::Dto::OutboxPostJob.new(outbox_id: "changed"), dispatch_key: "integration:dedup")
  abort "changed body accepted"
rescue Platform::Jobs::Errors::DispatchKeyReused
end
job = T.must(store.claim(worker_id: "fixture", now: now + 1))
abort "stale token" if store.complete(id: id, lease_token: "wrong", now: now + 2)
recovered = T.must(store.claim(worker_id: "recovery", now: now + 32))
abort "lease recovery" unless recovered.id == id && recovered.lease.token != job.lease.token
abort "complete" unless store.complete(id: id, lease_token: recovered.lease.token, now: now + 33)
uncertain = store.enqueue(kind: kind, payload: payload, dispatch_key: "integration:uncertain")
job = T.must(store.claim(worker_id: "fixture", now: now + 34))
abort "effect marker" unless job.lease.begin_effect(now: now + 35)
store.claim(worker_id: "recovery", now: now + 65)
abort "unsafe retry" unless T.must(store.find(id: uncertain)).status == Platform::Jobs::Dto::JobStatus::Uncertain
store.enqueue(kind: Platform::Jobs::Dto::JobKind::CommanderDispatch,
              payload: Domains::Commander::Dto::CommanderDispatchJob.new(request_id: "integration:request"),
              dispatch_key: "integration:blocked")
