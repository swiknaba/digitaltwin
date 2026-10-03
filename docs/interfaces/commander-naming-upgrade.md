# Commander naming audit and migration plan

Product prose now uses **Commander** consistently.
The prior rename changed the domain name and display text, but retained the application identifiers below.
These implementation leftovers still exist. The first implementation task removes them before Commander feature work.

The proposed migration is `009_commander_names`; migrations 001–008 remain immutable.
This document describes the required upgrade, not a completed or tested migration.

| Existing implementation name | Target name |
| --- | --- |
| `Services::Master`, `Adapters::Http::Master` | `Services::Commander`, `Adapters::Http::Commander` |
| Session and speaker role `controller` | `commander` |
| Role-file key `controller` | `commander` |
| Table `master_requests` | `commander_requests` |
| Job kinds `master.prompt`, `master.dispatch`, `master.control` | Corresponding `commander.*` kinds |
| `MASTER_CHANNEL_ID` | `COMMANDER_CHANNEL_ID` |
| `/internal/master/{manifest,tools,reply}` | `/internal/commander/{manifest,tools,reply}` |
| `DIGITALTWIN_MASTER_REQUEST_TOKEN_FILE` | `DIGITALTWIN_COMMANDER_REQUEST_TOKEN_FILE` |
| `digitaltwin master-reply` | `digitaltwin commander-reply` |
| `@agent recover-master` | `@agent recover-commander` |

## Planned upgrade for an existing installation

1. Stop the backend web, listener, and worker processes before migration.
2. Back up the dedicated backend database.
3. Replace the role-file key with `commander`; retain its existing profile and credentials.
4. Use the new environment names in operator configuration and CLI hooks.
5. Run `bundle exec rake db:migrate` with the new backend image.
6. Install the matching checksum-pinned Runtime clients and restart the backend processes.
7. Verify the recorded sessions and replies before allowing further work.

Do not run old backend processes against the migrated schema.
Accept the previous role-file key during transition; reject conflicting old and new entries.
New setup instructions must use `commander`.
The migration must preserve session IDs, generations, aliases, Runtime identities, credentials, request receipts, and job states.
It must rename stored workflow role keys and the synthetic Commander conversation binding.
It must not create or replace a live agent session.

The upgraded backend must temporarily accept the previous private route and recovery-command aliases.
Both route versions must use the same authorization and handlers.
Upgraded clients must accept the previous token variable for already-running Runtime workspaces.
The previous channel variable must remain a fallback; the new variable takes precedence.
These aliases must not enable dispatch or grant new authority.

## Historical bytes

Deduplication keys and request digests retain their original encoding.
Changing them could repeat a prompt or prevent recovery of a delivered Mattermost reply.
Previous migrations, audit history, captured evidence, and upstream framework `Controller` names also retain their original wording.
These are compatibility records, not alternative product roles.

## Required rollback behavior

Stop the backend processes before rollback.
Run `STEPS=1 bundle exec rake db:rollback` to restore schema version 8.
Restore the previous backend image, Runtime clients, and operator configuration together.
Keep credentials, Runtime conversations, and volumes intact.
