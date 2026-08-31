# Releasing to TestFlight

Bundle ID `pts.Scriptorium`, team `9RMKEEYW58`.

## First release only

1. **Reserve the name.** App Store Connect > Apps > **+** > New App.
   - Platform: iOS, Bundle ID: `pts.Scriptorium`, SKU: anything (`scriptorium`).
   - Name: `Scriptorium` if it's free. No app currently uses that exact name,
     but Apple may hold reservations that don't show in search — if it's taken,
     pick another and only the App Store listing changes, not the bundle ID.
   - If `pts.Scriptorium` isn't in the Bundle ID list, archiving once from Xcode
     registers it, or add it under Certificates, Identifiers & Profiles.

2. **Distribution certificate.** Xcode creates one the first time you distribute.
   Apple caps these at 3 per account, so reuse an existing one if you have it.

## Every release

```
xcodegen generate && open Scriptorium.xcodeproj
```

Product > Archive, then Organizer > Distribute App > TestFlight & App Store.

Or from the terminal, once a distribution certificate exists:

```
./Tools/archive.sh
```

Add `--upload` to send it to TestFlight without opening Xcode. That needs an
App Store Connect API key — see the comment at the top of the script.

## Version and build numbers

`MARKETING_VERSION` in `project.yml` is the version people see; bump it by hand.
The build number is set automatically by a build-phase script (see
`postBuildScripts` on the `Scriptorium` target in `project.yml`) from a UTC
timestamp, so it always increases and never needs a manual bump — this
applies whether you archive from Xcode's GUI or via `Tools/archive.sh`. App
Store Connect rejects a build number it has already seen, which is also why
this isn't the git commit count: a squash merge can reduce that number.

## Before the first external testers

- [ ] Test against a real server over the network the testers will actually use
      (Tailscale or a reverse proxy, not just the LAN).
- [ ] Confirm the local-network permission prompt reads sensibly on first launch.
- [ ] Check that a book downloads and opens on a physical device, not only the
      simulator.
- [ ] Write the "What to Test" note: connecting to a server, downloading, and
      whether position sync agrees with the web reader.

External testing needs Beta App Review; internal testers (up to 100 on your own
team) do not, which makes internal the faster first loop.
