# Start Semantics

This document explains exactly how DAM's `start` command works, including container creation and status reporting.

---

## Overview

The `start` command is designed to be robust. Rather than simply issuing a `docker compose start` (which only starts existing, stopped containers without evaluating configuration), DAM uses `docker compose up -d`. This ensures that any recent configuration changes to the Compose file are applied and containers are created if they don't already exist.

Use `<app>:<service>` to start one service rather than the whole project:

```bash
dkr start <app-name>:<service>
```

DAM passes the service name to `docker compose up -d` and displays status for that service.

---

## Start Flow

When the `start` command is executed for an app, DAM follows a consistent, two-step process per app:

### Step 1: Start/Create Containers (1/2)

```bash
# Executed from within the app's directory
docker compose [-f <file>...] up -d
```

DAM changes the working directory to the app's directory and issues the standard `up -d` command.
- **Detached Mode**: The `-d` flag runs containers in the background, leaving your terminal free.
- **Creation**: If the containers, networks, or volumes do not exist, Docker will create them based on the current Compose file.
- **Recreation**: If the Compose file has been modified since the containers were last started, Docker will detect the changes, stop the old containers, and recreate them with the new configuration.

> **Important**: Because it uses `up -d`, `start` effectively doubles as an "apply configuration" command.

### Step 2: Show Status (2/2)

```bash
docker compose ps
```

After the containers are created and started, DAM prints the current status of the app's services to confirm that all containers are successfully running.

### Explicit Compose Files

Append `using <file1> <file2>...` to select Compose files explicitly. If none of the requested files resolve for an app, `start` logs an informational message and falls back to that app's default Compose file. If one or more resolve, DAM uses only the resolved files and warns about any misses.

---

## State Diagram

```text
                ┌─────────────────┐
                │   start <app>   │
                └────────┬────────┘
                         │
                         ▼
                ┌──────────────────┐
                │ docker compose   │
                │ up -d            │
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
# Start a single app
dkr start <app-name>

# Start multiple specific apps
dkr start <app-name> <app-name-2> <app3>

# Start all available apps
dkr start all

# Start all apps except specific apps
dkr start all except <app3> <app4>

# Start an app merging specific compose files (e.g. dev and prod)
dkr start <app-name> using compose dev prod
```
