# Start Semantics

This document explains exactly how DAM's `start` command works, including container creation and status reporting.

---

## Overview

The `start` command is designed to be robust. Rather than simply issuing a `docker compose start` (which only starts existing, stopped containers without evaluating configuration), DAM uses `docker compose up -d`. This ensures that any recent configuration changes to the Compose file are applied and containers are created if they don't already exist.

---

## Start Flow

When the `start` command is executed for an app, DAM follows a consistent, two-step process per app:

### Step 1: Start/Create Containers (1/2)

```bash
# Executed from within the app's directory
docker compose up -d
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
dkr start n8n

# Start multiple specific apps
dkr start n8n langflow traefik

# Start all available apps
dkr start all

# Start all apps except the reverse proxy and portainer
dkr start all except traefik portainer
```
