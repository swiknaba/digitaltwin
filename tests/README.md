# Automated checks

Run the repository contract suite from the root:

```sh
python3 -m unittest tests.test_root_contract -v
```

The tests inspect the resolved default Compose stack and its bootstrap scripts. They
verify that PostgreSQL plus Kirei are the only default services, no retired chat or
agent runtime dispatch remains in the default worker, and the published web port is
loopback-only.

For a disposable live PostgreSQL check, run `scripts/acceptance dependencies`.
Commander component and Electron harness checks live with the maintained OpenCode
patch in [`commander/opencode-ui-patch`](../commander/opencode-ui-patch/README.md).

These checks do not prove a production Commander operator runtime or a complete Gate
1 acceptance. Future-task handlers and their production operator evidence are added
in subsequent slices.
