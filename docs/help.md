# Help and Summary

This document explains the behavior of the `help` command in DAM, including how to invoke it, what it outputs, and a comprehensive summary of all available operations.

---

## Overview

The `help` command provides inline documentation, usage examples, and an overview of all discovered applications. It is the built-in reference manual designed to be instantly accessible from the terminal.

---

## Syntax

There are multiple ways to invoke the help output. DAM intercepts standard help flags and empty invocations to display the usage summary:

```bash
# Explicit invocations
<cmd> help
<cmd> --help
<cmd> -h

# Implicit invocation
<cmd>
```

If you invoke your DAM command (e.g., `dkr`) without providing any arguments, the script automatically defaults to printing the help output.

---

## Help Output Structure

When invoked, the help command outputs a structured guide consisting of the following sections:

### 1. Header & Version
Displays the utility's name and its current version (e.g., `DAM (Docker Apps Lifecycle Manager) v1.1.0`).

### 2. Available Commands
Lists all the actions DAM supports. This is dynamically generated based on the script's capabilities, grouped by category:
- **Lifecycle Commands**: [`start`](start.md), [`stop`](stop.md), [`restart`](restart.md), [`recreate`](recreate.md), [`force-recreate`](recreate.md) [(or `frec`)](recreate.md), [`pause`](pause.md), [`unpause`](unpause.md), [`update`](update.md), [`cleanup`](cleanup.md), [`delete`](delete.md).
- **Information Commands**: [`status`](status.md), [`logs`](logs.md), [`get`](get.md), [`list`](list.md).
- **System Commands**: [`install`](install.md), [`config`](config.md), [`self-update`](self-update.md), [`uninstall`](uninstall.md), [`help`](help.md).

### 3. Usage Examples
Provides concrete examples of how to format commands, use the `<app>` selector, and combine multiple arguments. This section explicitly demonstrates the `all`, `all except`, and `[using files...]` syntax.

### 4. Available Apps
The help output dynamically scans your system based on the `SEARCH_DIRS` configured in `/etc/docker-app-manager.conf` and prints a columnar list of all discovered applications. 
- The list is divided by the search root (e.g., apps found in `/opt/stacks` vs `$HOME/apps`).
- It clearly separates excluded apps (those matching `EXCLUDE_DIRS`) at the bottom of the list.

---

## Summary of Operations

Below is a comprehensive technical mapping of every DAM command to its underlying Docker implementation and the scope of its execution:

| Command | Underlying Docker/Compose Command(s) | Scope |
| :------ | :------------------------------------ | :---- |
| `start` | `docker compose up -d` | Project |
| `stop` | `docker compose stop` | Project |
| `restart` | `docker compose restart` | Project |
| `recreate` | `docker compose down --remove-orphans` → `docker compose up -d` | Project |
| `force-recreate` / `frec` | `docker compose down --remove-orphans -t 0` → `docker compose up -d --force-recreate` | Project |
| `pause` | `docker compose pause` | Project |
| `unpause` | `docker compose unpause` | Project |
| `delete` | `docker compose down --remove-orphans [-v] [--rmi all]` + global dangling cleanup | Project + Host |
| `update` | `pull [--ignore-buildable]` → `build --pull` → `up -d` (or custom script) + global dangling cleanup | Project + Host |
| `status` | `docker ps -a` (filtered) + `docker stats --no-stream` | Containers |
| `list` | `find` + `docker ps -a` (labels) | Discovery |
| `get` | `docker ps -a` + `docker inspect` (filtered) | Containers |
| `logs` | `docker compose logs [flags]` | Project |
| `cleanup` | `docker image prune [-a] -f`, `docker network prune -f`, `docker volume prune [-a] -f`, `docker buildx prune -f` | Host |
| `debug` | *(not yet implemented)* | - |
| `install` | File operations (symlinks, config) | System |
| `config` | File operations (config update) | System |
| `self-update` | `curl` + file operations | System |
| `uninstall` | File removal | System |
| `help` | Outputs usage summary | CLI |

---

## Internal Behavior

When `help` is invoked:
1. DAM calls the internal `usage()` function.
2. The `usage()` function uses the configured `CUSTOM_CMD_NAME` to format the example commands (e.g., showing `dkr start` instead of `./dam.sh start`).
3. It triggers `list_available_apps()` which reads the filesystem to generate the current app inventory.
4. The script exits successfully (`exit 0`).
