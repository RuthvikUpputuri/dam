#!/usr/bin/env bash
# shellcheck shell=bash
#
# =============================================================================
# @title        Docker App Manager (DAM)
# @description  A powerful, centralized lifecycle manager for Docker Compose applications.
#               Built for sysadmins, hobbyists, and self-hosters to easily perform 
#               bulk operations (start, stop, update, clean) across multiple apps.
#
# @author       Ruthvik Upputuri
# @repository   https://github.com/RuthvikUpputuri/dam
# @license      MIT License
# @created      September 2026
# =============================================================================
#
# Supports all major app lifecycle operations in one script:
#   - start   : start app containers (create if needed)
#   - stop    : stop running app containers
#   - restart : restart app containers
#   - recreate: down + up -d (clean app stack restart)
#   - force-recreate (alias: frec)
#               : forceful down + up -d --force-recreate
#   - delete  : remove app containers/networks and then clean dangling resources
#   - cleanup : clean dangling images. (args: net, buildx, vol, all)
#   - update  : pull latest images, build (if any), and recreate containers (or run custom update*.sh)
#
# App selection syntax (same for start/stop/restart/recreate/force-recreate/delete/update):
#   <action> all                             - All apps (destructive actions require -y/--yes)
#   <action> all except traefik portainer    - All apps except specified apps
#   <action> homarr                          - Single specified app
#   <action> n8n langflow traefik            - Multiple specified apps
#
# Optional: Append 'with vol', 'with net', etc. to run extended cleanup on update/delete.
# Example:  delete all except traefik with vol net
#
# Note: App names and paths must not contain spaces.
# Scope and limitations: This tool manages one compose project per folder using the standard filenames.
# It does not support Swarm, Kubernetes, or folders that need several compose files selected manually.
#
# Examples:
#   start all except traefik
#   restart homarr n8n
#   recreate all except traefik
#   delete affine
#   cleanup
#   cleanup buildx
#   cleanup vol
#   cleanup all
#
# Installation:
#   To use commands like 'start appName' or 'update appName' globally from anywhere:
#   Run: sudo ./dam.sh install
# =============================================================================

set -uo pipefail

# Bash version check
# Bash 4.4+ is required for empty-array expansion under set -u (e.g. "${ARRAY[@]}")
(( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) )) || { echo "bash 4.4+ required"; exit 1; }

# ── Configuration ─────────────────────────────────────────────────────────────
# Set this to the raw URL of your script (e.g. GitHub raw link) for easy self-updating
UPDATE_URL="https://raw.githubusercontent.com/RuthvikUpputuri/dam/main/dam.sh"
CONFIG_FILE="/etc/docker-app-manager.conf"

if [[ -f "$CONFIG_FILE" ]]; then
    # Load user settings if they exist
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
else
    # Fallback defaults for quick local use if not installed
    real_user_home="$HOME"
    if [[ -n "${SUDO_USER:-}" ]]; then
        real_user_home="$(getent passwd "$SUDO_USER" | cut -d: -f6 2>/dev/null)"
        real_user_home="${real_user_home:-$HOME}"
    fi
    SEARCH_DIRS=()
    for default_dir in "/opt/stacks" "/opt/projects" "${real_user_home}/apps" "${real_user_home}/stacks"; do
        if [[ -d "$default_dir" ]]; then
            SEARCH_DIRS+=("$default_dir")
        fi
    done
    EXCLUDE_DIRS=("recovered" "recovered-configs" "unused")
fi

declare -p SEARCH_DIRS &>/dev/null || SEARCH_DIRS=()
declare -p EXCLUDE_DIRS &>/dev/null || EXCLUDE_DIRS=()

CMD_PREFIX="${CUSTOM_CMD_NAME:-}"
if [[ -n "$CMD_PREFIX" ]]; then
    P_CMD="${CMD_PREFIX} "
else
    P_CMD=""
fi

FIND_PRUNE_ARGS=()
for excl in "${EXCLUDE_DIRS[@]}"; do
    FIND_PRUNE_ARGS+=( -name "$excl" -prune -o )
done

declare -gA APP_DIR_CACHE

find_app_dir() {
    local target="$1"
    if [[ "$target" =~ [[:space:]] ]]; then
        echo -e "${RED}[ERROR]${NC} App names with spaces are not supported: '${target}'" >&2
        return 1
    fi
    
    if [[ -n "${APP_DIR_CACHE["$target"]:-}" ]]; then
        local cached_result="${APP_DIR_CACHE["$target"]}"
        if [[ "$cached_result" == "DUPLICATE:"* ]]; then
            echo -e "${RED}[ERROR]${NC} Multiple matching apps found for '${target}':" >&2
            local matches="${cached_result#DUPLICATE:}"
            while IFS='|' read -r match; do
                [[ -n "$match" ]] && echo -e "  - ${match}" >&2
            done <<< "$matches"
            return 1
        elif [[ "$cached_result" == "NOT_FOUND" ]]; then
            return 0
        else
            echo "$cached_result"
            return 0
        fi
    fi

    local valid_search_dirs=()
    for d in "${SEARCH_DIRS[@]}"; do
        [[ -d "$d" ]] && valid_search_dirs+=("$d")
    done
    
    if [[ ${#valid_search_dirs[@]} -gt 0 ]]; then
        local found=()
        while IFS= read -r -d '' match; do
            local has_compose=false
            for cf in "compose.yaml" "compose.yml" "docker-compose.yaml" "docker-compose.yml"; do
                if [[ -f "$match/$cf" ]]; then
                    has_compose=true
                    break
                fi
            done
            if ! $has_compose; then
                for f in "$match"/update*.sh; do
                    if [[ -f "$f" ]]; then
                        has_compose=true
                        break
                    fi
                done
            fi
            if $has_compose; then
                found+=("$match")
            fi
        done < <(find "${valid_search_dirs[@]}" -mindepth 1 -maxdepth 5 "${FIND_PRUNE_ARGS[@]}" -type d -name "$target" -print0 2>/dev/null)
        
        if [[ ${#found[@]} -eq 1 ]]; then
            APP_DIR_CACHE["$target"]="${found[0]}"
            echo "${found[0]}"
        elif [[ ${#found[@]} -gt 1 ]]; then
            local matches_str=""
            echo -e "${RED}[ERROR]${NC} Multiple matching apps found for '${target}':" >&2
            for match in "${found[@]}"; do
                matches_str+="${match}|"
                echo -e "  - ${match}" >&2
            done
            APP_DIR_CACHE["$target"]="DUPLICATE:${matches_str}"
            return 1
        else
            APP_DIR_CACHE["$target"]="NOT_FOUND"
        fi
    else
        APP_DIR_CACHE["$target"]="NOT_FOUND"
    fi
}

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Counters ──────────────────────────────────────────────────────────────────
TOTAL=0
SUCCESS=0
FAILED=0
SKIPPED=0
SUCCESS_APPS=()
FAILED_APPS=()
SKIPPED_APPS=()

# ── Helpers ───────────────────────────────────────────────────────────────────
print_header() {
    echo
    echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║          Docker Apps Lifecycle Manager               ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
    echo
}

print_section() {
    local action="$1"
    local name="$2"
    echo
    echo -e "${BOLD}┌─────────────────────────────────────────────────────${NC}"
    echo -e "${BOLD}│  ${action}: ${CYAN}${name}${NC}"
    echo -e "${BOLD}└─────────────────────────────────────────────────────${NC}"
}

print_summary() {
    local action="$1"
    echo
    echo -e "${BOLD}══════════════════════ SUMMARY ══════════════════════${NC}"
    echo -e "  Action performed     : ${BOLD}${action}${NC}"
    echo -e "  Total apps processed : ${BOLD}${TOTAL}${NC}"
    echo -e "  ${GREEN}✔ Successful         : ${SUCCESS}${NC}"
    [[ $FAILED  -gt 0 ]] && echo -e "  ${RED}✘ Failed             : ${FAILED}${NC}"
    [[ $SKIPPED -gt 0 ]] && echo -e "  ${YELLOW}⚠ Skipped            : ${SKIPPED}${NC}"

    if [[ ${#SUCCESS_APPS[@]} -gt 0 ]]; then
        echo -e "  ${GREEN}Successful apps:${NC} ${SUCCESS_APPS[*]}"
    fi

    if [[ ${#FAILED_APPS[@]} -gt 0 ]]; then
        echo -e "  ${RED}Failed apps:${NC}     ${FAILED_APPS[*]}"
    fi

    if [[ ${#SKIPPED_APPS[@]} -gt 0 ]]; then
        echo -e "  ${YELLOW}Skipped apps:${NC}    ${SKIPPED_APPS[*]}"
    fi

    echo -e "${BOLD}═════════════════════════════════════════════════════${NC}"
    echo
}

is_excluded() {
    local folder="$1"
    for excl in "${EXCLUDE_DIRS[@]}"; do
        [[ "$folder" == "$excl" ]] && return 0
    done
    return 1
}

dc() {
    if docker compose version &>/dev/null; then
        docker compose "$@"
    elif docker-compose version &>/dev/null; then
        docker-compose "$@"
    else
        echo -e "${RED}[ERROR]${NC} Neither 'docker compose' nor 'docker-compose' is available."
        return 1
    fi
}

docker_ready() {
    if ! command -v docker &>/dev/null; then
        echo -e "${RED}[ERROR]${NC} 'docker' command not found. Please install Docker."
        return 1
    fi

    if ! docker info &>/dev/null; then
        echo -e "${RED}[ERROR]${NC} Docker daemon is not running or you lack permission to access it."
        echo -e "        Try: sudo systemctl start docker"
        return 1
    fi
    
    if ! docker compose version &>/dev/null && ! docker-compose version &>/dev/null; then
        echo -e "${RED}[ERROR]${NC} Neither 'docker compose' (v2 plugin) nor 'docker-compose' (v1) is available."
        return 1
    fi

    return 0
}

has_compose_files() {
    local dir="$1"
    for cf in "compose.yaml" "compose.yml" "docker-compose.yaml" "docker-compose.yml"; do
        [[ -f "$dir/$cf" ]] && return 0
    done
    return 1
}

has_update_files() {
    local dir="$1"
    has_compose_files "$dir" && return 0
    for f in "$dir"/update*.sh; do
        [[ -f "$f" ]] && return 0
    done
    return 1
}

print_apps_in_columns() {
    local prefix="$1"
    shift
    local apps=("$@")
    if [[ ${#apps[@]} -eq 0 ]]; then return; fi
    
    mapfile -t sorted_apps < <(printf '%s\n' "${apps[@]}" | sort)
    local count=0
    local row=""
    for app in "${sorted_apps[@]}"; do
        local formatted_app
        printf -v formatted_app "• %-25s" "$app"
        row+="${formatted_app}"
        ((count++))
        if (( count % 3 == 0 )); then
            echo -e "${prefix}${row}"
            row=""
        fi
    done
    if [[ -n "$row" ]]; then
        echo -e "${prefix}${row}"
    fi
}

list_available_apps() {
    local mode="${1:-compose}"
    local prefix="${2:-  }"
    shift 2 || true
    local explicit_apps=("$@")

    local valid_search_dirs=()
    for d in "${SEARCH_DIRS[@]}"; do
        [[ -d "$d" ]] && valid_search_dirs+=("$d")
    done
    [[ ${#valid_search_dirs[@]} -eq 0 ]] && return

    local first_dir=true
    for sdir in "${valid_search_dirs[@]}"; do
        local LIST_PRUNE_ARGS=()
        for excl in "${EXCLUDE_DIRS[@]}"; do
            LIST_PRUNE_ARGS+=( -name "$excl" -prune -print0 -o )
        done

        local apps=()
        local excluded_apps=()
        while IFS= read -r -d '' d; do
            local name
            name="$(basename "$d")"
            
            local valid=false
            if [[ ${#explicit_apps[@]} -gt 0 ]]; then
                for e_app in "${explicit_apps[@]}"; do
                    if [[ "$e_app" == "$name" ]]; then
                        valid=true
                        break
                    fi
                done
            else
                case "$mode" in
                    compose)
                        has_compose_files "$d" && valid=true
                        ;;
                    update)
                        has_update_files "$d" && valid=true
                        ;;
                    *)
                        valid=true
                        ;;
                esac
            fi
            
            if is_excluded "$name"; then
                excluded_apps+=("$name")
            elif $valid; then
                apps+=("$name")
            fi
        done < <(find "$sdir" -mindepth 1 -maxdepth 5 "${LIST_PRUNE_ARGS[@]}" -type d -print0 2>/dev/null | sort -z)

        if [[ ${#apps[@]} -gt 0 || ${#excluded_apps[@]} -gt 0 ]]; then
            $first_dir || echo ""
            first_dir=false
            echo -e "${prefix}${CYAN}${BOLD}📁 ${sdir}${NC}"
            
            if [[ ${#apps[@]} -gt 0 ]]; then
                print_apps_in_columns "${prefix}  " "${apps[@]}"
            fi
            
            if [[ ${#excluded_apps[@]} -gt 0 ]]; then
                echo -e "${prefix}  ${YELLOW}🚫 Excluded:${NC}"
                print_apps_in_columns "${prefix}    " "${excluded_apps[@]}"
            fi
        fi
    done
}

get_all_apps() {
    local mode="${1:-compose}"
    local apps=()
    local valid_search_dirs=()
    for d in "${SEARCH_DIRS[@]}"; do
        [[ -d "$d" ]] && valid_search_dirs+=("$d")
    done
    [[ ${#valid_search_dirs[@]} -eq 0 ]] && return

    while IFS= read -r -d '' d; do
        local name
        name="$(basename "$d")"
        is_excluded "$name" && continue

        case "$mode" in
            compose)
                has_compose_files "$d" || continue
                ;;
            update)
                has_update_files "$d" || continue
                ;;
            *)
                ;;
        esac

        apps+=("$name")
    done < <(find "${valid_search_dirs[@]}" -mindepth 1 -maxdepth 5 "${FIND_PRUNE_ARGS[@]}" -type d -print0 2>/dev/null | sort -z)

    echo "${apps[@]}"
}

usage() {
    echo -e "${BOLD}Usage:${NC}"
    echo -e "  ${P_CMD}<action> all                             - All apps"
    echo -e "  ${P_CMD}<action> all except <name> [name ...]    - All apps except specified apps"
    echo -e "  ${P_CMD}<action> <name> [name ...]               - One or more specific apps"
    echo -e "  ${P_CMD}cleanup [net|buildx|vol|img|all] [-y]    - Clean dangling resources"
    echo
    echo -e "${BOLD}Examples:${NC}"
    echo -e "  ${P_CMD}start all except traefik"
    echo -e "  ${P_CMD}restart homarr n8n"
    echo -e "  ${P_CMD}update n8n langflow traefik"
    echo -e "  ${P_CMD}delete affine"
    echo -e "  ${P_CMD}cleanup vol"
    echo -e "  ${P_CMD}cleanup"
    echo
    echo -e "${BOLD}Actions:${NC}"
    echo -e "  start              Start app containers"
    echo -e "  stop               Stop app containers"
    echo -e "  restart            Restart app containers"
    echo -e "  recreate           Recreate app stack (down + up -d)"
    echo -e "  force-recreate     Forceful recreate (down -t 0 + up -d --force-recreate)"
    echo -e "                     alias: frec"
    echo -e "  delete             Remove app stack and run dangling cleanup"
    echo -e "  pause              Pause app containers"
    echo -e "  unpause            Unpause app containers"
    echo -e "  update             Pull latest images and recreate containers"
    echo -e "                     (or run your custom script, if it exists. Make sure to name it update*.sh)"
    echo -e "  status             View the current status of app containers"
    echo -e "  logs               View app logs. Chain arguments like: last 100, live, since 30m, time, first 50"
    echo -e "  debug              [Coming Soon] Advanced app debugging."
    echo -e "  cleanup [net|buildx|vol|img|all] [-y]"
    echo -e "                     Clean dangling images (default)"
    echo -e "                     args: [net] includes unused networks, [buildx] includes cache, [vol] includes volumes, [all] includes everything"
    echo -e "                     (Tip: You can append 'with vol', 'with net', etc. directly to 'delete' and 'update')"
    echo -e "                     (Accepts -y/--yes to skip confirmations)"
    echo -e "  Config options:    ALLOW_CUSTOM_UPDATE_SCRIPTS=true/false, UPDATE_SHA256=hash, UPDATE_URL=https://..."
    echo -e "  -y, --yes          Skip confirmations for 'all' on destructive actions (delete)"
    echo
    if [[ -n "$CMD_PREFIX" ]]; then
        echo -e "  sudo ${CMD_PREFIX} config          Re-run the setup wizard to change app directories or command name"
        echo -e "  sudo ${CMD_PREFIX} self-update     Fetch the latest version of this script online and install it"
        echo -e "  sudo ${CMD_PREFIX} uninstall       Uninstalls the script and removes all traces from your system"
    else
        echo -e "  sudo docker-app-manager config     Re-run the setup wizard to change app directories or command name"
        echo -e "  sudo docker-app-manager self-update Fetch the latest version of this script online and install it"
        echo -e "  sudo docker-app-manager uninstall  Uninstalls the script and removes all traces from your system"
    fi
    echo -e "  sudo ./dam.sh install           Installs the script universally to your system"
    echo -e "  sudo ./dam.sh install --refresh Refreshes the command symlinks non-interactively"
    echo -e "                                     (NOTE: Use this command only if you manually downloaded this script. Make sure to make it executable first!)"
    echo
    echo -e "${BOLD}Available apps (compose-based):${NC}"
    list_available_apps "compose" "  "
    echo
}

cleanup_dangling_resources() {
    local modes=("$@")
    if [[ ${#modes[@]} -eq 0 ]]; then
        modes=("basic")
    fi
    local mode_all=false
    local mode_vol=false
    local mode_net=false
    local mode_buildx=false
    local mode_img=false
    local mode_str="${modes[*]}"

    for m in "${modes[@]}"; do
        case "$m" in
            all) mode_all=true ;;
            vol) mode_vol=true ;;
            net) mode_net=true ;;
            buildx) mode_buildx=true ;;
            img) mode_img=true ;;
        esac
    done

    if $mode_all || $mode_vol; then
        local proceed_vol=false
        if [[ "${ASSUME_YES:-false}" == "true" ]]; then
            proceed_vol=true
        else
            if [[ ! -t 0 ]]; then
                echo -e "${RED}[ERROR]${NC} Volume prune requires confirmation, but input is not a terminal. Use -y / --yes to force."
                exit 1
            fi
            echo -e "\n${RED}${BOLD}  [WARNING] YOU ARE ABOUT TO DELETE UNUSED VOLUMES!${NC}"
            echo -e "${YELLOW}  This will permanently delete data for any apps that are currently stopped or deleted.${NC}"
            read -r -p "  Are you absolutely sure you want to proceed? [y/N] " response
            if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
                proceed_vol=true
            fi
        fi
    fi

    echo -e "${BOLD}── Docker cleanup (mode: ${mode_str}) ───────────────────${NC}"

    if $mode_all || $mode_img; then
        local proceed_img=false
        if [[ "${ASSUME_YES:-false}" == "true" ]]; then
            proceed_img=true
        else
            if [[ ! -t 0 ]]; then
                echo -e "${RED}[ERROR]${NC} Global image prune requires confirmation, but input is not a terminal. Use -y / --yes to force."
                exit 1
            fi
            echo -e "\n${YELLOW}${BOLD}  [WARNING] YOU ARE ABOUT TO DELETE ALL UNUSED IMAGES!${NC}"
            echo -e "${YELLOW}  This will permanently delete all downloaded Docker images that are not currently tied to a running container.${NC}"
            read -r -p "  Are you absolutely sure you want to proceed? [y/N] " response
            if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
                proceed_img=true
            fi
        fi
        
        if $proceed_img; then
            echo -e "${YELLOW}  [images]${NC}      Removing all unused images..."
            docker image prune -a -f | sed 's/^/                 /'
        else
            echo -e "${CYAN}  [images]${NC}      Skipped by user."
        fi
    else
        # Default behavior: prune only dangling (untagged) layers
        local dangling_images
        dangling_images="$(docker image ls -f dangling=true -q 2>/dev/null)"
        if [[ -n "$dangling_images" ]]; then
            echo -e "${YELLOW}  [images]${NC}      Removing dangling images..."
            docker image prune -f | sed 's/^/                 /'
        else
            echo -e "${CYAN}  [images]${NC}      No dangling images."
        fi
    fi

    # Unused (dangling) networks detached from every container.
    if $mode_all || $mode_net; then
        local proceed_net=false
        if [[ "${ASSUME_YES:-false}" == "true" ]]; then
            proceed_net=true
        else
            if [[ ! -t 0 ]]; then
                echo -e "${RED}[ERROR]${NC} Network prune requires confirmation, but input is not a terminal. Use -y / --yes to force."
                exit 1
            fi
            echo -e "\n${YELLOW}${BOLD}  [WARNING] YOU ARE ABOUT TO DELETE UNUSED NETWORKS!${NC}"
            echo -e "${YELLOW}  This will remove externally managed networks (e.g. Traefik proxy) if no containers are currently attached, which can break stacks that are stopped.${NC}"
            read -r -p "  Are you absolutely sure you want to prune networks? [y/N] " response
            if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
                proceed_net=true
            fi
        fi
        
        if $proceed_net; then
            local unused_nets
            unused_nets="$(docker network ls -q --filter dangling=true 2>/dev/null)"
            if [[ -n "$unused_nets" ]]; then
                echo -e "${YELLOW}  [networks]${NC}    Removing dangling networks..."
                docker network prune -f | sed 's/^/                 /'
            else
                echo -e "${CYAN}  [networks]${NC}    No dangling networks."
            fi
        else
            echo -e "${CYAN}  [networks]${NC}    Skipped by user."
        fi
    else
        echo -e "${CYAN}  [networks]${NC}    Global dangling networks skipped (app-networks were natively removed)."
    fi

    # Unused local volumes
    if $mode_all || $mode_vol; then
        if $proceed_vol; then
            local dangling_vols
            dangling_vols="$(docker volume ls -qf dangling=true 2>/dev/null)"
            if [[ -n "$dangling_vols" ]]; then
                echo -e "${YELLOW}  [volumes]${NC}     Removing unused volumes..."
                local out
                if out="$(docker volume prune -a -f 2>&1)"; then
                    # shellcheck disable=SC2001
                    sed 's/^/                 /' <<< "$out"
                elif out="$(docker volume prune -f 2>&1)"; then
                    # shellcheck disable=SC2001
                    sed 's/^/                 /' <<< "$out"
                else
                    echo -e "${RED}  [ERROR]${NC}       Volume prune failed:\n$out" | sed 's/^/                 /'
                fi
            else
                echo -e "${CYAN}  [volumes]${NC}     No dangling volumes."
            fi
        else
            echo -e "${CYAN}  [volumes]${NC}     Skipped by user."
        fi
    else
        echo -e "${CYAN}  [volumes]${NC}     Skipped (use 'cleanup vol' or 'cleanup all' to force prune)."
    fi

    # Unused build cache layers.
    if $mode_all || $mode_buildx; then
        local cache
        cache="$(docker buildx du --verbose 2>/dev/null | awk '/^Total/ {print $2; exit}' || true)"
        if [[ -n "$cache" && "$cache" != "0B" ]]; then
            echo -e "${YELLOW}  [build cache]${NC} Removing dangling build cache (${cache})..."
            local out
            if out="$(docker buildx prune -f 2>&1)"; then
                # shellcheck disable=SC2001
                sed 's/^/                 /' <<< "$out"
            elif out="$(docker builder prune -f 2>&1)"; then
                # shellcheck disable=SC2001
                sed 's/^/                 /' <<< "$out"
            else
                echo -e "${RED}  [ERROR]${NC}       Build cache prune failed:\n$out" | sed 's/^/                 /'
            fi
        else
            echo -e "${CYAN}  [build cache]${NC} No dangling build cache."
        fi
    else
        echo -e "${CYAN}  [build cache]${NC} Skipped (use 'cleanup buildx' or 'cleanup all' to force prune)."
    fi

    echo -e "${BOLD}─────────────────────────────────────────────────────${NC}"
    echo
}

run_compose_action_for_app() {
    local action="$1"
    local folder="$2"
    local dir
    dir="$(find_app_dir "$folder")"

    local canon_file=""
    for cf in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
        if [[ -f "$dir/$cf" ]]; then
            canon_file="$cf"
            break
        fi
    done
    if [[ -z "$canon_file" ]]; then
        echo -e "${RED}  [ERROR]${NC} No compose.yaml or docker-compose.yml found in '${folder}'."
        return 1
    fi

    echo -e "${CYAN}  [INFO]${NC} Compose file detected: ${canon_file}"

    pushd "$dir" > /dev/null || return 1

    case "$action" in
        start)
            echo
            echo -e "${BLUE}  [1/2]${NC} Starting containers..."
            dc up -d || { popd > /dev/null || true; return 1; }
            ;;
        stop)
            echo
            echo -e "${BLUE}  [1/2]${NC} Stopping containers..."
            dc stop || { popd > /dev/null || true; return 1; }
            ;;
        restart)
            echo
            echo -e "${BLUE}  [1/2]${NC} Restarting containers..."
            dc restart || { popd > /dev/null || true; return 1; }
            ;;
        pause)
            echo
            echo -e "${BLUE}  [1/2]${NC} Pausing containers..."
            dc pause || { popd > /dev/null || true; return 1; }
            ;;
        unpause)
            echo
            echo -e "${BLUE}  [1/2]${NC} Unpausing containers..."
            dc unpause || { popd > /dev/null || true; return 1; }
            ;;
        recreate)
            echo
            echo -e "${BLUE}  [1/3]${NC} Stopping and removing app stack..."
            dc down --remove-orphans || { popd > /dev/null || true; return 1; }
            echo
            echo -e "${BLUE}  [2/3]${NC} Recreating containers..."
            dc up -d || { popd > /dev/null || true; return 1; }
            ;;
        force-recreate)
            echo
            echo -e "${BLUE}  [1/3]${NC} Forcefully stopping and removing app stack..."
            dc down --remove-orphans -t 0 || { popd > /dev/null || true; return 1; }
            echo
            echo -e "${BLUE}  [2/3]${NC} Force-recreating containers..."
            dc up -d --force-recreate || { popd > /dev/null || true; return 1; }
            ;;
        delete)
            echo
            local app_down_args=("--remove-orphans")
            local del_vol=false
            local del_img=false
            for m in "${CLEANUP_MODES[@]}"; do
                [[ "$m" == "vol" || "$m" == "all" ]] && del_vol=true
                [[ "$m" == "img" || "$m" == "all" ]] && del_img=true
            done
            
            local msg_parts="containers, app networks"
            if $del_vol; then
                msg_parts+=", APP VOLUMES"
                app_down_args+=("-v")
            fi
            if $del_img; then
                msg_parts+=", APP IMAGES"
                app_down_args+=("--rmi" "all")
            fi
            
            echo -e "${BLUE}  [1/2]${NC} Removing app stack (${msg_parts})..."
            if $del_vol; then
                echo -e "${RED}  [WARNING]${NC} App-specific volumes are being permanently deleted."
            else
                echo -e "${CYAN}  [INFO]${NC} Volumes are preserved by default to protect data."
            fi
            if $del_img; then
                echo -e "${YELLOW}  [WARNING]${NC} App-specific images are being permanently deleted."
            fi
            dc down "${app_down_args[@]}" || { popd > /dev/null || true; return 1; }
            ;;
        *)
            popd > /dev/null || true
            echo -e "${RED}  [ERROR]${NC} Unknown compose action '${action}'."
            return 1
            ;;
    esac

    echo
    if [[ "$action" == "recreate" || "$action" == "force-recreate" ]]; then
        echo -e "${BLUE}  [3/3]${NC} Current service status:"
    else
        echo -e "${BLUE}  [2/2]${NC} Current service status:"
    fi
    dc ps || true

    popd > /dev/null || true
    return 0
}

run_update_action_for_app() {
    local folder="$1"
    local dir
    local rc
    dir="$(find_app_dir "$folder")"
    rc=$?

    if [[ $rc -ne 0 ]]; then
        return 1
    fi
    if [[ -z "$dir" ]]; then
        echo -e "${RED}  [ERROR]${NC} App '${folder}' not found in any search directory."
        return 1
    fi
    
    # Look for a custom update script
    local custom_script=""
    while IFS= read -r -d '' f; do
        custom_script="$f"
        break
    done < <(find "$dir" -maxdepth 1 -name "update*.sh" -print0 2>/dev/null | sort -z)

    if [[ -n "$custom_script" ]]; then
        echo -e "${CYAN}  [INFO]${NC} Custom update script found: ${BOLD}$(basename "$custom_script")${NC}"
        local allow_custom="${ALLOW_CUSTOM_UPDATE_SCRIPTS:-false}"
        if [[ "$allow_custom" =~ ^([yY][eE][sS]|[yY]|true|TRUE)$ ]]; then
            allow_custom="true"
        else
            allow_custom="false"
        fi

        if [[ "$allow_custom" != "true" ]]; then
            if [[ ! -t 0 ]]; then
                echo -e "${YELLOW}  [WARN]${NC} Cannot prompt for custom script (not a terminal). Skipping custom script and falling back to compose update."
            else
                read -r -p "  Do you want to run this custom update script? [y/N] " response
                if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
                    allow_custom="true"
                else
                    echo -e "${YELLOW}  [WARN]${NC} Skipping custom script. Falling back to compose update."
                fi
            fi
        fi
        
        if [[ "$allow_custom" == "true" ]]; then
            echo -e "${CYAN}  [INFO]${NC} Running custom script...\n"
            pushd "$dir" > /dev/null || return 1
            if bash "$(basename "$custom_script")"; then
                popd > /dev/null || true
                return 0
            else
                popd > /dev/null || true
                return 1
            fi
        fi
    fi

    local canon_file=""
    for cf in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
        if [[ -f "$dir/$cf" ]]; then
            canon_file="$cf"
            break
        fi
    done
    if [[ -z "$canon_file" ]]; then
        echo -e "${RED}  [ERROR]${NC} No compose.yaml or docker-compose.yml found in '${folder}'."
        return 1
    fi

    echo -e "${CYAN}  [INFO]${NC} Compose file detected: ${canon_file}"
    
    pushd "$dir" > /dev/null || return 1

    local running_containers
    running_containers="$(dc ps -q 2>/dev/null || true)"
    local was_running=false
    if [[ -n "$running_containers" ]]; then
        for cid in $running_containers; do
            if [[ "$(docker inspect -f '{{.State.Running}}' "$cid" 2>/dev/null)" == "true" ]]; then
                was_running=true
                break
            fi
        done
    fi
    if ! $was_running; then
        echo -e "${CYAN}  [INFO]${NC} App currently has no running containers. It will be left stopped."
    fi

    echo
    echo -e "${BLUE}  [1/4]${NC} Pulling latest images..."
    local pull_help
    pull_help="$(dc pull --help 2>&1 || true)"
    if [[ "$pull_help" == *"--ignore-buildable"* ]]; then
        if ! dc pull --ignore-buildable; then
            echo -e "${RED}  [FAIL]${NC} Image pull failed for '${folder}'."
            popd > /dev/null || true
            return 1
        fi
    else
        echo -e "${YELLOW}  [WARN]${NC} 'pull --ignore-buildable' unsupported. Falling back to ignore-pull-failures for buildable services."
        if ! dc pull --ignore-pull-failures; then
            echo -e "${RED}  [FAIL]${NC} Image pull failed for '${folder}'."
            popd > /dev/null || true
            return 1
        fi
    fi
    
    echo
    echo -e "${BLUE}  [2/4]${NC} Building images (if any)..."
    if ! dc build --pull; then
        echo -e "${RED}  [FAIL]${NC} Image build failed for '${folder}'."
        popd > /dev/null || true
        return 1
    fi

    echo
    if $was_running; then
        echo -e "${BLUE}  [3/4]${NC} Recreating containers with latest images..."
        if ! dc up -d; then
            echo -e "${RED}  [FAIL]${NC} Container recreation failed for '${folder}'."
            popd > /dev/null || true
            return 1
        fi
    else
        echo -e "${BLUE}  [3/4]${NC} Skipping container startup (app was stopped)."
    fi

    echo
    echo -e "${BLUE}  [4/4]${NC} Current service status:"
    dc ps || true

    popd > /dev/null || true
    return 0
}

run_logs_action_for_app() {
    local folder="$1"
    local dir
    dir="$(find_app_dir "$folder")"
    
    if [[ ! -d "$dir" ]]; then
        return 1
    fi

    pushd "$dir" > /dev/null || return 1
    
    local dc_args=()
    local head_lines=""
    
    local i=0
    while [[ $i -lt ${#LOG_ARGS_RAW[@]} ]]; do
        local kw="${LOG_ARGS_RAW[$i]}"
        case "$kw" in
            live|follow)
                dc_args+=("-f")
                ;;
            time|timestamps)
                dc_args+=("-t")
                ;;
            last)
                ((i++))
                if [[ $i -lt ${#LOG_ARGS_RAW[@]} && "${LOG_ARGS_RAW[$i]}" =~ ^[0-9]+[smhd]?$ ]]; then
                    dc_args+=("--tail" "${LOG_ARGS_RAW[$i]}")
                fi
                ;;
            first)
                ((i++))
                if [[ $i -lt ${#LOG_ARGS_RAW[@]} && "${LOG_ARGS_RAW[$i]}" =~ ^[0-9]+$ ]]; then
                    head_lines="${LOG_ARGS_RAW[$i]}"
                fi
                ;;
            since)
                ((i++))
                if [[ $i -lt ${#LOG_ARGS_RAW[@]} ]]; then
                    dc_args+=("--since" "${LOG_ARGS_RAW[$i]}")
                fi
                ;;
            until)
                ((i++))
                if [[ $i -lt ${#LOG_ARGS_RAW[@]} ]]; then
                    dc_args+=("--until" "${LOG_ARGS_RAW[$i]}")
                fi
                ;;
            *)
                # Safe fallback, handled in args.
                ;;
        esac
        ((i++))
    done

    echo -e "${BLUE}  [1/1]${NC} Fetching logs for '${folder}'..."
    if [[ -n "$head_lines" ]]; then
        set +o pipefail
        dc logs "${dc_args[@]}" | head -n "$head_lines"
        local rc=$?
        set -o pipefail
    else
        dc logs "${dc_args[@]}"
        local rc=$?
    fi

    # If the user pressed Ctrl+C to exit a live stream, Docker Compose exits with 130.
    # This is an expected exit, not a failure.
    if [[ $rc -eq 130 ]]; then
        rc=0
    fi

    popd > /dev/null || true
    return $rc
}

run_debug_action_for_app() {
    local folder="$1"
    echo -e "${YELLOW}  [TODO]${NC} Debug feature is coming soon."
    return 0
}

process_app() {
    local action="$1"
    local folder="$2"
    local dir
    local rc
    dir="$(find_app_dir "$folder")"
    rc=$?

    (( TOTAL++ )) || true
    print_section "$action" "$folder"

    if [[ $rc -ne 0 ]]; then
        (( FAILED++ )) || true
        FAILED_APPS+=("$folder")
        return 1
    fi
    if [[ -z "$dir" ]]; then
        echo -e "${RED}  [ERROR]${NC} App '${folder}' not found in any search directory."
        (( FAILED++ )) || true
        FAILED_APPS+=("$folder")
        return 1
    fi

    if is_excluded "$folder"; then
        echo -e "${YELLOW}  [SKIP]${NC} '${folder}' is excluded from operations."
        (( SKIPPED++ )) || true
        SKIPPED_APPS+=("$folder")
        return 0
    fi

    case "$action" in
        start|stop|restart|recreate|force-recreate|delete|pause|unpause|update|logs|debug)
            local success=false
            if [[ "$action" == "update" ]]; then
                if run_update_action_for_app "$folder"; then
                    success=true
                fi
            elif [[ "$action" == "logs" ]]; then
                if run_logs_action_for_app "$folder"; then
                    success=true
                fi
            elif [[ "$action" == "debug" ]]; then
                if run_debug_action_for_app "$folder"; then
                    success=true
                fi
            else
                if run_compose_action_for_app "$action" "$folder"; then
                    success=true
                fi
            fi

            if $success; then
                echo -e "\n${GREEN}  [DONE]${NC} '${folder}' ${action} completed successfully."
                (( SUCCESS++ )) || true
                SUCCESS_APPS+=("$folder")
                return 0
            fi
            echo -e "\n${RED}  [FAIL]${NC} '${action}' failed for '${folder}'."
            (( FAILED++ )) || true
            FAILED_APPS+=("$folder")
            return 1
            ;;
        *)
            echo -e "${RED}  [ERROR]${NC} Unsupported action '${action}'."
            (( FAILED++ )) || true
            FAILED_APPS+=("$folder")
            return 1
            ;;
    esac
}

parse_target_apps() {
    local action="$1"
    shift

    local mode="compose"
    if [[ "$action" == "update" ]]; then
        mode="update"
    fi

    if [[ $# -eq 0 ]]; then
        echo -e "${YELLOW}[WARN]${NC} No app selection provided."
        usage
        return 1
    fi

    local skip_prompt=false
    local requested=()
    local parsing_with=false
    CLEANUP_MODES=()
    LOG_ARGS_RAW=()
    ASSUME_YES=false

    for arg in "$@"; do
        if [[ "$arg" == "-y" || "$arg" == "--yes" ]]; then
            skip_prompt=true
            ASSUME_YES=true
        elif [[ "$arg" == "with" ]]; then
            parsing_with=true
        elif $parsing_with; then
            if [[ "$arg" == "vol" || "$arg" == "net" || "$arg" == "buildx" || "$arg" == "img" || "$arg" == "all" ]]; then
                CLEANUP_MODES+=("$arg")
            else
                echo -e "${RED}[ERROR]${NC} Unknown cleanup argument '${arg}' after 'with'."
                return 1
            fi
        else
            if [[ "$action" == "logs" || "$action" == "debug" ]]; then
                if [[ "$arg" =~ ^(last|first|since|until|live|follow|time|timestamps)$ || "$arg" =~ ^[0-9]+[smhd]?$ ]]; then
                    LOG_ARGS_RAW+=("$arg")
                    continue
                fi
            fi
            requested+=("$arg")
        fi
    done
    
    if [[ ${#requested[@]} -eq 0 ]]; then
        echo -e "${YELLOW}[WARN]${NC} No app selection provided."
        usage
        return 1
    fi

    APPS_TO_PROCESS=()

    if [[ "${requested[0]}" == "all" ]]; then
        local rest=("${requested[@]:1}")
        local user_excludes=()

        if [[ ${#rest[@]} -gt 0 ]]; then
            if [[ "${rest[0]}" != "except" ]]; then
                echo -e "${RED}[ERROR]${NC} Unexpected argument '${rest[0]}'. Did you mean 'all except ...'?"
                return 1
            fi
            user_excludes=("${rest[@]:1}")
        fi

        for excl in "${user_excludes[@]}"; do
            if [[ -z "$(find_app_dir "$excl")" ]]; then
                echo -e "${RED}[ERROR]${NC} except: app '${excl}' could not be found."
                return 1
            fi
        done

        read -ra all_apps <<< "$(get_all_apps "$mode")"
        if [[ ${#all_apps[@]} -eq 0 ]]; then
            echo -e "${RED}[ERROR]${NC} No matching apps found for action '${action}'."
            return 1
        fi

        for app in "${all_apps[@]}"; do
            local skip=false
            for excl in "${user_excludes[@]}"; do
                [[ "$app" == "$excl" ]] && skip=true && break
            done
            $skip || APPS_TO_PROCESS+=("$app")
        done

        if [[ ${#APPS_TO_PROCESS[@]} -eq 0 ]]; then
            echo -e "${YELLOW}[WARN]${NC} Nothing to process after exclusions."
            return 1
        fi

        if [[ ${#user_excludes[@]} -gt 0 ]]; then
            echo -e "${BOLD}Mode:${NC} ${action} ALL apps ${YELLOW}except${NC}: ${user_excludes[*]}"
        else
            echo -e "${BOLD}Mode:${NC} ${action} ALL apps"
        fi
        echo
        echo -e "${CYAN}Apps to process (${#APPS_TO_PROCESS[@]}):${NC}"
        list_available_apps "compose" "  " "${APPS_TO_PROCESS[@]}"
    else
        echo -e "${BOLD}Mode:${NC} ${action} specific app(s): ${CYAN}${requested[*]}${NC}"
        APPS_TO_PROCESS=(${requested[@]+"${requested[@]}"})
    fi

    if [[ "$action" == "logs" && "${requested[0]}" == "all" ]]; then
        for arg in "${LOG_ARGS_RAW[@]:-}"; do
            if [[ "$arg" == "live" || "$arg" == "follow" ]]; then
                echo -e "${RED}[ERROR]${NC} You cannot live-stream logs for 'all' apps simultaneously in the terminal."
                echo -e "        Please specify a single app, or drop the 'live/follow' argument."
                return 1
            fi
        done
    fi

    if [[ "${requested[0]}" == "all" ]]; then
        if [[ "$action" == "delete" ]]; then
            if ! $skip_prompt; then
                if [[ ! -t 0 ]]; then
                    echo -e "${RED}[ERROR]${NC} Destructive action '${action} all' requires confirmation, but input is not a terminal. Use -y / --yes to force."
                    return 1
                fi
                echo -e "\n${RED}${BOLD}  [WARNING] You are about to run '${action}' on ALL apps listed above!${NC}"
                read -r -p "  Type 'yes' to proceed: " response
                if [[ "$response" != "yes" ]]; then
                    echo -e "${CYAN}  Action cancelled.${NC}"
                    return 1
                fi
            fi
        fi
    fi

    return 0
}

# ── Entry point ───────────────────────────────────────────────────────────────
# 1. Multicall logic (detect if called as start, stop, etc.)
COMMAND_NAME="$(basename "$0")"
SUPPORTED_ACTIONS=("start" "stop" "restart" "recreate" "force-recreate" "frec" "delete" "cleanup" "pause" "unpause" "update" "status")

if [[ " ${SUPPORTED_ACTIONS[*]} " =~ \ ${COMMAND_NAME}\  ]]; then
    set -- "$COMMAND_NAME" "$@"
fi

# 2. Universal Install, Config, Uninstall & Self-Update logic
if [[ "${1:-}" == "install" || "${1:-}" == "config" || "${1:-}" == "uninstall" || "${1:-}" == "self-update" ]]; then
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}[ERROR]${NC} This command must be run with sudo."
        exit 1
    fi
    
    if [[ "${1:-}" == "install" && "${2:-}" == "--refresh" ]]; then
        # Symlink the script instead of copying to ensure edits are globally reflected immediately
        if [[ "$(realpath "$0" 2>/dev/null)" != "/usr/local/bin/docker-app-manager" && -f "$0" ]]; then
            ln -sf "$(realpath "$0")" "/usr/local/bin/docker-app-manager"
            chmod 755 "/usr/local/bin/docker-app-manager"
        fi
        if [[ -f "$CONFIG_FILE" ]]; then
            # shellcheck source=/dev/null
            source "$CONFIG_FILE"
            declare -p SEARCH_DIRS &>/dev/null || SEARCH_DIRS=()
            declare -p EXCLUDE_DIRS &>/dev/null || EXCLUDE_DIRS=()
        fi
        CMD_PREFIX="${CUSTOM_CMD_NAME:-}"
        # Remove old raw links just in case
        for act in "${SUPPORTED_ACTIONS[@]}"; do
            if [[ -L "/usr/local/bin/$act" && "$(readlink "/usr/local/bin/$act")" == "/usr/local/bin/docker-app-manager" ]]; then
                rm -f "/usr/local/bin/$act"
            fi
        done
        if [[ -z "$CMD_PREFIX" ]]; then
            for cmd in "${SUPPORTED_ACTIONS[@]}"; do
                ln -sf "/usr/local/bin/docker-app-manager" "/usr/local/bin/$cmd"
            done
        else
            ln -sf "/usr/local/bin/docker-app-manager" "/usr/local/bin/$CMD_PREFIX"
        fi
        echo -e "${GREEN}✔ Configuration refreshed successfully.${NC}"
        exit 0
    fi

    if [[ "$1" == "self-update" ]]; then
        if [[ -z "$UPDATE_URL" ]]; then
            echo -e "${RED}[ERROR]${NC} UPDATE_URL is not set inside the script!"
            echo -e "Please edit the script and set UPDATE_URL to your script's raw hosted URL (e.g., GitHub raw link)."
            exit 1
        fi
        if [[ "$UPDATE_URL" != https://* ]]; then
            echo -e "${RED}[ERROR]${NC} UPDATE_URL must use https://."
            exit 1
        fi
        echo -e "${YELLOW}Fetching latest version from: ${UPDATE_URL}${NC}"
        
        tmp_script="$(mktemp /tmp/docker-app-manager-XXXXXX.tmp)"
        if curl -fsSLo "$tmp_script" "$UPDATE_URL"; then
            if ! head -n 1 "$tmp_script" | grep -q "^#!"; then
                echo -e "${RED}[ERROR]${NC} Downloaded file does not appear to be a valid script. Update aborted."
                rm -f "$tmp_script"
                exit 1
            fi
            if ! bash -n "$tmp_script"; then
                echo -e "${RED}[ERROR]${NC} Downloaded script failed syntax check. Update aborted."
                rm -f "$tmp_script"
                exit 1
            fi
            
            dl_sha="$(sha256sum "$tmp_script" | awk '{print $1}')"
            echo -e "${CYAN}Downloaded SHA-256: ${dl_sha}${NC}"
            
            if [[ -n "${UPDATE_SHA256:-}" ]]; then
                if [[ "$dl_sha" != "$UPDATE_SHA256" ]]; then
                    echo -e "${RED}[ERROR]${NC} Checksum mismatch! Expected ${UPDATE_SHA256} but got ${dl_sha}."
                    rm -f "$tmp_script"
                    exit 1
                fi
            fi

            chmod 755 "$tmp_script"
            mv "$tmp_script" "/usr/local/bin/docker-app-manager"
            echo -e "${GREEN}✔ Successfully updated to the latest version!${NC}"
            
            if [[ -f "$CONFIG_FILE" ]]; then
                echo -e "${YELLOW}Refreshing configuration...${NC}"
                if ! bash "/usr/local/bin/docker-app-manager" install --refresh; then
                    echo -e "${RED}[ERROR]${NC} Failed to refresh configuration."
                fi
            fi
            exit 0
        else
            echo -e "${RED}[ERROR]${NC} Failed to download update."
            rm -f "$tmp_script"
            exit 1
        fi
    fi

    if [[ "$1" == "uninstall" ]]; then
        echo -e "${YELLOW}Uninstalling Docker Apps Lifecycle Manager...${NC}"
        
        # 1. Remove symlinks
        if [[ -z "${CUSTOM_CMD_NAME:-}" ]]; then
            for cmd in "${SUPPORTED_ACTIONS[@]}"; do
                if [[ -L "/usr/local/bin/$cmd" && "$(readlink "/usr/local/bin/$cmd")" == "/usr/local/bin/docker-app-manager" ]]; then
                    rm -f "/usr/local/bin/$cmd"
                    echo -e "  ${RED}✔ Removed command:${NC} $cmd"
                fi
            done
        else
            if [[ -L "/usr/local/bin/${CUSTOM_CMD_NAME}" ]]; then
                rm -f "/usr/local/bin/${CUSTOM_CMD_NAME}"
                echo -e "  ${RED}✔ Removed command:${NC} ${CUSTOM_CMD_NAME}"
            fi
        fi

        # 2. Remove the main script binary
        if [[ -f "/usr/local/bin/docker-app-manager" ]]; then
            rm -f "/usr/local/bin/docker-app-manager"
            echo -e "  ${RED}✔ Removed core script:${NC} /usr/local/bin/docker-app-manager"
        fi

        # 3. Remove the configuration file
        if [[ -f "$CONFIG_FILE" ]]; then
            rm -f "$CONFIG_FILE"
            echo -e "  ${RED}✔ Removed configuration:${NC} $CONFIG_FILE"
        fi

        echo -e "\n${BOLD}Success! Uninstallation Complete.${NC}"
        exit 0
    fi

    print_header
    if [[ "$1" == "install" ]]; then
        echo -e "${CYAN}Starting Universal Installation & Setup...${NC}\n"
    else
        echo -e "${CYAN}Updating Configuration...${NC}\n"
    fi
    
    # Read from terminal explicitly
    exec < /dev/tty

    skip_config=false
    if [[ "$1" == "install" && -f "$CONFIG_FILE" ]]; then
        echo -e "${GREEN}Existing configuration found at ${CONFIG_FILE}.${NC}"
        read -r -p "Do you want to just update the script and keep your existing settings? (Y/n) > " update_only
        if [[ -z "$update_only" || "$update_only" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            skip_config=true
            # source the config to get the existing values
            # shellcheck source=/dev/null
            source "$CONFIG_FILE"
            declare -p SEARCH_DIRS &>/dev/null || SEARCH_DIRS=()
            declare -p EXCLUDE_DIRS &>/dev/null || EXCLUDE_DIRS=()
            input_dirs="${SEARCH_DIRS[*]:-}"
            input_excludes="${EXCLUDE_DIRS[*]:-}"
            input_cmd_name="${CUSTOM_CMD_NAME:-}"
        fi
        echo
    fi

    if ! $skip_config; then
        if [[ -f "$CONFIG_FILE" ]]; then
            # shellcheck source=/dev/null
            source "$CONFIG_FILE"
            declare -p SEARCH_DIRS &>/dev/null || SEARCH_DIRS=()
            declare -p EXCLUDE_DIRS &>/dev/null || EXCLUDE_DIRS=()
        fi
        
        real_user_home="$HOME"
        if [[ -n "${SUDO_USER:-}" ]]; then
            real_user_home="$(getent passwd "$SUDO_USER" | cut -d: -f6 2>/dev/null)"
            real_user_home="${real_user_home:-$HOME}"
        fi
        default_dirs="/opt/stacks /opt/projects ${real_user_home}/apps ${real_user_home}/stacks"
        existing_dirs="${SEARCH_DIRS[*]:-$default_dirs}"
        
        echo -e "${BOLD}Step 1: Configuration${NC}"
        while true; do
            echo -e "Where are your Docker Compose apps located?"
            echo -e "Enter full paths separated by spaces (e.g., /opt/stacks /home/user/apps)"
            echo -e "(Default: ${existing_dirs})"
            read -r -p "> " input_dirs
            
            if [[ -z "$(echo -e "${input_dirs}" | tr -d '[:space:]')" ]]; then
                input_dirs="$existing_dirs"
            fi
            
            # Check for spaces in paths and existence
            invalid=false
            checked_dirs=""
            for d in $input_dirs; do
                if [[ "$d" =~ [[:space:]] ]]; then
                    echo -e "${RED}[ERROR]${NC} Directory paths cannot contain spaces: '${d}'"
                    invalid=true
                    break
                fi
                if [[ ! -d "$d" ]]; then
                    echo -e "${YELLOW}[WARN]${NC} Directory does not exist: '${d}'"
                    read -r -p "  Keep it anyway? [y/N] " keep_dir
                    if [[ ! "$keep_dir" =~ ^([yY][eE][sS]|[yY])$ ]]; then
                        invalid=true
                        break
                    fi
                fi
                checked_dirs="$checked_dirs $d"
            done
            if ! $invalid; then
                input_dirs="$checked_dirs"
                break
            fi
        done
        
        existing_excludes="${EXCLUDE_DIRS[*]:-}"
        echo -e "\n${BOLD}Are there any folder names you want to ALWAYS ignore? (optional)${NC}"
        echo -e "Enter folder names separated by spaces (type 'none' to clear, or press enter to skip)"
        if [[ -n "$existing_excludes" ]]; then
            echo -e "(Default: ${existing_excludes})"
        fi
        read -r -p "> " input_excludes
        if [[ -z "$(echo -e "${input_excludes}" | tr -d '[:space:]')" && -n "$existing_excludes" ]]; then
            input_excludes="$existing_excludes"
        elif [[ "${input_excludes,,}" == "none" ]]; then
            input_excludes=""
        fi

        EXISTING_CMD="${CUSTOM_CMD_NAME:-}"
        while true; do
            echo -e "\n${BOLD}Step 2: Custom Command Name${NC}"
            echo -e "What command name would you like to use to run this script globally?"
            if [[ -n "$EXISTING_CMD" ]]; then
                echo -e "(Leave blank to keep '${EXISTING_CMD}'. Enter 'none' to use raw commands like 'start'/'stop')"
            else
                echo -e "(Leave blank to use the default 'dkr'. Enter 'none' to use raw commands like 'start'/'stop')"
            fi
            read -r -p "> " input_cmd_name
            
            input_cmd_name="$(echo -e "${input_cmd_name}" | tr -d '[:space:]')"
            
            if [[ "$input_cmd_name" == "none" ]]; then
                input_cmd_name=""
            elif [[ -z "$input_cmd_name" && -n "$EXISTING_CMD" ]]; then
                input_cmd_name="$EXISTING_CMD"
            elif [[ -z "$input_cmd_name" ]]; then
                input_cmd_name="dkr"
            fi

            if [[ -z "$input_cmd_name" ]]; then
                echo -e "\n${YELLOW}[CHECKING CONFLICTS] Scanning system for raw command conflicts...${NC}"
                conflict_found=false
                for act in "${SUPPORTED_ACTIONS[@]}"; do
                    if command -v "$act" >/dev/null 2>&1; then
                        cmd_path="$(command -v "$act")"
                        real_path="$(realpath "$cmd_path" 2>/dev/null || echo "$cmd_path")"
                        if [[ "$real_path" != "/usr/local/bin/docker-app-manager" ]]; then
                            echo -e "  ${RED}✘ Conflict detected:${NC} '${act}' is already in use by: ${cmd_path}"
                            conflict_found=true
                        fi
                    fi
                done
                
                if $conflict_found; then
                    echo -e "\n${RED}[ERROR] You cannot use raw commands because conflicts were found!${NC}"
                    echo -e "You MUST enter a custom command name to avoid breaking your system/apps."
                    continue
                else
                    echo -e "\n${YELLOW}[WARNING] No immediate conflicts found for raw commands.${NC}"
                    echo -e "However, using generic commands (start, stop, etc.) might cause conflicts with future apps or system updates."
                    read -r -p "Are you sure you want to proceed without a custom command name? [y/N] " confirm_raw
                    if [[ ! "$confirm_raw" =~ ^([yY][eE][sS]|[yY])$ ]]; then
                        continue
                    fi
                fi
            else
                if command -v "$input_cmd_name" >/dev/null 2>&1; then
                    cmd_path="$(command -v "$input_cmd_name")"
                    real_path="$(realpath "$cmd_path" 2>/dev/null || echo "$cmd_path")"
                    if [[ "$real_path" != "/usr/local/bin/docker-app-manager" ]]; then
                        echo -e "\n${RED}[ERROR] Conflict detected:${NC} '${input_cmd_name}' is already in use by: ${cmd_path}"
                        echo -e "Please choose a different command name."
                        continue
                    fi
                fi
            fi
            break
        done

        existing_allow_custom="${ALLOW_CUSTOM_UPDATE_SCRIPTS:-false}"
        echo -e "\n${BOLD}Step 3: Update Settings${NC}"
        echo -e "Allow custom update*.sh scripts to run automatically during updates? [y/N/true/false]"
        echo -e "(Default: ${existing_allow_custom})"
        read -r -p "> " input_allow_custom
        if [[ -z "$input_allow_custom" ]]; then
            input_allow_custom="$existing_allow_custom"
        elif [[ "$input_allow_custom" =~ ^([yY][eE][sS]|[yY]|true|TRUE)$ ]]; then
            input_allow_custom="true"
        else
            input_allow_custom="false"
        fi

        existing_sha="${UPDATE_SHA256:-}"
        echo -e "\nSelf-Update SHA-256 (optional, for verification):"
        if [[ -n "$existing_sha" ]]; then
            echo -e "(Default: ${existing_sha})"
        fi
        read -r -p "> " input_sha
        if [[ -z "$input_sha" && -n "$existing_sha" ]]; then
            input_sha="$existing_sha"
        fi

        existing_url="${UPDATE_URL:-}"
        echo -e "\nSelf-Update URL (optional, e.g. https://...):"
        if [[ -n "$existing_url" ]]; then
            echo -e "(Default: ${existing_url})"
        fi
        read -r -p "> " input_url
        if [[ -z "$input_url" && -n "$existing_url" ]]; then
            input_url="$existing_url"
        fi

        CONF_PATH="/etc/docker-app-manager.conf"
        echo -e "\n${YELLOW}Saving configuration to $CONF_PATH...${NC}"
        
        format_array() {
            for item in $1; do printf '"%s" ' "$item"; done
        }
        
        if [[ -f "$CONF_PATH" ]]; then
            grep -vE '^(SEARCH_DIRS|EXCLUDE_DIRS|CUSTOM_CMD_NAME|ALLOW_CUSTOM_UPDATE_SCRIPTS|UPDATE_SHA256|UPDATE_URL)=' "$CONF_PATH" > "${CONF_PATH}.tmp" || true
        else
            echo "# Auto-generated by Docker Apps Lifecycle Manager" > "${CONF_PATH}.tmp"
        fi
        
        {
            echo "SEARCH_DIRS=($(format_array "$input_dirs"))"
            echo "EXCLUDE_DIRS=($(format_array "$input_excludes"))"
            echo "CUSTOM_CMD_NAME=\"$input_cmd_name\""
            echo "ALLOW_CUSTOM_UPDATE_SCRIPTS=\"$input_allow_custom\""
            if [[ -n "$input_sha" ]]; then
                echo "UPDATE_SHA256=\"$input_sha\""
            fi
            if [[ -n "$input_url" ]]; then
                echo "UPDATE_URL=\"$input_url\""
            fi
        } >> "${CONF_PATH}.tmp"
        mv "${CONF_PATH}.tmp" "$CONF_PATH"

        # Remove old symlink if we are changing the mode
        if [[ -n "${CUSTOM_CMD_NAME+x}" && "${CUSTOM_CMD_NAME:-}" != "$input_cmd_name" ]]; then
            if [[ -z "${CUSTOM_CMD_NAME:-}" ]]; then
                # Old was raw commands, remove them
                for act in "${SUPPORTED_ACTIONS[@]}"; do
                    if [[ -L "/usr/local/bin/$act" && "$(readlink "/usr/local/bin/$act")" == "/usr/local/bin/docker-app-manager" ]]; then
                        rm -f "/usr/local/bin/$act"
                    fi
                done
                echo -e "  ${YELLOW}Removed old raw commands.${NC}"
            else
                # Old was custom command name
                if [[ -L "/usr/local/bin/${CUSTOM_CMD_NAME}" ]]; then
                    rm -f "/usr/local/bin/${CUSTOM_CMD_NAME}"
                    echo -e "  ${YELLOW}Removed old command:${NC} ${CUSTOM_CMD_NAME}"
                fi
            fi
        fi
    fi # End of ! $skip_config

    if [[ "$1" == "install" ]]; then
        echo -e "${YELLOW}Installing core system files...${NC}"
        
        # Symlink the script to the system bin to enforce DRY
        if [[ "$(realpath "$0" 2>/dev/null)" != "/usr/local/bin/docker-app-manager" && -f "$0" ]]; then
            ln -sf "$(realpath "$0")" "/usr/local/bin/docker-app-manager"
            chmod 755 "/usr/local/bin/docker-app-manager"
        fi
    fi
        
    if [[ -z "$input_cmd_name" ]]; then
        for cmd in "${SUPPORTED_ACTIONS[@]}"; do
            ln -sf "/usr/local/bin/docker-app-manager" "/usr/local/bin/$cmd"
            if [[ "$cmd" == "frec" ]]; then
                echo -e "  ${GREEN}✔ Created universal command:${NC} $cmd (alias for force-recreate)"
            else
                echo -e "  ${GREEN}✔ Created universal command:${NC} $cmd"
            fi
        done
    else
        ln -sf "/usr/local/bin/docker-app-manager" "/usr/local/bin/$input_cmd_name"
        echo -e "  ${GREEN}✔ Created universal command:${NC} $input_cmd_name"
    fi
    
    if [[ "$1" == "install" ]]; then
        echo -e "\n${BOLD}Success! Installation Complete.${NC}"
        if [[ -z "$input_cmd_name" ]]; then
            echo -e "You can now type 'start', 'update', 'cleanup', etc. directly from anywhere."
        else
            echo -e "You can now type '${input_cmd_name} start', '${input_cmd_name} update', '${input_cmd_name} cleanup', etc. directly from anywhere."
        fi
    else
        echo -e "\n${BOLD}Success! Configuration Updated.${NC}"
        if [[ -n "$input_cmd_name" ]]; then
            echo -e "You can now use '${input_cmd_name}' as your command."
        fi
    fi
    exit 0
fi

print_header

if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

for arg in "$@"; do
    if [[ "$arg" == "--help" || "$arg" == "-h" || "$arg" == "help" ]]; then
        usage
        exit 0
    fi
done

ACTION="$1"
shift

# Normalize frec to force-recreate
if [[ "$ACTION" == "frec" ]]; then
    ACTION="force-recreate"
fi

case "$ACTION" in
    (start|stop|restart|recreate|force-recreate|delete|pause|unpause|update|status|logs|debug)
        if ! docker_ready; then
            exit 1
        fi

        if ! parse_target_apps "$ACTION" "$@"; then
            echo
            echo -e "${BOLD}Available apps for action '${ACTION}':${NC}"
            fallback_mode="compose"
            [[ "$ACTION" == "update" ]] && fallback_mode="update"
            list_available_apps "$fallback_mode" "  "
            echo
            exit 1
        fi

        if [[ "$ACTION" == "status" ]]; then
            echo -e "${CYAN}Gathering status for ${#APPS_TO_PROCESS[@]} app(s)...${NC}"
            all_containers=()
            
            declare -A target_apps
            for app in "${APPS_TO_PROCESS[@]}"; do
                target_apps["$app"]=1
                (( TOTAL++ )) || true
            done
            
            declare -A found_dirs
            while IFS='|' read -r cid project wdir; do
                [[ -z "$cid" ]] && continue
                app_name=""
                if [[ -n "$project" ]] && [[ -n "${target_apps["$project"]:-}" ]]; then
                    app_name="$project"
                elif [[ -n "$wdir" ]]; then
                    bname=$(basename "$wdir")
                    if [[ -n "${target_apps["$bname"]:-}" ]]; then
                        app_name="$bname"
                    fi
                fi
                if [[ -n "$app_name" ]]; then
                    all_containers+=("$cid")
                    if [[ -n "$wdir" && -z "${found_dirs["$app_name"]:-}" ]]; then
                        found_dirs["$app_name"]="$wdir"
                    fi
                fi
            done < <(docker ps -a --filter "label=com.docker.compose.project" --format '{{.ID}}|{{.Label "com.docker.compose.project"}}|{{.Label "com.docker.compose.project.working_dir"}}' 2>/dev/null)
            
            for app in "${APPS_TO_PROCESS[@]}"; do
                if is_excluded "$app"; then
                    (( SKIPPED++ )) || true
                    SKIPPED_APPS+=("$app")
                    continue
                fi
                
                dir="${found_dirs["$app"]:-}"
                if [[ -z "$dir" ]]; then
                    dir="$(find_app_dir "$app")"
                fi
                
                if [[ "$dir" == "DUPLICATE" ]]; then
                    echo -e "${RED}  [ERROR]${NC} Multiple matching apps found for '${app}'"
                    (( FAILED++ )) || true
                    FAILED_APPS+=("$app")
                elif [[ -z "$dir" ]]; then
                    echo -e "${RED}  [ERROR]${NC} App '${app}' not found in any search directory or missing compose file."
                    (( FAILED++ )) || true
                    FAILED_APPS+=("$app")
                else
                    (( SUCCESS++ )) || true
                    SUCCESS_APPS+=("$app")
                fi
            done

            echo
            if [[ ${#all_containers[@]} -eq 0 ]]; then
                echo -e "${YELLOW}No containers found for the requested apps.${NC}"
            else
                filter_args=()
                for cid in "${all_containers[@]}"; do
                    filter_args+=("-f" "id=$cid")
                done
                echo -e "${BLUE}  [1/2]${NC} Current service status:"
                # Format exactly like docker compose ps, but inject the App name for absolute clarity!
                docker ps -a "${filter_args[@]}" --format 'table {{.Names}}\t{{.Label "com.docker.compose.project"}}\t{{.Label "com.docker.compose.service"}}\t{{.Image}}\t{{.RunningFor}}\t{{.Status}}\t{{.Ports}}' | sed '1s/com.docker.compose.project/APP/' | sed '1s/com.docker.compose.service/SERVICE/'
                echo
                echo -e "${BLUE}  [2/2]${NC} Real-time resource usage:"
                docker stats --no-stream "${all_containers[@]}" || true
            fi
        else
            for app in "${APPS_TO_PROCESS[@]}"; do
                process_app "$ACTION" "$app" || true
            done
        fi

        print_summary "$ACTION"

        # 'delete' and 'update' additionally perform a global dangling-only cleanup.
        if [[ "$ACTION" == "delete" || "$ACTION" == "update" ]]; then
            # Protect against global vol/net destruction when chained
            safe_cleanup_modes=()
            for m in "${CLEANUP_MODES[@]}"; do
                if [[ "$m" == "buildx" ]]; then
                    safe_cleanup_modes+=("buildx")
                fi
            done
            if [[ ${#safe_cleanup_modes[@]} -gt 0 ]]; then
                cleanup_dangling_resources "${safe_cleanup_modes[@]}"
            else
                cleanup_dangling_resources
            fi
        fi

        [[ $FAILED -gt 0 ]] && exit 1
        exit 0
        ;;

    cleanup)
        cleanup_modes=()
        ASSUME_YES=false
        
        if [[ $# -eq 0 ]]; then
            cleanup_modes=("basic")
        else
            has_all=false
            has_others=false
            for arg in "$@"; do
                if [[ "$arg" == "-y" || "$arg" == "--yes" ]]; then
                    ASSUME_YES=true
                elif [[ "$arg" == "net" || "$arg" == "buildx" || "$arg" == "vol" || "$arg" == "img" ]]; then
                    cleanup_modes+=("$arg")
                    has_others=true
                elif [[ "$arg" == "all" ]]; then
                    has_all=true
                else
                    echo -e "${RED}[ERROR]${NC} Unknown cleanup argument '${arg}'."
                    echo -e "        Use: ${BOLD}cleanup [all] [-y]${NC} OR ${BOLD}cleanup [net] [buildx] [vol] [img] [-y]${NC}"
                    echo
                    usage
                    exit 1
                fi
            done
            if $has_all && $has_others; then
                echo -e "${RED}[ERROR]${NC} 'all' cannot be combined with other cleanup targets."
                echo -e "        Use: ${BOLD}cleanup [all] [-y]${NC} OR ${BOLD}cleanup [net] [buildx] [vol] [img] [-y]${NC}"
                echo
                usage
                exit 1
            fi
            if $has_all; then
                cleanup_modes=("all")
            elif [[ ${#cleanup_modes[@]} -eq 0 ]]; then
                cleanup_modes=("basic")
            fi
        fi
        
        if ! docker_ready; then
            exit 1
        fi
        cleanup_dangling_resources "${cleanup_modes[@]}"
        exit 0
        ;;

    help|-h|--help)
        usage
        exit 0
        ;;

    *)
        echo -e "${RED}[ERROR]${NC} Unknown action '${ACTION}'."
        usage
        exit 1
        ;;
esac
