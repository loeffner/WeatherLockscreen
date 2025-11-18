# GitHub Copilot Instructions for WeatherLockscreen

## Project Overview
WeatherLockscreen is a KOReader plugin that displays weather information on e-reader sleep screens. It's written in Lua and integrates with KOReader's widget system to create custom lockscreen displays.

## Technology Stack
- **Language**: Lua
- **Platform**: KOReader (e-reader framework)
- **API**: WeatherAPI.com (forecast endpoint)
- **UI Framework**: KOReader widget system (ImageWidget, TextWidget, containers, etc.)

## Architecture

### Core Modules
1. **main.lua**: Plugin entry point, menu system, screensaver patching
2. **weather_api.lua**: API fetching, JSON parsing, data processing
3. **weather_utils.lua**: Utility functions for caching, icons, time formatting, localization
4. **display_*.lua**: Display mode implementations (default, card, nightowl, retro, reading)

### Key Design Patterns
- **Display Strategy Pattern**: Each display mode is a separate module with a `create(weather_lockscreen, weather_data)` function
- **Widget Composition**: UI built using nested widget containers (VerticalGroup, HorizontalGroup, OverlapGroup, etc.)
- **Dynamic Scaling**: Content scales to fit different screen sizes using DPI-independent base sizes and calculated scale factors
- **Caching System**: Two-tier caching (30min min delay for API calls, configurable max age for data)

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

### Weather Data Structure
The processed weather data has this structure:
```lua
{
    lang = "en",  -- Language code
    is_cached = false,  -- Whether data is from cache
    current = {
        icon_path = "/path/to/icon.png",
        temperature = "20°C",
        condition = "Partly cloudy",
        location = "London",
        timestamp = "2024-11-18 14:30",
        feels_like = "18°C",
        humidity = "65%",
        wind = "15 km/h",
        wind_dir = "NW"
    },
    hourly_today_all = { {hour="6:00", hour_num=6, icon_path="...", temperature="15°", condition="..."}, ... },
    hourly_tomorrow_all = { ... },
    forecast_days = { {day_name="Today", icon_path="...", high_low="20° / 10°", condition="..."}, ... },
    astronomy = { sunrise="06:30", sunset="18:45", moon_phase="Full Moon", ... }
}
```

### Settings Management
- Settings stored via `G_reader_settings:readSetting()` and `G_reader_settings:saveSetting()`
- Always call `G_reader_settings:flush()` after saving
- Use `G_reader_settings:nilOrTrue()` for boolean settings that default to true

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
- Use `require("gettext")` and wrap user-facing strings with `_("Text")`
- For formatted strings: `local T = require("ffi/util").template` then `T(_("Format %1"), value)`
- Day names: Use KOReader's localized `os.date("%A")` when `WeatherUtils:shouldTranslateWeather()` is true
- Weather conditions from API include localized text based on language setting

### HTTP Requests
```lua
local ltn12 = require("ltn12")
local sink_table = {}
local code, err = http_request_code(url, sink_table)
if code == 200 then
    local response = table.concat(sink_table)
    -- Process response
end
```

## Common Tasks

### Adding a New Display Mode
1. Create `display_<name>.lua` with `create(weather_lockscreen, weather_data)` function
2. Add menu entry in `main.lua:getSubMenuItems()` under "Display Style" submenu
3. Follow scaling pattern: define base sizes, build function, measure, rescale
4. Return an OverlapGroup or CenterContainer widget
5. Consider adding conditional menu items (like cover scaling for reading mode)

### Modifying Weather Data Processing
1. Edit `weather_api.lua:processWeatherData()` to extract new fields from API response
2. Update weather data structure documentation
3. Consider cache invalidation if data format changes significantly

### Adding New Settings
1. Add menu item in `main.lua:getSubMenuItems()`
2. Use `checked_func` for radio/checkbox items
3. Use `text_func` for dynamic labels showing current value
4. Save with `G_reader_settings:saveSetting()` and flush
5. Set `keep_menu_open = true` for inline updates
6. Use `touchmenu_instance:updateItems()` to refresh menu after changes

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

## Plugin Conventions

### Menu Structure
- Top level: `Tools > Weather Lockscreen`
- Use separators (`separator = true`) to group related settings
- Use `sub_item_table` for nested menus
- Use `callback` for actions, `checked_func` for toggles

### File Organization
- Icons: `icons/` directory (bundled with plugin)
- Cache: DataStorage directory (user data)
- Plugin directory obtained via: `debug.getinfo(2, "S").source:gsub("^@(.*)/[^/]*", "%1")`

### API Usage Guidelines
- Respect 30-minute minimum between API calls
- Use cached data when available and not expired
- Default cache duration: 1 hour (configurable 1-24h)
- Show asterisk (*) in timestamp when displaying cached data
- Include error handling for network failures

## Dependencies & Compatibility
- Requires KOReader with screensaver support
- Uses socket.http or ssl.https for HTTPS requests
- Requires JSON library for API response parsing
- Compatible with devices that support custom screensavers (ads must be disabled)

## Contributing Guidelines
- Maintain backward compatibility with existing settings
- Test on different screen sizes/DPI settings
- Preserve user's custom icons (check existence before copying bundled icons)
- Add localization support for new user-facing strings
- Follow existing code structure and naming patterns
- Document new features in README.md

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
