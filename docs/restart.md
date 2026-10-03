# Restart Semantics

This document explains exactly how DAM's `restart` command works, including container state behavior and when it should be used versus `recreate`.

---

## Overview

The `restart` command performs a simple, in-place restart of running containers for the selected apps. It is a quick way to bounce services (e.g., to reload an internal configuration file mapped via a volume), but it **does not** apply changes made to the Compose file itself.

---

## Restart Flow

When the `restart` command is executed for an app, DAM follows a consistent, two-step process per app:

### Step 1: Restart Containers (1/2)

```bash
# Executed from within the app's directory
docker compose [-f <file>...] restart
```

DAM changes the working directory to the app's directory and issues the standard compose restart command.
- **In-place Restart**: The existing containers are stopped and then started again. Their internal container IDs remain exactly the same.
- **No Configuration Updates**: Docker **will not** read `compose.yaml` to check for changes. If you changed a port mapping, environment variable, or volume mount, the restarted container will still use the old configuration.
- **No Image Updates**: Even if a newer image exists locally, the container will continue using the exact image hash it was originally created with.

> **Important**: If you have modified `compose.yaml` or pulled new images, you must use `recreate` or `update` instead of `restart`.

### Step 2: Show Status (2/2)

```bash
docker compose ps
```

After the restart operation completes, DAM prints the current status of the app's services to confirm that all containers have successfully started back up.

---

## State Diagram

```text
                ┌─────────────────┐
                │ restart <app>   │
                └────────┬────────┘
                         │
                         ▼
                ┌──────────────────┐
                │ docker compose   │
                │ restart          │
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
# Restart a single app
dkr restart <app-name>

# Restart multiple specific apps
dkr restart <app-name> <app-name-2> <proxy-app>

# Restart all available apps
dkr restart all

# Restart all apps except the reverse proxy and portainer
dkr restart all except <proxy-app> portainer
```
