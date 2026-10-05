# Better OQB

Better OQB is a Flutter study client for the Hong Kong Education City Online
Question Bank (`oqb.edcity.hk`). The real OQB website runs inside an embedded
browser and stays responsible for login, permissions and authentication;
Better OQB uses OQB's JSON API from that same authenticated page and renders
a responsive study interface for phones, tablets and desktops.

It does not bypass permissions, mirror the question database, or store your
OQB password, token or trial session keys.

## How it works

```text
Flutter UI (CatalogView, StudyView, review)
        │
StudyController / CatalogController      lib/src/controllers/
        │
OqbRepository + typed models             lib/src/services/, lib/src/models/
        │
OqbRequests → OqbWebViewApiClient        endpoint layouts, request ids, timeouts
        │
window.betterOqbApi (assets/oqb_api_client.js)
        │  same-origin fetch, token + sesskey stay in this closure
https://oqb.edcity.hk/api/...
```

- **Login** happens on the real OQB page. If you are not signed in, Better OQB
  shows the original page automatically and switches back once OQB has an
  authenticated session.
- **Home** is built from `get_usable_packages` (banks the account can use,
  with topic/difficulty counts), `load_papers` (papers to start/resume, preset
  papers), `load_submitted_papers` and `/public/meta.json` labels.
- **Studying** calls `start_trial` and renders each `trial_question` directly
  from API data (HTML, tables and images preserved). Navigation, jumping and
  answer selection are local and immediate; answers are saved with
  `save_trial` using the trial-question id, with a visible
  saved / unsaved / saving / not-saved state, automatic retry and manual retry.
  Answers are never discarded until OQB accepts them.
- **Exercise papers** have a "Show answer" button, like OQB's own Show:
  it checks the question (`status=submitted`), marks the correct choice and
  locks that answer. Test papers do not have it.
- **Submitting** is only possible from a confirmation dialog. It first saves
  any pending answers and refuses to submit if they cannot be saved.
- **Review** uses `start_trial(opts[review]=1)` and a detailed `load_paper`
  to show score, per-question correctness, suggested/model answers and
  topic/difficulty breakdowns.
- **Original OQB** is always one tap away (app bar or the study ⋮ menu). During
  an attempt it opens at the same question. If you open a paper in the
  original page, Better OQB picks up its `/paper/{id}/do/{n}` route and opens
  the same attempt at the same question through the API.
- **Compatibility fallback**: if the API cannot load a paper that OQB is
  showing, the older DOM-scraped question view (`assets/oqb_bridge.js`) is
  shown with a "compatibility mode" banner.

The observed API is documented in [`docs/OQB_API_MAP.md`](docs/OQB_API_MAP.md),
including which request/response details are still assumptions.

### Layouts

- Phone: single column, bottom Previous / question grid / Next bar, submit in
  the header.
- Tablet (≥1000 px wide): permanent question navigator panel with
  filters (to do / done / pending or wrong).
- Wide desktop: question and answers side by side so the answers stay visible
  next to long questions and diagrams.
- Images can be tapped to zoom. Keyboard: ←/→ to navigate, A–H or 1–8 to answer.

### Privacy and security

- The OQB token is learned inside the page from OQB's own requests and never
  leaves it; Flutter only learns whether a token is available.
- Trial sesskeys are captured from `start_trial` inside the page and never
  leave it.
- Requests are only made to same-origin `/api/` paths on `oqb.edcity.hk`, from
  an allow-list of commands.
- Payloads passed to Flutter have tokens, sesskeys and personal identifiers
  removed. Signed asset URLs are used for rendering only and kept in memory.
- The API inspector (heart-monitor icon) shows redacted traffic and a
  non-sensitive client log (commands, outcomes and payload shapes).

## Platforms

- `flutter_inappwebview` on Android, iOS/iPadOS, macOS and Windows.
- CEF Chromium through `webview_cef` on Linux.

## Bootstrap

Generate Flutter's native runner projects on a machine with Flutter installed:

```bash
flutter create --platforms=android,ios,linux,macos,windows .
flutter pub get
flutter run -d linux   # or an attached iPad/Android device (flutter devices)
```

## Development

```bash
flutter analyze
flutter test
```

Tests cover request layouts (including MC answer serialization and the
trial-question vs question id distinction), `start_trial`/review parsing,
malformed payloads, the WebView client protocol, save state and retry,
submission rules, route detection, and phone/tablet/desktop layouts.
