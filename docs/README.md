# Documentation

Accepted specifications, implementation plans, service interfaces, operations contracts, and acceptance evidence.

## Why This Exists

The shared specification and interface decisions must survive individual implementation sessions.
These documents give component owners and reviewers one versioned source for scope, dependencies, and evidence gaps.

## Current product contract

The [Commander feature specification](commander-feature-spec.md) defines the
OpenCode, Commander, and Kirei split. The [implementation plan](superpowers/plans/2026-10-12-opencode-commander-reset.md)
records the remaining tranches. The [layout](repository-layout-and-parallel-build.md)
defines source paths and ownership, while the [service boundaries](interfaces/service-boundaries.md)
separate the current local evidence from production gates.

Historical plans remain under `superpowers/plans/`; they are not current runtime
instructions. Update the current contract when a source boundary changes.
