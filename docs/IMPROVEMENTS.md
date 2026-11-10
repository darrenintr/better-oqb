# Better OQB improvements

This branch implements the supplied 25-phase plan in the existing Flutter app.
Physical-device performance acceptance remains separate from implementation.

| Plan | Implementation |
| --- | --- |
| 0: measurements | `OQB_PERF` overlay and bounded timeline samples; 100/500/1000-stroke host benchmarks; device profile harness |
| 1: incremental ink | Independent paper, committed-ink and active-ink repaint boundaries; pointer moves do not rebuild the widget tree or notify completed-ink listeners |
| 2–3: hold and shapes | 450 ms hold within 2 logical paper pixels; 140 ms preview; line, circle, ellipse, rectangle, triangle, polygon, single-stroke arrow and right-angle axes recognizers |
| 4: scratch erase | Fast, dense backtracking with at least four reversals and repeated old-ink crossings; spatial lookup; optional toggle |
| 5: erasers | Whole-stroke and segment splitting; interpolated eraser path avoids skipping sparse samples; one undo per drag |
| 6–7: ink quality | 0.6 paper-pixel sample filtering, quadratic smoothing, off/low/medium pressure (low default) |
| 8: Pencil extras | iOS local plugin: double tap switches tools, squeeze opens palette; Flutter hover preview. Hardware support is device-dependent |
| 9: history | Delta commands retain added/removed stroke identities and indices, including reversible shape snapping and grouped erasing |
| 10: persistence | v2 metadata and stroke records; v1 read compatibility; 650 ms debounce; lifecycle/navigation/close flush; off-isolate encoding for 100+ strokes; pending-write buffer and atomic serialized disk replacement |
| 11–12: rendering | Session/navigation notifier separated from answer/save updates; retained HTML widgets invalidate on content, style or inherited dependency changes |
| 13–14: resources | Next-question resource parsing and image fetch/decode; exact-HTML bounded resource cache; encoded bytes budget 32 MiB, Flutter decoded image cache 64 MiB, max three asset fetches; full resolution available when zooming |
| 15–16: catalogue | Concurrent meta/packages/papers; two subject workers, selected-subject priority; persisted allowlisted package metadata with background authenticated refresh |
| 17–19: workspace | Secondary tools in menus/outlined actions; saved draggable 30–70% landscape split; full-screen portrait working with one-action close |
| 20–21: study intelligence | Async correctness history after OQB reveals a result; subject/topic/difficulty and timestamps only; accuracy, recent/previous 20-attempt trend, weak topics, latest-wrong retry queue, AI revision prompt export |
| 22: startup | Flutter shell first; authenticated WebView mounted after first frame; catalogue refresh waits for the API session |
| 23–24: interaction | 160 ms question transition; existing reduced-motion support also disables snap animation; divider screen-reader increase/decrease actions, question numbering, high-contrast themes, standard scalable text and tool hit targets |
| 25: validation | Ink, persistence, catalogue concurrency, asset cache, mistake history, workspace layouts and retained-HTML tests; existing regression suite |
| P3 | Freehand lasso, move, grow/shrink selection with reversible edits |

## Run checks

```sh
flutter pub get
flutter analyze
flutter test --reporter expanded
flutter run --profile --dart-define=OQB_PERF=true
```

The opt-in overlay reports shell startup, paper API, question-render interval,
HTML first-frame interval, asset fetch, ink event-to-paint, save latency, stroke
counts and UI/raster frame durations. Event-to-paint is a Flutter-side interval,
not physical pen-to-photon latency. Timeline samples are memory-only and bounded.
Use DevTools for heap/retained memory; the device harness also records process RSS.

## Device profile benchmark

```sh
flutter drive --profile \
  --driver=test_driver/performance_driver.dart \
  --target=integration_test/ink_performance_test.dart \
  --dart-define=OQB_PERF=true
```

The harness seeds 100/500/1000 completed strokes with 80 points each and draws a
new stylus stroke. It reports frame timings/GC via `watchPerformance`, process
RSS, JSON size and a real temporary-file save duration. Synthetic input tests
rendering and storage, not the Pencil radio/input stack. Compare the same device,
refresh rate, build mode, dataset and thermal state before/after changes. Remove
the benchmark temporary file through the app sandbox after profiling if desired.

Manual acceptance on iPad, Android tablet and desktop:

- Measure home readiness, paper opening, Q1→Q2, image display and ink-save latency.
- Check UI/raster frame budgets: 16.7 ms at 60 Hz, 8.3 ms at 120 Hz.
- Draw at 100/500/1000 strokes; inspect memory and sustained rendering in profile.
- Check Pencil still down → hold preview → lift; resume drawing after snapping.
- Scratch existing writing; preserve sine graphs and deliberate slow zigzags.
- Exercise pressure, hover, double tap and squeeze on compatible Pencil hardware.
- Switch questions/background/close while the pen is down; reopen and undo erasing.
- Check large text, screen reader, reduced motion and high contrast.

## Limits that must not be confused with verified outcomes

No iPad or Android physical-device timings have been measured in the cloud
workspace. Host timing tests do not establish 120 FPS or physical Pencil latency.
The native iOS plugin requires the macOS CI build and device testing. Shape and
scratch heuristics have deterministic tests but require real handwriting tuning.
A retry entry navigates to a question in the current paper; older papers must be
opened from the catalogue. Checking/reviewing an answer does not silently create
another OQB attempt or unlock an already checked answer.

AI is the existing explicit ChatGPT/export flow plus an aggregate revision
prompt. No paid model backend, automatic cloud uploads or speculative OQB API
has been added. Catalogue disk caching deliberately excludes private paper lists,
signed URLs, tokens and sesskeys. Stroke files and correctness history stay local.
