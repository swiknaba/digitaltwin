# Explicit synthetic session credential markers; no provider or chat login.
db = Kirei::App.raw_db_connection
db[:projects].insert(id: 'integration:project', channel_id: 'fixture-channel', slug: 'fixture/repository',
                     remote_identity: 'fixture.invalid/repository', workspace: '/workspace/repos/fixture')
2.times do |offset|
  index = offset + 1
  db[:workflows].insert(id: "integration:workflow:#{index}", project_id: 'integration:project',
                       channel_id: 'fixture-channel', thread_id: "fixture-root-#{index}",
                       branch: "fixture-#{index}", worktree_path: "/workspace/worktrees/fixture-#{index}")
  db[:sessions].insert(id: "integration:session:#{index}", workflow_id: "integration:workflow:#{index}",
                      role: 'writer', generation: 1, pane_id: 'synthetic', alias: 'synthetic',
                      configuration: Sequel.pg_jsonb({}),
                      credential_digest: Digest::SHA256.hexdigest("synthetic-integration-#{index}"),
                      credential_expires_at: Time.now + 120)
end
