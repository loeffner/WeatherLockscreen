# Weather Lockscreen Plugin for KOReader

A comprehensive KOReader plugin that displays beautiful weather information on your device's sleep screen.

![Beautiful Weather Lockscreen](resources/beautiful.jpg)

![License](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)
![KOReader](https://img.shields.io/badge/KOReader-Plugin-orange.svg)
![GitHub last commit (branch)](https://img.shields.io/github/last-commit/loeffner/WeatherLockscreen/main)
![GitHub Release](https://img.shields.io/github/v/release/loeffner/WeatherLockscreen)
![GitHub Downloads](https://img.shields.io/github/downloads/loeffner/WeatherLockscreen/total)


## Features

- **Real-time Weather Data** - Displays current weather conditions with icons, temperature, and detailed descriptions
- **Several Display Formats** - Choose from multiple layout options to suit your preferences
- **Active Sleep** - The device will temporarily wake up from sleep to refresh data if enabled (Kindle only).
- **Easy Configuration** - Configure settings via main menu, no need to edit source code
- **Smart Caching** - Automatic caching with configurable expiration
- **Offline Support** - Uses cached data when internet connection is unavailable

## Installation

1. Download the latest release from the [Releases](https://github.com/loeffner/WeatherLockscreen/releases) page
2. Extract the `weatherlockscreen.koplugin` folder
3. Copy it to your KOReader plugins directory:
   - **Kindle**: `/mnt/us/koreader/plugins/`
   - **Kobo**: `/mnt/onboard/.adds/koreader/plugins/`
   - **Android**: `/sdcard/koreader/plugins/`
4. Restart KOReader

## Configuration

### Initial Setup

<table>
  <tr>
    <td valign="top">
      <ol>
        <li>Navigate to <b>Tools &gt; Weather Lockscreen</b></li>
        <li>Configure the following:
          <ul>
            <li><b>Location</b>: Enter your location (city name, airport code, us postal code, or coordinates)
              <br><i>Examples: "London", "MUC", "10001", "48.8567,2.3508"</i>
              <br>You will see a list of search results. Select your location.
            </li>
            <li><b>Temperature Scale</b>: Choose Celsius (°C) or Fahrenheit (°F)</li>
            <li><b>Display Format</b>: Select your layout</li>
          </ul>
        </li>
        <li>Navigate to <b>Settings &gt; Screen  &gt;  Sleep Screen  &gt;  Wallpaper </b></li>
          <ul>
            <li><a href="https://github.com/koreader/koreader/issues/14098">KOReader's "Sleep Screen" option is only exposed if you have ads disabled</a>.</li>
          </ul>
        <li>Select <b>"Show weather on sleep screen" </b></li>
      </ol>
    </td>
    <td valign="top" width="220">
      <img src="resources/settings_where_to_find.png" width="300"><br>
      <img src="resources/settings.png" width="300"><br>
      <img src="resources/sleep_screen_settings.png" width="300">
    </td>
  </tr>
</table>

## Display Modes

The plugin offers several display formats to customize your lockscreen:

<table>
  <tr>
    <td align="center">
      <strong>Detail Display</strong><br>
      <img src="resources/detail.jpg" width="300">
    </td>
    <td align="center">
      <strong>Minimal Display</strong><br>
      <img src="resources/minimal.jpg" width="300">
    </td>
  </tr>
  <tr>
      <td align="center">
      <strong>Cover Display</strong><br>
      <img src="resources/cover.jpg" width="300">
    </td>
    <td align="center">
      <strong>Retro Analog Display</strong><br>
      <img src="resources/retro_analog.jpg" width="300">
    </td>
  </tr>
  <tr>
    <td align="center">
      <strong>Night Owl Display</strong><br>
      <img src="resources/night_owl.jpg" width="300">
    </td>
    <td></td>
  </tr>
</table>

## Active Sleep and Dashboard

### Active Sleep (Kindle Only)
Since version 0.9.4, the plugin supports updating weather data while the device is locked and sleeping.
To enable this feature:
1. Go to the plugin settings via <b>Tools &gt; Weather Lockscreen</b>
2. Enable the <b>"Active Sleep"</b> option by setting an interval.

#### Additional requirements:
- Only supported on Kindle devices.
- `Settings > Network > "Action when Wi-Fi is off"` must be set to `Turn on`.

#### How it works:
- The device will wake up from sleep at the specified interval to refresh weather data.
- After updating, the device will return to sleep mode automatically.
- This feature is only available on Kindle devices (because Kobo and Android devices handle sleep differently and I do not have the devices to test on.)
- This feature will increase battery consumption slightly, depending on the interval set. However, the device will still spend most of the time in sleep mode.

## Dasboard
For devices that do not support `Active Sleep`, you can use the Dashboard feature to show live weather data.
To enable this feature:
1. Go to the plugin settings via `Tools > Weather Lockscreen`
2. Enable the `Dashboard` option by setting an interval.
3. Long press `Dashboard` to show the dashboard. You can also set a gesture in `Settings > Taps & Gestures > Gesture Manager`. The WeatherLockscreen gesture can be found in the `General` section.

#### How it works:
- The dashboard is a full screen widget that shows live weather data.
- Backlight will be disabled, but the touchscreen will remain active.
- To dismiss the dashboard, tap the screen.
- This feature works on all devices, including Kindle, Kobo, and Android.
- This feature will consume more battery than `Active Sleep`, as the screen will remain on while the dashboard is displayed.

## API Information

The plugin uses [WeatherAPI.com](https://www.weatherapi.com/)'s forecast endpoint. \
It uses my account and API Key. Please be responsible, otherwise I can not sustain this plugin. \
You can create your own account and API key at [WeatherAPI.com](https://www.weatherapi.com/).
The free tier allows 1 000 000 API calls per month.

<a href="https://www.weatherapi.com/" title="Free Weather API"><img src='https://cdn.weatherapi.com/v4/images/weatherapi_logo.png' alt="Weather data by WeatherAPI.com" border="0"></a>

## Localization

The plugin supports multiple languages through a hybrid localization approach:

### What Gets Translated and How

1. **Weather Conditions** - Automatically translated by WeatherAPI in 40+ languages (see list below)
2. **Day/Month Names** and a few other common words/phrases - Use KOReader's system localization
3. **Plugin UI Strings** - Menu items, settings, and display labels are translated via `.po` files

### Current Translation Status

**Fully Translated Languages:**
- 🇩🇪 German (de) - Complete
- 🇪🇸 Spanish (es) - Complete by @jeubm

**English (en)** - Default language (no translation needed)

### Contributing Translations

I welcome translation contributions! The plugin uses standard gettext `.po` files for localization.
If you want to contribute, but don't know how, feel free to open an issue.

<details>
<summary>Supported languages by WeatherAPI</summary>

    ar = "ar",         -- Arabic
    bg_BG = "bg",      -- Bulgarian
    bn = "bn",         -- Bengali
    cs = "cs",         -- Czech
    da = "da",         -- Danish
    de = "de",         -- German
    el = "el",         -- Greek
    es = "es",         -- Spanish
    fi = "fi",         -- Finnish
    fr = "fr",         -- French
    hi = "hi",         -- Hindi
    hu = "hu",         -- Hungarian
    it_IT = "it",      -- Italian
    ja = "ja",         -- Japanese
    ko_KR = "ko",      -- Korean
    nl_NL = "nl",      -- Dutch
    pl = "pl",         -- Polish
    pt_PT = "pt",      -- Portuguese
    pt_BR = "pt",      -- Portuguese (WeatherAPI only supports one pt variant. I think, its better to use it than to default to english)
    ro = "ro",         -- Romanian
    ro_MD = "ro",      -- Romanian (WeatherAPI only supports one ro variant. I think, its better to use it than to default to english)
    ru = "ru",         -- Russian
    si = "si",         -- Sinhalese
    sk = "sk",         -- Slovak
    sr = "sr",         -- Serbian
    sv = "sv",         -- Swedish
    ta = "ta",         -- Tamil
    te = "te",         -- Telugu
    tr = "tr",         -- Turkish
    uk = "uk",         -- Ukrainian
    ur = "ur",         -- Urdu
    vi = "vi",         -- Vietnamese
    zh_CN = "zh",      -- Chinese Simplified
    zh_TW = "zh_tw",   -- Chinese Traditional
</details>


## Customization

<details>
<summary>Displayed hours in "Detailed" display</summary>

You can find a user patch to modify the hours here:
[2-weather-detailed-view-hours.lua](https://github.com/loeffner/KOReader.patches?tab=readme-ov-file#-2-weather-detailed-view-hourslua)
</details>

<details>
<summary>Fallback Icons (sun/moon)</summary>

You can customize the fallback sun/moon icons:

1. Create or download `sun.svg` and `moon.svg` icons
2. Place them in `<koreader_data_dir>/icons/`
3. The plugin will use these icons when weather data is unavailable
</details>

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Work in Progress for 0.9.4
<details>
<summary>Done</summary>


- Periodically refresh the lockscreen (its not easy, let me tell you that!)
- Attempt connecting to wifi: See #1
</details>

<details>
<summary>In progress</summary>
</details>

<details>
<summary>Backlog</summary>

- More display modes: I am always open for requests.
- A transparent display mode (either transparent image over weather or transparent weather over image)
- Fallback: A more configurable fallback, when no weather data is available.
</details>

## Related Projects

- [KOReader](https://github.com/koreader/koreader) - The main KOReader project
- [WeatherAPI.com](https://www.weatherapi.com/) - Weather data provider
- [roygbyte/weather.koplugin](https://github.com/roygbyte/weather.koplugin/) - Inspiration for this project
- [svgrepo.com](https://www.svgrepo.com/) - Provider of the arrows for the wind direction in the Retro Analog view

### My user patches

- [loeffner/KOReader.patches](https://github.com/loeffner/KOReader.patches)


## Author

**Andreas Lösel**

## License

This project is licensed under the GNU Affero General Public License v3.0 - see the [LICENSE](LICENSE) file for details.
