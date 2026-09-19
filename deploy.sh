#!/bin/bash
# Deploy the plugin to a Kindle over ssh for on-device testing.
# Usage: ./deploy.sh [ssh-host]   (default: ploetze)

set -e

REMOTE_HOST="${1:-ploetze}"
REMOTE_PLUGINS_DIR="/mnt/us/koreader/plugins"
REMOTE_DIR="$REMOTE_PLUGINS_DIR/weatherlockscreen.koplugin"

echo "Compiling translations..."
bash ./compile_translations.sh

TEMP_DIR=$(mktemp -d)
STAGE_DIR="$TEMP_DIR/weatherlockscreen.koplugin"
mkdir -p "$STAGE_DIR"

# Same exclude list as create-release.sh: ship only what the plugin needs on-device.
rsync -a --exclude='.git' \
         --exclude='.gitignore' \
         --exclude='.github' \
         --exclude='.claude' \
         --exclude='resources' \
         --exclude='*.zip' \
         --exclude='*.log' \
         --exclude='*.sh' \
         --exclude='flake.nix' \
         --exclude='flake.lock' \
         ./ "$STAGE_DIR/"

TARBALL="$TEMP_DIR/weatherlockscreen.tar.gz"
tar czf "$TARBALL" -C "$TEMP_DIR" weatherlockscreen.koplugin

echo "Uploading to $REMOTE_HOST..."
scp "$TARBALL" "$REMOTE_HOST:/tmp/weatherlockscreen.tar.gz"

echo "Installing on device..."
ssh "$REMOTE_HOST" "rm -rf '$REMOTE_DIR' && tar xzf /tmp/weatherlockscreen.tar.gz -C '$REMOTE_PLUGINS_DIR' && rm /tmp/weatherlockscreen.tar.gz"

rm -rf "$TEMP_DIR"

echo "Deployed to $REMOTE_HOST:$REMOTE_DIR"
echo "Restart KOReader on the device to load the changes."
