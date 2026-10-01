# Repository Scripts

Non-deployable commands for local setup, acceptance orchestration, and infrastructure handoff preparation.
Application process commands stay in their component folders.

## API and Configuration Contract

Commands must document arguments, required environment, exit codes, and external effects.
Keep repository checks independent of real credentials where possible.
Future `scripts/acceptance local` runs local simulated flows; `operator` prepares a live checklist and starts no deployment.
Production infrastructure provisioning remains separately authorized work in the infrastructure repository or hosting platform.

The integration owner owns this folder. Component workers propose shared script changes through that owner.
