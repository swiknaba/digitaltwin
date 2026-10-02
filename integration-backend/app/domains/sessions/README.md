# Sessions

This domain manages the lifecycle of isolated agent sessions. It drives Herdr through
`Adapters::Herdr`, reserves and renews session records, keeps short-lived credentials in
`Adapters::Credentials`, and reconciles completed operations. Workflow code requests a session through this domain
instead of addressing an agent pane or credential file directly.
