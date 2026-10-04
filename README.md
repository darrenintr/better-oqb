# Better OQB

Better OQB is a Flutter study client that keeps the real `oqb.edcity.hk`
website as the authenticated backend while presenting it in a cleaner,
responsive interface for phones, tablets, and desktops.

## Current prototype

- Opens the real OQB site; login and entitlement remain handled by OQB.
- Uses `flutter_inappwebview` on Android, iOS/iPadOS, macOS, and Windows.
- Uses CEF Chromium through `webview_cef` on Linux.
- Injects a small JavaScript adapter after page load.
- Sends page headings/actions back to Flutter through a JS bridge.
- Includes a temporary inspector so the real OQB DOM can be mapped before the
  optimized question renderer is implemented.
- Does not store passwords or mirror the OQB question database.

## Bootstrap

This branch contains the application source first. Generate Flutter's native
runner projects on a machine with Flutter installed:

```bash
flutter create --platforms=android,ios,linux,macos,windows .
flutter pub get
```

Then run the platform you want, for example:

```bash
flutter run -d linux
```

or select an attached iPad/Android device with `flutter devices`.

## Architecture

```text
Flutter responsive UI
        |
        +-- OQB bridge/model
        |
Embedded real OQB browser
        |
https://oqb.edcity.hk
```

The next stage is to log in normally, navigate through a question set, and use
the inspector output to map stable selectors for subjects, question text,
answers, diagrams, navigation, and result state. Those mappings will stay in
the adapter layer rather than being spread throughout the Flutter UI.
