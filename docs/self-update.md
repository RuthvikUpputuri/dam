# Self-Update Semantics

This document explains exactly how DAM's `self-update` command works, including security validations, checksum verification, and symlink refreshing.

---

## Overview

The `self-update` command allows DAM to seamlessly fetch its own latest version from the internet and replace the globally installed binary. It includes built-in safeguards to ensure the downloaded update is complete, valid, and safe before applying it.

> **Note**: Because this command modifies system binaries, it must be run with `sudo`.

---

## Update Flow

When `self-update` is executed, DAM proceeds through a rigorous validation and installation process:

### Step 1: URL Validation

DAM first checks its internal configuration for `UPDATE_URL`.
- If `UPDATE_URL` is empty, the update aborts.
- If `UPDATE_URL` does not start with `https://`, the update aborts to prevent insecure downloads over HTTP.

### Step 2: Download

```bash
# Executed with strict umask 077
curl -fsSLo /tmp/docker-app-manager-XXXXXX.tmp "$UPDATE_URL"
```

DAM uses `curl` to silently download the latest script into a secure temporary file created with strict permissions (`umask 077`) to prevent local tampering.

### Step 3: Syntax and Safety Validation

Before modifying any system files, DAM verifies the integrity of the downloaded file:
1. **Shebang Check**: It reads the first line (`head -n 1`) to ensure it starts with `#!`. If the URL returned a 404 HTML page instead of a bash script, this catches it.
2. **Bash Syntax Check**: It runs `bash -n` against the temporary file to perform a dry-run syntax check. If the download was truncated or contains syntax errors, the update immediately aborts.

### Step 4: Checksum Verification (Optional)

```bash
sha256sum /tmp/docker-app-manager-XXXXXX.tmp
```

If the user has set an `UPDATE_SHA256` value in `/etc/docker-app-manager.conf`, DAM compares the downloaded file's SHA-256 hash against the expected hash. If they do not match, the update is aborted to protect against supply chain attacks or corrupted downloads.

### Step 5: Installation

```bash
chmod 755 /tmp/docker-app-manager-XXXXXX.tmp
mv /tmp/docker-app-manager-XXXXXX.tmp /usr/local/bin/docker-app-manager
```

DAM makes the temporary file executable and moves it to `/usr/local/bin/docker-app-manager`, replacing the older version.

### Step 6: Configuration Refresh

If a `/etc/docker-app-manager.conf` configuration file is detected, DAM immediately runs its own install refresh routine:
```bash
bash /usr/local/bin/docker-app-manager install refresh
```
This ensures that any custom command aliases (like `dkr` or `app`) remain properly symlinked to the newly installed binary.

---

## State Diagram

```text
                ┌─────────────────┐
                │   self-update   │
                └────────┬────────┘
                         │
                         ▼
                ┌──────────────────┐
                │ Valid HTTPS URL? │
                └───┬──────────┬───┘
                    │ Yes      │ No
                    ▼          ▼
             ┌──────────┐   ┌───────┐
             │ curl -f  │   │ Abort │
             │ download │   └───────┘
             └───┬──────┘
                 │
                 ▼
          ┌────────────────┐
          │ Validate:      │
          │ 1. Shebang #!  │
          │ 2. bash -n     │
          │ 3. SHA-256     │
          └───┬─────────┬──┘
              │ Pass    │ Fail
              ▼         ▼
        ┌───────────┐ ┌───────┐
        │ chmod + mv│ │ Abort │
        └─────┬─────┘ └───────┘
              │
              ▼
        ┌───────────┐
        │ install   │
        │ refresh   │
        └───────────┘
```

---

## Examples

```bash
# Update DAM to the latest version (requires sudo)
sudo dkr self-update

# If using raw installation mode
sudo docker-app-manager self-update
```
