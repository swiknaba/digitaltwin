# Sessions

This domain manages the lifecycle of isolated agent sessions. It talks to the local
Herdr socket, reserves and renews session records, writes short-lived credentials, and
reconciles completed operations. Workflow code requests a session through this domain
instead of addressing an agent pane or credential file directly.
