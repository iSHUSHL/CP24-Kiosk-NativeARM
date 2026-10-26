import Foundation

struct ReleaseNote {
    let version: String
    let date: String
    let changes: [String]
}

enum ReleaseNotes {
    static let latestLimit = 10
    static let archivePageSize = 20

    static let all: [ReleaseNote] = [
        ReleaseNote(version: "v2.22", date: "2026-10-26", changes: [
            "Added connection-aware quality limits for CP24, CityNews, and Global.",
            "Lowers quality during buffering and raises it cautiously after sustained stable playback.",
            "Remembers each channel's quality limit during rotation and uses extra buffering at low quality.",
            "Preserves recovery backoff through brief playback resumptions and retries when no fallback is enabled."
        ]),
        ReleaseNote(version: "v2.21", date: "2026-10-16", changes: [
            "Added Global News Toronto native HLS playback and keyboard shortcut 3.",
            "Added saved per-channel rotation preferences in Settings.",
            "Automatic rotation and fallback skip unchecked channels and channels cooling down.",
            "Uncheck all channels to disable automatic switching; manual selection remains available.",
            "Corrected the Apple Silicon architecture description."
        ]),
        ReleaseNote(version: "v2.20 HLS", date: "2026-10-16", changes: [
            "Native CP24 HLS playback on Apple Silicon with FairPlay license requests.",
            "Preserved CP24 and CityNews, dashboard, and kiosk safeguards.",
            "Brief buffering no longer immediately reloads the stream.",
            "Separate app settings and watchdog from News TV Kiosk."
        ]),
        ReleaseNote(
            version: "v2.19",
            date: "2026-06-18",
            changes: [
                "Added Intel-only native CP24 FairPlay key handling using CP24's certificate and CKC license endpoints.",
                "Kept Apple Silicon on the existing CP24 web-player path while changing only Intel CP24 playback.",
                "Improved black-screen detection so CP24 is unhealthy if playback time advances but no video becomes visible.",
                "Recovery now retries black CP24 video and then switches channels instead of staying on a dead screen."
            ]
        ),
        ReleaseNote(
            version: "v2.18",
            date: "2026-06-18",
            changes: [
                "Switched CP24 from the WebView player to a direct native HLS stream.",
                "Fixed Intel Mac CP24 black screen by bypassing WebKit video rendering entirely.",
                "CP24 now uses the same native AVPlayer path as CityNews for more reliable video.",
                "Captions remain disabled through the native player path."
            ]
        ),
        ReleaseNote(
            version: "v2.17",
            date: "2026-06-18",
            changes: [
                "Fixed Intel Mac CP24 black video when audio is playing.",
                "Changed the CP24 WebView to use an opaque black video surface for more reliable Intel rendering.",
                "Reworked CP24 video-layer styling to keep the actual video visible above black placeholders.",
                "Added a repeated video-layer repair script during CP24 startup, health checks, and recovery."
            ]
        ),
        ReleaseNote(
            version: "v2.16",
            date: "2026-06-18",
            changes: [
                "Fixed Intel Mac close/quit behavior that could leave an empty white full-screen Space.",
                "Quit now exits full-screen kiosk mode first, restores normal desktop presentation, then terminates.",
                "Close and Quit now share the same desktop cleanup path for safer wallpaper restoration.",
                "Dock reopen still restores the player and full-screen kiosk behavior."
            ]
        ),
        ReleaseNote(
            version: "v2.15",
            date: "2026-06-18",
            changes: [
                "Fixed CP24 not autoplaying by removing the official no-autoplay embed fallback.",
                "Changed the controlled CP24 player to Jasper's strongest autoplay mode.",
                "Improved CP24 startup nudging so the app keeps requesting playback during startup.",
                "Delayed hiding CP24 player controls until playback is actually running."
            ]
        ),
        ReleaseNote(
            version: "v2.14",
            date: "2026-06-18",
            changes: [
                "Fixed CP24 startup on Intel Macs by using the official CP24 embed path for x86_64 builds.",
                "Added automatic CP24 fallback from the custom player to the official embed when no video is detected.",
                "Improved CP24 black-screen recovery so a loaded-but-empty web player does not stay stuck.",
                "Kept CityNews native playback unchanged."
            ]
        ),
        ReleaseNote(
            version: "v2.13",
            date: "2026-06-18",
            changes: [
                "Redesigned the Live Dashboard cards with a cleaner modern control-center style.",
                "Locked every dashboard card to the same size with two wide cards per row.",
                "Added icon tiles and consistent right-side visual panels to make the dashboard easier to scan.",
                "Tightened the dashboard header and spacing so the layout feels cleaner and less crowded."
            ]
        ),
        ReleaseNote(
            version: "v2.12",
            date: "2026-06-18",
            changes: [
                "Redesigned the Live Dashboard into a wide control-center layout with equal-size cards.",
                "Centered the LIVE text inside the green live status badge.",
                "Added an Auto Rotation card so the dashboard shows the current channel switching interval.",
                "Rebalanced graph cards so system monitoring feels cleaner, wider, and more consistent."
            ]
        ),
        ReleaseNote(
            version: "v2.11",
            date: "2026-06-18",
            changes: [
                "Redesigned the Live Dashboard with a colorful glass-style visual system.",
                "Added a dedicated Network Activity card with a live graph.",
                "Expanded the dashboard into a richer 8-card monitoring grid.",
                "Improved graph styling with darker glass panels, subtle grid lines, and brighter trend lines."
            ]
        ),
        ReleaseNote(
            version: "v2.10",
            date: "2026-06-18",
            changes: [
                "Redesigned the Live Dashboard into a richer monitoring console.",
                "Added live graph cards for system RAM, disk space, CPU load, and app memory.",
                "Added system monitoring cards for Mac uptime and Stream Health Log size.",
                "Dashboard monitoring now refreshes live every few seconds."
            ]
        ),
        ReleaseNote(
            version: "v2.9",
            date: "2026-06-17",
            changes: [
                "Added a Dashboard menu next to Channels in the macOS menu bar.",
                "Added a standalone Live Dashboard window from the Dashboard menu.",
                "Added a Safeguards menu after Dashboard for direct access to the safeguards window."
            ]
        ),
        ReleaseNote(
            version: "v2.8",
            date: "2026-06-17",
            changes: [
                "Added Last Known Good Channel behavior so failed channels are held out of auto-rotation for one hour.",
                "Added Network Awareness with an offline waiting overlay and network-safe restart behavior.",
                "Added a modern live status dashboard in Settings.",
                "Health logs now automatically remove entries older than 30 days."
            ]
        ),
        ReleaseNote(
            version: "v2.7",
            date: "2026-06-17",
            changes: [
                "Fixed restart timer relaunch so the app opens again after quitting the old instance.",
                "Daily restart and unhealthy-stream restart now use a delayed external helper with a fresh app launch.",
                "Crash watchdog relaunch now uses the same stronger fresh-open behavior."
            ]
        ),
        ReleaseNote(
            version: "v2.6",
            date: "2026-06-17",
            changes: [
                "Added a Safeguards button to the About window.",
                "Added a dedicated Safeguards page listing all 24/7 protection features built into the app.",
                "Safeguards now document stream recovery, crash recovery, relaunch logic, sleep prevention, launch at login, health logging, close/reopen protection, and kiosk behavior."
            ]
        ),
        ReleaseNote(
            version: "v2.5",
            date: "2026-06-17",
            changes: [
                "Added a crash watchdog that automatically reopens CP24 HLS Kiosk after an unexpected app crash.",
                "Normal Quit remains intentional and will not restart the app.",
                "Crash watchdog events are written to the Stream Health Log."
            ]
        ),
        ReleaseNote(
            version: "v2.4",
            date: "2026-06-17",
            changes: [
                "Added a small on-screen Now Playing overlay that disappears after a few seconds.",
                "Added automatic app relaunch if playback remains unhealthy for 10 minutes.",
                "Added optional daily auto-restart with a time picker in Settings.",
                "Settings now includes the new restart safeguards alongside Launch at Login, Disable Sleep, and Stream Health Log."
            ]
        ),
        ReleaseNote(
            version: "v2.3",
            date: "2026-06-17",
            changes: [
                "Closing the player now keeps CP24 HLS Kiosk active instead of switching focus to Finder.",
                "The app menu remains available after the stream window is closed, so About, Settings, and Release Notes stay accessible.",
                "The close flow still exits full screen before hiding the player to avoid an empty full-screen Space."
            ]
        ),
        ReleaseNote(
            version: "v2.2",
            date: "2026-06-17",
            changes: [
                "Fixed closing the full-screen player so macOS no longer stays on an empty kiosk Space.",
                "Close now exits full screen first, stops video and audio, releases kiosk mode, and returns to the desktop.",
                "Dock reopen still brings the player back and restarts the current channel."
            ]
        ),
        ReleaseNote(
            version: "v2.1",
            date: "2026-06-17",
            changes: [
                "Added Launch at Login support for 24/7 kiosk startup.",
                "Added Disable Sleep while streaming to keep the Mac and display awake.",
                "Added Stream Health Log with refresh and clear controls in Settings.",
                "Health log now records channel changes, recoveries, stalls, failures, close/reopen, and power/login status."
            ]
        ),
        ReleaseNote(
            version: "v2",
            date: "2026-06-17",
            changes: [
                "Renamed the app to CP24 HLS Kiosk.",
                "Updated app metadata, release zip naming, executable name, and icon resource name.",
                "Updated the app icon artwork to remove CP24 branding.",
                "Upgraded Release Notes with a polished latest view and archived history.",
                "Archive loads older notes 20 at a time with Load More."
            ]
        ),
        ReleaseNote(
            version: "v1.9",
            date: "2026-06-17",
            changes: [
                "Redesigned Release Notes with a modern card layout.",
                "Closing the player window now stops video and audio.",
                "Clicking the Dock icon reopens the player and starts the stream again."
            ]
        ),
        ReleaseNote(
            version: "v1.8",
            date: "2026-06-17",
            changes: [
                "Added Release Notes from the About window.",
                "Release Notes shows the latest 10 versions to keep the list short."
            ]
        ),
        ReleaseNote(
            version: "v1.7",
            date: "2026-06-17",
            changes: [
                "Added CP24 audio watchdog to keep the stream unmuted at full volume.",
                "Improved ESC window centering after leaving full screen."
            ]
        ),
        ReleaseNote(
            version: "v1.6",
            date: "2026-06-17",
            changes: [
                "Made the app Universal for Intel and Apple silicon Macs.",
                "Verified the binary includes x86_64 and arm64."
            ]
        ),
        ReleaseNote(
            version: "v1.5",
            date: "2026-06-17",
            changes: [
                "Moved auto-switch settings into the normal macOS Settings window.",
                "Improved CP24 startup audio handling."
            ]
        ),
        ReleaseNote(
            version: "v1.4",
            date: "2026-06-17",
            changes: [
                "Added larger custom About window.",
                "Added Made by Igor Baran and copyright notice."
            ]
        ),
        ReleaseNote(
            version: "v1.3",
            date: "2026-06-17",
            changes: [
                "Added ESC behavior to exit full screen into a centered movable window.",
                "Kept the stream playing while windowed."
            ]
        ),
        ReleaseNote(
            version: "v1.2",
            date: "2026-06-17",
            changes: [
                "Reworked CP24 playback through a custom full-screen kiosk player shell.",
                "Reduced CP24 startup pokes to avoid playback looping."
            ]
        ),
        ReleaseNote(
            version: "v1.1",
            date: "2026-06-17",
            changes: [
                "Added auto-switch interval choices from 1 minute to 2 hours.",
                "Saved the selected interval between app launches."
            ]
        ),
        ReleaseNote(
            version: "v1",
            date: "2026-06-17",
            changes: [
                "Initial kiosk app with CP24 and CityNews channels.",
                "Added full-screen startup, keyboard shortcuts, channel switching, stream recovery, auto-switching, and custom app icon."
            ]
        )
    ]

    static var latest: [ReleaseNote] {
        Array(all.prefix(latestLimit))
    }

    static var archive: [ReleaseNote] {
        Array(all.dropFirst(latestLimit))
    }

    static func archivePage(count: Int) -> [ReleaseNote] {
        Array(archive.prefix(count))
    }
}
