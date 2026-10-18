# Hermes Commander profile template

`scripts/local-hermes-profile` copies these tracked context files into the
ignored `local/hermes/commander-profile` only after an operator supplies the
project-local Hermes API-server configuration and bearer token. It never copies
provider credentials from the default Hermes home.

`config.yaml.example` binds the API server to loopback only. Its bearer key is
provided at process launch from the ignored project-local token file rather than
stored in the profile configuration.

Hermes loads `SOUL.md` from `HERMES_HOME` and discovers `AGENTS.md` from the
workspace chain. During the isolated Anthropic API-key handoff,
`scripts/local-hermes-gateway` links its credential-free runtime home back to
this profile's `SOUL.md`, so the active Commander persona and worker-model
policy remain current without copying provider login state. Hermes `MEMORY.md`,
`USER.md`, session SQLite state, skills, and any token remain ignored under
`local/hermes/`.
