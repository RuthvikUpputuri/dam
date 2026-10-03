# `unpause`

This document details the behavior, execution flow, and selection mechanics of DAM's `unpause` command.

---

## Purpose

Resumes containers that have been suspended using the `pause` command. The processes inside the containers will continue execution exactly where they left off, without restarting or losing their in-memory state.

---

## Syntax

```bash
<cmd> unpause <app-selection>
```

---

## Execution Flow

For each specified app, DAM performs the following exact sequence:

### Step 1: Directory Resolution
DAM locates the application directory using its discovery engine (`find_app_dir`).

### Step 2: Unpause Containers (1/2)
DAM changes into the application directory and runs:
```bash
docker compose [-f <file>...] unpause
```
- If the app's containers are currently paused, Docker resumes their processes via cgroups freezing logic.
- If the app's containers are already running (not paused), Docker gracefully handles it by doing nothing and returning success.
- If the app is fully stopped (down), Docker Compose will return an error indicating there are no running containers to unpause, and DAM will catch this and report failure for that app.

### Step 3: Show Status (2/2)
Immediately after unpausing, DAM verifies the new state by running:
```bash
docker compose ps
```
This gives you immediate visual confirmation that the `STATUS` column has shifted from `Paused` back to `Up`.

---

## Example Scenarios

### Scenario 1: Unpausing a Single App
```bash
dkr unpause nextcloud
```
**Behavior:** Locates the `nextcloud` project, runs `docker compose unpause`, and prints the resulting `docker compose ps` table just for `nextcloud`.

### Scenario 2: Unpausing Multiple Specific Apps
```bash
dkr unpause radarr sonarr lidarr
```
**Behavior:** Processes each app sequentially. It will unpause `radarr` and show its status, then move to `sonarr`, and finally `lidarr`. If `sonarr` is stopped and fails to unpause, DAM will print an error for it but will **continue** and successfully unpause `lidarr`.

### Scenario 3: Unpausing All Apps
```bash
dkr unpause all
```
**Behavior:** Discovers every single valid app across your `SEARCH_DIRS`. It attempts to unpause every project one by one. 
*Note: Since it targets all apps, any apps that are fully stopped will trigger an expected warning/error from Docker Compose ("no containers to unpause"). This is normal and safe.*

### Scenario 4: Unpausing All Except Certain Apps
```bash
dkr unpause all except plex jellyfin
```
**Behavior:** Unpauses every discovered app *except* `plex` and `jellyfin` (which will remain in their current state, whether paused, running, or stopped).

---

## Scope & State Changes

- **Scope**: Compose project level (targets all services defined in the app's `compose.yaml`).
- **Memory/State**: Preserved entirely. Processes resume using the exact RAM footprint and state they had when they were paused.
- **Network**: Connections that timed out during the pause duration will naturally be dropped by the client, but the container's internal network state remains untouched.
