# Contributing

## Getting set up

```
brew install xcodegen swiftlint swiftformat
xcodegen generate
```

The `.xcodeproj` is generated from `project.yml` and gitignored. Add files by
creating them in the right directory and re-running `xcodegen generate` — never
by editing project settings in Xcode, since those changes are discarded on the
next generate. Structural changes belong in `project.yml`.

## Before opening a pull request

```
swiftformat . && swiftlint
xcodebuild -project Scriptorium.xcodeproj -scheme Scriptorium \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## Things worth knowing

**Grimmory's API is the source of truth, and it has sharp edges.** Covers are
served from `/api/books/{id}/cover` while everything else lives under
`/api/v1/`. `/api/v1/version` requires authentication, so the server-version
check can't happen during onboarding. Both are verified against a live server,
not inferred — see `GrimmoryEndpoint`.

**Don't trust the Java DTOs for boolean key names.** Grimmory uses Lombok
`@Data`, and Lombok's generated getters change how Jackson names booleans: a
primitive `boolean isAdmin` serialises as `"admin"`, while a boxed
`Boolean isPhysical` stays `"isPhysical"`. When adding a model, capture a real
payload with `Tools/capture-fixtures.sh` and check.

**Reading position is CFI-based and must stay exact.** Anything touching the
reader or progress sync should preserve byte-identical CFIs — that is what keeps
the app in step with Grimmory's web reader, Kobo and KOReader. If you change how
positions are produced or stored, test it against a real server both ways.

**Privacy is a feature, not a default.** No analytics SDKs, no crash reporters
that phone home, no network calls to anything but the user's own server. A pull
request that adds one will be declined.

## Commit and PR style

Small, focused commits with a plain description of the change and why. If a
change is user-visible, say what someone would notice.
