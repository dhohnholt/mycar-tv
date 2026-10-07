# Car TV

A private IPTV + YouTube player for the CarPlay screen. Distributed to yourself via TestFlight.

- **IPTV:** M3U/M3U8 playlists and Xtream Codes logins (live TV + movies).
- **YouTube:** sign in with Google; search, Liked videos, Subscriptions and Playlists on the car screen.
- **Privacy:** credentials and tokens live only in the iPhone Keychain (`ThisDeviceOnly`, no iCloud/backup). No analytics, no third-party SDKs, ephemeral networking (no disk cache).
- **Safety:** car-screen video pauses (and is covered) when GPS speed passes ~5 mph. Can be turned off in Settings.

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

## 2. CarPlay entitlement (Apple)

Video on the car screen relies on the **CarPlay navigation** entitlement (`com.apple.developer.carplay-maps`). It gives the app a full window to draw video into.

- **Simulator:** works now, no approval needed. Run the app, then in Simulator choose **I/O → External Displays → CarPlay**.
- **Real iPhone/car:** request the entitlement at <https://developer.apple.com/contact/carplay/>. Once Apple adds it to your team, add the CarPlay capability to the App ID in the developer portal. Automatic signing then picks it up.
- Until it's granted, device builds fail to sign. To test the phone-only parts on your iPhone first, temporarily delete the key from `CarPlayTV/CarPlayTV.entitlements`.

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
