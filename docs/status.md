# Status Semantics

This document explains exactly how DAM's `status` command works, including cross-project querying, aggregated status reporting, and resource usage statistics.

---

## Overview

Unlike other lifecycle operations (like `start` or `stop`) that execute sequentially inside each app's directory, the `status` command aggregates information across all selected apps simultaneously. It provides a high-level, consolidated view of container states and real-time resource consumption without changing any container states.

---

## Status Flow

When the `status` command is executed, DAM bypasses individual `docker compose` calls and instead interacts directly with the Docker engine to gather data efficiently:

### Step 1: Container Discovery

Before displaying any output, DAM identifies all containers belonging to the selected apps:
```bash
docker ps -a --filter "label=com.docker.compose.project" \
  --format '{{.ID}}|{{.Label "com.docker.compose.project"}}|{{.Label "com.docker.compose.project.working_dir"}}'
```
It matches the found project names (and working directories) against your requested apps to build a complete, accurate list of relevant container IDs. This approach successfully discovers containers even if they were started outside of DAM.

### Step 2: Current Service Status (1/2)

If containers are found for the requested apps, DAM queries their state:
```bash
docker ps -a -f "id=<cid1>" -f "id=<cid2>" ... \
  --format 'table {{.Names}}\t{{.Label "com.docker.compose.project"}}\t{{.Label "com.docker.compose.service"}}\t{{.Image}}\t{{.RunningFor}}\t{{.Status}}\t{{.Ports}}'
```

DAM formats the standard Docker process list to provide a clear, app-centric view. 
- The output table modifies standard headers to specifically highlight the **APP** (`com.docker.compose.project`) and **SERVICE** (`com.docker.compose.service`) labels.
- This provides a clean overview of what is running, exited, starting, or unhealthy across all selected applications in one table.

### Step 3: Real-time Resource Usage (2/2)

After displaying states, DAM captures a point-in-time snapshot of the resource consumption for all identified containers:
```bash
docker stats --no-stream <cid1> <cid2> ...
```

- Shows CPU percentage, Memory usage/limit, Network I/O, and Block I/O for each container.
- The `--no-stream` flag ensures the command prints the current metrics once and immediately exits, returning you to your prompt instead of taking over the terminal.

---

## State Diagram

```text
                ┌─────────────────┐
                │  status <app>   │
                └────────┬────────┘
                         │
                         ▼
                ┌──────────────────┐
                │ Query docker ps  │
                │ for matching apps│
                └────────┬─────────┘
                         │
             ┌───────────┴───────────┐
             │                       │
         Containers              No Containers
           Found                     Found
             │                       │
             ▼                       ▼
    ┌──────────────────┐    ┌─────────────────┐
    │ Show aggregated  │    │ Print warning:  │
    │ docker ps table  │    │ "No containers  │
    └────────┬─────────┘    │  found..."      │
             │              └─────────────────┘
             ▼
    ┌──────────────────┐
    │ Show resource    │
    │ usage with       │
    │ docker stats     │
    └──────────────────┘
```

---

## Examples

```bash
# View status for a single app
dkr status n8n

# View aggregated status for multiple apps
dkr status n8n langflow traefik

# View status for all available apps
dkr status all

# View status for all apps except the reverse proxy
dkr status all except traefik
```
