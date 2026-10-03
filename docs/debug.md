# Debug Command Status

`debug` is present in DAM's command parser and global command list, but it does not currently collect diagnostics. It is a placeholder for a future debugging workflow.

## Syntax

```bash
<cmd> debug <app>
<cmd> debug <app1> <app2>
<cmd> debug all
<cmd> debug all except <app1> <app2>
```

It uses the standard application-selection grammar. `all` discovers Compose-based applications and excludes names configured in `EXCLUDE_DIRS`. App names refer to application directory names, not service or container names.

## Current Behavior

Before parsing targets, DAM still verifies that Docker is installed, its daemon is reachable, and either `docker compose` or `docker-compose` is available. It then resolves each selected app directory using the normal discovery rules.

For every app that resolves successfully and is not excluded, DAM prints:

```text
[TODO] Debug feature is coming soon.
```

That placeholder returns success. DAM records the app as successful and prints the usual final action summary.

An app that is missing or ambiguous is still recorded as failed. An excluded app is recorded as skipped. DAM continues through the rest of the selected apps and exits nonzero when one or more apps failed discovery.

## Parsing Quirk

The current parser also recognizes the log-style keywords `last`, `first`, `since`, `until`, `live`, `follow`, `time`, and `timestamps`, plus numeric values such as `10` or `30m`, while handling `debug`. It removes those tokens from the app selection, but the placeholder ignores them completely.

For example, this currently performs the same placeholder operation as `dkr debug <app-name>`:

```bash
dkr debug <app-name> last 100
```

This is not a supported diagnostics feature and should not be relied on. Other words are treated as app names and may therefore produce normal app-not-found failures.

## What `debug` Does Not Do

At present, `debug` does not:

- run `docker compose logs`, `docker inspect`, `docker events`, or `docker stats`
- validate Compose files or application configuration
- target a Compose service or a container
- change containers, networks, volumes, images, or build cache
- produce a diagnostic bundle or write files

Use [logs.md](logs.md), [status.md](status.md), `get`, and native Docker commands for diagnosis until a real debug implementation exists.

