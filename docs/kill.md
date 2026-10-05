# Kill Semantics

This document explains exactly how DAM's `kill` command works, including process termination behavior and status reporting.

---

## Overview

The `kill` command forcefully halts running containers for the selected apps without removing any resources. Unlike `stop`, which waits for a 10-second grace period for processes to cleanly exit, `kill` bypasses graceful shutdown and immediately sends a `SIGKILL` to terminate the containers instantly.

This is extremely useful when containers are frozen, unresponsive, or when you need to shut down an app immediately without waiting for standard shutdown procedures.

---

## Kill Flow

When the `kill` command is executed for an app, DAM follows a consistent, two-step process per app:

### Step 1: Force Stop Containers (1/2)

```bash
# Executed from within the app's directory
docker compose [-f <file>...] kill
```

DAM changes the working directory to the app's directory and issues the standard compose kill command.
- **Immediate termination**: Docker skips the `SIGTERM` grace period entirely and directly sends a `SIGKILL` to the primary process in each container, forcing it to stop immediately.
- **State preservation**: Containers transition from "running" to "exited". They remain on disk. Their filesystem state and configuration are entirely preserved, though data currently in memory but not yet written to disk may be lost due to the lack of graceful shutdown.
- **Persistent resources**: Networks and volumes associated with the app are completely untouched.

### Step 2: Show Status (2/2)

```bash
docker compose ps
```

After the kill operation completes, DAM prints the current status of the app's services to confirm that all containers have successfully exited.

### Explicit Compose Files

Append `using <file1> <file2>...` to select Compose files explicitly. If none of the requested files resolve for an app, `kill` fails that app instead of killing the stack described by its default Compose file. If one or more resolve, DAM uses only the resolved files and warns about any misses.

---

## State Diagram

```text
                ┌─────────────────┐
                │   kill <app>    │
                └────────┬────────┘
                         │
                         ▼
                ┌──────────────────┐
                │ docker compose   │
                │ kill             │
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
# Force stop a single app
dkr kill <app-name>

# Force stop multiple specific apps
dkr kill <app-name> <app-name-2> <app3>

# Force stop all available apps
dkr kill all

# Force stop all apps except specific apps
dkr kill all except <app3>
```
