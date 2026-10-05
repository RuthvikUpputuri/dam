#!/usr/bin/env bash
# shellcheck shell=bash
#VERSION="1.2.0"
#
# =============================================================================
# @title        Docker App Manager (DAM)
# @description  A powerful, centralized lifecycle manager for Docker Compose applications.
#               Built for sysadmins, hobbyists, and self-hosters to easily perform 
#               bulk operations (start, stop, update, clean) across multiple apps.
#
# @author       Ruthvik Upputuri
# @repository   https://gh.upputuri.in/dam
# @license      MIT License
# @created      September 2026
# =============================================================================
#
#Always run shellcheck after making changes and before committing.
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
#   <action> all except <app3> <app4>    - All apps except specified apps
#   <action> homarr                          - Single specified app
#   <action> n8n langflow <app-name>            - Multiple specified apps
#
# Optional: Append 'with vol', 'with net', etc. to run extended cleanup on delete.
# Example:  delete all except <app-name> with vol net
#
# Note: App names and paths must not contain spaces.
# Scope and limitations: This tool manages one compose project per folder using the standard filenames.
# It does not support Swarm, Kubernetes, or folders that need several compose files selected manually.
#
# Examples:
#   start all except <app-name>
#   restart homarr n8n
#   recreate all except <app-name>
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
UPDATE_URL="https://gh.upputuri.in/dam.sh"
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
COMPOSE_FILENAMES=("compose.yaml" "compose.yml" "docker-compose.yaml" "docker-compose.yml")
MAX_SEARCH_DEPTH="${MAX_SEARCH_DEPTH:-5}"

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

declare -g APP_DIR_CACHE_BUILT=false

build_app_dir_cache() {
    local valid_search_dirs=()
    declare -gA APP_DIR_PRIMARY=()
    local valid_matches=()
    for d in "${SEARCH_DIRS[@]}"; do
        [[ -d "$d" ]] && valid_search_dirs+=("$d")
    done
    [[ ${#valid_search_dirs[@]} -eq 0 ]] && return 0

    local LIST_PRUNE_ARGS=()
    for excl in "${EXCLUDE_DIRS[@]}"; do
        LIST_PRUNE_ARGS+=( -name "$excl" -prune -print0 -o )
    done

    while IFS= read -r -d '' match; do
        local has_compose=false
        for cf in "${COMPOSE_FILENAMES[@]}"; do
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
            valid_matches+=("$match")
            local folder_name
            folder_name="$(basename "$match")"
            
            local existing="${APP_DIR_CACHE["$folder_name"]:-}"
            if [[ -z "$existing" ]]; then
                APP_DIR_CACHE["$folder_name"]="$match"
                APP_DIR_PRIMARY["$folder_name"]=true
            elif [[ "$existing" != "$match" && "$existing" != *"|$match"* ]]; then
                if [[ "$existing" == "DUPLICATE:"* ]]; then
                    APP_DIR_CACHE["$folder_name"]="${existing}|${match}"
                else
                    APP_DIR_CACHE["$folder_name"]="DUPLICATE:${existing}|${match}"
                fi
                APP_DIR_PRIMARY["$folder_name"]=true
            fi
        fi
    done < <(find "${valid_search_dirs[@]}" -mindepth 1 -maxdepth "${MAX_SEARCH_DEPTH}" "${LIST_PRUNE_ARGS[@]}" -type d -print0 2>/dev/null)
    
    # Pass 2: map effective names as secondary aliases
    for match in "${valid_matches[@]}"; do
        local effective_name
        effective_name="$(get_effective_app_name "$match")"
        
        # Don't map it if the effective name is exactly the folder name (already mapped in pass 1)
        [[ "$effective_name" == "$(basename "$match")" ]] && continue
        
        local existing="${APP_DIR_CACHE["$effective_name"]:-}"
        if [[ -z "$existing" ]]; then
            APP_DIR_CACHE["$effective_name"]="$match"
        elif [[ "$existing" != "$match" && "$existing" != *"|$match"* ]]; then
            # Conflict. Let primary folder names win.
            if [[ "${APP_DIR_PRIMARY["$effective_name"]:-false}" == "true" ]]; then
                continue
            else
                if [[ "$existing" == "DUPLICATE:"* ]]; then
                    APP_DIR_CACHE["$effective_name"]="${existing}|${match}"
                else
                    APP_DIR_CACHE["$effective_name"]="DUPLICATE:${existing}|${match}"
                fi
            fi
        fi
    done
    
    APP_DIR_CACHE_BUILT=true
}

find_app_dir() {
    local target="$1"
    if [[ "$target" =~ [[:space:]] ]]; then
        echo -e "${RED}[ERROR]${NC} App names with spaces are not supported: '${target}'" >&2
        return 1
    fi
    
    if [[ "${APP_DIR_CACHE_BUILT:-false}" != "true" ]]; then
        build_app_dir_cache
    fi
    
    local cached_result="${APP_DIR_CACHE["$target"]:-NOT_FOUND}"
    
    # Fallback to case-insensitive search if exact match fails
    if [[ "$cached_result" == "NOT_FOUND" ]]; then
        local target_lower="${target,,}"
        local ci_matches=()
        for key in "${!APP_DIR_CACHE[@]}"; do
            if [[ "${key,,}" == "$target_lower" ]]; then
                local mapped_dir="${APP_DIR_CACHE["$key"]}"
                # If the key itself is a duplicate, we need to extract all its dirs
                if [[ "$mapped_dir" == "DUPLICATE:"* ]]; then
                    local dupes="${mapped_dir#DUPLICATE:}"
                    IFS='|' read -ra dupe_array <<< "$dupes"
                    for match in "${dupe_array[@]}"; do
                        [[ -n "$match" ]] && ci_matches+=("$match")
                    done
                else
                    ci_matches+=("$mapped_dir")
                fi
            fi
        done
        
        # Deduplicate ci_matches
        if [[ ${#ci_matches[@]} -gt 0 ]]; then
            local unique_matches=()
            for m in "${ci_matches[@]}"; do
                local found_unique=false
                for u in "${unique_matches[@]}"; do
                    if [[ "$m" == "$u" ]]; then
                        found_unique=true
                        break
                    fi
                done
                if ! $found_unique; then
                    unique_matches+=("$m")
                fi
            done
            
            if [[ ${#unique_matches[@]} -eq 1 ]]; then
                cached_result="${unique_matches[0]}"
            elif [[ ${#unique_matches[@]} -gt 1 ]]; then
                local matches_str=""
                for m in "${unique_matches[@]}"; do
                    matches_str+="${m}|"
                done
                cached_result="DUPLICATE:${matches_str}"
            fi
        fi
    fi
    
    if [[ "$cached_result" == "DUPLICATE:"* ]]; then
        echo -e "${RED}[ERROR]${NC} Multiple matching apps found for '${target}':" >&2
        local matches="${cached_result#DUPLICATE:}"
        IFS='|' read -ra match_array <<< "$matches"
        for match in "${match_array[@]}"; do
            [[ -n "$match" ]] && echo -e "  - ${match}" >&2
        done
        FOUND_APP_DIR="DUPLICATE:$matches"
        return 1
    elif [[ "$cached_result" == "NOT_FOUND" ]]; then
        FOUND_APP_DIR=""
        return 0
    else
        FOUND_APP_DIR="$cached_result"
        return 0
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
    local excl
    for excl in "${EXCLUDE_DIRS[@]}"; do
        [[ "$folder" == "$excl" ]] && return 0
    done
    return 1
}

_DC_CMD=()

dc() {
    if [[ ${#_DC_CMD[@]} -eq 0 ]]; then
        if docker compose version &>/dev/null; then
            _DC_CMD=(docker compose)
        elif docker-compose version &>/dev/null; then
            _DC_CMD=(docker-compose)
        else
            echo -e "${RED}[ERROR]${NC} Neither 'docker compose' nor 'docker-compose' is available."
            return 1
        fi
    fi
    "${_DC_CMD[@]}" ${DC_FILE_ARGS[@]+"${DC_FILE_ARGS[@]}"} "$@"
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
    for cf in "${COMPOSE_FILENAMES[@]}"; do
        [[ -f "$dir/$cf" ]] && return 0
    done
    return 1
}

get_app_compose_file() {
    local dir="$1"
    for cf in "${COMPOSE_FILENAMES[@]}"; do
        if [[ -f "$dir/$cf" ]]; then
            echo "$cf"
            return 0
        fi
    done
    for f in "$dir"/update*.sh; do
        if [[ -f "$f" ]]; then
            basename "$f"
            return 0
        fi
    done
    echo "-"
}

has_update_files() {
    local dir="$1"
    has_compose_files "$dir" && return 0
    for f in "$dir"/update*.sh; do
        [[ -f "$f" ]] && return 0
    done
    return 1
}

get_effective_app_name() {
    local dir="$1"
    local cfile
    cfile="$(get_app_compose_file "$dir")"
    
    local name=""
    
    if [[ -f "$dir/.env" ]]; then
        name="$(awk -F '=' '/^[[:space:]]*COMPOSE_PROJECT_NAME[[:space:]]*=/ {
            sub(/^[[:space:]]*COMPOSE_PROJECT_NAME[[:space:]]*=[[:space:]]*/, "");
            gsub(/["'"'"']/, "");
            print $1;
            exit;
        }' "$dir/.env")"
    fi
    
    if [[ -z "$name" && "$cfile" != "-" && -f "$dir/$cfile" ]]; then
        name="$(awk '/^name:[[:space:]]*/ {
            sub(/^name:[[:space:]]*/, "");
            gsub(/["'"'"']/, "");
            print $1;
            exit;
        }' "$dir/$cfile")"
    fi
    
    if [[ -z "$name" ]]; then
        name="$(basename "$dir")"
    fi
    
    name="${name,,}"
    echo "${name//[^a-z0-9_-]/}"
}

resolve_compose_files() {
    local dir="$1"
    local folder="$2"
    local action="${3:-}"
    DC_FILE_ARGS=()
    local found_any_custom=false
    
    if [[ ${#CUSTOM_COMPOSE_FILES_RAW[@]} -gt 0 ]]; then
        local display_files=()
        for cf in "${CUSTOM_COMPOSE_FILES_RAW[@]}"; do
            local matched_file=""
            if [[ -f "$dir/$cf" ]]; then
                matched_file="$cf"
            else
                for ext in "" ".yaml" ".yml"; do
                    if [[ -f "$dir/${cf}${ext}" ]]; then
                        matched_file="${cf}${ext}"
                        break
                    elif [[ -f "$dir/compose.${cf}${ext}" ]]; then
                        matched_file="compose.${cf}${ext}"
                        break
                    elif [[ -f "$dir/docker-compose.${cf}${ext}" ]]; then
                        matched_file="docker-compose.${cf}${ext}"
                        break
                    fi
                done
            fi
            
            if [[ -n "$matched_file" ]]; then
                DC_FILE_ARGS+=("-f" "$matched_file")
                display_files+=("$matched_file")
                found_any_custom=true
                GLOBAL_USED_COMPOSE_FILES["$cf"]=1
            else
                echo -e "${YELLOW}  [WARN]${NC} Requested file '${cf}' not found for this app. Ignoring."
                GLOBAL_MISSING_COMPOSE_FILES["$cf"]+="${folder} "
            fi
        done
        
        if $found_any_custom; then
            echo -e "${CYAN}  [INFO]${NC} Compose files detected: ${display_files[*]}"
            return 0
        fi

        case "$action" in
            stop|recreate|force-recreate|delete)
                echo -e "${RED}  [ERROR]${NC} None of the requested compose files (${CUSTOM_COMPOSE_FILES_RAW[*]}) were found in '${folder}'. Refusing to fall back to default for '${action}'."
                return 1
                ;;
            *)
                echo -e "${CYAN}  [INFO]${NC} None of the requested compose files were found. Falling back to the default Compose file."
                return 0
                ;;
        esac
    fi

    local canon_file=""
    for cf in "${COMPOSE_FILENAMES[@]}"; do
        if [[ -f "$dir/$cf" ]]; then
            canon_file="$cf"
            break
        fi
    done
    if [[ -z "$canon_file" ]]; then
        echo -e "${RED}  [ERROR]${NC} No valid compose file (${COMPOSE_FILENAMES[*]}) found in '${folder}'."
        return 1
    fi
    echo -e "${CYAN}  [INFO]${NC} Compose file detected: ${canon_file}"
    return 0
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
            local folder_name
            folder_name="$(basename "$d")"
            local valid=false
            if [[ ${#explicit_apps[@]} -gt 0 ]]; then
                for e_app in "${explicit_apps[@]}"; do
                    if [[ "$e_app" == "$folder_name" ]]; then
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
            
            if is_excluded "$folder_name"; then
                excluded_apps+=("$folder_name")
            elif $valid; then
                apps+=("$folder_name")
            fi
        done < <(find "$sdir" -mindepth 1 -maxdepth "${MAX_SEARCH_DEPTH}" "${LIST_PRUNE_ARGS[@]}" -type d -print0 2>/dev/null | sort -z)

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

inventory_apps_table() {
    local valid_search_dirs=()
    for d in "${SEARCH_DIRS[@]}"; do
        [[ -d "$d" ]] && valid_search_dirs+=("$d")
    done
    [[ ${#valid_search_dirs[@]} -eq 0 ]] && return

    declare -A app_status
    declare -A app_status_by_wdir
    if docker info >/dev/null 2>&1; then
        while IFS='|' read -r project state wdir; do
            [[ -z "$project" ]] && continue
            if [[ "$state" == "running" ]]; then
                app_status["$project"]="running"
            elif [[ -z "${app_status["$project"]:-}" ]]; then
                app_status["$project"]="stopped"
            fi
            if [[ -n "$wdir" ]]; then
                if [[ "$state" == "running" ]]; then
                    app_status_by_wdir["$wdir"]="running"
                elif [[ -z "${app_status_by_wdir["$wdir"]:-}" ]]; then
                    app_status_by_wdir["$wdir"]="stopped"
                fi
            fi
        done < <(docker ps -a --filter "label=com.docker.compose.project" --format '{{.Label "com.docker.compose.project"}}|{{.State}}|{{.Label "com.docker.compose.project.working_dir"}}' 2>/dev/null)
    fi

    (
        echo "APP|PROJECT|LOCATION|COMPOSE|STATUS"
        for sdir in "${valid_search_dirs[@]}"; do
            local LIST_PRUNE_ARGS=()
            for excl in "${EXCLUDE_DIRS[@]}"; do
                LIST_PRUNE_ARGS+=( -name "$excl" -prune -print0 -o )
            done

            while IFS= read -r -d '' d; do
                local folder_name
                folder_name="$(basename "$d")"
                
                local cfile
                cfile="$(get_app_compose_file "$d")"

                if [[ "$cfile" == "-" ]] && ! is_excluded "$folder_name"; then
                    continue
                fi

                local eff_name
                eff_name="$(get_effective_app_name "$d")"
                
                local project_col="-"
                if [[ "$folder_name" != "$eff_name" ]]; then
                    project_col="$eff_name"
                fi

                local status="inactive"
                if is_excluded "$folder_name"; then
                    status="excluded"
                elif [[ -n "${app_status["$eff_name"]:-}" ]]; then
                    status="${app_status["$eff_name"]}"
                elif [[ -n "${app_status_by_wdir["$d"]:-}" ]]; then
                    status="${app_status_by_wdir["$d"]}"
                fi

                local display_path="$d"
                if [[ "$d" == "$HOME"* ]]; then
                    display_path="~${d#"$HOME"}"
                fi

                echo "$folder_name|$project_col|$display_path|$cfile|$status"
                
            done < <(find "$sdir" -mindepth 1 -maxdepth "${MAX_SEARCH_DEPTH}" "${LIST_PRUNE_ARGS[@]}" -type d -print0 2>/dev/null | sort -z)
        done
    ) | column -t -s '|' | awk 'NR==1{print; gsub(/./, "-"); print} NR>1'
}

print_app_level_details_table() {
    local apps=("$@")
    
    declare -A app_status
    declare -A app_status_by_wdir
    if docker info >/dev/null 2>&1; then
        while IFS='|' read -r project state wdir; do
            [[ -z "$project" ]] && continue
            if [[ "$state" == "running" ]]; then
                app_status["$project"]="running"
            elif [[ -z "${app_status["$project"]:-}" ]]; then
                app_status["$project"]="stopped"
            fi
            if [[ -n "$wdir" ]]; then
                if [[ "$state" == "running" ]]; then
                    app_status_by_wdir["$wdir"]="running"
                elif [[ -z "${app_status_by_wdir["$wdir"]:-}" ]]; then
                    app_status_by_wdir["$wdir"]="stopped"
                fi
            fi
        done < <(docker ps -a --filter "label=com.docker.compose.project" --format '{{.Label "com.docker.compose.project"}}|{{.State}}|{{.Label "com.docker.compose.project.working_dir"}}' 2>/dev/null)
    fi

    (
        echo "APP|PROJECT|PATH|COMPOSE FILE|OVERALL STATE"
        for app in "${apps[@]}"; do
            find_app_dir "$app" 2>/dev/null
            dir="$FOUND_APP_DIR"
            if [[ -z "$dir" || "$dir" == "DUPLICATE"* ]]; then
                continue
            fi
            
            local folder_name
            folder_name="$(basename "$dir")"
            
            local eff_name
            eff_name="$(get_effective_app_name "$dir")"
            
            local project_col="-"
            if [[ "$folder_name" != "$eff_name" ]]; then
                project_col="$eff_name"
            fi
            
            display_path="$dir"
            if [[ "$dir" == "$HOME"* ]]; then
                display_path="~${dir#"$HOME"}"
            fi
            cfile="$(get_app_compose_file "$dir")"
            
            state="inactive"
            if is_excluded "$folder_name"; then
                state="excluded"
            elif [[ -n "${app_status["$eff_name"]:-}" ]]; then
                state="${app_status["$eff_name"]}"
            elif [[ -n "${app_status_by_wdir["$dir"]:-}" ]]; then
                state="${app_status_by_wdir["$dir"]}"
            fi
            echo "$folder_name|$project_col|$display_path|$cfile|$state"
        done
    ) | column -t -s '|' | awk 'NR==1{print; gsub(/./, "-"); print} NR>1'
}

get_all_apps() {
    local mode="${1:-compose}"
    local apps=()
    local valid_search_dirs=()
    for d in "${SEARCH_DIRS[@]}"; do
        [[ -d "$d" ]] && valid_search_dirs+=("$d")
    done
    [[ ${#valid_search_dirs[@]} -eq 0 ]] && return

    local -A seen_apps=()
    while IFS= read -r -d '' d; do
        local folder_name
        folder_name="$(basename "$d")"
        is_excluded "$folder_name" && continue

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

        if [[ -z "${seen_apps["$folder_name"]:-}" ]]; then
            apps+=("$folder_name")
            seen_apps["$folder_name"]=1
        fi
    done < <(find "${valid_search_dirs[@]}" -mindepth 1 -maxdepth "${MAX_SEARCH_DEPTH}" "${FIND_PRUNE_ARGS[@]}" -type d -print0 2>/dev/null | sort -z)

    echo "${apps[@]}"
}

usage() {
    echo -e "${BOLD}Usage:${NC}"
    echo -e "  ${P_CMD}<action> all [using files...]                           - All apps"
    echo -e "  ${P_CMD}<action> all except <name> [name ...] [using files...]  - All apps except specified apps"
    echo -e "  ${P_CMD}<action> <name> [name ...] [using files...]             - One or more specific apps"
    echo -e "  ${P_CMD}list [all|name...]                                      - Detailed list of apps"
    echo -e "  ${P_CMD}get [app] [resource]                                    - Get specific raw data (cid, iid, vol, mnt, net, port, state)"
    echo -e "  ${P_CMD}cleanup [net|buildx|vol|img|all] [-y]                   - Clean dangling resources"
    echo
    echo -e "${BOLD}Examples:${NC}"
    echo -e "  ${P_CMD}start all except <app-name>"
    echo -e "  ${P_CMD}restart <app1> <app2>"
    echo -e "  ${P_CMD}update <app1> <app2> <app3>"
    echo -e "  ${P_CMD}delete <app-name>"
    echo -e "  ${P_CMD}cleanup vol"
    echo -e "  ${P_CMD}cleanup"
    echo
    echo -e "${BOLD}Actions:${NC}"
    echo -e "  start              Start app containers"
    echo -e "  stop               Stop app containers"
    echo -e "  kill               Force stop containers (SIGKILL)"
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
    echo -e "  list               View high-level inventory or detailed app info."
    echo -e "  get                Get specific raw container data for scripting."
    echo -e "                     resources: cid, iid, vol, mnt, net, port, state, health"
    echo -e "  logs               View app logs. Chain arguments like: last 100, live, since 30m, time, first 50"
    echo -e "  debug              [Coming Soon] Advanced app debugging."
    echo -e "  cleanup [net|buildx|vol|img|all] [-y]"
    echo -e "                     Clean dangling images (default)"
    echo -e "                     args: [net] includes unused networks, [buildx] includes cache, [vol] includes volumes, [all] includes everything"
    echo -e "                     (Tip: You can append 'with vol', 'with img', etc. directly to 'delete')"
    echo -e "                     (Accepts -y/--yes to skip confirmations)"
    echo -e "  Config options:    ALLOW_CUSTOM_UPDATE_SCRIPTS=true/false, UPDATE_SHA256=hash"
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
    echo -e "  sudo ./dam.sh install refresh   Refreshes the command symlinks non-interactively"
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
            echo -e "${YELLOW}  [build cache]${NC} Removing build cache (${cache})..."
            local out
            if out="$(docker buildx prune -a -f 2>&1)"; then
                # shellcheck disable=SC2001
                sed 's/^/                 /' <<< "$out"
            elif out="$(docker builder prune -a -f 2>&1)"; then
                # shellcheck disable=SC2001
                sed 's/^/                 /' <<< "$out"
            else
                echo -e "${RED}  [ERROR]${NC}       Build cache prune failed:\n$out" | sed 's/^/                 /'
            fi
        else
            echo -e "${CYAN}  [build cache]${NC} No build cache to remove."
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
    find_app_dir "$folder"
    dir="$FOUND_APP_DIR"

    if ! resolve_compose_files "$dir" "$folder" "$action"; then
        return 1
    fi

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
        kill)
            echo
            echo -e "${BLUE}  [1/2]${NC} Killing containers (SIGKILL)..."
            dc kill || { popd > /dev/null || true; return 1; }
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
    dc ps -a || true

    popd > /dev/null || true
    return 0
}

run_update_action_for_app() {
    local folder="$1"
    local dir
    local rc
    find_app_dir "$folder"
    rc=$?
    dir="$FOUND_APP_DIR"

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

    if ! resolve_compose_files "$dir" "$folder" "update"; then
        return 1
    fi
    
    pushd "$dir" > /dev/null || return 1

    local running_containers=()
    mapfile -t running_containers < <(dc ps -q 2>/dev/null || true)
    local was_running=false
    if [[ ${#running_containers[@]} -gt 0 ]]; then
        if docker inspect -f '{{.State.Running}}' "${running_containers[@]}" 2>/dev/null | grep -q "true"; then
            was_running=true
        fi
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
    dc ps -a || true

    popd > /dev/null || true
    return 0
}

run_logs_action_for_app() {
    local folder="$1"
    local dir
    find_app_dir "$folder"
    dir="$FOUND_APP_DIR"
    
    if [[ ! -d "$dir" ]]; then
        return 1
    fi

    if ! resolve_compose_files "$dir" "$folder" "logs"; then
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
    local rc=0
    if [[ -n "$head_lines" ]]; then
        (set +o pipefail; dc logs "${dc_args[@]}" | head -n "$head_lines")
        rc=$?
    else
        dc logs "${dc_args[@]}"
        rc=$?
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
    find_app_dir "$folder"
    rc=$?
    dir="$FOUND_APP_DIR"

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

    if is_excluded "$(basename "$dir")"; then
        echo -e "${YELLOW}  [SKIP]${NC} '${folder}' is excluded from operations."
        (( SKIPPED++ )) || true
        SKIPPED_APPS+=("$folder")
        return 0
    fi

    case "$action" in
        update)
            run_update_action_for_app "$folder" ;;
        logs)
            run_logs_action_for_app "$folder" ;;
        debug)
            run_debug_action_for_app "$folder" ;;
        start|stop|kill|restart|recreate|force-recreate|delete|pause|unpause)
            run_compose_action_for_app "$action" "$folder" ;;
        *)
            echo -e "${RED}  [ERROR]${NC} Unsupported action '${action}'."
            (( FAILED++ )) || true
            FAILED_APPS+=("$folder")
            return 1
            ;;
    esac
    local action_rc=$?

    if [[ $action_rc -eq 0 ]]; then
        echo -e "\n${GREEN}  [DONE]${NC} '${folder}' ${action} completed successfully."
        (( SUCCESS++ )) || true
        SUCCESS_APPS+=("$folder")
        return 0
    fi
    echo -e "\n${RED}  [FAIL]${NC} '${action}' failed for '${folder}'."
    (( FAILED++ )) || true
    FAILED_APPS+=("$folder")
    return 1
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
    local parsing_using=false
    CLEANUP_MODES=()
    LOG_ARGS_RAW=()
    CUSTOM_COMPOSE_FILES_RAW=()
    GET_RESOURCE_RAW=""
    GET_FULL_SHA=false
    ASSUME_YES=false

    for arg in "$@"; do
        if [[ "$arg" == "-y" || "$arg" == "--yes" ]]; then
            skip_prompt=true
            ASSUME_YES=true
        elif [[ "$arg" == "using" ]]; then
            parsing_using=true
            parsing_with=false
        elif [[ "$arg" == "with" ]]; then
            if [[ "$action" != "delete" ]]; then
                echo -e "${RED}[ERROR]${NC} The 'with' modifier is only supported for the 'delete' command."
                return 1
            fi
            parsing_with=true
            parsing_using=false
        elif $parsing_using; then
            CUSTOM_COMPOSE_FILES_RAW+=("$arg")
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
            elif [[ "$action" == "get" ]]; then
                if [[ "$arg" == "full" ]]; then
                    GET_FULL_SHA=true
                    continue
                fi
                if [[ "$arg" =~ ^(cid|container-id|iid|image-id|vol|volume|volumes|mnt|mount|mountpoint|mountpoints|net|network|networks|port|ports|state|status|health|info)$ ]]; then
                    if [[ -n "$GET_RESOURCE_RAW" ]]; then
                        echo -e "${RED}[ERROR]${NC} You can only specify one resource type at a time. (Found: '$GET_RESOURCE_RAW' and '$arg')"
                        return 1
                    fi
                    GET_RESOURCE_RAW="$arg"
                    continue
                fi
            fi
            if [[ "$arg" == *":"* ]]; then
                local app_part="${arg%%:*}"
                local svc_part="${arg#*:}"
                requested+=("${app_part}:${svc_part}")
            else
                requested+=("${arg}")
            fi
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

        local -a exclude_dirs_resolved=()
        for excl in "${user_excludes[@]}"; do
            find_app_dir "${excl%%:*}"
            if [[ -z "$FOUND_APP_DIR" ]]; then
                echo -e "${RED}[ERROR]${NC} except: app '${excl%%:*}' could not be found."
                return 1
            fi
            if [[ "$FOUND_APP_DIR" == "DUPLICATE:"* ]]; then
                return 1
            fi
            exclude_dirs_resolved+=("$FOUND_APP_DIR")
        done

        read -ra all_apps <<< "$(get_all_apps "$mode")"
        if [[ ${#all_apps[@]} -eq 0 ]]; then
            echo -e "${RED}[ERROR]${NC} No matching apps found for action '${action}'."
            return 1
        fi

        for app in "${all_apps[@]}"; do
            local skip=false
            find_app_dir "$app" 2>/dev/null
            local app_resolved_dir="$FOUND_APP_DIR"
            for exc_dir in "${exclude_dirs_resolved[@]}"; do
                [[ "$app_resolved_dir" == "$exc_dir" ]] && skip=true && break
            done
            $skip || APPS_TO_PROCESS+=("$app")
        done

        if [[ ${#APPS_TO_PROCESS[@]} -eq 0 ]]; then
            echo -e "${YELLOW}[WARN]${NC} Nothing to process after exclusions."
            return 1
        fi

        if [[ "$action" != "get" ]]; then
            if [[ ${#user_excludes[@]} -gt 0 ]]; then
                echo -e "${BOLD}Mode:${NC} ${action} ALL apps ${YELLOW}except${NC}: ${user_excludes[*]}"
            else
                echo -e "${BOLD}Mode:${NC} ${action} ALL apps"
            fi
            echo
            echo -e "${CYAN}Apps to process (${#APPS_TO_PROCESS[@]}):${NC}"
            list_available_apps "compose" "  " "${APPS_TO_PROCESS[@]}"
        fi
    else
        if [[ "$action" != "get" ]]; then
            echo -e "${BOLD}Mode:${NC} ${action} specific app(s): ${CYAN}${requested[*]}${NC}"
        fi
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
SUPPORTED_ACTIONS=("start" "stop" "kill" "restart" "recreate" "force-recreate" "frec" "delete" "cleanup" "pause" "unpause" "update" "status" "logs" "debug" "list" "get")

if [[ " ${SUPPORTED_ACTIONS[*]} " =~ \ ${COMMAND_NAME}\  ]]; then
    set -- "$COMMAND_NAME" "$@"
fi

# 2. Universal Install, Config, Uninstall & Self-Update logic
if [[ "${1:-}" == "install" || "${1:-}" == "config" || "${1:-}" == "uninstall" || "${1:-}" == "self-update" ]]; then
    if [[ "$EUID" -ne 0 ]]; then
        echo -e "${RED}[ERROR]${NC} This command must be run with sudo."
        exit 1
    fi

    # [SECURITY] Mitigate TOCTOU vulnerability during installation
    # If executing from a world-writable temp directory, immediately stage the script
    # into a root-owned, non-world-writable location to prevent malicious modification
    # by an unprivileged user during the interactive prompts.
    if [[ "$(realpath "$0" 2>/dev/null)" != "/usr/local/bin/docker-app-manager" && -f "$0" ]]; then
        SCRIPT_SOURCE_PATH="$(realpath "$0")"
        if [[ "$SCRIPT_SOURCE_PATH" == /tmp/* || "$SCRIPT_SOURCE_PATH" == /var/tmp/* ]]; then
            old_umask=$(umask)
            umask 077
            safe_staged_script="$(mktemp /tmp/dam-install-XXXXXX.tmp)"
            umask "$old_umask"
            cat "$SCRIPT_SOURCE_PATH" > "$safe_staged_script"
            SCRIPT_SOURCE_PATH="$safe_staged_script"
            trap 'rm -f "$safe_staged_script"' EXIT
        fi
    fi
    
    if [[ "${1:-}" == "install" && ( "${2:-}" == "--refresh" || "${2:-}" == "refresh" ) ]]; then
        # Install the script to system bin: copy from temp paths, symlink from persistent paths
        if [[ -n "${SCRIPT_SOURCE_PATH:-}" ]]; then
            if [[ "$SCRIPT_SOURCE_PATH" == /tmp/* || "$SCRIPT_SOURCE_PATH" == /var/tmp/* ]]; then
                rm -f "/usr/local/bin/docker-app-manager"
                cp -f "$SCRIPT_SOURCE_PATH" "/usr/local/bin/docker-app-manager"
            else
                ln -sf "$SCRIPT_SOURCE_PATH" "/usr/local/bin/docker-app-manager"
            fi
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
        
        # Enforce strict permissions for the temporary file to prevent local tampering
        old_umask=$(umask)
        umask 077
        tmp_script="$(mktemp /tmp/docker-app-manager-XXXXXX.tmp)"
        umask "$old_umask"
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
                if ! bash "/usr/local/bin/docker-app-manager" install refresh; then
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
            
            if [[ -z "${input_dirs//[[:space:]]/}" ]]; then
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
        if [[ -z "${input_excludes//[[:space:]]/}" && -n "$existing_excludes" ]]; then
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
            
            input_cmd_name="${input_cmd_name//[[:space:]]/}"
            
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
        echo -e "Allow custom update*.sh scripts to run automatically without prompting during updates?"
        echo -e "${CYAN}Note: If 'No', DAM will interactively ask you for permission each time it finds a script.${NC}"
        echo -e "Choice: [y/N/true/false]"
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
        echo -e "${YELLOW}Note: It is only there for highly strict security environments where administrators want to manually approve and verify every single update before allowing the script to pull it. For normal use, leaving it blank is the best approach.${NC}"
        if [[ -n "$existing_sha" ]]; then
            echo -e "(Default: ${existing_sha})"
        fi
        read -r -p "> " input_sha
        if [[ -z "$input_sha" && -n "$existing_sha" ]]; then
            input_sha="$existing_sha"
        fi

        existing_url="${UPDATE_URL:-}"

        CONF_PATH="/etc/docker-app-manager.conf"
        echo -e "\n${YELLOW}Saving configuration to $CONF_PATH...${NC}"
        
        format_array() {
            local arr
            read -ra arr <<< "$1"
            for item in "${arr[@]}"; do 
                printf '"%s" ' "$item"
            done
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
            if [[ -n "$existing_url" ]]; then
                echo "UPDATE_URL=\"$existing_url\""
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
        
        # Install the script to system bin: copy from temp paths to avoid dangling
        # symlinks (e.g. quick-install one-liner), symlink from persistent paths
        # so edits are globally reflected immediately.
        if [[ -n "${SCRIPT_SOURCE_PATH:-}" ]]; then
            if [[ "$SCRIPT_SOURCE_PATH" == /tmp/* || "$SCRIPT_SOURCE_PATH" == /var/tmp/* ]]; then
                rm -f "/usr/local/bin/docker-app-manager"
                cp -f "$SCRIPT_SOURCE_PATH" "/usr/local/bin/docker-app-manager"
                echo -e "  ${CYAN}[INFO]${NC} Copied script to /usr/local/bin (source is in a temp directory)."
            else
                ln -sf "$SCRIPT_SOURCE_PATH" "/usr/local/bin/docker-app-manager"
                echo -e "  ${CYAN}[INFO]${NC} Symlinked script from ${SCRIPT_SOURCE_PATH}."
            fi
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

if [[ "$1" != "get" ]]; then
    print_header
fi

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

# Normalize aliases
if [[ "$ACTION" == "frec" ]]; then
    ACTION="force-recreate"
fi

case "$ACTION" in
    (start|stop|kill|restart|recreate|force-recreate|delete|pause|unpause|update|status|logs|debug|list|get)
        if ! docker_ready; then
            exit 1
        fi

        if [[ "$ACTION" == "list" && $# -eq 0 ]]; then
            echo -e "${BOLD}Application Inventory:${NC}"
            inventory_apps_table
            exit 0
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

        if [[ "$ACTION" == "list" ]]; then
            echo -e "${CYAN}Gathering details for ${#APPS_TO_PROCESS[@]} app(s)...${NC}"
            echo
            echo -e "${BOLD}Application Level Details:${NC}"
            print_app_level_details_table "${APPS_TO_PROCESS[@]}"
            echo
            exit 0
        elif [[ "$ACTION" == "get" ]]; then
            if [[ -z "$GET_RESOURCE_RAW" ]]; then
                echo -e "${RED}[ERROR]${NC} You must specify a resource to get. (e.g. cid, iid, vol, mnt, net, port, state, info)"
                exit 1
            fi
            
            if [[ "$GET_RESOURCE_RAW" == "info" ]]; then
                echo -e "${CYAN}Gathering details for ${#APPS_TO_PROCESS[@]} app(s)...${NC}"
                all_containers=()
                
                declare -A target_eff_names
                declare -A resolved_dirs
                for app in "${APPS_TO_PROCESS[@]}"; do
                    (( TOTAL++ )) || true
                    find_app_dir "$app" 2>/dev/null
                    dir="$FOUND_APP_DIR"
                    if [[ -d "$dir" ]]; then
                        eff_name="$(get_effective_app_name "$dir")"
                        target_eff_names["$eff_name"]="$app"
                        resolved_dirs["$app"]="$dir"
                    elif [[ "$dir" == "DUPLICATE:"* ]]; then
                        resolved_dirs["$app"]="DUPLICATE"
                    fi
                done
                
                while IFS='|' read -r cid project wdir; do
                    [[ -z "$cid" ]] && continue
                    app_name=""
                    if [[ -n "$project" ]] && [[ -n "${target_eff_names["$project"]:-}" ]]; then
                        app_name="$project"
                    elif [[ -n "$wdir" ]]; then
                        bname=$(get_effective_app_name "$wdir")
                        if [[ -n "${target_eff_names["$bname"]:-}" ]]; then
                            app_name="$bname"
                        fi
                    fi
                    if [[ -n "$app_name" ]]; then
                        all_containers+=("$cid")
                    fi
                done < <(docker ps -a --filter "label=com.docker.compose.project" --format '{{.ID}}|{{.Label "com.docker.compose.project"}}|{{.Label "com.docker.compose.project.working_dir"}}' 2>/dev/null)
                
                for app in "${APPS_TO_PROCESS[@]}"; do
                    if is_excluded "$app"; then
                        (( SKIPPED++ )) || true
                        SKIPPED_APPS+=("$app")
                        continue
                    fi
                    
                    dir="${resolved_dirs["$app"]:-}"
                    
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
                    echo -e "${BOLD}1. Application Level Details:${NC}"
                    print_app_level_details_table "${APPS_TO_PROCESS[@]}"
                    echo

                    echo -e "${BOLD}2. Container Level Details:${NC}"
                    (
                            echo "APP|SERVICE|CONTAINER|IMAGE|STATE|HEALTH|PORTS"
                        docker ps -a --filter "label=com.docker.compose.project" --format '{{.Label "com.docker.compose.project"}}|{{.Label "com.docker.compose.project.working_dir"}}|{{.Label "com.docker.compose.service"}}|{{.Names}}|{{.Image}}|{{.State}}|{{.Status}}|{{.Ports}}' | \
                        while IFS='|' read -r project wdir svc name image state status ports; do
                            app_name=""
                            if [[ -n "$project" ]] && [[ -n "${target_eff_names["$project"]:-}" ]]; then
                                app_name="$project"
                            elif [[ -n "$wdir" ]]; then
                                bname=$(get_effective_app_name "$wdir")
                                if [[ -n "${target_eff_names["$bname"]:-}" ]]; then
                                    app_name="$bname"
                                fi
                            fi
                            if [[ -z "$app_name" ]]; then continue; fi
                            
                            health="-"
                            if [[ "$status" == *"healthy"* ]]; then health="healthy"; fi
                            if [[ "$status" == *"unhealthy"* ]]; then health="unhealthy"; fi
                            
                            ports="${ports:--}"
                            echo "$project|$svc|$name|$image|$state|$health|$ports"
                        done
                    ) | column -t -s '|' | awk 'NR==1{print; gsub(/./, "-"); print} NR>1'
                    echo

                    echo -e "${BOLD}3. Docker Resources:${NC}"
                    (
                            echo "APP|CONTAINER ID|IMAGE ID|NETWORKS|VOLUMES|MOUNTPOINTS"
                        docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}|{{printf "%.12s" .Id}}|{{.Image}}|{{range $k, $v := .NetworkSettings.Networks}}{{$k}},{{end}}|{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}={{.Destination}},{{else if eq .Type "bind"}}{{.Source}}={{.Destination}},{{end}}{{end}}' "${all_containers[@]}" | \
                        while IFS='|' read -r project cid image_id networks mounts; do
                            image_id="${image_id#sha256:}"
                            image_id="${image_id:0:12}"
                            networks="${networks%,}"
                            [[ -z "$networks" ]] && networks="-"
                            
                            mounts="${mounts%,}"
                            volumes=""
                            mountpoints=""
                            if [[ -n "$mounts" ]]; then
                                IFS=',' read -ra mnt_array <<< "$mounts"
                                for m in "${mnt_array[@]}"; do
                                    v="${m%%=*}"
                                    p="${m#*=}"
                                    volumes+="${v},"
                                    mountpoints+="${p},"
                                done
                                volumes="${volumes%,}"
                                mountpoints="${mountpoints%,}"
                            fi
                            [[ -z "$volumes" ]] && volumes="-"
                            [[ -z "$mountpoints" ]] && mountpoints="-"
                            
                            echo "$project|$cid|$image_id|$networks|$volumes|$mountpoints"
                        done
                    ) | column -t -s '|' | awk 'NR==1{print; gsub(/./, "-"); print} NR>1'
                fi
                exit 0
            fi
            
            for raw_app in "${APPS_TO_PROCESS[@]}"; do
                app_name="${raw_app%%:*}"
                target_service="${raw_app#*:}"
                [[ "$target_service" == "$raw_app" ]] && target_service=""
                
                find_app_dir "$app_name"
                dir="$FOUND_APP_DIR"
                if [[ -d "$dir" ]]; then
                    app_name="$(get_effective_app_name "$dir")"
                fi
                
                filter_args=("-f" "label=com.docker.compose.project=$app_name")
                if [[ -n "$target_service" ]]; then
                    filter_args+=("-f" "label=com.docker.compose.service=$target_service")
                fi

                docker ps -a "${filter_args[@]}" --format '{{.Label "com.docker.compose.service"}}|{{.ID}}' 2>/dev/null | while IFS='|' read -r svc cid; do
                    [[ -z "$cid" ]] && continue
                    
                    val=""
                    case "$GET_RESOURCE_RAW" in
                        cid|container-id)
                            if [[ "${GET_FULL_SHA:-false}" == "true" ]]; then
                                val=$(docker inspect --format '{{.Id}}' "$cid" 2>/dev/null)
                            else
                                val="$cid"
                            fi
                            ;;
                        iid|image-id)
                            val=$(docker inspect --format '{{.Image}}' "$cid" 2>/dev/null)
                            val="${val#sha256:}"
                            if [[ "${GET_FULL_SHA:-false}" != "true" ]]; then
                                val="${val:0:12}"
                            fi
                            ;;
                        vol|volume|volumes)
                            val=$(docker inspect --format '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{else if eq .Type "bind"}}{{.Source}}{{end}}{{println}}{{end}}' "$cid" 2>/dev/null | grep -v '^$' || true)
                            ;;
                        mnt|mount|mountpoint|mountpoints)
                            val=$(docker inspect --format '{{range .Mounts}}{{.Destination}}{{println}}{{end}}' "$cid" 2>/dev/null | grep -v '^$' || true)
                            ;;
                        net|network|networks)
                            val=$(docker inspect --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{println}}{{end}}' "$cid" 2>/dev/null | grep -v '^$' || true)
                            ;;
                        port|ports)
                            val=$(docker ps -a -f "id=$cid" --format '{{.Ports}}' 2>/dev/null | grep -v '^$' || true)
                            ;;
                        state|status)
                            val=$(docker ps -a -f "id=$cid" --format '{{.State}}' 2>/dev/null | grep -v '^$' || true)
                            ;;
                        health)
                            val=$(docker ps -a -f "id=$cid" --format '{{.Status}}' 2>/dev/null | grep -o "(.*)" | tr -d '()' | grep -v '^$' || true)
                            ;;
                    esac
                    
                    if [[ -n "$val" ]]; then
                        if [[ -n "$target_service" ]]; then
                            echo "$val"
                        else
                            while IFS= read -r line; do
                                [[ -n "$line" ]] && echo "${svc}: ${line}"
                            done <<< "$val"
                        fi
                    fi
                done
            done
            exit 0
        elif [[ "$ACTION" == "status" ]]; then
            echo -e "${CYAN}Gathering status for ${#APPS_TO_PROCESS[@]} app(s)...${NC}"
            all_containers=()
            
            declare -A target_eff_names
            declare -A resolved_dirs
            for app in "${APPS_TO_PROCESS[@]}"; do
                (( TOTAL++ )) || true
                find_app_dir "$app"
                dir="$FOUND_APP_DIR"
                if [[ -d "$dir" ]]; then
                    eff_name="$(get_effective_app_name "$dir")"
                    target_eff_names["$eff_name"]="$app"
                    resolved_dirs["$app"]="$dir"
                elif [[ "$dir" == "DUPLICATE:"* ]]; then
                    resolved_dirs["$app"]="DUPLICATE"
                fi
            done
            
            while IFS='|' read -r cid project wdir; do
                [[ -z "$cid" ]] && continue
                app_name=""
                if [[ -n "$project" ]] && [[ -n "${target_eff_names["$project"]:-}" ]]; then
                    app_name="$project"
                elif [[ -n "$wdir" ]]; then
                    bname=$(get_effective_app_name "$wdir")
                    if [[ -n "${target_eff_names["$bname"]:-}" ]]; then
                        app_name="$bname"
                    fi
                fi
                if [[ -n "$app_name" ]]; then
                    all_containers+=("$cid")
                fi
            done < <(docker ps -a --filter "label=com.docker.compose.project" --format '{{.ID}}|{{.Label "com.docker.compose.project"}}|{{.Label "com.docker.compose.project.working_dir"}}' 2>/dev/null)
            
            for app in "${APPS_TO_PROCESS[@]}"; do
                if is_excluded "$app"; then
                    (( SKIPPED++ )) || true
                    SKIPPED_APPS+=("$app")
                    continue
                fi
                
                dir="${resolved_dirs["$app"]:-}"
                
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
                docker ps -a "${filter_args[@]}" --format 'table {{.Names}}\t{{.Label "com.docker.compose.project"}}\t{{.Label "com.docker.compose.service"}}\t{{.Image}}\t{{.RunningFor}}\t{{.Status}}\t{{.Ports}}' | sed '1{ s/com.docker.compose.project/APP/; s/com.docker.compose.service/SERVICE/; }'
                echo
                echo -e "${BLUE}  [2/2]${NC} Real-time resource usage:"
                docker stats --no-stream "${all_containers[@]}" || true
            fi
        else
            declare -A GLOBAL_USED_COMPOSE_FILES=()
            declare -A GLOBAL_MISSING_COMPOSE_FILES=()
            for app in "${APPS_TO_PROCESS[@]}"; do
                process_app "$ACTION" "$app" || true
            done
            if [[ ${#CUSTOM_COMPOSE_FILES_RAW[@]} -gt 0 ]]; then
                for cf in "${CUSTOM_COMPOSE_FILES_RAW[@]}"; do
                    if [[ -z "${GLOBAL_USED_COMPOSE_FILES[$cf]:-}" ]]; then
                        echo -e "${YELLOW}[WARN]${NC} The requested file '${cf}' was not found in any processed app."
                    elif [[ -n "${GLOBAL_MISSING_COMPOSE_FILES[$cf]:-}" ]]; then
                        missing_apps="${GLOBAL_MISSING_COMPOSE_FILES[$cf]}"
                        echo -e "${YELLOW}[WARN]${NC} The requested file '${cf}' was missing in the following apps: ${missing_apps% }"
                    fi
                done
            fi
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
