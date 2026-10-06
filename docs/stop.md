# Stop Semantics

This document explains exactly how DAM's `stop` command works, including container state preservation and status reporting.

---

## Overview

The `stop` command safely halts running containers for the selected apps without removing any resources. It uses standard Docker Compose operations to gracefully terminate processes while preserving all data, logs, and configuration.

To stop one service only, use `<app>:<service>`:

```bash
dkr stop <app-name>:<service>
```

DAM passes the service name to `docker compose stop` and displays status for that service.

---

## Stop Flow

When the `stop` command is executed for an app, DAM follows a consistent, two-step process per app:

### Step 1: Stop Containers (1/2)

```bash
# Executed from within the app's directory
docker compose [-f <file>...] stop
```

DAM changes the working directory to the app's directory and issues the standard compose stop command.
- **Graceful shutdown**: Docker sends a `SIGTERM` signal to the primary process in each container, allowing it to shut down cleanly. If the process doesn't exit within the grace period (usually 10 seconds), Docker forces shutdown with a `SIGKILL`.
- **State preservation**: Containers transition from "running" to "exited". They remain on disk. Their filesystem state, logs, and configuration are entirely preserved.
- **Persistent resources**: Networks and volumes associated with the app are completely untouched.

### Step 2: Show Status (2/2)

```bash
docker compose ps
```

After the stop operation completes, DAM prints the current status of the app's services to confirm that all containers have successfully exited.

### Explicit Compose Files

Append `using <file1> <file2>...` to select Compose files explicitly. If none of the requested files resolve for an app, `stop` fails that app instead of stopping the stack described by its default Compose file. If one or more resolve, DAM uses only the resolved files and warns about any misses.

---

## State Diagram

```text
                ┌─────────────────┐
                │   stop <app>    │
                └────────┬────────┘
                         │
                         ▼
                ┌──────────────────┐
                │ docker compose   │
                │ stop             │
                └────────┬─────────┘
                         │
                         ▼
                ┌──────────────────┐
                │ Show status      │
                │ docker compose ps│
                └──────────────────┘
```

---

## Examples

```bash
# Stop a single app
dkr stop <app-name>

# Stop multiple specific apps
dkr stop <app-name> <app-name-2> <app3>

# Stop all available apps
dkr stop all

# Stop all apps except specific apps
dkr stop all except <app3> <app4>
```
