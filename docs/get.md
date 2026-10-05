# Get Semantics

This document explains exactly how DAM's `get` command works. Designed primarily for scripting, automation, and deep inspection, `get` is unique because it strips away all visual formatting (like the standard DAM header) to return raw, scriptable data—unless you ask for the comprehensive `info` table.

---

## Overview

The `get` command allows you to extract precise, granular information about your applications down to the individual container level. It interacts directly with `docker inspect` and `docker ps` to pull exact data points without you needing to remember complex `docker format` strings.

---

## Syntax

```bash
dkr get <app-selection> <resource>
```

You can target apps broadly, or drill down into a specific service using the colon syntax (`:`):

```bash
dkr get <app> <resource>             # Returns data for ALL services in the app
dkr get <app>:<service> <resource>   # Returns data for ONLY the specified service
dkr get <app1> <app2> <resource>     # Returns data for multiple apps at once
dkr get all <resource>               # Returns data for ALL services across ALL apps
dkr get all except <app> <resource>  # Returns data for ALL apps except specified ones
```

---

## The `info` Resource (Deep Dive)

The `info` resource is a special case. Instead of returning raw scriptable text, it generates three comprehensive human-readable tables detailing every aspect of the requested apps.

```bash
dkr get <app> info
```

**What it does:**
1. Collects all containers associated with the target apps.
2. Generates **Table 1: Application Level Details** (APP | PATH | COMPOSE FILE | OVERALL STATE).
3. Generates **Table 2: Container Level Details** (APP | SERVICE | CONTAINER | IMAGE | STATE | HEALTH | PORTS).
4. Generates **Table 3: Docker Resources** (APP | CONTAINER ID | IMAGE ID | NETWORKS | VOLUMES | MOUNTPOINTS).

*Note: For the volumes in Table 3, it formats them as `Source=Destination` (for bind mounts) and `Name=Destination` (for docker volumes) for absolute clarity.*

---

## Raw Resources (For Scripting)

For all other resources, DAM drops the formatting, suppresses the standard startup header, and returns exactly what you asked for.

> **CRITICAL LIMITATION:** You can only ask for **one** raw resource type at a time (e.g. `dkr get <app-name> cid`). You cannot combine them (e.g. `dkr get <app-name> cid iid`). If you need multiple fields simultaneously, use the `info` resource instead.

| Resource Argument | Accepted Aliases | What It Returns |
| :------- | :------ | :-------------- |
| `cid` | `container-id` | The container ID. |
| `iid` | `image-id` | The Image ID (specifically, the first 12 characters of the `sha256:` digest). |
| `vol` | `volume`, `volumes` | Volume names (for managed volumes) or source paths (for bind mounts). |
| `mnt` | `mount`, `mountpoint`, `mountpoints` | The destination paths *inside* the container. |
| `net` | `network`, `networks` | The names of the Docker networks the container is attached to. |
| `port` | `ports` | Published port mappings (e.g., `0.0.0.0:80->80/tcp`). |
| `state` | `status` | The current container state (e.g., `running`, `exited`). |
| `health` | (none) | The health check status extracted from the docker status (e.g., `healthy`, `unhealthy`). Returns empty if no healthcheck is defined. |

### The `full` Modifier

By default, Docker and DAM artificially truncate the Container ID and Image ID to the first 12 characters to make them human-readable. If you are writing strict automation scripts and need the complete 64-character SHA-256 string, simply insert the word `full` before the resource name.
*(Note: The `full` modifier has no effect on the `info` tables, only on raw scriptable output).*

```bash
dkr get <app-name>:redis full cid   # Returns the 64-character container ID
dkr get <app-name>:redis full iid   # Returns the 64-character image ID
```

### Output Prefixing Behavior

To make the output scriptable but still legible when dealing with multiple containers, DAM intelligently formats the raw output based on how specific your target was:

**1. Targeting an Entire App (Implicit Services)**
If you ask for a resource of an app with multiple services (e.g., `dkr get <app-name> cid`), DAM will prefix the output with the service name so you know which ID belongs to which container:
```text
redis: 123456789abc
<app-name>: abcdef123456
```

**2. Targeting a Specific Service (Explicit Service)**
If you specifically target a single service using the colon syntax (e.g., `dkr get <app-name>:redis cid`), DAM assumes you are piping this into another script. It drops the prefix entirely and returns **just the value**:
```text
123456789abc
```

---

## Scripting Examples

Because `get` suppresses the header when returning raw data, you can pipe it directly into other bash commands.

**1. Restarting a specific container manually:**
```bash
docker restart $(dkr get <app-name>:redis cid)
```

**2. Finding out exactly where a specific service is storing its data:**
```bash
dkr get my-app:database vol
```

**3. Inspecting the image of a specific service:**
```bash
docker inspect $(dkr get <app3>:<app3> iid)
```

**4. Seeing the health status of an entire app stack:**
```bash
dkr get <app-name> health
```
*(Output might look like: `redis: healthy`, `<app-name>: starting`)*

**5. Getting all network attachments for every app except your VPN:**
```bash
dkr get all except vpn net
```

---

## Flexible Sentence Structure

Because of how DAM's argument parser is written, it extracts the resource arguments (`net`, `cid`, `info`, `full`, etc.) the exact moment it sees them, regardless of where they are in the sentence. 

This means **the order of the words is incredibly flexible**. You can write your commands in whatever way feels like the most legible, natural English sentence to you.

### Bare Skeleton Structures

The only rule for ordering is that the core command (`dkr get` or `<cmd> get` or `get` if custom command name is set to `none`) must come first. Because DAM dynamically plucks the `<resource>` out of the sentence the moment it sees it, the `<resource>` (and the `full` modifier) can literally be dropped anywhere—even right in the middle of other group words!

**Single/Multiple Apps:**
- `dkr get <resource> <app1> <app2>`
- `dkr get <app1> <resource> <app2>`
- `dkr get <app1> <app2> <resource>`

**All Apps:**
- `dkr get <resource> all`
- `dkr get all <resource>`

**All Except Specific Apps:**
- `dkr get <resource> all except <app>`
- `dkr get all <resource> except <app>`
- `dkr get all except <app> <resource>`

### Examples

This flexibility applies to *all* resources, including the `info` table. For example, all of these lines execute the exact same logic:
- `dkr get all except vpn net`
- `dkr get all net except vpn`
- `dkr get net all except vpn`

And the exact same rule applies when requesting the deep-dive `info` tables too:
- `dkr get info <app2> <app3>`
- `dkr get <app2> info <app3>`
- `dkr get <app2> <app3> info`
