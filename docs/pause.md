# Pause Semantics

This document explains exactly how DAM's `pause` command works, detailing how it safely suspends containers without tearing down resources or exiting processes.

---

## Overview

The `pause` command freezes all running processes inside the containers of the selected apps. Unlike `stop` (which tells the application to gracefully shut down and exit), `pause` literally suspends the process threads in the host operating system kernel. The application remains in memory exactly as it was, but consumes no CPU cycles.

---

## Pause Flow

When the `pause` command is executed for an app, DAM follows a consistent, two-step process per app:

### Step 1: Pause Containers (1/2)

```bash
# Executed from within the app's directory
docker compose [-f <file>...] pause
```

DAM changes the working directory to the app's directory and issues the standard compose pause command.
- **Process Freezing**: Docker uses Linux cgroups to send a `SIGSTOP` signal to all processes within the containers.
- **Memory Preservation**: The applications do not lose their current state or drop their RAM. They are completely frozen in time.
- **Instantaneous**: Because there is no graceful shutdown logic for the application to execute, pausing is typically instantaneous.

### Step 2: Show Status (2/2)

```bash
docker compose ps
```

After the pause operation completes, DAM prints the current status of the app's services. You will see the state change to `Paused` (instead of `Up` or `Exited`).

---

## State Diagram

```text
                ┌─────────────────┐
                │   pause <app>   │
                └────────┬────────┘
                         │
                         ▼
                ┌──────────────────┐
                │ docker compose   │
                │ pause            │
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
# Pause a single app
dkr pause <app-name>

# Pause multiple specific apps
dkr pause <app-name> <app-name-2> <proxy-app>

# Pause all available apps
dkr pause all

# Pause all apps except the reverse proxy and portainer
dkr pause all except <proxy-app> portainer
```
