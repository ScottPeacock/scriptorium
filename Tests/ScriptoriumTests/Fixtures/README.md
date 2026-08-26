# API fixtures

Captured from a real Grimmory server so decoding is tested against payloads the
server actually emits, not against a reading of its Java sources.

- `public-settings.json` / `error-401.json` — captured anonymously from
  Grimmory 26.x at `192.168.1.21:6060`.
- Authenticated fixtures (`app-books.json`, `app-book-detail.json`,
  `app-user-me.json`) are captured with `Tools/capture-fixtures.sh`.

The capture script redacts nothing, so review anything you commit. Files ending
`.local.json` are gitignored for captures you'd rather keep off the record.

Booleans are the thing to check when adding a fixture: Grimmory's DTOs are
Lombok `@Data`, and Lombok's generated getters change how Jackson names them —
a primitive `boolean isAdmin` serialises as `"admin"`, a boxed `Boolean
isPhysical` stays `"isPhysical"`. See `BoolKeyDecoding.swift`.
