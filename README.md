# CP24 HLS Kiosk — Native Apple Silicon

A native macOS live-news kiosk with **CP24 and CityNews**, built for Apple Silicon. Version **2.20** plays CP24 through AVPlayer using HLS and the broadcaster’s FairPlay certificate/license exchange, instead of the embedded Jasper web player.

**[Download notarized DMG for Apple Silicon](https://github.com/iSHUSHL/CP24-Kiosk-NativeARM/releases/download/v2.20/CP24-HLS-Kiosk-Notarized.dmg)** · [All releases](https://github.com/iSHUSHL/CP24-Kiosk-NativeARM/releases)

## Requirements and installation

- Apple Silicon Mac (M-series); this release is **arm64 only**, not an Intel/universal build.
- macOS 13 or later and an internet connection.
- CP24 playback depends on the broadcaster continuing to authorize the native FairPlay request and making the stream available in your location.

1. Download and open **CP24-HLS-Kiosk-Notarized.dmg**.
2. Drag **CP24 HLS Kiosk.app** onto the **Applications** shortcut in the disk image.
3. Open the app. It starts with CP24 in full screen.
4. Press **Esc** to leave full screen, and use **Settings** to configure rotation and safeguards.

**Recommended download: the notarized DMG.** Its stapled notarization ticket was validated, and macOS Gatekeeper accepted the included v2.20 app as **Notarized Developer ID** on October 16, 2026.

The original ZIP remains available as an alternative; that ZIP and local builds are ad-hoc signed and **not notarized**.

This is a separate app from News TV Kiosk. It uses its own bundle identifier, preferences, health logs, and watchdog files. Installing it does not replace your previous app. Quit the previous kiosk before running this one to avoid simultaneous playback.

## Channels and playback

| Channel | Shortcut | Playback |
| --- | --- | --- |
| CP24 — startup channel | `1` | Native HLS with FairPlay license requests |
| CityNews | `2` | Native HLS |

- Native AVPlayer video and audio with adaptive HLS playback.
- CP24 FairPlay certificate, content-key request, license response, cancellation, and renewal handling.
- No Jasper embed or browser-player startup scripts.
- Brief buffering lets AVPlayer refill before sustained-stall recovery reloads the stream.
- Clean channel switching stops the previous stream.
- Captions, subtitles, and text tracks are disabled when streams load.
- A temporary **Now Playing** overlay appears at startup and on channel changes.
- Full-screen kiosk presentation hides the Dock and menu bar and limits process switching while active.
- **Esc** returns to a centered, movable window while playback continues.

## Automatic rotation

Choose a saved switching interval of **1, 5, 10, 20, 30, or 45 minutes**, **1 hour**, **90 minutes**, or **2 hours**. You can also switch manually using the Channels menu or number keys.

## Playback and uptime safeguards

| Safeguard | What it does |
| --- | --- |
| Stream health monitoring | Checks roughly every 15 seconds for failures, missing video, empty buffers, and lack of playback progress. |
| Recovery with backoff | Retries unhealthy playback with increasing delays, rather than endlessly reloading at a fixed rapid interval. |
| Brief-stall tolerance | Allows native buffering recovery before the health monitor escalates. |
| Channel fallback | Requests the other channel after repeated recovery failures. Availability of either stream is not guaranteed. |
| Last known good channel | Tracks successful playback and holds repeatedly failed channels out of auto-rotation for an hour. |
| Network awareness | Shows **Waiting for network** offline, suppresses offline health-relaunch decisions, and recovers when connectivity returns. |
| Unhealthy-stream relaunch | Optional clean app relaunch after 10 minutes of unhealthy playback. |
| Daily restart | Optional scheduled restart at a chosen local time. |
| Crash watchdog | A separate process reopens the app after an unexpected exit. Intentional Quit does not trigger recovery. |
| Launch at login | Optional macOS login-item registration, available from Settings. |
| Sleep prevention | Optional prevention of both display and system sleep while streaming. |
| Safe close | Stops audio/video, exits kiosk full screen, releases sleep protection, and leaves app menus available. |
| Dock reopen | Reopens the player and resumes the selected channel after its window was closed. |

These features are designed for unattended use; they do not establish guaranteed 24/7 uptime.

## Live Dashboard

Open **Dashboard → Show Live Dashboard** for a separate monitoring window with live status cards and graph trends:

- Current channel and network status.
- Active protection state and next scheduled restart.
- System RAM, disk space, network activity, CPU load, and app memory.
- Mac uptime, last known good channel, and last healthy playback time.
- Health-log size and current auto-rotation interval.

Settings also includes stream/protection status. The **Safeguards** window describes the recovery features, and **About → Release Notes** provides recent changes and paginated older history.

## Diagnostics

The **Stream Health Log** records app launches, channel loads, playback failures, stalls, recovery, fallback switches, network changes, restart/watchdog events, window close/reopen, and login/power status.

- View, refresh, or clear the log in the app.
- Entries older than 30 days are pruned automatically.
- Size-based log management prevents indefinite growth.
- Log location: `~/Library/Application Support/CP24 HLS Kiosk/stream-health.log`.

## Keyboard controls

| Key | Action |
| --- | --- |
| `1` | CP24 |
| `2` | CityNews |
| `Command-R` | Request current-stream recovery/reload |
| `Esc` | Leave full screen |
| `Command-,` | Settings |
| `Command-Q` | Quit intentionally |

## Build from source

Install Apple’s Xcode Command Line Tools or Xcode with a macOS SDK and Swift compiler, then run:

```sh
git clone https://github.com/iSHUSHL/CP24-Kiosk-NativeARM.git
cd CP24-Kiosk-NativeARM
./build.sh
```

The script compiles an optimized **arm64** executable targeting macOS 13, assembles the app with the included icon and metadata, applies an ad-hoc signature, and produces:

- `build/CP24 HLS Kiosk.app`
- `releases/CP24-HLS-Kiosk-v2.20-Apple-Silicon.zip`

No earlier News TV Kiosk ZIP is required to build this repository. No third-party package installation or API key is required. Playback still requires the broadcaster’s license service.

## Validation and limitations

The native CP24 player was tested on an Apple Silicon Mac on **October 16, 2026**. A 60-second probe obtained 60 decoded-video samples with no reported player error or error-log entries. The packaged app’s arm64 architecture, ad-hoc signature, archive integrity, and stream URLs were checked. This was a short native-player test, not an extended full-app endurance test or audible-audio verification.

- Broadcaster commercials can still appear. This app does not promise ad removal or bypass playback authorization.
- Stream URLs, certificates, licensing requirements, and geographic availability can change.
- The original v2.20 app retains an inherited “Universal Mac Build” description in its Safeguards window. That label is inaccurate for this package: the binary and build script are **Apple Silicon only**.
- Historical release notes describe earlier versions and may mention channels or architectures not included in this release.

This project is not affiliated with or endorsed by CP24, Bell Media, CityNews, or their owners. Channel names and stream content belong to their respective owners.
