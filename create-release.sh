#!/bin/bash

# Script to create a release zip for weatherlockscreen.koplugin

VERSION=${1:-"dev"}
OUTPUT_FILE="weatherlockscreen.koplugin-${VERSION}.zip"

echo "Creating release archive: $OUTPUT_FILE"

# Compile translations
echo "Compiling translations..."
./compile_translations.sh

# Create temporary directory
TEMP_DIR=$(mktemp -d)
PLUGIN_DIR="$TEMP_DIR/weatherlockscreen.koplugin"

# Copy all files to temp directory
mkdir -p "$PLUGIN_DIR"
rsync -av --exclude='.git' \
          --exclude='.gitignore' \
          --exclude='.github' \
          --exclude='.vscode' \
          --exclude='resources' \
          --exclude='*.zip' \
          --exclude='*.log' \
          --exclude='*.sh' \
          ./ "$PLUGIN_DIR/"

# Create zip archive
cd "$TEMP_DIR"
zip -r "$OUTPUT_FILE" weatherlockscreen.koplugin/

# Move zip to original directory
mv "$OUTPUT_FILE" "$OLDPWD/"

# Clean up
cd "$OLDPWD"
rm -rf "$TEMP_DIR"

echo "Release archive created: $OUTPUT_FILE"
echo "Contents:"
unzip -l "$OUTPUT_FILE" | head -20
