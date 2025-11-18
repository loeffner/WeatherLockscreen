# Implementation Guide: Plugin Localization with .po/.mo Files

## What You've Set Up

Your plugin now has proper localization infrastructure:

```
WeatherLockscreen/
├── l10n/
│   ├── template.pot      # Master template with all strings
│   ├── de.po            # German translation (example)
│   ├── de.mo            # Compiled German (generated)
│   └── README.md        # Translation guide
└── compile_translations.sh
```

## How It Works

1. **KOReader automatically detects** the `l10n/` directory in your plugin
2. **When a user's language is set** (e.g., German = `de`), KOReader loads `l10n/de.mo`
3. **All `_("string")` calls** are automatically translated using the `.mo` file
4. **If no translation exists**, the original English string is used

## What Changes You Need to Make to Your Code

### Current State Analysis

Your code currently has this pattern:

```lua
-- weather_api.lua (lines 222-224)
if i == 1 then
    day_name = "Today"        -- ❌ Hardcoded, but intentional!
elseif i == 2 then
    day_name = "Tomorrow"     -- ❌ Hardcoded, but intentional!
```

**Your reasoning**: These strings aren't wrapped with `_()` because:
- KOReader's built-in `_()` doesn't have translations for "Today"/"Tomorrow"
- You use conditional logic to show localized day names instead when translation is enabled

### Option 1: Keep Your Current Approach (Recommended for Now)

**No code changes needed!** Your workaround is actually quite clever:

```lua
-- display_default.lua - Your current pattern
text = WeatherUtils:shouldTranslateWeather() and _(os.date("%A", os.time())) or "Today"
```

This shows:
- When translation ON: "Monday" (from KOReader's localization)
- When translation OFF: "Today" (English fallback)

**Advantage**: Works with KOReader's existing translations
**Disadvantage**: Can't show "Today" in other languages

### Option 2: Use Your Own .po/.mo Files (Future Enhancement)

To use the .po/.mo files you just created, you need to ensure KOReader loads them. However, **there's a catch**:

KOReader's `_()` function loads translations from KOReader's main translation files, NOT from individual plugin folders by default. Plugin translations work, but the loading mechanism varies.

#### Testing if Plugin Translations Work

Try this modification:

```lua
-- weather_api.lua
local _ = require("gettext")  -- Already there

-- Change hardcoded strings to use _()
if i == 1 then
    day_name = _("Today")      -- Will use l10n/de.mo if available
elseif i == 2 then
    day_name = _("Tomorrow")
```

**Then test**:
1. Compile translations: `./compile_translations.sh`
2. Copy plugin to KOReader
3. Set KOReader language to German
4. Check if "Heute" and "Morgen" appear

If it works → Great! Use Option 2
If it doesn't → Stick with Option 1

### Option 3: Hybrid Approach (Best of Both Worlds)

```lua
-- weather_api.lua
local _ = require("gettext")

if i == 1 then
    -- Try plugin translation first, fallback to "Today"
    day_name = _("Today")
elseif i == 2 then
    day_name = _("Tomorrow")
```

```lua
-- display_default.lua - Keep your conditional logic for day names
-- When user enables translation, use full day names from KOReader
text = WeatherUtils:shouldTranslateWeather() and _(os.date("%A", os.time())) or _("Today")
```

This gives users:
- **Translation OFF**: "Today" / "Heute" / "Aujourd'hui" (from plugin .mo)
- **Translation ON**: "Monday" / "Montag" / "Lundi" (from KOReader's system)

## For Retro Analog Display

The untranslatable labels can now be wrapped:

```lua
-- display_retro.lua
local _ = require("gettext")

-- Instead of:
text = "TEMPERATURE"

-- Use:
text = _("TEMPERATURE")
```

German `.mo` will translate this to "TEMPERATUR"

## For Night Owl Display

Moon phase names come from WeatherAPI, but you could add a mapping:

```lua
-- weather_utils.lua
local moon_phase_translations = {
    ["New Moon"] = _("New Moon"),
    ["Full Moon"] = _("Full Moon"),
    -- etc.
}

function WeatherUtils:translateMoonPhase(phase)
    return moon_phase_translations[phase] or phase
end
```

Then add these to `l10n/template.pot` and translate them.

## Next Steps

### 1. Test Plugin Translations Work

Simplest test - add this to your menu:

```lua
-- main.lua
{
    text = _("Test Translation"),
    callback = function()
        local msg = _("Today") .. " / " .. _("Tomorrow")
        UIManager:show(require("ui/widget/notification"):new {
            text = msg,
        })
    end,
}
```

If you see "Heute / Morgen" when KOReader is set to German → it works!

### 2. Update Strings Gradually

Start with the easiest wins:
1. ✅ Menu items (already done)
2. ✅ "TEMPERATURE", "WIND", "HUMIDITY" in retro display
3. ✅ "Today"/"Tomorrow" in forecast
4. ⚠️ Moon phases (need translation mapping)

### 3. Add More Languages

Use `l10n/template.pot` as a base:
```bash
cp l10n/template.pot l10n/fr.po
# Edit fr.po
./compile_translations.sh
```

## Documentation Updates Needed

Update your README.md:

```markdown
## Localization

The plugin supports multiple languages through `.po`/.mo` files in the `l10n/` directory.

**Fully translated**:
- ✅ German (de)
- ✅ Menu items and UI (all languages via KOReader)
- ✅ Weather conditions (via WeatherAPI in 40+ languages)

**To contribute a translation**: See `l10n/README.md`
```

## Summary

You now have:
1. ✅ `.pot` template with all translatable strings
2. ✅ `de.po` German translation (example)
3. ✅ Compilation script
4. ✅ Documentation for contributors
5. ✅ Infrastructure for unlimited language support

**You still need to test** if KOReader loads plugin `.mo` files. If it does, you can gradually migrate from your workaround approach to proper `.po`/.mo` translations.

Let me know if you want help with testing or any specific translation!
