#!/usr/bin/env bash
#
# wp-url-replace.sh
# Replace a WordPress site URL in the database using WP-CLI.
#
# The old URL is replaced in three formats, in this order:
#   1. https://old-domain  ->  new URL
#   2. http://old-domain   ->  new URL
#   3. old-domain          ->  new domain   (catches leftovers such as emails or protocol-less links)
#
# Usage:
#   bash wp-url-replace.sh [path-to-wordpress]
#   (If no path is given, the current directory is used.)
#

set -uo pipefail

# ---------- Colors ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'; ITALIC='\033[3m'

info()    { echo -e "${CYAN}$*${NC}"; }
success() { echo -e "${GREEN}$*${NC}"; }
warn()    { echo -e "${YELLOW}$*${NC}"; }
error()   { echo -e "${RED}Error: $*${NC}" >&2; }

# This script needs an interactive terminal for its prompts. When piped directly
# into bash, stdin contains the script itself rather than the user's responses.
if [[ ! -t 0 ]]; then
    error "Interactive terminal required. Download this script to a file, then run it with bash; do not pipe it directly into bash."
    exit 1
fi

# ---------- Pre-checks ----------
WP_PATH="${1:-$(pwd)}"

if ! command -v wp >/dev/null 2>&1; then
    error "WP-CLI is not installed or not in your PATH."
    echo "Install it from https://wp-cli.org and try again."
    exit 1
fi

WP=(wp --path="$WP_PATH")
# Allow running as root (common on servers)
[[ $EUID -eq 0 ]] && WP+=(--allow-root)

if ! "${WP[@]}" core is-installed >/dev/null 2>&1; then
    error "No WordPress installation found at: $WP_PATH"
    echo "Run this script from your WordPress root folder, or pass the path as an argument."
    exit 1
fi

# Remove the protocol and trailing slash, leaving only the domain (and sub-path, if any)
strip_url() {
    local url="$1"
    url="${url#http://}"
    url="${url#https://}"
    url="${url%/}"
    echo "$url"
}

# ---------- Header ----------
CURRENT_SITEURL="$("${WP[@]}" option get siteurl 2>/dev/null)"
clear
echo -e "${BOLD}============================================${NC}"
echo -e "${BOLD}     WordPress URL Search & Replace Tool     ${NC}"
echo -e "${BOLD}============================================${NC}"
echo "WordPress path : $WP_PATH"
echo "Current siteurl: $CURRENT_SITEURL"
echo

# ---------- Input ----------
while true; do
    if ! read -e -r -i "$CURRENT_SITEURL" -p "Enter the OLD URL (prefilled from siteurl; edit if needed): " OLD_INPUT; then
        error "No old URL was entered. Run the script in an interactive terminal and try again."
        exit 1
    fi
    OLD_INPUT="$(echo "$OLD_INPUT" | xargs)"
    [[ -n "$OLD_INPUT" && "$OLD_INPUT" != *" "* ]] && break
    error "The old URL cannot be empty or contain spaces."
done

while true; do
    if ! read -e -r -p "Enter the NEW URL (e.g. https://new-domain.com, http://new-domain.com, or new-domain.com): " NEW_INPUT; then
        error "No new URL was entered. Run the script in an interactive terminal and try again."
        exit 1
    fi
    NEW_INPUT="$(echo "$NEW_INPUT" | xargs)"
    [[ -n "$NEW_INPUT" && "$NEW_INPUT" != *" "* ]] && break
    error "The new URL cannot be empty or contain spaces."
done

OLD_DOMAIN="$(strip_url "$OLD_INPUT")"
NEW_DOMAIN="$(strip_url "$NEW_INPUT")"

if [[ "$OLD_DOMAIN" == "$NEW_DOMAIN" ]]; then
    error "The old and new URLs are the same. Nothing to replace."
    exit 1
fi

# ---------- Confirmation ----------
echo
echo -e "${BOLD}The following replacements will be made:${NC}"
printf "  1. %-40s ->  %s\n" "https://$OLD_DOMAIN" "https://$NEW_DOMAIN"
printf "  2. %-40s ->  %s\n" "http://$OLD_DOMAIN"  "http://$NEW_DOMAIN"
printf "  3. %-40s ->  %s\n" "$OLD_DOMAIN"         "$NEW_DOMAIN"
echo
warn "Please make sure both URLs are correct."
if ! read -r -p "Press Enter to continue, or Ctrl+C to cancel... " _; then
    error "Input ended before confirmation. No changes were made."
    exit 1
fi

# ---------- Mode selection ----------
echo
echo -e "${BOLD}Select an option:${NC}"
echo "  1) Dry run  (preview changes only, nothing is saved)"
echo "  2) Proceed to replace URL  (changes are written to the database)"
echo
while true; do
    if ! read -r -p "Enter your choice [1-2] and press Enter: " CHOICE; then
        error "Input ended before a mode was selected. No changes were made."
        exit 1
    fi
    case "$CHOICE" in
        1|2) break ;;
        *)   error "Invalid choice. Please enter 1 or 2." ;;
    esac
done

COMMON_FLAGS=(--all-tables-with-prefix --skip-columns=guid --precise --recurse-objects --report-changed-only)

if [[ "$CHOICE" == "1" ]]; then
    MODE_FLAGS=(--dry-run)
    echo
    info ">>> Running in DRY RUN mode. No changes will be saved."
else
    MODE_FLAGS=()
    echo
    warn "You are about to modify the database permanently."
    if ! read -r -p "Create a database backup first? [Y/n]: " BACKUP; then
        error "Input ended before the backup choice. No changes were made."
        exit 1
    fi
    if [[ ! "$BACKUP" =~ ^[Nn]$ ]]; then
        BACKUP_FILE="$WP_PATH/db-backup-$(date +%Y%m%d-%H%M%S).sql"
        info "Exporting database to: $BACKUP_FILE"
        if "${WP[@]}" db export "$BACKUP_FILE" --quiet; then
            success "Backup created successfully."
        else
            error "Backup failed. Aborting to keep your data safe."
            exit 1
        fi
    fi
    echo
    info ">>> Replacing URLs..."
fi

# ---------- Run replacements ----------
run_replace() {
    local step="$1" from="$2" to="$3"
    echo
    echo -e "${BOLD}[$step/3] '$from'  ->  '$to'${NC}"
    if ! "${WP[@]}" search-replace "$from" "$to" "${COMMON_FLAGS[@]}" "${MODE_FLAGS[@]}"; then
        error "Search-replace failed at step $step."
        exit 1
    fi
}

run_replace 1 "https://$OLD_DOMAIN" "https://$NEW_DOMAIN"
run_replace 2 "http://$OLD_DOMAIN"  "http://$NEW_DOMAIN"
run_replace 3 "$OLD_DOMAIN"         "$NEW_DOMAIN"

# ---------- Finish ----------
echo
if [[ "$CHOICE" == "1" ]]; then
    success "Dry run completed. Review the results above."
    echo "Run the script again and choose option 2 to apply the changes."
else
    info "Flushing the WordPress object cache..."
    if "${WP[@]}" cache flush; then
        success "WordPress object cache flushed."
    else
        warn "WordPress object cache flush failed."
    fi

    if "${WP[@]}" cli has-command litespeed-purge >/dev/null 2>&1; then
        info "Purging the LiteSpeed cache..."
        if "${WP[@]}" litespeed-purge all; then
            success "LiteSpeed cache purged."
        else
            warn "LiteSpeed cache purge failed."
        fi
    else
        info "LiteSpeed Cache WP-CLI command not found; skipping the optional LiteSpeed purge."
    fi

    info "Flushing WordPress rewrite rules..."
    if "${WP[@]}" rewrite flush; then
        success "WordPress rewrite rules flushed."
    else
        warn "WordPress rewrite rules flush failed."
    fi

    success "URL replacement completed successfully."
    echo "New siteurl: $("${WP[@]}" option get siteurl 2>/dev/null)"
    [[ -n "${BACKUP_FILE:-}" ]] && echo "Backup file: $BACKUP_FILE"
    printf '%b\n' "${BOLD}${YELLOW}${ITALIC}CDN CACHE: If this site uses Cloudflare or another CDN, purge its cache separately so visitors receive the updated URLs.${NC}"
fi
