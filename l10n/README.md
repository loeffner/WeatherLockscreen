# Localization Guide for WeatherLockscreen

## Overview

This plugin uses `.po`/`.mo` files for translations following the standard gettext format used by KOReader.

## File Structure

```
l10n/
├── template.pot     # Translation template (all translatable strings)
├── de.po           # German translation
├── de.mo           # Compiled German translation (generated)
├── fr.po           # French translation (if added)
└── ...
```

## How KOReader Plugin Localization Works

KOReader automatically loads plugin translations from the `l10n/` directory if:
1. The directory exists in your plugin folder
2. There's a `.mo` file matching the user's language code
3. You use `_()` to wrap strings in your code

The language code is determined by KOReader's `language` setting (e.g., `de`, `fr`, `es`).

## Adding a New Language

### 1. Create a `.po` file

Copy `template.pot` to a new file named after the language code:

```bash
cp l10n/template.pot l10n/fr.po
```

### 2. Edit the header

Update the header in the `.po` file:

```po
"Language: fr\n"
"Last-Translator: Your Name <your@email.com>\n"
```

### 3. Translate the strings

Find each `msgid` and add the translation in `msgstr`:

```po
msgid "Today"
msgstr "Aujourd'hui"

msgid "Tomorrow"
msgstr "Demain"
```

### 4. Compile to `.mo`

Run the compilation script:

```bash
./compile_translations.sh
```

Or manually with msgfmt:

```bash
msgfmt -o l10n/fr.mo l10n/fr.po
```

## Current Translation Status

- ✅ **German (de)**: Complete
- ⚠️ **Other languages**: Need contributors

## Strings That Are NOT in These Files

Some strings are already translated by other sources:

1. **Weather conditions** (e.g., "Partly cloudy", "Rainy")
   - Provided by WeatherAPI.com in user's language
   - No translation needed

2. **Day names** (e.g., "Monday", "Tuesday")
   - Provided by KOReader's `os.date()` function
   - Already localized by koreader

3. **Month abbreviations** (e.g., "Jan", "Feb")
   - Provided by KOReader's `os.date()` function
   - Already localized by koreader

## Testing Translations

1. Compile your translation: `./compile_translations.sh`
2. Copy plugin to KOReader
3. Change KOReader language to your target language:
   - Settings → Language → Select your language
4. Restart KOReader
5. Check the plugin menu and display screens

## Language Code Reference

Common KOReader language codes:

| Language | Code | Example File |
|----------|------|--------------|
| German | `de` | `de.po` |
| French | `fr` | `fr.po` |
| Spanish | `es` | `es.po` |
| Italian | `it_IT` | `it_IT.po` |
| Dutch | `nl_NL` | `nl_NL.po` |
| Polish | `pl` | `pl.po` |
| Portuguese (Portugal) | `pt_PT` | `pt_PT.po` |
| Portuguese (Brazil) | `pt_BR` | `pt_BR.po` |
| Russian | `ru` | `ru.po` |
| Chinese (Simplified) | `zh_CN` | `zh_CN.po` |
| Chinese (Traditional) | `zh_TW` | `zh_TW.po` |
| Japanese | `ja` | `ja.po` |
| Korean | `ko_KR` | `ko_KR.po` |

## Format Placeholders

Some strings have placeholders like `%1`, `%2` that get replaced at runtime:

```po
msgid "Location (%1)"
msgstr "Standort (%1)"

msgid "Page %1 of %2"
msgstr "Seite %1 von %2"
```

**Important**: Keep the placeholders in the translation! They maintain the order.

## Contributing Translations

1. Fork the repository
2. Add your language's `.po` file in `l10n/`
3. Compile it to ensure it works: `./compile_translations.sh`
4. Test in KOReader
5. Submit a Pull Request

Include both `.po` and `.mo` files in your PR.

## Extracting New Strings

If you add new translatable strings to the code:

1. Add them to `l10n/template.pot`
2. Add them to all existing `.po` files
3. Translate them
4. Recompile with `./compile_translations.sh`

Or use gettext tools to extract automatically:

```bash
xgettext --language=Lua --keyword=_ --from-code=UTF-8 \
  --output=l10n/template.pot \
  *.lua
```

## Tools

- **msgfmt**: Compile `.po` to `.mo`
- **msgmerge**: Update `.po` files with new strings from `.pot`
- **msginit**: Create new `.po` from `.pot` template
- **Poedit**: GUI editor for `.po` files (https://poedit.net/)

## Questions?

See KOReader's main localization docs or open an issue.
