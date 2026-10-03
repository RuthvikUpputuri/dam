# Logs Semantics

This document explains exactly how DAM's `logs` command works, including its human-readable keyword parsing, restrictions, and piping behavior.

---

## Overview

The `logs` command allows you to view the standard output (`stdout`) and standard error (`stderr`) streams for your app containers. Rather than forcing you to memorize Docker's specific flags (`-f`, `--tail`, `-t`), DAM provides a human-friendly, chainable keyword syntax. 

> This logs command is still in development phase and is not fully integrated with traditional docker compose logs, so please expect bugs or unexpected behavior and be patient.

> DAM operates at the project/app level. If you have an app like `<app-name>` that has multiple services inside its `compose.yaml` (e.g., `<app-name>`, `postgres`, `redis`), DAM's `logs` command will always fetch and interleave the logs for all three services at once.

If you try to specify a service name, like: `dkr logs <app-name> postgres`

DAM will think `postgres` is a second app folder, fail to find it, and throw an error.

---

## Examples Scenarios

```bash
# View all logs for a single app
dkr logs <app-name>

# View the last 100 lines
dkr logs <app-name> last 100

# View the first 50 lines (piped through head)
dkr logs <app-name> first 50

# Chain multiple keywords: last 10 lines, live stream, with timestamps
dkr logs <app-name> last 10 live time

# View logs from the last 30 minutes
dkr logs <app-name> since 30m

# View static logs for all apps (no 'live' allowed)
dkr logs all last 20
```

---
## Argument Parsing and Flow

When the `logs` command is executed, DAM parses your requested app(s) alongside any number of chaining keywords. 

### Step 1: Keyword Translation

DAM parses the arguments sequentially, looking for specific keywords to translate into `docker compose logs` flags:

| Keyword | Alias | Translated Flag | Effect |
| :--- | :--- | :--- | :--- |
| `live` | `follow` | `-f` | Streams logs in real-time, keeping the connection open. |
| `time` | `timestamps` | `-t` | Prefixes every log line with a precise timestamp. |
| `last <N>` | | `--tail <N>` | Shows only the last `N` lines of logs. |
| `since <time>` | | `--since <time>` | Shows logs generated after a specific time or duration (e.g. `30m`). |
| `until <time>` | | `--until <time>` | Shows logs generated before a specific time. |

**Special Case: `first <N>`**
Because Docker Compose does not natively support a `--head` or `first` flag, DAM intercepts this keyword. Instead of passing a flag, DAM pipes the output of the entire command through standard Unix `head`:
```bash
docker compose [-f <file>...] logs [flags] | head -n <N>
```
To safely handle broken pipe errors that occur when `head` closes the stream early, DAM temporarily disables `set -o pipefail` for this specific execution block in `dam.sh`.

### Step 2: Live Stream Safety Check

```bash
if [[ "$action" == "logs" && "${requested[0]}" == "all" ]]; then
    # Block 'live' or 'follow'
```
DAM intentionally blocks you from using `live` or `follow` when querying `all` apps. Interleaving real-time logs from dozens of unrelated applications directly into a single terminal session creates an unreadable, chaotic output. 
- If attempted, DAM will throw an error and abort the command.
- If querying `all` apps *without* `live`, DAM will sequentially print the static logs for each app.

### Step 3: Fetching Logs (1/1)

```bash
# Executed from within the app's directory
docker compose [-f <file>...] logs [translated-flags]
```

DAM changes the working directory to the app's directory and executes the log fetch.
- If you were using `live` or `follow`, pressing `Ctrl+C` will cause Docker to exit with code `130`. DAM explicitly catches this exit code and masks it as a successful `0` exit, preventing your terminal from displaying a failure message when you intentionally closed a stream.

---

## State Diagram

```text
                ┌─────────────────┐
                │   logs <app>    │
                │   [keywords]    │
                └────────┬────────┘
                         │
                         ▼
                ┌──────────────────┐
                │ Parse keywords   │
                │ into docker flags│
                └────────┬─────────┘
                         │
                         ▼
                ┌──────────────────┐
                │ Is target 'all'  │
                │ AND keyword      │
                │ 'live'/'follow'? │
                └───┬──────────┬───┘
                    │ Yes      │ No
                    ▼          │
             ┌────────────┐    │
             │ Throw Error│    │
             │ & Abort    │    │
             └────────────┘    │
                               ▼
                ┌──────────────────┐
                │ docker compose   │
                │ logs [flags]     │
                └────────┬─────────┘
                         │
                         ▼
                ┌──────────────────┐
                │ User presses     │
                │ Ctrl+C?          │
                ├─── Yes ──────────► (Exit 130 masked to 0)
                │                  │
                ├─── No  ──────────► Return exit code
                └──────────────────┘
```

---