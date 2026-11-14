# Reading Mode implementation plan

## Scope and status

Implement opt-in steady scrolling and explicit forward/back steps. Existing pointer,
scroll, onboarding and gesture defaults remain unchanged. No new permissions,
network calls, dependencies, text capture or input logging. No commits or pushes
are performed by the implementation agent.

Phases 1–3 have an initial implementation, not yet compiled: session engine,
settings, menu/settings controls, shortcuts, reading gesture overrides and
interruption checks. This Windows workspace has no Swift toolchain. All macOS
build, integration and hardware checks below remain release blockers.

## Integration decisions and remaining limitations

- Start and step use shortcuts/stem presses over the document; panel buttons only
  pause, change speed or exit. Starting checks the Accessibility element owner at
  the pointer against the foreground app to reject our controls/background apps.
- A separate frame path ignores head velocity and suppresses normal clicks/recenter.
- Pause latches on stale samples, long frames, physical clicks/wheel/typing, pointer
  displacement, application activation, sleep and motion failures. Synthetic scroll
  events carry a marker so they do not trigger the physical-scroll monitor.
- ⌃⌥R enters/exits; ⌃⌥P starts/pauses; ⌃⌥N/⌃⌥B step forward/back.
- Reading overrides: single stem starts/pauses, double goes back, triple exits;
  left/right tilt changes speed; shake pauses or exits if already paused. Nod is
  deliberately disabled pending false-activation testing. Overrides do not rewrite
  saved normal bindings. These shortcuts/overrides are currently fixed, not configurable.
- Foreground app and pointer anchor are checked, but this is not window/pane locking.
  Programmatic same-app window changes and nested panes still need validation and
  stronger target tracking before release. Unsupported Accessibility hit tests
  reject playback rather than guessing a destination.
- No floating panel, focus band, viewport-relative steps or end-of-document detection.
- Global input-monitor delivery and Carbon shortcut ordering require real macOS
  verification, including keyboard permission behavior and media-key conflicts.

## 1. Core foundation

- [x] Inactive → ready → running → paused state machine; explicit restart.
- [x] Fractional point accumulation independent of frame rate.
- [x] Interruptions stop output without catch-up; steps leave scrolling paused.
- [x] Bound numeric settings and decode old preferences without changing defaults.
- [x] Tests for transitions, timing, interruptions, stepping and settings.
- [ ] Run tests on macOS with Xcode 16+.

The initial 30 points/second and 300-point step are prototype values, not validated
reading preferences. No claim of words/minute or exact line/page movement.

## 2. App adapter and interruption handling

- Add reading mode and a published session status in AppController.
- On entry release drag, clear smoothing/dwell/remainders, capture target app/window
  and pointer anchor, and enter Ready. Do not scroll until explicitly started.
- Feed the existing frame timer into ReadingSession; invert its positive-down
  output for EventSynthesizer. Do not reuse pointer acceleration.
- Compute permission on every frame AND every step/start: tracking enabled,
  Accessibility trusted, fresh motion, correct foreground target and no manual input.
- Pause on sleep, disconnect, motion error/stall, permission loss, target changes,
  keyboard input, physical clicks/wheel and deliberate physical pointer movement.
- Distinguish synthesized events from real input; never let generated scroll events
  pause themselves. Do not add input logging or new permission requirements.
- Clear time/remainders on transitions. Reconnect/wake never resumes automatically.
- Validate nested panes and target routing before promising target locking. If a
  target cannot be safely identified, pause and ask the user to reposition.
- Menu/panel interaction must not recapture the menu as the document target.

## 3. Controls and discoverability

- Add Reading to menu and main-window mode selectors, with Ready/Running/Paused status.
- Provide Start/Pause, Slower/Faster, Step forward, Back a little and Exit.
- Add configurable actions and a documented shortcut without replacing existing ones.
- Reading-specific optional nod start/pause and tilt speed changes: display the
  overrides clearly, debounce them, preserve saved normal bindings on exit.
- Suppress click/drag actions and hover clicks while reading; preserve emergency
  pause. Ensure users can exit hands-free even while paused.
- Make controls accessible and keyboard reachable. Keep status visible without
  taking focus from the reading app. Respect reduced-motion preferences.

## 4. Verification and release gate

- Add app tests for click suppression, gesture conflicts, target changes and safety
  guards. Include no-auto-resume after reconnect/wake and physical-input priority.
- Run swift test, swift build, and git diff --check on macOS.
- Exercise Safari, Chrome, Preview and a document editor with real AirPods.
- Test nested panes, multiple displays, text selection, menus, scroll boundaries,
  media stem conflicts, disconnected headphones and Accessibility revocation.
- Test 15-minute reading sessions, including step-only reading; tune speed/gesture
  thresholds from observed comfort, false activations and overshoot.
- Update README with actual supported controls and limitations after integration.

Defer focus-band overlays, tilt-held scrolling, text extraction, automatic pace
estimation and exact end-of-document detection until the basic session is validated.
