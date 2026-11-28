# Mapbox 3D run replay (Strava-style flyover)

Question: can Timburr add a Strava-style 3D flyover replay of a recorded Run using Mapbox, what does it cost for one user, how do the tokens fit the repo's secrets rules, and how would it be built? The target is described in `docs/research/interval-summary-garmin-strava.md:99`: a satellite 3D camera follows the route, orange route line, moving marker, live pace/elevation/distance header, play/pause scrubber, 1x/2x speed. That note rated the 3D version out of scope (`:158`, `:171`); this note re-checks it against Mapbox's own docs and source.

Labels used on every claim: **[verified]** with the URL, `file:line` or command that settles it; **[unverified]** stated by a source with no evidence, or inferred, with a confidence. Docs pages were read on 2026-11-28 (fetched as Markdown from docs.mapbox.com where possible). Plugin source was read from a clone of `mapbox/mapbox-maps-flutter` at tag `v3.36.0` (commit `1fa256a`), cited as `mmf:path:line`. Nothing here was built or run on the phone.

## Short answers

1. **Pricing.** Billed per Maps SDK MAU. 25,000 MAU a month are free; above that it is $4.00 per 1,000. Satellite and terrain are included in the MAU. One user on one phone is 1 MAU, so it costs **$0**. A card is not required to sign up, but the card-free trial blocks the Raster Tiles API, and satellite imagery comes from that API. **In practice, satellite needs a payment method on the account.**
2. **Tokens.** Only a public `pk.` token is needed. The secret `DOWNLOADS:READ` token was dropped in plugin 2.4.0, and the v3.36.0 Gradle file fetches release artifacts with no credentials. The `pk.` token can go in `.env.json` next to the Supabase publishable key and be passed with `--dart-define-from-file`. That fits the repo rules.
3. **Capabilities.** Everything the replay needs is in the plugin: `setStyleTerrain` with `mapbox-terrain-dem-v1`, `MapboxStyles.STANDARD_SATELLITE`, `setCamera`/`flyTo`/`easeTo` with pitch and bearing, and the new `setFreeCameraOptions` (v3.36.0) for per-frame follow. The route is a `GeoJsonSource(lineMetrics: true)` with a `LineLayer` that uses `lineGradientExpression` and `lineTrimOffset`. The marker is a GeoJSON point updated each frame. The official `animated_route_example.dart` already does a Ticker-driven free-camera follow over terrain. The repo already meets the requirements: minSdk 26 (needs 21), Flutter 3.44.3 / Dart 3.12.2 (needs 3.44.2 / 3.12.0), and AGP 9 with `builtInKotlin=false`, which is the exact build bug 3.36.0 fixed.
4. **Offline.** Yes. `OfflineManager.loadStylePack` plus `TileStore.loadTileRegion` can store a corridor around the route, and the official example does this with `STANDARD_SATELLITE`. The limit is 750 unique tile packs, and offline use is billed inside the MAU. The terms do not allow bundling the tiles in the APK. The app must fetch them from Mapbox.
5. **Coexistence.** Keep flutter_map everywhere and use Mapbox only on a new replay screen. The cost is APK size. Measured from the Maven AARs, about **+62 MB** for the current fat APK (3 ABIs), or about +22 MB for an arm64-only build. That is an estimate. The Mapbox wordmark and attribution must stay visible on the map, with `© Maxar` credit for satellite. Telemetry is on by default, and the attribution control provides the opt-out.
6. **MapLibre alternative.** `maplibre_gl` 0.28.1 needs no key, but its Android and iOS `setTerrain` throws `UnsupportedError`: MapLibre Native has no 3D terrain yet. It cannot do the 3D flyover today. MapTiler's free plan is non-commercial (fine here) and pauses when the quota runs out, which is a safer failure than a bill, but it does not fix the missing terrain.
7. **Verdict.** Feasible, with medium effort: about 2 to 4 focused days for a first replay screen. The main risks are APK size, satellite needing a card on the account, network dependence unless the corridor is pre-downloaded, and per-frame platform-channel jank on a mid-range phone.

## 1. Pricing

| Claim | Source | Status |
| --- | --- | --- |
| Maps SDK for Android is billed by "monthly active users (MAUs), specifically 'Maps SDKs for Mobile' MAUs". A user counts once the app uses Maps SDK functionality, e.g. viewing a map. | https://docs.mapbox.com/android/maps/guides/pricing/ | verified, high |
| Free tier: up to 25,000 MAU a month. Then $4.00 per 1,000 (25,001-125,000), $3.20, $2.40, then contact sales. | https://www.mapbox.com/pricing (Maps SDKs section) | verified (fetched page), high |
| "Maps SDK MAUs cover any use of the Vector Tiles API and Raster Tiles API in an application that includes the Maps SDK". | https://docs.mapbox.com/android/maps/guides/pricing/ | verified, high |
| Mapbox Satellite is a raster tileset served through the Raster Tiles API. | https://docs.mapbox.com/data/tilesets/reference/mapbox-satellite/ | verified, high |
| Terrain-DEM v1 is a raster-dem tileset and "is not available via the Raster Tiles API". It is used as a style source (`mapbox://mapbox.mapbox-terrain-dem-v1`). | https://docs.mapbox.com/data/tilesets/reference/mapbox-terrain-dem-v1/ | verified, high |
| So satellite and terrain cost nothing extra inside the SDK: both are tile traffic covered by the MAU. | inference from the rows above; no page says "terrain is free" | unverified, high |
| MAU resets each billing period. Upgrading the app keeps it one MAU. "Deleting and re-installing an app that uses the Maps SDK will result in an additional MAU." Each device is counted separately. | https://docs.mapbox.com/android/maps/guides/pricing/ ; https://docs.mapbox.com/help/glossary/monthly-active-users/ | verified, high |
| Sign-up without a card is possible ("Start without a credit card"). The trial is capped at 100 Maps SDK MAU a month and allows one token, which cannot be rotated. | https://docs.mapbox.com/accounts/guides/signup/ | verified, high |
| The trial does not include "the Raster Tiles API and Permanent Geocoding. Adding a payment method unlocks the Raster Tiles API". | https://docs.mapbox.com/accounts/guides/signup/ | verified, high |
| So the satellite style will not load on a card-free trial account, and Daniel's account needs a payment method on file for this feature. | inference from the two rows above | unverified, medium-high. Check in the Console; Daniel may already have a card on file from earlier use. |
| On a trial, hitting a cap cuts off "all Mapbox APIs until you upgrade". | https://docs.mapbox.com/accounts/guides/demo-access/ | verified, high |
| With a payment method (pay-as-you-go), usage above the free tier is invoiced and charged automatically. Mapbox emails the first time a free tier is exceeded, and usage-threshold email alerts can be set. No hard spending cap is documented. | https://docs.mapbox.com/help/faq/how-does-pay-as-you-go-billing-work/ ; https://docs.mapbox.com/accounts/guides/demo-access/ | alerts verified; no hard cap: unverified (none found), medium |

**Realistic cost for Timburr:** 1 phone = 1 MAU per billing period. `tool/phone.sh` installs with `adb install -r` (`tool/phone.sh:3,27`), which is an upgrade, not a reinstall, so it does not add MAUs. A wipe and reinstall adds one. Even a few test devices or reinstalls stay orders of magnitude under 25,000. **Expected bill: $0/month** [verified pricing; usage estimate unverified, high].

## 2. Tokens

| Claim | Source | Status |
| --- | --- | --- |
| Tokens have public or secret scopes. "Secret scopes cannot be added to a public (`pk`) token." For maps in apps, use a public token with `styles:read`, `fonts:read`. | https://docs.mapbox.com/accounts/guides/tokens/ | verified, high |
| URL restrictions do not work for requests from apps built with the Mapbox Maps SDK, so a mobile `pk.` token can't be locked to the app. | https://docs.mapbox.com/accounts/guides/tokens/ | verified, high |
| Plugin 2.4.0: "Configuring Mapbox's secret token is no longer required when installing our SDKs." | `mmf:mapbox_maps_flutter/CHANGELOG.md:427` (under `### 2.4.0`) | verified, high |
| In v3.36.0 the Android plugin adds `https://api.mapbox.com/downloads/v2/releases/maven` with no credentials. Only the snapshots repo reads `SDK_REGISTRY_TOKEN`. | `mmf:mapbox_maps_flutter_mobile/android/build.gradle:19-31` | verified, high |
| 2.19.1 fixed a build failure when `SDK_REGISTRY_TOKEN` is unset, so leaving it unset is supported. | `mmf:mapbox_maps_flutter/CHANGELOG.md:225` | verified, high |
| The release Maven repo serves the SDK anonymously. | `curl` of `.../releases/maven/com/mapbox/maps/android-ndk27/11.36.0/android-ndk27-11.36.0.pom` and of the `android-core-ndk27` AAR returned HTTP 200 with no auth (run 2026-11-28) | verified, high |
| The Flutter plugin's documented token path: `MapboxOptions.setAccessToken(const String.fromEnvironment('ACCESS_TOKEN'))` in `main()` before any `MapWidget`, passed with `--dart-define`. | `mmf:mapbox_maps_flutter/README.md:29-50`; https://pub.dev/packages/mapbox_maps_flutter | verified, high |
| The native Android alternative is a `mapbox_access_token` string resource in `res/values`. The Flutter route doesn't need it. | https://docs.mapbox.com/android/maps/guides/install/ | verified, high |

**Where each token goes in Timburr**
- `pk.` public token: add `"MAPBOX_PUBLIC_TOKEN": "pk...."` to `.env.json`, which is git-ignored (`.gitignore:8-10`), and to `.env.example.json`. Read it in `lib/config.dart` next to the Supabase constants (`lib/config.dart:2-3`). `tool/phone.sh:25` already builds with `--dart-define-from-file=.env.json`, so nothing else changes there. In CI, add a `MAPBOX_PUBLIC_TOKEN` repo secret, add it to the empty-secret check loop (`.github/workflows/release.yml:24`), and pass it into the `jq` that writes `.env.json` (`:41-42`). The build line (`:52`) stays the same.
- `sk.` secret token: **none needed** [verified above]. No `gradle.properties` or `~/.gradle` entry is needed.
- Fit with the CLAUDE.md rules: "The app ships only the Supabase publishable (anon) key". A Mapbox `pk.` token is the same kind of thing, public and shipped in the binary, but it is a second public key, so the rule's wording should be widened to cover it. It is public, but anyone who extracts it can bill MAUs to the account. Mitigations: a dedicated token with only the default public scopes, a usage-threshold alert in the Console, and rotation if abused [docs verified; risk assessment unverified, high].

## 3. mapbox_maps_flutter capabilities

**Version and constraints**
- Latest: **3.36.0**, released 2026-11-27 (`gh api repos/mapbox/mapbox-maps-flutter/releases/latest`). It uses native Maps SDK `com.mapbox.maps:android-ndk27:11.36.0` (`mmf:mapbox_maps_flutter_mobile/android/build.gradle:68`) [verified].
- Constraints: Flutter >= 3.44.2, Dart >= 3.12.0 (`mmf:mapbox_maps_flutter/CHANGELOG.md`, 3.36.0-rc.1 notes; `mapbox_maps_flutter/pubspec.yaml` on main: `sdk: ">=3.12.0 <4.0.0"`, `flutter: ">=3.44.2"`). The repo has `sdk: ^3.12.2` (`pubspec.yaml:7`), and the local toolchain is Flutter 3.44.3 / Dart 3.12.2 (`flutter --version`) [verified, high].
- Android minSdk: the plugin needs 21 (`mmf:mapbox_maps_flutter_mobile/android/build.gradle:45`; https://docs.mapbox.com/android/maps/guides/ "Android SDK 21 or higher"). Timburr has `minSdk = 26` (`android/app/build.gradle.kts:34`) [verified, high].
- GPU: the native SDK needs "Devices that support OpenGL ES 3". An optional Vulkan backend is arm64-only, with Android 12+ recommended (https://docs.mapbox.com/android/maps/guides/) [verified]. Any recent phone has ES 3 [unverified, high].
- Build: 3.36.0 "uses built-in Kotlin and no longer applies the Kotlin Gradle Plugin. This fixes the `Could not find method kotlin()` build error with AGP 9 and `android.builtInKotlin=false`" (`mmf:mapbox_maps_flutter/CHANGELOG.md`, 3.36.0-rc.1). Timburr is on AGP 9.0.1 (`android/settings.gradle.kts:22`) with `android.builtInKotlin=false` (`android/gradle.properties`), so **use >= 3.36.0, not an older 2.x** [verified, high].

**APIs the replay needs**

| Need | API | Source | Status |
| --- | --- | --- | --- |
| Satellite style | `MapboxStyles.STANDARD_SATELLITE` (`mapbox://styles/mapbox/standard-satellite`), or the older `SATELLITE_STREETS` / `SATELLITE` | `mmf:mapbox_maps_flutter/lib/src/mapbox_styles.dart:10-11,32,37` | verified |
| Standard Satellite keeps Standard's 3D features and config (`lightPreset`, `show3dObjects`), set at runtime with `style.setStyleImportConfigProperty("basemap", ...)` | https://docs.mapbox.com/map-styles/standard/guides/ ; `mmf:mapbox_maps_flutter_mobile/lib/src/controllers/style_controller.dart:411` | verified |
| Whether Standard Satellite turns terrain on by itself | not stated on the Standard guide | unverified, low. Add the DEM explicitly (next row). |
| 3D terrain | `addStyleSource(id, {"type":"raster-dem","url":"mapbox://mapbox.mapbox-terrain-dem-v1","tileSize":514})` then `setStyleTerrain(jsonEncode({"source": id, "exaggeration": ...}))`; `setStyleTerrainProperty`, `removeStyleTerrain` | `mmf:mapbox_maps_flutter/example/lib/platform/performance_statistics_example.dart:143-164`; `mmf:mapbox_maps_flutter_mobile/lib/src/controllers/style_controller.dart:262,470` | verified |
| Camera pitch/bearing, one-shot moves | `setCamera(CameraOptions(center, zoom, pitch, bearing))`, `easeTo`, `flyTo` | `mmf:mapbox_maps_flutter_mobile/lib/src/mapbox_map.dart:302,706,713`; `example/lib/camera/camera_example.dart:95-99` | verified |
| Per-frame follow camera | `setFreeCameraOptions(FreeCameraOptions)`, added in 3.36.0 "to follow a moving object", with helpers `withLocation(point, altitude:)`, `withPitchBearing`, `lookingAt(point)` | `mmf:mapbox_maps_flutter/CHANGELOG.md` (3.36.0-rc.1); `mmf:mapbox_maps_flutter/lib/src/free_camera_options_extensions.dart:30-108`; `mmf:mapbox_maps_flutter_mobile/lib/src/mapbox_map.dart:314` | verified |
| Ground height for the camera | `getElevation(Point)` (null while terrain loads) | `mmf:mapbox_maps_flutter/example/lib/animations/animated_route_example.dart:697-698,773` | verified |
| A worked example of exactly this pattern | `animated_route_example.dart`: "drives a 3D car around the same circuit and moves the camera on every frame with `setFreeCameraOptions`", Ticker-driven, and skips a frame while the last is in flight so calls don't queue | `mmf:.../animated_route_example.dart:24-25,66,638,741-781` | verified |
| Route line | `GeoJsonSource(id, data, lineMetrics: true)` + `LineLayer(lineColor/lineWidth/lineCap/lineJoin)` | `mmf:.../animated_route_example.dart:129-150,183-190` | verified |
| Pace-coloured line | `LineLayer.lineGradientExpression` over `['line-progress']`. It "Can only be used with GeoJSON sources that specify `"lineMetrics": true`". `line-progress` is fraction of projected length, so pace stops must be mapped from distance fractions. | `mmf:mapbox_maps_flutter/lib/src/style/layer/line_layer.dart:294-298`; example `:137-147` | verified |
| "Drawn so far" effect | `LineLayer.lineTrimOffset` ([start, end] fractions), `lineTrimColor`, `lineTrimFadeRange` | `mmf:.../line_layer.dart:83-88,376` | verified |
| Line hidden by 3D objects | `lineOcclusionOpacity` | `mmf:.../animated_route_example.dart:192-194` | verified |
| Moving marker | A `GeoJsonSource` point + `CircleLayer` updated with `setStyleSourceProperty` / `updateGeoJSONSourceFeatures` each frame. The example uses this instead of `PointAnnotation` for portability. `PolylineAnnotationManager` also exists (with `setLineTrimOffset`) but has no gradient. | `mmf:.../animated_route_example.dart:156-175`; `mmf:mapbox_maps_flutter_platform_interface/lib/src/interfaces/style_interface.dart:170,319`; `mmf:mapbox_maps_flutter_mobile/lib/src/annotation/polyline_annotation_manager.dart:368` | verified |
| Name clashes | The package exports `Point`/`Position` (turf). The example imports `geolocator` with a prefix to avoid the clash. Timburr uses geolocator and latlong2, so import Mapbox with a prefix in the replay file. | `mmf:.../animated_route_example.dart:7-10` | verified |

## 4. Offline

| Claim | Source | Status |
| --- | --- | --- |
| Style packs (`OfflineManager.loadStylePack`) plus tile regions (`TileStore.loadTileRegion` with `TileRegionLoadOptions(geometry, descriptorsOptions: [TilesetDescriptorOptions(styleURI, minZoom, maxZoom)])`). Both return a cancellable future since 3.36.0. | `mmf:mapbox_maps_flutter_mobile/lib/src/offline/offline_manager.dart:68`, `tile_store.dart:94`; `mmf:mapbox_maps_flutter/CHANGELOG.md` 3.36.0-rc.1 | verified |
| The official example downloads `STANDARD_SATELLITE` to z16 for a region. | `mmf:mapbox_maps_flutter/example/lib/docs/offline_map_example.dart:83-116` | verified |
| A region geometry can be a point, a linestring or a polygon. A linestring limits the area more precisely than a bbox, which suits a route corridor. | https://docs.mapbox.com/android/maps/guides/offline/concepts/ | verified |
| Tile regions support Mapbox v4 vector/raster tiles and Raster DEM v1, so terrain can be stored offline. | same page | verified |
| "The cumulative number of unique tile packs used in the tile regions cannot be greater than 750." | same page; https://docs.mapbox.com/help/dive-deeper/mobile-offline/ | verified |
| "Resources downloaded for offline use are included in the regular monthly active user (MAU) billing." | https://docs.mapbox.com/help/dive-deeper/mobile-offline/ | verified (current page). A legacy-SDK pricing page says otherwise; it applies to old SDKs only [unverified, medium]. |
| Terms: offline maps may not be redistributed. "the data may not be preloaded, bundled or otherwise redistributed." The app must download them itself. | https://docs.mapbox.com/android/maps/guides/offline/concepts/ (citing the ToS) | verified |
| Tile packs can range "from tens to hundreds of megabytes". Offline data does not refresh itself. There is no size limit on the tile store by default (`TileStoreOptions.diskQuota`). | same page | verified |
| Without a region, the normal disk cache keeps recently viewed tiles with "no guarantees about how long", so a replay watched once online may partly work offline later. | same page | verified (behaviour); usefulness unverified, medium |

For Timburr: download a linestring-corridor region for a Run only when Daniel taps "Save replay for offline" (or auto, on Wi-Fi). A replay otherwise needs network; flutter_map's OSM maps keep working offline as today.

## 5. Coexistence, size, terms

- **Keep flutter_map; add Mapbox only for the replay screen.** flutter_map is used in `lib/ui/cardio/run_page.dart:200-240` (`osmTileLayer`, `RunMap`), `lib/ui/running/heatmap_screen.dart:75-80` and `lib/ui/running/running_tab.dart:183-189` [verified, grep]. Replacing those would put every map behind a token, the network, and MAU counting, for no gain. The two packages don't share native code, so they can sit side by side [unverified, high].
- **APK size (measured estimate).** Mapbox documents no size. The native libraries come from the Maven AARs, counted per ABI: `libmapbox-maps.so` (`android-core-ndk27:11.36.0`) is arm64 14.9 MB, armv7 10.3 MB, x86_64 16.5 MB; `libmapbox-common.so` (`common-ndk27:24.36.0`) is 7.2, 4.8 and 7.7 MB; and `libc++_shared.so` (about 1.3 MB per ABI) is not in the current APK. The current release APK is 103 MB and stores its `.so` files uncompressed (`unzip -v`: "Stored 0%"), with 3 ABIs. That adds about **+62 MB** for the fat APK (about 103 to 165 MB), or **about +23 MB** for arm64 only (`--split-per-abi` / `--target-platform android-arm64`). Dex and resources are extra [verified sizes by command; total unverified, medium].
- **Attribution (required).** "You must include the Mapbox wordmark on any map that uses the Mapbox Maps SDK for Android." You must also show attribution. Both can be moved but must stay visible on the map (https://docs.mapbox.com/android/maps/guides/). Satellite styles also need `© Maxar` (https://docs.mapbox.com/help/getting-started/attribution/). The SDK adds the logo and info button itself [verified]. Keep the replay header and scrubber from covering them.
- **Telemetry.** "By default, the SDK sends unidentified location and usage data to Mapbox". The ToS require a per-user opt-out, which the built-in attribution control provides (https://docs.mapbox.com/android/maps/guides/) [verified]. For a personal app this matters for privacy, not legality: opt out once through the info button. The replay shows recorded points, not live location, so the location component should stay off [unverified, high].
- **Caching and redistribution.** See section 4: no bundling or preloading of Mapbox tiles [verified]. The fetched ToS page itself only says not to remove proprietary notices (https://www.mapbox.com/legal/tos) [verified, low detail].

## 6. Alternative: MapLibre + MapTiler

| | Mapbox (`mapbox_maps_flutter` 3.36.0) | MapLibre (`maplibre_gl` 0.28.1) + MapTiler free |
| --- | --- | --- |
| 3D terrain on Android | yes (`setStyleTerrain`) [verified] | **no**: `setTerrain` throws `UnsupportedError` "because MapLibre Native does not implement 3D terrain yet. Terrain is supported on web." (`maplibre_gl/lib/src/native_map_platform.dart:1814-1819`, tag v0.28.1; `CHANGELOG.md:241`) [verified] |
| Pitch/bearing, 2.5D satellite with pitch | yes | yes (pitch exists; flat imagery) [verified pitch in examples; flat result unverified, high] |
| Key | public `pk.` token | MapLibre: "no account or API key required" (https://pub.dev/packages/maplibre_gl); MapTiler needs its own key in the app [verified; MapTiler key unverified, high] |
| Free tier | 25k MAU, overage billed | MapTiler Free: 5k sessions + 100k API requests/month, "No credit card needed", "Suitable for ... personal, or non-commercial use", and "service will pause until the next month" past the limit (https://www.maptiler.com/cloud/pricing/) [verified]. Satellite/terrain on Free not stated [unverified]. |
| Min SDK | 21 | 24 (`maplibre_gl/android/build.gradle:62`) [verified] |
| Offline | yes | "Offline regions" on Android/iOS (pub.dev) [verified] |

So MapLibre gives a cheaper, card-free 2.5D tilted satellite replay, but not the terrain flyover. If the goal is Strava's look, Mapbox is the only option of the two today.

## 7. Implementation sketch for Timburr

**Files**
- `pubspec.yaml`: add `mapbox_maps_flutter: ^3.36.0`.
- `lib/config.dart`: `const mapboxPublicToken = String.fromEnvironment('MAPBOX_PUBLIC_TOKEN');`.
- `lib/main.dart`: if the token is non-empty, call `MapboxOptions.setAccessToken(mapboxPublicToken)` after `WidgetsFlutterBinding.ensureInitialized()`. Hide the Replay button when it is empty, the same way sync is off without a Supabase URL.
- `.env.example.json`, `.env.json`: add `MAPBOX_PUBLIC_TOKEN`.
- `tool/phone.sh`: no build change (it already uses `--dart-define-from-file`). Optionally extend `check_config` to grep `libapp.so` for the token's prefix, as it does for the Supabase host (`tool/phone.sh:11-21`).
- `.github/workflows/release.yml`: add the `MAPBOX_PUBLIC_TOKEN` secret to the env blocks, the check loop (`:24`) and the `jq` (`:41-42`).
- `lib/data/replay.dart` (new, pure, tested in `test/replay_test.dart`): from a `Track` (`lib/data/track.dart:22-33`) build the timed, non-null points. Reuse `timedIndices`/`smoothAltitude` from `lib/data/run_analysis.dart:19,67`. Provide `sampleAt(seconds) -> (lat, lon, distanceM, altitudeM, paceSecPerKm, headingDeg)` with linear interpolation, a smoothed heading (so the camera doesn't jitter on GPS noise), the pace stops for `lineGradientExpression` keyed by distance fraction, and the camera pose (a point behind the runner along the smoothed heading at height H, `lookingAt` the runner). This holds all the logic, with no Mapbox imports.
- `lib/ui/cardio/replay_screen.dart` (new): full-screen `MapWidget(styleUri: MapboxStyles.STANDARD_SATELLITE)`. Its `onStyleLoaded` adds the DEM source, `setStyleTerrain` and the route `GeoJsonSource(lineMetrics: true)` + orange `LineLayer`, plus the marker source + `CircleLayer`. It has a header (pace / elevation / distance) and a bottom scrubber with play/pause and 1x/2x.
- `lib/ui/cardio/run_page.dart:109`: a "Replay" button on or under `RunMap` that pushes the replay screen. `RunMap` itself stays on flutter_map.
- `CLAUDE.md` / `docs/design.md`: widen the "only publishable key" rule to name the Mapbox `pk.` token, and record the Mapbox attribution and telemetry choices.

**Animation loop** (after the official example, `animated_route_example.dart:741-781`)
- A `Ticker` (via `SingleTickerProviderStateMixin`) advances `replaySec += dt * speed`. Pick a speed so a 30-60 min run plays in about 60-90 s at "1x", like Strava. The exact Strava mapping is unverified.
- Each tick: `s = replay.sampleAt(replaySec)`, then `setState` for the header and scrubber (Flutter side, cheap). If no frame is in flight, `Future.wait([` update the marker source, set `lineTrimOffset`/progress, `setFreeCameraOptions(FreeCameraOptions().withLocation(camPoint, altitude: groundElev + H).lookingAt(runnerPoint))`, and `getElevation(runner)` for the next frame `])`. Skip frames while a call is in flight so platform-channel calls don't pile up.
- Start with a `flyTo` from an overview to the start pose. Pause stops the Ticker. Dragging the scrubber sets `replaySec` and renders one frame.
- Offline (optional, phase 2): a "Download for offline" action builds a linestring region from the route and calls `loadStylePack(STANDARD_SATELLITE)` + `loadTileRegion` (z10-16, terrain included), with a `TileStoreOptions.diskQuota`.

**Verdict**
- **Feasible:** yes. Every piece is a documented plugin API, and an official example already does Ticker + free camera + terrain + trimmed gradient line [verified].
- **Effort:** medium, about 2 to 4 days: half a day for setup and token plumbing (CI too), a day for pure `replay.dart` with tests, a day or two for the screen and camera tuning on the phone, plus optional offline [unverified estimate, medium].
- **Risks:**
  - APK +23 to 62 MB [measured estimate].
  - Satellite needs a payment method on the Mapbox account [inference, medium-high].
  - Needs network unless pre-downloaded.
  - Per-frame method-channel latency could stutter on the phone. The example's frame-skip pattern is the mitigation; test early [unverified, medium].
  - `line-progress` is projected length, not run distance, so pace colours drift slightly on long runs [verified definition; impact unverified, low].
  - Telemetry is on by default.
  - The token is extractable, so set a usage alert.

## Phone checks before committing to it

1. Create (or check) the Mapbox account: payment method present? Make a dedicated `pk.` token.
2. Spike: add the package, open one `MapWidget` with `STANDARD_SATELLITE` + terrain on the phone via `tool/phone.sh`. Check it builds under AGP 9 / `builtInKotlin=false`, check the APK size delta, and check satellite loads.
3. Run the plugin's `animated_route_example` "Free camera drive" scene on the phone to judge smoothness before writing Timburr's loop.
4. Check that the Console shows 1 MAU after a day of testing.

## Gaps (searched, not found)

- Whether Standard Satellite enables terrain by default.
- A documented APK size for the Android SDK (estimated above from the AARs instead).
- A hard spending cap for pay-as-you-go accounts.
- The ToS clause text on caching (only the offline guide's summary of it was read).
