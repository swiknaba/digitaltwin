# Repository layout

DigitalTwin is now a small OpenCode companion.

```text
digitaltwin/
├── commander/            # maintained OpenCode UI patch and bridge contracts
├── integration-backend/  # Kirei FutureTasks schema, web, and worker
├── docs/                 # product, capability, and operator evidence
├── scripts/              # local PostgreSQL/Kirei checks
├── tests/                # root Compose contract checks
└── compose.yml           # PostgreSQL plus Kirei only
```

OpenCode owns project agents, sessions, remote workspaces, and Git feedback. Its
operator installation is outside this repository. No Mattermost server, push proxy,
DigitalTwin mobile client, or custom multi-CLI runtime remains in the local product
stack.

Kirei owns durable Commander future commitments. Its `FutureTasks` domain and worker
are one deployable: callers create/update/cancel task records; only its job handler
may deliver a due check-in through the Commander bridge boundary. Keep an operator
runtime or production credentials outside Git, images, and Compose.
