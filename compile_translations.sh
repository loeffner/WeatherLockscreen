#!/bin/bash
# Script to compile .po files to .mo files for KOReader plugin

# Requires gettext tools (msgfmt)
# Install on Ubuntu/Debian: sudo apt-get install gettext
# Install on macOS: brew install gettext

echo "Compiling translation files..."

# Create l10n directory if it doesn't exist
mkdir -p l10n

# Compile each .po file to .mo
for lang_dir in l10n/*/; do
    if [ -d "$lang_dir" ]; then
        po_file="${lang_dir}koreader.po"
        if [ -f "$po_file" ]; then
            # Get the language code (directory name)
            lang=$(basename "$lang_dir")

            # Output .mo file in same directory
            mo_file="${lang_dir}koreader.mo"

            echo "Compiling ${po_file} -> ${mo_file}"
            msgfmt -o "$mo_file" "$po_file"

            if [ $? -eq 0 ]; then
                echo "✓ Successfully compiled $lang"
            else
                echo "✗ Failed to compile $lang"
            fi
        fi
    fi
done

echo "Done!"
