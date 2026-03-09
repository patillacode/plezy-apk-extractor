#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source .env
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/.env"
fi

: "${FORGEJO_TOKEN:?FORGEJO_TOKEN is required}"
: "${FORGEJO_USER:?FORGEJO_USER is required}"
: "${FORGEJO_REPO:?FORGEJO_REPO is required}"
: "${FORGEJO_URL:?FORGEJO_URL is required}"
: "${TELEGRAM_TOKEN:?TELEGRAM_TOKEN is required}"
: "${TELEGRAM_CHAT_ID:?TELEGRAM_CHAT_ID is required}"

LAST_VERSION_FILE="$SCRIPT_DIR/.last_version"
TMPDIR="$(mktemp -d)"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

send_telegram() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=${message}" \
        -d "parse_mode=HTML" \
        > /dev/null
}

cleanup() {
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

on_error() {
    local exit_code=$?
    local line_number=$1
    local msg="plezy-apk-extractor failed at line ${line_number} (exit ${exit_code})"
    log "ERROR: $msg"
    send_telegram "❌ <b>plezy-apk-extractor</b>: $msg"
    exit 1
}
trap 'on_error $LINENO' ERR

log "Script started"

# 1. Fetch latest GitHub release
log "Fetching latest Plezy release from GitHub..."
release_json="$(curl -sf "https://api.github.com/repos/edde746/plezy/releases/latest")"
tag_name="$(echo "$release_json" | jq -r '.tag_name')"
release_name="$(echo "$release_json" | jq -r '.name')"
release_body="$(echo "$release_json" | jq -r '.body // ""')"

log "Latest upstream version: $tag_name"

# 2. Compare with last known version
last_version=""
if [[ -f "$LAST_VERSION_FILE" ]]; then
    last_version="$(cat "$LAST_VERSION_FILE")"
fi

if [[ "$tag_name" == "$last_version" ]]; then
    log "Already up to date ($tag_name). Nothing to do."
    log "Script finished"
    exit 0
fi

log "New version detected: $tag_name (was: ${last_version:-none})"

# 3. Find arm64-v8a asset
asset_url="$(echo "$release_json" | jq -r '.assets[] | select(.name | contains("arm64-v8a")) | .browser_download_url' | head -1)"
asset_name="$(echo "$release_json" | jq -r '.assets[] | select(.name | contains("arm64-v8a")) | .name' | head -1)"

if [[ -z "$asset_url" || "$asset_url" == "null" ]]; then
    log "ERROR: No arm64-v8a asset found in release $tag_name"
    send_telegram "❌ <b>plezy-apk-extractor</b>: No arm64-v8a asset found in release $tag_name"
    exit 1
fi

log "Downloading: $asset_name"

# 4. Download the tarball
tarball_path="$TMPDIR/$asset_name"
curl -sfL "$asset_url" -o "$tarball_path"

# 5. Find and extract APK
log "Locating APK inside tarball..."
apk_path_in_tar="$(tar -tzf "$tarball_path" | grep '\.apk$' | head -1)"

if [[ -z "$apk_path_in_tar" ]]; then
    log "ERROR: No APK found inside $asset_name"
    send_telegram "❌ <b>plezy-apk-extractor</b>: No APK found inside $asset_name"
    exit 1
fi

log "Extracting: $apk_path_in_tar"
tar -xzf "$tarball_path" -C "$TMPDIR" "$apk_path_in_tar"

apk_local_path="$TMPDIR/$apk_path_in_tar"
apk_filename="$(basename "$apk_path_in_tar")"

# Rename APK to include version tag for clarity
versioned_apk_name="plezy-${tag_name}-arm64-v8a.apk"
mv "$apk_local_path" "$TMPDIR/$versioned_apk_name"
apk_local_path="$TMPDIR/$versioned_apk_name"

log "APK ready: $versioned_apk_name"

# 6. Create release on Forgejo
log "Creating Forgejo release $tag_name..."
forgejo_release="$(curl -sf -X POST \
    "${FORGEJO_URL}/api/v1/repos/${FORGEJO_USER}/${FORGEJO_REPO}/releases" \
    -H "Authorization: token ${FORGEJO_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
        --arg tag "$tag_name" \
        --arg name "${release_name:-$tag_name}" \
        --arg body "$release_body" \
        '{tag_name: $tag, name: $name, body: $body}')")"

release_id="$(echo "$forgejo_release" | jq -r '.id')"

if [[ -z "$release_id" || "$release_id" == "null" ]]; then
    log "ERROR: Failed to create Forgejo release"
    send_telegram "❌ <b>plezy-apk-extractor</b>: Failed to create Forgejo release for $tag_name"
    exit 1
fi

log "Created Forgejo release ID: $release_id"

# 7. Upload APK as release asset
log "Uploading $versioned_apk_name to Forgejo release..."
curl -sf -X POST \
    "${FORGEJO_URL}/api/v1/repos/${FORGEJO_USER}/${FORGEJO_REPO}/releases/${release_id}/assets" \
    -H "Authorization: token ${FORGEJO_TOKEN}" \
    -F "attachment=@${apk_local_path};type=application/vnd.android.package-archive" \
    > /dev/null

log "APK uploaded successfully."

# 8. Save new version
echo "$tag_name" > "$LAST_VERSION_FILE"
log "Done. Published $tag_name to ${FORGEJO_URL}/${FORGEJO_USER}/${FORGEJO_REPO}/releases/tag/${tag_name}"
send_telegram "✅ <b>Plezy ${tag_name}</b> published to Forgejo — APK ready for Obtainium"
log "Script finished"
