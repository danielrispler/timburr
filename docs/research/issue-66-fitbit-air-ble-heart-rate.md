# Fitbit Air BLE heart rate sharing (issue #66, parent #53)

Question: can Timburr read live heart rate during a Run from a Google Fitbit Air over the standard BLE Heart Rate Profile, after "Share heart rate" is turned on in the Google Health app (Connections, the device)? Sources: https://github.com/danielrispler/timburr/issues/66 and https://github.com/danielrispler/timburr/issues/53

Labels used on every claim: **[official]** Google help center; **[vendor]** a third-party app's own docs (they ship Air support, but are not Google); **[blog]** a third-party article; **[user]** a community report; **[unverified]** stated by a source with no evidence, or inferred. Nothing here was tested on the device. Search results were summarised by a fetch tool, so exact wording should be re-checked on the pages before quoting.

## Short answers

1. **Standard HR service for any app?** Probably yes, not officially confirmed at GATT level. Google says the Air works with equipment and apps that use the Bluetooth Heart Rate Profile [official, g-help]. A GitHub project lists `0x180D` with notify on `0x2A37` (about 1 Hz), plus Battery `0x180F` and Device Information `0x180A`, but it states no measurements [vendor/unverified, gh-air-research]. Pulsoid says the Air "works like a regular Bluetooth (BLE) heart rate monitor" [vendor, pulsoid]. Pulsoid, HeartCast, FITIV and ZonePoints list it as a source [vendor, pulsoid, fitiv, zonepoints]. Same feature on Fitbit Edge, Charge 6 and Pixel Watch 2 or later [official, g-help]. The Air is documented differently: it is set up from the Google Health app (Connections, device, Share heart rate, Get started); Charge 6 and Edge use "Broadcast HR" on the tracker; Pixel Watch uses Connected Fitness [official, g-help]. Charge 6 behaviour is not proven to carry over.
2. **Streams while Google Health stays connected?** Not documented. Google's page gives connection limits only for other devices: Charge 6 one at a time, Pixel Watch 3 or later up to two [official, g-help]. It gives no limit for the Air. ZonePoints says sharing is one-to-one and a second scan cannot find the band while an app holds the connection [blog, zonepoints], and it also does not state the Air's limit. Google Health listing the device under "Connected equipment and apps" as "Sharing heart rate" [vendor, pulsoid] suggests Google Health is itself a party to sharing, but that is not a statement about its sync link. Unknown; this is the main thing to test.
3. **Does sharing switch itself off?** Conflicting or unverified. ZonePoints says sharing usually ends with the workout and the band stops broadcasting rather than returning to advertising, and that toggling Share heart rate off and on restores it [blog, unverified, zonepoints]. Matching Charge 6 reports of sharing dropping at workout end and needing re-pairing each session exist [user, see below]. Google's page does not mention a timeout, a workout end, low battery, or restart [official, g-help; checked for these topics and found none]. The "Always visible" toggle keeps the band advertising in the background without Google Health open; Google warns it may affect battery [vendor, pulsoid; blog, zonepoints; vendor, fitiv]. Battery: Google says sharing "impacts battery life" [official, g-help]; no figure found. Effect on sync: nothing found.
4. **Pairing, bonding, Android specifics?** Unclear. Google says Pixel Watch 3 or later may ask for a PIN, and not all equipment prompts for one [official, g-help]; nothing says the Air does. The GitHub project says Google's implementation "may require bonding" before streaming, hedged and unmeasured, and advises accepting the system pairing prompt [vendor/unverified, gh-air-research, gh-air-troubleshooting]. FITIV pairs it inside its own sensor list [vendor, fitiv]. The Air advertises `0x180D` only while sharing is on, so it is invisible to scanners otherwise [vendor, gh-air-troubleshooting; blog, zonepoints]. While another app holds the connection a scan does not see it [blog, zonepoints]. Google documents no Android permissions for this; the Bluetooth permissions the app needs are Android's own (see "What this means").
5. **Known third-party problems?** No Air-specific bug reports found. Reports found are for Charge 6: sharing with Strava and Wahoo works after re-pairing, then drops at workout end, every session [user, fc-charge6-search]; a firmware-update thread titled "Constant issues sharing HR to devices since latest firmware update" [user, fc-firmware]; and one user who could not enter a pairing code for a NordicTrack bike [user]. Google's troubleshooting: update equipment firmware, restart the device, make sure it is not connected elsewhere, unpair, toggle Bluetooth on the equipment, pick the most recent entry if several appear [official, g-help]. Workarounds seen: Always visible; toggle Share heart rate off and on [blog, zonepoints]; FITIV says Always visible can reset after an app update [vendor, fitiv]. Google lists Strava, Zwift, Peloton, Wahoo, Concept2 (latest firmware only), Echelon, Hydrow, iFIT, Life Fitness, Matrix, Schwinn, Spinning, Tonal as compatible with the Air; Garmin and Technogym are not [official, g-help].

## What this means for Timburr

**Buildable as specified?** Likely, with an explicit "unconfirmed" label until the phone check passes. Strava finding the band (already seen) and the vendor reports above point at a standard HR service. Nothing found says third-party apps are blocked. Nothing official guarantees the GATT layout, so the first thing to read is the actual GATT table.

**Risks, most serious first**
- Concurrent connection with Google Health is undocumented. If the Air allows one connection, live HR in Timburr could break Google Health's sharing state, or the reverse. Health Connect fill-in after the run (already in the design) is the fallback and needs no BLE.
- Sharing may stop at workout end or on its own. Plan for the stream dropping mid-Run: reconnect, keep GPS recording, and show a gap rather than failing the Run.
- Always visible has a battery cost and may reset after Google Health updates [vendor, fitiv]. It is the likely required setting, so the app should say so when no band is found.
- Possible bonding requirement [unverified]. The app must handle a failed subscribe by prompting for pairing, not retrying silently.
- The band stops advertising while connected elsewhere [blog, zonepoints], so "device not found" can mean "someone else holds it".
- Android permissions are from Android, not Google's page: Android 12 and up needs BLUETOOTH_SCAN and BLUETOOTH_CONNECT at runtime, and older versions need location. This is from general knowledge, not a source fetched here; check against developer.android.com before building.

**What to check on the phone** (this is issue #66)
1. With nRF Connect: turn on Share heart rate, and with Always visible off then on, see whether the band advertises, and note the advertised name and service UUIDs.
2. Connect and read the GATT table: is `0x180D` with `0x2A37` notify present, and do values stream at about 1 Hz? Is `0x2A38` body sensor location present?
3. Does subscribing succeed with no bonding? If not, does the system prompt appear, and does it work after bonding?
4. With Google Health open and its connection to the band active (sync, "Sharing heart rate" status), connect nRF Connect. Does it connect, and do values stream? Then connect a second scanner while the first holds the link, to learn the connection limit.
5. Start and end a workout on the band while streaming. Does sharing continue, stop, or need re-enabling?
6. Leave it streaming about an hour, then restart the band and run a sync. Does it survive? Note battery drop per hour, with and without Always visible.
7. Test Strava as a second client at the same time as nRF Connect, since the Run will use the same path.
8. Record firmware and Google Health app versions with the results; the reports above tie behaviour to firmware.

## Gaps (searched, not found)

- Any Google statement of the Air's GATT services, bonding behaviour, or connection limit.
- Any Google statement on timeouts, workout-end behaviour, low-battery behaviour, restart, or sync interaction.
- Any battery figure for sharing.
- Any Air-specific problem report with a third-party Android app. The Charge 6 community threads are the only reports; the firmware thread URL redirected to a generic community page when fetched, so its content was not read.
- Bluetooth SIG specification text was not fetched; the HR service and measurement UUIDs above are as quoted by the sources.

## Sources

- [g-help] Google Health Help, "Share your real-time heart rate with fitness equipment & apps" [official]: https://support.google.com/fitbit/answer/14236705
- [pulsoid] Pulsoid, "How to show heart rate on stream using Fitbit Air" [vendor]: https://blog.pulsoid.net/post/how-to-show-heart-rate-on-stream-using-fitbit-air
- [zonepoints] ZonePoints, "How to see your Fitbit Air's live heart rate on Android" [blog]: https://zonepoints.app/articles/fitbit-air-live-heart-rate/
- [fitiv] FITIV, "How to See Live Heart Rate on Fitbit Air" [vendor]: https://www.fitiv.com/blog/fitbit-air-live-heart-rate
- [gh-air] AyushSagar16/fitbit-air README [vendor/unverified]: https://github.com/AyushSagar16/fitbit-air
- [gh-air-research] same repo, docs/RESEARCH.md: https://github.com/AyushSagar16/fitbit-air/blob/main/docs/RESEARCH.md
- [gh-air-troubleshooting] same repo, docs/TROUBLESHOOTING.md: https://github.com/AyushSagar16/fitbit-air/blob/main/docs/TROUBLESHOOTING.md
- [fc-firmware] Fitbit Community, Charge 6, "Constant issues sharing HR to devices since latest firmware update" [user; not read, redirected]: https://community.fitbit.com/t5/Charge-6/Constant-issues-sharing-HR-to-devices-since-latest-firmware-update/td-p/5651133
- [fc-charge6-search] Fitbit Community Charge 6 threads on HR broadcasting [user; seen only as search snippets]: https://community.fitbit.com/t5/Charge-6/Charge-6-HR-broadcasting-incompatibility-I-ll-evaluate-workarounds-please/td-p/5577725 and https://community.fitbit.com/t5/Charge-6/Charge-6-cannot-connect-with-my-equipment/td-p/5573064
