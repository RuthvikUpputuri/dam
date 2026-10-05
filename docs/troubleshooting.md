# Troubleshooting

This document covers common issues, error messages, and their resolutions.

---

## Error Messages from DAM

### `bash 4.4+ required`

**Cause:** DAM requires Bash 4.4+ for safe empty-array expansion under `set -u`.

**Fix:**
```bash
bash --version  # Check your version
# Upgrade Bash via your package manager:
sudo apt update && sudo apt install bash      # Debian/Ubuntu
sudo yum update && sudo yum install bash      # RHEL/CentOS
```

### `'docker' command not found`

**Cause:** Docker is not installed or not in PATH.

**Fix:** Install Docker following the [official instructions](https://docs.docker.com/engine/install/).

### `Docker daemon is not running or you lack permission`

**Cause:** Either the Docker daemon isn't running, or your user can't access it.

**Fix:**
```bash
# Start the daemon:
sudo systemctl start docker

# Check permissions (add yourself to the docker group):
sudo usermod -aG docker $USER
# Log out and back in for group changes to take effect
```

### `Neither 'docker compose' (v2 plugin) nor 'docker-compose' (v1) is available`

**Cause:** Neither the v2 Compose plugin nor the standalone v1 binary is installed.

**Fix:**
```bash
# Install the v2 plugin (recommended):
sudo apt install docker-compose-plugin     # Debian/Ubuntu
# Or install standalone:
sudo apt install docker-compose            # Older systems
```

### `App names with spaces are not supported: '<name>'`

**Cause:** A directory name or app argument contains spaces.

**Fix:** Rename the directory to remove spaces (use hyphens or underscores instead).

### `Multiple matching apps found for '<name>'`

**Cause:** Two or more directories with the same basename exist across (or within) your search directories.

**Example:**
```
[ERROR] Multiple matching apps found for 'myapp':
  - /opt/stacks/myapp
  - /home/user/apps/myapp
```

**Fix:**
- Rename one of the directories
- Remove the unwanted path from `SEARCH_DIRS`
- Move one into a directory name listed in `EXCLUDE_DIRS`

### `App '<name>' not found in any search directory`

**Cause:** No directory with that basename was found in any search root, or the found directory doesn't contain a Compose file.

**Fix:**
1. Check the app name spelling (it must match the directory basename exactly)
2. Verify the directory exists: `ls /opt/stacks/<name>/`
3. Verify it contains a Compose file: `ls /opt/stacks/<name>/compose.yaml`
4. Run `dkr list` to see all discovered apps
5. Check that the parent directory is in `SEARCH_DIRS`

### `No compose.yaml or docker-compose.yml found in '<name>'`

**Cause:** The directory was found but doesn't contain any recognized Compose file.

**Fix:** Ensure the directory contains one of: `compose.yaml`, `compose.yml`, `docker-compose.yaml`, or `docker-compose.yml`.

### `except: app '<name>' could not be found`

**Cause:** An app listed in `all except <name>` doesn't exist.

**Fix:** Check the spelling. DAM validates exception targets before proceeding.

### `Unexpected argument '<arg>'. Did you mean 'all except ...'?`

**Cause:** You used `all` followed by a word other than `except`.

**Fix:** Use the correct syntax: `<action> all except app1 app2`

### `Unknown cleanup argument '<arg>'`

**Cause:** An invalid argument was passed to `cleanup` or after `with`.

**Valid arguments:** `vol`, `net`, `buildx`, `img`, `all`

### `'all' cannot be combined with other cleanup targets`

**Cause:** You passed `cleanup all net` or similar.

**Fix:** Use `cleanup all` by itself, or list individual targets: `cleanup net vol`.

### `You cannot live-stream logs for 'all' apps simultaneously`

**Cause:** You tried `logs all live`.

**Fix:** Specify a single app for live log streaming: `logs <app-name> live`

### `This command must be run with sudo`

**Cause:** `install`, `config`, `uninstall`, or `self-update` was run without root privileges.

**Fix:** Prefix with `sudo`: `sudo dkr config`

### `Destructive action '<action> all' requires confirmation, but input is not a terminal`

**Cause:** Running a destructive `all` command in a non-interactive context (pipe, cron, CI/CD) without `-y`.

**Fix:** Add `-y` or `--yes`: `dkr delete all -y`

---

## Docker / Compose Errors

These errors come from Docker itself, not DAM. DAM passes them through.

### Pull failures

```
[FAIL] Image pull failed for '<app>'
```

**Possible causes:**
- Network connectivity issues
- Invalid image name in Compose file
- Private registry requiring authentication
- Rate limiting (especially Docker Hub)

### Build failures

```
[FAIL] Image build failed for '<app>'
```

**Possible causes:**
- Dockerfile syntax errors
- Missing build context files
- Base image unavailable
- Build dependencies not met

### Container creation failures

```
[FAIL] Container recreation failed for '<app>'
```

**Possible causes:**
- Port conflicts with other containers
- Volume mount issues
- Invalid environment variables
- Insufficient resources (memory, disk)

---

## Behavioral Notes

### App status shows "inactive" but the app is running

This can happen if:
- The Compose project name doesn't match the directory name (e.g., `name:` is set in the Compose file)
- The app was started outside of DAM and the project label doesn't match

DAM's `status` and `list` commands use the `com.docker.compose.project` Docker label to identify containers. If this label doesn't match the directory basename, the association won't be made.

### `update` didn't restart a stopped app

This is intentional. DAM preserves the running state:
- If the app was running before `update` → containers are recreated and started
- If the app was stopped before `update` → images are pulled/built but containers are NOT started

Use `start <app>` after `update` if you want to start a previously stopped app.

### `cleanup vol` removed volumes from other apps

`cleanup vol` runs `docker volume prune`, which removes **all** unused volumes system-wide. Volumes from stopped apps are considered "unused" by Docker.

**To avoid this:**
- Use `delete <app> with vol` instead (only removes that app's volumes)
- Don't stop apps before running `cleanup vol`
- Verify what will be removed before confirming

### `start` recreated my containers

DAM's `start` uses `docker compose up -d`, not `docker compose start`. This means if your Compose file or images have changed since the containers were last created, `docker compose up -d` will detect the changes and recreate the affected containers.

This is by design - it ensures your app matches the current Compose configuration.

### Custom update script wasn't found

The script must:
- Be in the app's root directory (not a subdirectory)
- Match the glob `update*.sh` (e.g., `update.sh`, `update-app.sh`, `update_v2.sh`)
- Be a regular file (not a directory or symlink that `find` wouldn't match)

### Partial failure during multi-app operation

If one app fails during a multi-app operation (e.g., `update all`):
- Processing **continues** with the remaining apps
- The failed app is tracked in the summary
- The script exits with code 1 if any app failed
- The post-operation cleanup still runs

---

## Diagnostic Commands

```bash
# See all discovered apps and their status:
dkr list

# Check details for specific apps:
dkr list <app-name> <app3>

# View detailed container info:
dkr get <app-name> info

# Check container states:
dkr get <app-name> state

# Check health:
dkr get <app-name> health

# View the configuration file:
cat /etc/docker-app-manager.conf

# Verify Docker is working:
docker info
docker compose version
```


