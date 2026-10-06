# Control

**Your whole home media setup, in your pocket.**

Control is a remote control for a self-hosted media server, for iPhone and Android. Your download clients, your Sonarr, Radarr and Lidarr libraries, requests, subtitles and who's watching are all in one app. You can see what's trending and request it, watch downloads come in live, fix a stuck queue item and stop a stream from your couch or from across the city. It's built in the spirit of [nzb360](https://nzb360.com), the Android favourite, and runs on both platforms from one Flutter codebase.

Control talks to your servers directly, at home or away. There's no account, no cloud service and no tracking. Your API keys stay in your phone's secure storage.

## Works with

| Kind | Services |
| --- | --- |
| Download clients | SABnzbd, NZBGet, qBittorrent (4 and 5), Transmission |
| Library managers | Sonarr, Radarr, Lidarr |
| Subtitles | Bazarr |
| Indexers | Prowlarr |
| Requests and discovery | Overseerr, Jellyseerr, Seerr |
| Now playing | Plex (through Tautulli), Emby, Jellyfin |

## What it does

| Tab | What you get |
| --- | --- |
| **Home** | A swiping banner of what's trending, with artwork and ratings. A "Now downloading" strip showing what Sonarr, Radarr and Lidarr are grabbing, with progress and time left. Live speed and queue for each download client, who's watching right now, requests waiting for approval, what's coming up this week, and rows of popular and upcoming movies and shows. Tap any title to request it. |
| **Downloads** | Queue and history for every download client. Pause and resume one item or everything, delete with or without files, and add an NZB, torrent or magnet link. Refreshes every 3 seconds. |
| **Media** | Sonarr, Radarr and Lidarr libraries as posters or a list, filtered by monitored, missing or unmonitored. Detail pages to monitor, search, refresh or delete, with seasons and episodes for series. Add new series, movies or artists with your root folders and quality, language and metadata profiles. The download queue, with blocklisting. |
| **Calendar** | Upcoming episodes, movie releases and albums from all your library managers, grouped by day. |
| **More** | Search every indexer through Prowlarr, then grab through Prowlarr or send the release to any download client. Approve or decline requests, and search for something new to request. See what's playing on Plex, Emby and Jellyfin, and long-press to stop a stream. Bazarr subtitles: what's missing, search one language or everything, and history. Server setup. |

### Servers

- **Any number of servers** of each kind. Switch between them with the chips at the top of each tab.
- **Home and away addresses.** Give a server a home-network address and a remote one (reverse proxy or VPN). Control tries home first with a short timeout, falls back to away, and remembers which one worked.
- **URL bases** such as `http://nas:8989/sonarr`.
- **Reverse proxy basic auth** in front of any service.
- **Custom headers** per server, for Cloudflare Access service tokens, Authelia and the like.
- **Test connection** checks each address on its own and says what's wrong.
- API keys, passwords and headers are kept in the **iOS Keychain** or **Android's encrypted storage**, never in plain preferences.

## Install

### Android

Download `control.apk` from the [latest Android build](https://github.com/Jeffpoze/control/releases/tag/android-latest) on your phone and open it. Android asks once to allow installs from your browser or file manager. Every change merged into `main` publishes a new build there.

### iPhone

You need a Mac with Xcode and [Flutter](https://docs.flutter.dev/get-started/install/macos) (stable).

**Shortcut:** plug in your iPhone and double-click `iphone.command` in Finder. It builds Control and installs it on the phone. `run.command` opens it in the iOS Simulator instead, and also runs analyze and the tests. Both expect Flutter in `~/flutter`. The first iPhone install stops at signing: pick your Apple ID as the Team in Xcode (Runner, then Signing & Capabilities), then run it again.

By hand:

1. Open `ios/Runner.xcworkspace` in Xcode.
2. Select the **Runner** target, then **Signing & Capabilities**. Tick *Automatically manage signing* and pick your team. A free Apple ID works for personal installs, but those apps expire after 7 days and you can have at most 3.
3. If Xcode says the bundle identifier is taken, change `com.jeffpoze.control` to something unique.
4. Plug in the phone, pick it as the run destination, and press Run (or `flutter run --release`).

On the iPhone, trust your developer profile once under **Settings, General, VPN & Device Management**. The first time Control talks to a server on your network, iOS asks for **Local Network** permission. Allow it, or nothing on your network will answer.

## Development

```sh
git clone https://github.com/Jeffpoze/control.git
cd control
flutter pub get
flutter analyze
flutter test
flutter run                         # Simulator, emulator or a plugged-in phone
python3 scripts/generate_icon.py    # redraws the iOS and Android icons (needs Pillow)
```

Layout:

- `lib/services/`: one client per service, all built on `ServiceClient`, which handles home/away switching, auth headers, custom headers and friendly errors. Download clients share the `DownloadClient` interface. Sonarr, Radarr and Lidarr share `ArrClient`. Tautulli, Emby and Jellyfin share `StreamingClient`.
- `lib/state/`: `ServerStore` (servers, secrets, one live client per server) and `NavState` (tabs).
- `lib/screens/`: one file per screen. `lib/widgets/`: shared pieces such as the trending banner and poster rows.
- `test/`: each client against mocked HTTP (login flows, Transmission's session handshake, qBittorrent 4 vs 5, address fallback, Emby and Jellyfin auth, Bazarr), formatting, and widget tests.

CI runs format, analyze and the tests, then builds both the Android app and an unsigned iOS release. See [CONTRIBUTING.md](CONTRIBUTING.md) for the house rules.

## Not yet

- Notifications when downloads finish. Phones don't let apps check servers in the background, so this needs webhooks from the apps and a push relay such as ntfy.
- Deluge, rTorrent/ruTorrent, µTorrent; Readarr; Jackett and NZBHydra2 (Prowlarr covers most indexer needs); Unraid; Tracearr.
- Home screen widgets, and a share option for sending links to a download client.
- Wake on LAN. On iPhone it needs Apple's multicast networking entitlement, which takes a request to Apple.
- Servers with self-signed HTTPS certificates. Use plain HTTP at home, or a real certificate (Let's Encrypt, Tailscale) for remote access.
