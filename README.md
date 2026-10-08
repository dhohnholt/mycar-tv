# Car TV

A private IPTV + YouTube player for the CarPlay screen. Distributed to yourself via TestFlight.

- **IPTV:** M3U/M3U8 playlists and Xtream Codes logins (live TV + movies).
- **YouTube:** sign in with Google; search, Liked videos, Subscriptions and Playlists on the car screen.
- **Privacy:** credentials and tokens live only in the iPhone Keychain (`ThisDeviceOnly`, no iCloud/backup). No analytics, no third-party SDKs, ephemeral networking (no disk cache).
- **Safety:** iOS decides when video may show on the car display (typically only while parked).

## Project

Generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) — edit `project.yml`, then:

```bash
xcodegen generate
```

| Folder | What's in it |
| --- | --- |
| `CarPlayTV/Library` | M3U parser, Xtream client, Keychain, library store |
| `CarPlayTV/YouTube` | Google OAuth (PKCE), YouTube Data API, IFrame player |
| `CarPlayTV/Playback` | Player controller (routes video to car or phone), speed lock |
| `CarPlayTV/CarPlay` | CarPlay scene + templates |
| `CarPlayTV/Views` | iPhone SwiftUI screens |

## 1. YouTube sign-in (Google Cloud, ~10 min)

1. Go to <https://console.cloud.google.com/>, create a project (e.g. "Car TV").
2. **APIs & Services → Library** → enable **YouTube Data API v3**.
3. **APIs & Services → OAuth consent screen** (Google Auth Platform):
   - User type **External**, app name "Car TV", your email.
   - Scopes: add `https://www.googleapis.com/auth/youtube.readonly`.
   - **Audience → Test users:** add the Google account you watch YouTube with.
4. **Credentials → Create credentials → OAuth client ID** → type **iOS**, bundle ID `com.hohnholt.carplaytv`.
5. Copy the client ID (`1234…-abc….apps.googleusercontent.com`) into `GOOGLE_CLIENT_ID` in `project.yml`, then run `xcodegen generate`.

Notes:
- While the consent screen is in **Testing** status, Google expires refresh tokens after **7 days**, so you'll need to sign in again weekly. Publishing the app on the consent screen removes that limit, but sensitive scopes then need Google verification. For one person, weekly re-sign-in is the practical choice.
- Quota is 10,000 units/day. A search costs 100 units, so about 100 searches a day. Browsing lists costs 1 unit per page.
- Playback uses YouTube's official embedded player, so ads may appear and YouTube Premium perks don't carry over. Some videos block embedding and won't play.

## 2. CarPlay video entitlement (Apple)

Car TV is a **CarPlay video app** (`com.apple.developer.carplay-video`, iOS 27+). It uses only system
templates (tab bar, lists, search, Now Playing). List rows carry a `CPPlaybackConfiguration` with
`preferredPresentation: .video`, and iOS presents the video on the car display over AirPlay when the car
allows it (otherwise Now Playing). The app never draws on the car screen itself.

- Requested from Apple as app type VIDEO, Case-ID 22734816.
- **Build with Xcode 27** (iOS 27 SDK), e.g. `DEVELOPER_DIR=/Applications/Xcode-27.app/Contents/Developer`.
- **Simulator:** `CarPlayTV.entitlements` includes the entitlement. Boot an iOS 27 simulator in the classic
  Simulator app (Xcode 26's, which still has **I/O → External Displays → CarPlay**).
- **Device / TestFlight:** build 4 enables CarPlay video in `CarPlayTV-Device.entitlements`.
  Archiving and distribution require an Apple-approved provisioning profile containing this entitlement.

## 3. TestFlight

1. In App Store Connect, create an app with bundle ID `com.hohnholt.carplaytv`.
2. In Xcode, choose **Product → Archive → Distribute App → TestFlight & App Store** (or *TestFlight Internal Only*).
3. In App Store Connect → TestFlight, add yourself as an **internal tester**. Internal builds don't go through Beta App Review.
4. Bump `CURRENT_PROJECT_VERSION` in `project.yml` for every upload.

TestFlight builds expire after 90 days, so upload a fresh one before then.

## Known limits / ideas

- Xtream **series** aren't supported yet (live + movies only).
- AVPlayer handles HLS and MP4. Raw MPEG-TS or other formats some IPTV providers use would need VLCKit.
- Many IPTV servers are plain HTTP, so App Transport Security is relaxed. On those servers your IPTV credentials travel unencrypted. That's the provider's limitation, not the app's.
