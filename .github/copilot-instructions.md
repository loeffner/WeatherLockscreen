# GitHub Copilot Instructions for WeatherLockscreen

## Project Overview
WeatherLockscreen is a KOReader plugin that displays weather information on e-reader sleep screens. It's written in Lua and integrates with KOReader's widget system to create custom lockscreen displays. The plugin supports multiple display modes, periodic refresh features, and multi-language localization.

## Technology Stack
- **Language**: Lua
- **Platform**: KOReader (e-reader framework)
- **API**: WeatherAPI.com (forecast endpoint)
- **UI Framework**: KOReader widget system (ImageWidget, TextWidget, containers, etc.)
- **Localization**: gettext (.po/.mo files)

## Architecture

### Core Modules
1. **main.lua**: Plugin entry point, screensaver patching, event handlers, settings initialization
2. **weather_menu.lua**: Menu system and UI dialogs for settings
3. **weather_api.lua**: API fetching, JSON parsing, data processing
4. **weather_utils.lua**: Utility functions for caching, icons, time formatting, localization, device detection
5. **weather_dashboard.lua**: Full-screen dashboard mode with periodic refresh
6. **display_*.lua**: Display mode implementations (default, card, nightowl, retro, reading)
7. **display_helper.lua**: Shared display utilities
8. **_meta.lua**: Plugin metadata (name, version, description)

### Key Design Patterns
- **Display Strategy Pattern**: Each display mode is a separate module with a `create(weather_lockscreen, weather_data)` function
- **Widget Composition**: UI built using nested widget containers (VerticalGroup, HorizontalGroup, OverlapGroup, etc.)
- **Dynamic Scaling**: Content scales to fit different screen sizes using DPI-independent base sizes and calculated scale factors
- **Two-Tier Caching**: Minimum delay between API calls + configurable max cache age for offline use
- **Safe Network Wrapper**: All network calls wrapped in pcall to prevent crashes

## Code Style & Conventions

### Lua Best Practices
- Use `local` for all variables and functions unless global scope is required
- Follow KOReader naming conventions: snake_case for variables/functions
- Comment blocks use `--[[  ]]` format with module description
- Inline comments use `--` prefix
- Always check for nil before accessing nested tables: `if data and data.current and data.current.field then`

### Widget Creation Pattern
```lua
local widget = WidgetType:new {
    property = value,
    nested_widget = OtherWidget:new { ... }
}
```

### Scaling Pattern for Display Modes
```lua
-- Define base sizes (DPI-independent)
local base_font_size = 24
local base_icon_size = 100

-- Function to build content with scale factor
local function buildContent(scale_factor)
    local font_size = math.floor(base_font_size * scale_factor)
    local icon_size = math.floor(base_icon_size * scale_factor)
    -- ... build widgets with scaled sizes
    return VerticalGroup:new { ... }
end

-- Measure content and calculate optimal scale
local content = buildContent(1.0)
local content_height = content:getSize().h
-- ... calculate scale based on available_height
-- Rebuild if needed: content = buildContent(new_scale)
```

## Important Implementation Details

### Settings System
All settings are prefixed with `weather_` and initialized in `main.lua:initDefaultSettings()`:

```lua
-- Core settings
weather_location           -- Location string (lat,lon coordinates e.g., "48.8567,2.3508")
weather_location_name      -- Display name for location (e.g., "Paris")
weather_temp_scale         -- "C" or "F"
weather_display_style      -- "default", "card", "nightowl", "retro", "reading"

-- Display settings
weather_show_header        -- boolean, show location/timestamp bar (default: true via nilOrTrue)
weather_override_scaling   -- boolean, enable manual scaling
weather_fill_percent       -- 30-130, content fill percentage (stored as string)
weather_cover_scaling      -- "fit" or "zoom" (for reading mode)

-- Cache settings
weather_cache_max_age      -- seconds (default: 3600 = 1 hour), max cache age for offline
weather_min_update_delay   -- seconds (default: 1800 = 30 min), min time between API calls

-- Periodic refresh settings
weather_periodic_refresh_rtc       -- 0 (off) or interval in seconds
weather_periodic_refresh_dashboard -- 0 (off) or interval in seconds
weather_active_sleep_min_battery   -- 0-100, stop RTC refresh below this battery % (default: 20)

-- Debug settings
weather_debug_options      -- boolean, show advanced options in menu
```

### Weather Data Structure
The processed weather data (from `WeatherAPI:processWeatherData()`) has this structure:
```lua
{
    lang = "en",  -- Language code used for API request
    is_cached = false,  -- Whether data is from cache (set after loading)
    current = {
        icon_path = "/path/to/cached/icon.png",
        temp_c = 20,           -- Raw temperature in Celsius (number)
        temp_f = 68,           -- Raw temperature in Fahrenheit (number)
        condition = "Partly cloudy",
        location = "London",
        timestamp = "2024-11-18 14:30",  -- API localtime string
        feelslike_c = 18,
        feelslike_f = 64,
        humidity = "65%",
        wind = "15 km/h",
        wind_dir = "NW"
    },
    hourly_today_all = {
        {hour="6:00 AM", hour_num=6, icon_path="...", temp_c=15, temp_f=59, condition="..."},
        -- ... all 24 hours
    },
    hourly_tomorrow_all = { ... },  -- Same structure as hourly_today_all
    forecast_days = {
        {day_name="Today", icon_path="...", high_c=20, high_f=68, low_c=10, low_f=50, condition="..."},
        {day_name="Tomorrow", ...},
        -- Up to 3 days
    },
    astronomy = {
        sunrise = "06:30 AM",
        sunset = "06:45 PM",
        moonrise = "08:15 PM",
        moonset = "07:30 AM",
        moon_phase = "Full Moon"
    }
}
```

**Temperature Formatting**: Use `WeatherUtils` helper functions to format temperatures based on user settings:
- `WeatherUtils:getCurrentTemp(weather_data, with_unit)` - Format current temp
- `WeatherUtils:getHourlyTemp(hour_data, with_unit)` - Format hourly temp
- `WeatherUtils:getForecastHighLow(day_data)` - Format "high° / low°" string
- `WeatherUtils:getTempValue(weather_data)` - Get raw number for calculations

### Settings Management
- Settings stored via `G_reader_settings:readSetting()` and `G_reader_settings:saveSetting()`
- Always call `G_reader_settings:flush()` after saving
- Use `G_reader_settings:nilOrTrue()` for boolean settings that default to true
- All settings initialized with defaults on first run via `initDefaultSettings()`

### Screen Dimensions & Scaling
- Get screen size: `Screen:getWidth()`, `Screen:getHeight()`, `Screen:getSize()`
- Scale by DPI: `Screen:scaleBySize(pixels)`
- Widgets have `getSize()` method returning `{w=width, h=height}`

### Icon Management
- Weather icons downloaded from API and cached in `DataStorage:getDataDir() .. "/cache/weather-icons/"`
- Fallback icons (sun/moon) in `DataStorage:getDataDir() .. "/icons/"`
- Moon phase icons in `DataStorage:getDataDir() .. "/icons/moonphases/"`
- Wind direction arrows in `DataStorage:getDataDir() .. "/icons/arrows/"`
- SVG format supported via ImageWidget with `alpha = true`

### Localization
- Plugin uses custom gettext loader: `require("l10n/gettext")`
- The custom gettext proxies KOReader's gettext, loading plugin translations first then falling back to KOReader's
- Translation files in `l10n/` directory: `template.pot`, `de/`, `es/`
- User-facing strings wrapped with `_("Text")`
- For formatted strings: `local T = require("ffi/util").template` then `T(_("Format %1"), value)`
- Dynamic strings (moon phases, setting values) also need entries in .po files
- Weather conditions from API include localized text based on language setting
- Language mapping from KOReader locale to WeatherAPI lang code in `WeatherUtils.lang_map`

### HTTP Requests (Safe Pattern)
```lua
local ltn12 = require("ltn12")
local sink_table = {}

-- Always use pcall wrapper for network operations
local success, result = pcall(function()
    local code, err = http_request_code(url, sink_table)
    if code == 200 then
        return table.concat(sink_table)
    end
    return nil, code
end)

if success and result then
    -- Process response
end
```

## Periodic Refresh Features

### Dashboard Mode
- Full-screen weather display that refreshes periodically
- Works on all devices
- Uses `UIManager:scheduleIn()` for refresh timing
- Tap to dismiss
- Higher battery consumption (device stays awake)

### Active Sleep Mode (RTC)
- Device wakes from sleep to update weather, then goes back to sleep
- Lower battery consumption than dashboard
- **Kindle**: Fully supported via WakeupMgr and device's RTC
- **Kobo**: Supported (uses WakeupMgr)
- **Other devices**: Not supported
- Battery saver: Stops when battery falls below configurable threshold (default 20%)
- Requires `wifi_enable_action` set to "turn_on" in KOReader settings

### Device Detection
```lua
local Device = require("device")
Device:isKindle()  -- Check if Kindle
Device:isKobo()    -- Check if Kobo
Device:hasWifiToggle()  -- Check for WiFi capability
```

## Common Tasks

### Adding a New Display Mode
1. Create `display_<name>.lua` with `create(weather_lockscreen, weather_data)` function
2. Add menu entry in `weather_menu.lua:getDisplayStyleMenuItem()`
3. Follow scaling pattern: define base sizes, build function, measure, rescale
4. Return an OverlapGroup or CenterContainer widget
5. Consider adding conditional menu items (like cover scaling for reading mode)

### Modifying Weather Data Processing
1. Edit `weather_api.lua:processWeatherData()` to extract new fields from API response
2. Update weather data structure documentation
3. Consider cache invalidation if data format changes significantly

### Adding New Settings
1. Add default value in `main.lua:initDefaultSettings()`
2. Add menu item in appropriate function in `weather_menu.lua`
3. Use `checked_func` for radio/checkbox items
4. Use `text_func` for dynamic labels showing current value
5. Save with `G_reader_settings:saveSetting()` and flush
6. Set `keep_menu_open = true` for inline updates
7. Use `touchmenu_instance:updateItems()` to refresh menu after changes
8. For debug-only options, check `G_reader_settings:isTrue("weather_debug_options")`

### Adding New Localized Strings
1. Add `_("String")` in code
2. Add entry in `l10n/template.pot`
3. Add translations in `l10n/de/koreader.po` and `l10n/es/koreader.po`
4. Run `msgfmt` to compile `.mo` files
5. For dynamic strings (like setting values), add entries even if they're not literal in code

### Working with Fonts
- Standard fonts: `"cfont"` (content), `"ffont"` (fixed-width/monospace)
- Get font face: `Font:getFace("cfont", size)` or `Font:getFace("cfont", size, bold)`
- Use `bold = true` in TextWidget for emphasis

### Working with Colors
- Available via `Blitbuffer.COLOR_*` constants
- Common: `COLOR_WHITE`, `COLOR_BLACK`, `COLOR_GRAY`, `COLOR_DARK_GRAY`, `COLOR_LIGHT_GRAY`
- Numbered grays: `COLOR_GRAY_3` through `COLOR_GRAY_E` (darker to lighter)
- Use `fgcolor` in TextWidget, `background` in FrameContainer

## Testing & Debugging

### Debug Mode
- Toggle via searching "debug on" or "debug off" in location search
- When enabled, shows additional options in menu:
  - Minimum cache duration setting
  - Custom interval options for Dashboard/Active Sleep

### Logging
```lua
local logger = require("logger")
logger.dbg("WeatherLockscreen: Debug message", variable)
logger.warn("WeatherLockscreen: Warning message")
logger.info("WeatherLockscreen: Info message")
```

### Common Issues
- **Widget not displaying**: Check returned widget has proper dimen (dimensions)
- **Layout broken**: Verify widget nesting (VerticalGroup needs vertical widgets, HorizontalGroup needs horizontal alignment)
- **Scaling issues**: Ensure base sizes are DPI-independent and scale factor applied consistently
- **Cache problems**: Clear cache via menu or delete files in cache directory
- **API failures**: Check logger for HTTP response codes and error messages
- **Crash on network error**: Ensure all network calls use pcall wrapper

## Plugin Conventions

### Dispatcher Actions
The plugin registers actions that can be bound to gestures:
- `weather_dashboard_toggle` - Toggle dashboard mode on/off
- `weather_clear_cache` - Clear cached weather data and icons

### Menu Structure
- Top level: `Tools > Weather Lockscreen`
- Use separators (`separator = true`) to group related settings
- Use `sub_item_table` for static nested menus
- Use `sub_item_table_func` for dynamic nested menus
- Use `callback` for actions, `checked_func` for toggles

### File Organization
- Icons: `icons/` directory (bundled with plugin)
- Translations: `l10n/` directory
- Cache: `DataStorage:getDataDir()/cache/weather-icons/`
- Plugin directory obtained via: `debug.getinfo(2, "S").source:gsub("^@(.*)/[^/]*", "%1")`

### API Usage Guidelines
- Respect minimum delay between API calls (configurable, default 30 min)
- Use cached data when available and not expired
- Default max cache age: 1 hour (configurable 1-24h)
- Show asterisk (*) in timestamp when displaying cached data
- Include error handling for network failures

## Dependencies & Compatibility
- Requires KOReader with screensaver support
- Uses socket.http or ssl.https for HTTPS requests
- Requires JSON library for API response parsing
- Compatible with devices that support custom screensavers (ads must be disabled)

## Key Classes and Modules

### WeatherLockscreen (main.lua)
The main plugin class extending `WidgetContainer`:
- `init()` - Plugin initialization, patches screensaver, registers menu
- `createWeatherWidget()` - Creates the display widget based on current style
- `schedulePeriodicRefresh()` - Sets up RTC wakeup for active sleep
- `onSuspend()` / `onResume()` - Handle device sleep/wake events
- `patchScreensaver()` - Hooks into KOReader's Screensaver.show()
- `patchDofile()` - Injects "weather" option into screensaver menu

### WeatherAPI (weather_api.lua)
Handles all API communication:
- `fetchWeatherData(weather_lockscreen)` - Main fetch with caching logic
- `processWeatherData(result)` - Transforms API response to internal format
- `searchLocations(query, api_key)` - Location search for settings
- `getIconPath(icon_url)` - Downloads and caches weather icons

### WeatherUtils (weather_utils.lua)
Utility functions:
- Temperature: `formatTemp()`, `getCurrentTemp()`, `getHourlyTemp()`, `getForecastHighLow()`
- Caching: `saveWeatherCache()`, `loadWeatherCache()`, `clearCache()`
- Icons: `installIcons()`, `getMoonPhaseIcon()`, `getPluginDir()`
- Network: `safeGoOnlineToRun()`, `wifiEnableActionTurnOn()`
- Device: `canScheduleWakeup()`, `getBatteryCapacity()`, `toggleSuspend()`
- Time: `formatHourLabel()`, `koLangAsWeatherAPILang()`

### WeatherDashboard (weather_dashboard.lua)
Manages dashboard mode:
- `start(weather_lockscreen)` - Starts dashboard, prevents sleep
- `stop(weather_lockscreen)` - Stops dashboard, allows sleep
- `showWidget(weather_lockscreen)` - Creates and displays dashboard widget
- `scheduleNextRefresh()` - Schedules periodic refresh
- `scheduleAutosuspendReset()` - Broadcasts InputEvent to prevent Kindle auto-suspend

### DisplayHelper (display_helper.lua)
Shared display utilities:
- `createHeaderWidgets()` - Location and timestamp bar
- `createFallbackWidget()` - Sun/moon icon when no data
- `createLoadingWidget()` - Hourglass icon during fetch

## Contributing Guidelines
- Maintain backward compatibility with existing settings
- Test on different screen sizes/DPI settings
- Preserve user's custom icons (check existence before copying bundled icons)
- Add localization support for new user-facing strings
- Follow existing code structure and naming patterns
- Document new features in README.md
- Initialize new settings in `initDefaultSettings()`

## Special Considerations

### E-Reader Display Characteristics
- E-ink displays: slow refresh, grayscale only
- Consider dithering for image rendering
- Keep layouts simple and high-contrast
- Minimize widget nesting for better performance

### Night Mode Support
- Some displays invert colors in night mode
- Use `G_reader_settings:isTrue("night_mode")` to detect
- Set `original_in_nightmode` appropriately for ImageWidgets
- Use `invert` property on FrameContainer when needed

### Twelve Hour Clock
- Check `G_reader_settings:isTrue("twelve_hour_clock")`
- Format times appropriately: "3:00 PM" vs "15:00"
- Use `WeatherUtils:formatHourLabel(hour, twelve_hour_clock)` for consistency

### WiFi Management
- Check `Device:hasWifiToggle()` for capability
- Use `WeatherUtils:wifiEnableActionTurnOn()` to check if WiFi auto-on is configured
- Use `WeatherUtils:safeGoOnlineToRun(callback, fallback, suppress_messages, call_after_wifi_action)` for safe network operations
- Active Sleep requires WiFi to be available
