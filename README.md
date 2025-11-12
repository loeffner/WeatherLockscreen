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
            </li>
            <li><b>Temperature Scale</b>: Choose Celsius (°C) or Fahrenheit (°F)</li>
            <li><b>Display Format</b>: Select your layout</li>
          </ul>
        </li>
        <li>Navigate to <b>Settings &gt; Screen  &gt;  Sleep Screen  &gt;  Wallpaper </b></li>
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

## How It Works

1. **Data Fetching**: Weather data is automatically fetched from WeatherAPI.com when your device enters sleep mode
2. **Caching**: Data is cached locally for a configurable amount of time (1h - 24h)
3. **Offline Mode**: If the API request fails or no internet connection is available, the plugin uses cached data
4. **Fallback Display**: If no cached data is available, displays a sun/moon icon based on the current time of day

## API Information

The plugin uses [WeatherAPI.com](https://www.weatherapi.com/)'s forecast endpoint. \
It uses my account and API Key. Please be responsible, otherwise I can not sustain this plugin. \
You can create your own account and API key at [WeatherAPI.com](https://www.weatherapi.com/).
The free tier allows 1 000 000 API calls per month.

<a href="https://www.weatherapi.com/" title="Free Weather API"><img src='https://cdn.weatherapi.com/v4/images/weatherapi_logo.png' alt="Weather data by WeatherAPI.com" border="0"></a>

## Customization

<details>
<summary>Fallback Icons (sun/moon)</summary>

You can customize the fallback sun/moon icons:

1. Create or download `sun.svg` and `moon.svg` icons
2. Place them in `<koreader_data_dir>/icons/`
3. The plugin will use these icons when weather data is unavailable
</details>

## Troubleshooting

<details>
<summary>Weather not displaying</summary>

- Check your internet connection
- Ensure your location is entered correctly
- Check the KOReader log for error messages
</details>

<details>
<summary>Icons not showing</summary>

- Ensure you have an active internet connection for the first fetch
- Weather icons are automatically downloaded and cached
- Check the cache directory has write permissions
</details>

<details>
<summary>Outdated weather data</summary>

- Weather data is cached for the configured time (1 hour default)
- Enter sleep mode again to force a refresh after the cache expires
- Check your internet connection
</details>

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Work in Progress
<details>
<summary>Done</summary>

- Dark Mode: Currently, the weather icons that are supplied by the API only look good in light mode.
- Improved Scaling: Make scaling more consistent / configurable
</details>
<details>
<summary>In progress</summary>

</details>
<details>
<summary>Backlog</summary>

- Localization: Support more languages
- Attempt connecting to wifi: See #1
- Fallback: A more configurable fallback, when no weather data is available.
- More display modes: I am always open for requests.
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
