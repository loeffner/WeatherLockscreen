#!/bin/bash
# Script to compile .po files to .mo files for KOReader plugin

# Requires gettext tools (msgfmt)
# Install on Ubuntu/Debian: sudo apt-get install gettext
# Install on macOS: brew install gettext

echo "Compiling translation files..."

# Create l10n directory if it doesn't exist
mkdir -p l10n

# Compile each .po file to .mo
for po_file in l10n/*.po; do
    if [ -f "$po_file" ]; then
        # Get the language code (filename without extension)
        lang=$(basename "$po_file" .po)

        # Output .mo file
        mo_file="l10n/${lang}.mo"

        echo "Compiling ${po_file} -> ${mo_file}"
        msgfmt -o "$mo_file" "$po_file"

        if [ $? -eq 0 ]; then
            echo "✓ Successfully compiled $lang"
        else
            echo "✗ Failed to compile $lang"
        fi
    fi
done

echo "Done!"
