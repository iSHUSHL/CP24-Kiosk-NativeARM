# CP24 HLS Kiosk — Native Apple Silicon

A native macOS live-news kiosk with **CP24, CityNews, and Global News Toronto**, built for Apple Silicon. Version **2.23** plays CP24 through AVPlayer using HLS and the broadcaster’s FairPlay certificate/license exchange, instead of the embedded Jasper web player.

**[Download notarized v2.23 DMG for Apple Silicon](https://github.com/iSHUSHL/CP24-Kiosk-NativeARM/releases/download/v2.23/CP24-HLS-Kiosk-Notarized.dmg)** · [All releases](https://github.com/iSHUSHL/CP24-Kiosk-NativeARM/releases)


### New in v2.23 — diagnostics, startup preferences, and update checks

[Download v2.23 ZIP](https://github.com/iSHUSHL/CP24-Kiosk-NativeARM/releases/download/v2.23/CP24-HLS-Kiosk-v2.23-Apple-Silicon.zip)

- **Playback diagnostics:** open **Channels → Playback Diagnostics…** (`Command-Option-D`). It refreshes about every five seconds with current channel/state, video resolution, the stream's reported bitrate, adaptive preferred bitrate cap, buffered seconds, fresh transfer throughput, and the eight most recent playback events. The event history includes buffering, resumption, quality changes, stalls, failures, and reload requests. It describes observed events; it cannot establish every freeze's root cause. Throughput is recent media-transfer throughput, not a general speed test.
- **Startup channel:** in **Settings → Start with**, select **Last watched channel** (default), CP24, CityNews, or Global News Toronto. Last watched remembers channel selections and successful playback across app restarts; first launch falls back to CP24. Fixed startup choices always take precedence over the remembered channel. Changing startup does not change the current stream or rotation selection.
- **Update notifications:** optional automatic checks use the public GitHub releases API after startup and roughly daily thereafter. Choose **Check for Updates…** in Settings or the app menu for a manual check. Only newer numeric versions with an uploaded DMG whose filename contains “Notarized” are offered; drafts, prereleases, unsigned-ZIP-only releases, and older versions are skipped. The app trusts this repository's asset labeling and does not itself verify notarization before download. A nonmodal notice offers **Download Update**, which opens the GitHub download in your browser; installation is manual. Automatic notices appear once per offered version. Turn automatic checks off in Settings. Failed automatic checks do not interrupt playback.
- **Preferences now scrolls** so all existing reliability and channel-rotation settings remain accessible.

**All three channel-rotation checkboxes remain available.** Startup choices and update checks are independent of rotation.

**v2.23 is now available as a notarized DMG**, including diagnostics, startup preferences, and update checks. This is the recommended download. The ZIP and local builds remain ad-hoc signed and are not notarized.

### New in v2.22 — adaptive streaming

[Download v2.22 ZIP — adaptive streaming](https://github.com/iSHUSHL/CP24-Kiosk-NativeARM/releases/download/v2.22/CP24-HLS-Kiosk-v2.22-Apple-Silicon.zip)

CP24, CityNews, and Global now have additional connection-aware quality limits on top of native HLS adaptation. No setup is required:

- Starts with a conservative 2.5 Mbps preferred cap; AVPlayer picks a rendition offered by each channel.
- Checks playback, buffered media, and fresh transfer measurements every five seconds.
- Lowers the preferred cap on stalls, sustained buffering, or insufficient throughput with a low buffer. Reductions are spaced at least 20 seconds apart.
- Increases one step only after at least two minutes of stable playback, sufficient buffered media, and fresh bandwidth evidence with 35% headroom.
- Uses preferred caps from 0.8 to 8 Mbps and a 30-second preferred buffer at the lowest levels (20 seconds otherwise).
- Retains each channel's cap across rotation and retries during the app session; a new launch starts conservatively again.
- Logs quality changes, shows a buffering message, and preserves retry backoff until playback has been stable for a minute.
- Continues bounded retries when no enabled fallback channel is available.

These are AVPlayer preferences, not guaranteed bitrates or buffer sizes. The stream must offer a suitable lower-bitrate rendition. A slower connection than the lowest rendition, broadcaster faults, or an outage can still interrupt playback. More buffering can increase live delay. This does not remove FairPlay output restrictions during screen capture.

**v2.22 is now available as a notarized DMG**, including adaptive streaming. The newer v2.23 DMG is recommended. The ZIP and local builds remain ad-hoc signed and are not notarized.

Implementation references: [Apple bitrate preferences](https://developer.apple.com/documentation/avfoundation/avplayeritem/preferredpeakbitrate) and [buffer preferences](https://developer.apple.com/documentation/avfoundation/avplayeritem/preferredforwardbufferduration).

### New in v2.21

[Download v2.21 ZIP — Global + rotation preferences](https://github.com/iSHUSHL/CP24-Kiosk-NativeARM/releases/download/v2.21/CP24-HLS-Kiosk-v2.21-Apple-Silicon.zip)

Adds Global News Toronto (key `3`) and saved per-channel rotation checkboxes in **Settings → Include in automatic rotation and fallback**. All three channels are included by default. Select one to stay on that channel once rotation reaches it; uncheck all to stop automatic switching. Manual switching remains available for every channel. Recovery fallback respects the same selection and skips channels in cooldown.

**v2.21 is now available as a notarized DMG**, including Global and rotation preferences. Quit the previous app before replacing it. The ZIP remains an ad-hoc-signed alternative; it is not notarized.

## Requirements and installation

- Apple Silicon Mac (M-series); this release is **arm64 only**, not an Intel/universal build.
- macOS 13 or later and an internet connection.
- CP24 playback depends on the broadcaster continuing to authorize the native FairPlay request and making the stream available in your location.

1. Download and open **CP24-HLS-Kiosk-Notarized.dmg**.
2. Quit the older kiosk app, then drag **CP24 HLS Kiosk.app** onto the **Applications** shortcut in the disk image.
3. Open the app. v2.23 starts full screen with your chosen startup channel (or last watched); a first launch defaults to CP24.
4. Press **Esc** to leave full screen, and use **Settings** to configure rotation and safeguards.

**Recommended download: the notarized DMG.** Its stapled notarization ticket was validated, and macOS Gatekeeper accepted the included v2.23 app as **Notarized Developer ID** on October 26, 2026.

The original ZIP remains available as an alternative; that ZIP and local builds are ad-hoc signed and **not notarized**.

This is a separate app from News TV Kiosk. It uses its own bundle identifier, preferences, health logs, and watchdog files. Installing it does not replace your previous app. Quit the previous kiosk before running this one to avoid simultaneous playback.

## Channels and playback

| Channel | Shortcut | Playback |
| --- | --- | --- |
| CP24 — startup channel | `1` | Native HLS with FairPlay license requests |
| CityNews | `2` | Native HLS |
| Global News Toronto | `3` | Native HLS |

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
| Channel fallback | Requests another selected channel after repeated recovery failures. Availability of either stream is not guaranteed. |
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
| `3` | Global News Toronto |
| `Command-R` | Request current-stream recovery/reload |
| `Command-Option-D` | Playback diagnostics |
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
- `releases/CP24-HLS-Kiosk-v2.23-Apple-Silicon.zip`

No earlier News TV Kiosk ZIP is required to build this repository. No third-party package installation or API key is required. Playback still requires the broadcaster’s license service.

## Validation and limitations

The native CP24 player was tested on an Apple Silicon Mac on **October 16, 2026**. A 60-second probe obtained 60 decoded-video samples with no reported player error or error-log entries. The packaged app’s arm64 architecture, ad-hoc signature, archive integrity, and stream URLs were checked. This was a short native-player test, not an extended full-app endurance test or audible-audio verification.

- Broadcaster commercials can still appear. This app does not promise ad removal or bypass playback authorization.
- Stream URLs, certificates, licensing requirements, and geographic availability can change.
- Fixed in v2.21: the original v2.20 app retains an inherited “Universal Mac Build” description in its Safeguards window. That label is inaccurate for this package: the binary and build script are **Apple Silicon only**.
- Historical release notes describe earlier versions and may mention channels or architectures not included in this release.

This project is not affiliated with or endorsed by CP24, Bell Media, CityNews, or their owners. Channel names and stream content belong to their respective owners.

## Rotation tests

```sh
xcrun swiftc Sources/CP24HLSKiosk/Channel.swift Sources/CP24HLSKiosk/ChannelRotation.swift Tests/ChannelRotationTests.swift -o /tmp/cp24-rotation-tests
/tmp/cp24-rotation-tests
```

Covers all 192 combinations of current channel, included channels, and cooldown channels, plus saved preferences and rotation order.

## Adaptive quality tests

```sh
xcrun swiftc Sources/CP24HLSKiosk/Channel.swift Sources/CP24HLSKiosk/AdaptiveQuality.swift Tests/AdaptiveQualityTests.swift -o /tmp/cp24-quality-tests
/tmp/cp24-quality-tests
```

Tests cover quality reductions, anti-flapping delays, slow upgrades, buffer and throughput requirements, invalid measurements, and independent channel state. Network conditions are simulated in the policy tests; they are not a long-duration network-throttling or endurance test.

### v2.22 live validation (October 26, 2026)

The updated PlayerViewController was exercised on all three feeds for approximately 25 seconds each. The repeat run produced 25 CP24, 25 CityNews, and 24 Global decoded-video samples with no final item errors. Injected stall notifications lowered preferred caps without replacing the current item; CP24's reduced cap survived rotation, and stopping removed the player item. An initial run encountered a CityNews playback failure before the simulated stall; the repeat run was clean. These short checks do not establish long-term reliability or eliminate upstream failures.

## Startup and update tests

```sh
xcrun swiftc -parse-as-library Sources/CP24HLSKiosk/Channel.swift Sources/CP24HLSKiosk/StartupPreference.swift Sources/CP24HLSKiosk/UpdateChecker.swift Tests/StartupAndUpdatesTests.swift -o /tmp/cp24-startup-updates-tests
/tmp/cp24-startup-updates-tests
```

Tests use isolated preferences, verify fixed/last-watched startup and numeric version ordering, filter release and asset fixtures, and perform a read-only live GitHub API check. The v2.23 diagnostics/startup probe decoded 14 Global video samples during a 15-second test and verified live metrics and a simulated stall event. Preferences, diagnostics, and a fixture update notice were rendered for layout review. No newer real release was available for an end-to-end update notification or installation test.
