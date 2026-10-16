# Zank Android Remote for Control4 (open source)

Unoffical API from https://github.com/duckyngo/Zank-Remote-for-Desktop 

IP control of Android / AOSP TV boxes from Control4 through the **Zank Remote** app running on the box. Built for boxes where the official Android TV remote protocol is not available (no Google certification, no Android TV Remote Service).

Includes:

- **Zank Android Remote** (`zank_android_remote.c4z`) - media player driver with full navigation and transport mapping, press-and-hold repeat, colour-button app shortcuts, programming commands, and a Virtual Switcher with 25 Android App inputs for mini apps.
- **Preset mini apps** (`zank_miniapp_<app>.c4z`) - Netflix, YouTube, SmartTube, Prime Video, Disney+, Plex, Kodi, and more (see `apps.json`).
- **Custom mini app** (`zank_miniapp_custom.c4z`) - add as many as you like; set the app name and Android package in Composer.
- **Tools** - `zank_capture.py` to learn the exact command strings your Zank version uses, and `zank_cli.py` to test commands against a box.

MIT licensed. Not affiliated with Zank, Chowmain, Google or Snap One.

## Important: confirm the command strings first

Zank's TV-side protocol is not publicly documented. What is confirmed (from Zank's own open source desktop server): plaintext UDP commands on port **1028** (`getName`, `click`, `setText`, `pageUp`, `volumeUp`, ...) and a `!len!payload` framed TCP channel on port **1029**.

The D-pad, home, back, app launch and app list strings in this driver are **best-guess defaults**. Every one can be replaced through the **Command Overrides** property, so the driver adapts to whatever your Zank version uses. Plan 10 minutes to capture them:

1. On a PC on the same network: `python3 tools/zank_capture.py wizard`
2. In the Zank phone app, search for devices and connect to "Zank Capture PC".
3. Press each button when asked. The tool prints a line like `UP=dpadUp; DOWN=dpadDown; LAUNCH=openApp {pkg}; ...`
4. Paste it into the driver's **Command Overrides** property, then run the **Print Command Map** action.

If the phone app will not send buttons to the fake TV, capture the real box instead: install **PCAPdroid** on the phone, capture the Zank app while you press buttons and launch an app, export a `.pcap`, then run `python3 tools/zank_capture.py pcap capture.pcap`.

You can also try candidates directly: `python3 tools/zank_cli.py <box-ip> probe UP` sends likely strings one at a time and asks whether the box reacted.

Alternative: set **Key Mode** to **Android Keycodes**, which sends every key as a key event using the `KEYCODE` template (default `keycode {code}`, e.g. `keycode 19` for up). If your Zank version accepts key codes, one override (`KEYCODE=...`) covers every button.

## Prepare the Android box

1. Give the box a DHCP reservation (static IP).
2. Enable Developer options (Settings > Device Preferences > About > press Build 7 times) and turn on USB debugging. Zank uses it for its fast control mode.
3. Install **Zank Remote** on the box, open it, allow the debugging prompt ("Always allow"), and enable its accessibility service when asked.
4. Disable automatic app updates on the box if possible; an update can stop Zank running in the background.
5. Confirm with the Zank phone app that you can control the box.
6. Optional check from a PC: `python3 tools/zank_cli.py <box-ip> name` should print the box name.

## Install in Composer Pro

1. Driver > Add or Update Driver: add `zank_android_remote.c4z` and any mini app `.c4z` files you want.
2. Add **Zank Android Remote** to the room. Set **IP Address**. **Connection Status** shows Online once the box answers.
3. Connections. All AV and room connections live on the **Virtual Switcher** sub-item; the root Zank Android Remote has none.
   - Connect the Virtual Switcher **OUTPUT** (HDMI, Component, Composite, S-Video, VGA, audio) to the TV or AVR input.
   - The Virtual Switcher's **Room Selection** outputs make it the Watch source for the box itself.
   - Mini apps bind to its **Android App 1-25** inputs.
4. Paste your captured **Command Overrides** (see above).
5. Run **Request App List**, then **Print Apps** to see the packages installed on the box.

## Mini apps

1. Add a preset mini app (for example **Netflix (Zank)**) or **Zank Custom Mini App** to the room.
2. Connections > Video: bind the mini app's output to an **Android App n** input on the **Virtual Switcher**.
3. Custom mini app: set **App Name** and **Package** (for example `com.example.app`). Optional **Activity** for apps that need a specific launch activity.
4. Refresh Navigators. Selecting the mini app launches the app on the box; remote buttons pass through to the box.

Package differs on your box? Change the mini app's **Package** property. **Print Mini App Bindings** on the remote driver lists what each input will launch.

**Passthrough Mode** (remote driver): **On** keeps the mini app selected in Navigator. **Off** reselects the Virtual Switcher after the app launches.

The Android App inputs use the `RF_ANDROID_APP` connection class, which existing Chowmain-style Android mini apps also use. The driver finds the app to launch from the mini app's package variable, then its app name, then its Composer name ("YouTube (Android TV)" matches YouTube).

## Mini app icons

The mini apps ship with plain name tiles. App logos belong to their owners and aren't bundled, but you can add the real ones for your install:

- From the apps on the box (needs `adb`; USB debugging is already on for Zank): `python3 tools/import_icons.py from-box <box-ip>`
- From an image, a `.c4z` you own, or an `.apk`: `python3 tools/import_icons.py from-file netflix path/to/file`

Then run `python3 tools/build.py` and update the mini app drivers in Composer. See `icons/README.md`.

## Passthrough troubleshooting

The remote driver tells each bound mini app where to send its button presses: when it starts, when bindings change, when the app is selected, and every 5 minutes. If buttons do nothing while a mini app is selected:

1. Check the mini app's **Status** property. It should say `Ready ... (remote device N)`.
2. Run **Print Mini App Bindings** on the remote driver. This also re-announces to every mini app.
3. Turn on **Debug Mode** on both drivers. Each press should log on the mini app (`-> <id> UP`) and then on the remote (`>> UDP dpadUp`).

## Remote mapping

- Up / Down / Left / Right / Select - D-pad
- Cancel - Back
- Menu, Guide - Home
- Info - see **Info Button Action**: Long press OK (default, `dpadCenterLong`; opens info/context menus in Plex and most Android TV apps), Menu key, or Info key
- Play, Pause - Play/Pause (or discrete, see **Play/Pause Mode**)
- Stop - Media stop or Back (see **Stop Button**)
- Skip Fwd / Rev - Next / Previous
- Scan Fwd / Rev - Fast forward / Rewind
- Page Up / Down, Channel Up / Down - Page Up / Down
- DVR (sent by Control4 as `PVR`) - does the same as Info when **DVR Button As Info** is On (off by default)
- Numbers - digit keys
- Red / Green / Yellow / Blue - launch the app chosen in the **Colour Button App** properties, or send the colour key
- Volume - handled by the audio endpoint by default; set **Volume Handling** to **Send to Box** to send it to Android
- Hold any navigation key - repeats at **Key Repeat Rate (ms)**

## Long press OK (Info in Plex)

Zank's long press of OK is `dpadCenterLong` (confirmed on a real box) and is the default for Info and DVR. If a future Zank version changes it, run the **Find Long Press Command** action with an app tile focused on the home screen, note the step that opens a menu, and set `LONG_SELECT=<string>` in **Command Overrides**.

## Command Overrides format

`KEY=value; KEY=value`

- Keys: `UP DOWN LEFT RIGHT SELECT LONG_SELECT BACK HOME MENU RECENTS SEARCH INFO SETTINGS GUIDE PLAY_PAUSE PLAY PAUSE STOP NEXT PREVIOUS REWIND FAST_FORWARD PAGE_UP PAGE_DOWN CHANNEL_UP CHANNEL_DOWN VOLUME_UP VOLUME_DOWN MUTE POWER SLEEP WAKEUP RED GREEN YELLOW BLUE CLICK DIGIT_0..DIGIT_9 KEYCODE LAUNCH APP_LIST TEXT OPEN_URL PING`
- Placeholders: `{code}` Android key code, `{pkg}` package, `{activity}` launch activity, `{text}` typed text, `{url}` deep link
- Prefix a value with `tcp:` to send it on the TCP channel (framed per **TCP Framing**), or `udp:` to force UDP.
- Example: `UP=dpadUp; SELECT=dpadCenter; LAUNCH=tcp:openApp {pkg}; APP_LIST=tcp:getApps`

## App list

**Request App List** sends the `APP_LIST` command and parses the reply. JSON (array of objects with package/name, or a package map) and line-based replies (`Label|package`) are understood. Set **Log Incoming Data** to **Yes** to see raw replies in the Lua output. Installed apps feed the **Launch App** programming command and the colour-button lists; the preset list is always available as a fallback.

## Programming

Commands: **Launch App** (pick from list), **Launch Package**, **Send Key**, **Send Text**, **Open Deep Link**, **Send Raw Command**, **Refresh App List**.

Events: **App Launched**, **Device Online**, **Device Offline**.

Variables: `ONLINE`, `CURRENT_APP`, `CURRENT_APP_PACKAGE`.

## Actions

Reconnect, Request App List, Print Apps, Clear App List, Print Command Map, Test D-Pad, Print Mini App Bindings.

## Limitations

- Power: Android boxes cannot be powered on over IP. **On Command** / **Off Command** can send wake/sleep or home.
- Not for TVs running Android TV OS (no input switching or power on).
- Navigator does not show an on-screen app grid; use mini apps, colour buttons or programming.
- Untested on hardware at release. Validate with the capture tool and Print Command Map before deploying.

## Building from source

`python3 tools/build.py` writes every `.c4z` plus `zank-c4-drivers.zip` to `dist/`. Add a preset by adding an entry to `apps.json`. Lua tests: `texlua tests/run_tests.lua` (or any Lua 5.1+ interpreter).
