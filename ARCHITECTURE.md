# Architecture

## Source Layout

```
Sources/
  main.swift                   App entry point
  AppDelegate.swift            Menu bar setup, orchestration, settings
  HotkeyManager.swift          Carbon-based global hotkey (rebindable)
  Shortcut.swift               Shortcut value type + UserDefaults persistence
  ShortcutRecorderWindow.swift Floating panel that captures the next key combo
  GestureManager.swift         Multitouch four-finger tap detection
  DisplayManager.swift         Screen enumeration and ordering
  CursorMover.swift            Coordinate math and cursor warping
  WindowFocusManager.swift     Detect + activate topmost window on target display
  OverlayFeedbackManager.swift Visual feedback overlay (Subtle/Standard/Prominent presets)
```

No third-party dependencies. Uses Carbon Event Manager for global hotkeys, MultitouchSupport.framework for trackpad gestures, CoreGraphics for cursor movement, and AppKit/QuartzCore for the overlay animation.

## Display Ordering

Displays are ordered by their spatial position:

1. **Left-to-right** by the screen's x-coordinate
2. **Top-to-bottom** by the screen's y-coordinate (for vertically stacked displays)
3. **Display ID** as a stable tiebreaker if positions are identical

The ordering is recalculated each time the shortcut is triggered, so it adapts if you rearrange displays.

## Cursor Positioning & Auto-Focus

D-Switch places the cursor at the actual focus point — not a generic center — so you can interact immediately after jumping.

**Four-tier cursor landing (in priority order):**

| Priority | Lands at | When |
|----------|---------|------|
| 1 | **Text caret / insertion point** | Focused element is a text field with a caret (via AX `kAXBoundsForRangeParameterizedAttribute`) |
| 2 | **Center of focused UI element** | Focused element is a button, list item, etc. (via AX `kAXFocusedUIElementAttribute`) |
| 3 | **Center of topmost window** | AX unavailable or no focused element |
| 4 | **Center of the display** | No window on the target display |

The AX queries run BEFORE app activation to read the last-known focus state without timing issues. Accessibility permission is required for tiers 1–2; without it, D-Switch falls back to tier 3/4 automatically.

**How it works:**

1. `CGWindowListCopyWindowInfo` finds the topmost normal window (layer 0, ≥50×50pt, >10% overlap) on the target display
2. `AXUIElementCreateApplication` → `kAXFocusedUIElementAttribute` queries the focused element
3. For text elements: `kAXSelectedTextRangeAttribute` + `kAXBoundsForRangeParameterizedAttribute` gets the caret position
4. For non-text elements: `kAXPositionAttribute` + `kAXSizeAttribute` gets the element bounds → center
5. The owning app is activated via `NSRunningApplication.activate()`
6. The cursor warps to the best available point (clamped to screen bounds)

## Visual Feedback

After the cursor moves, a brief ring animation appears at the landing position:

- Accent-colored ring with subtle glow for visibility on any background
- Scale-down and fade animation (~0.75s total)
- Non-interactive floating overlay — doesn't steal focus or block clicks

## Four-Finger Tap

The trackpad gesture uses the private MultitouchSupport framework — the same approach used by established macOS trackpad utilities (BetterTouchTool, Jitouch, etc.). This provides direct access to raw multitouch data, which is the only way to detect custom multi-finger taps on macOS.

**How tap detection works:**

1. When fingers touch the trackpad, D-Switch starts tracking
2. When all fingers lift, it evaluates: was the peak finger count exactly 4, the total duration under ~280ms, and the centroid movement under ~3.5% of the trackpad surface?
3. If all conditions pass, it triggers a cursor jump
4. A 450ms cooldown prevents double-triggers

**Distinguishing taps from swipes:** The gesture recognizer checks both timing (taps are short) and centroid movement (taps are stationary). Four-finger swipes for Mission Control, App Exposé, and desktop switching are longer and involve significant movement, so they should not trigger false positives.

**Struct layout detection:** The raw multitouch data layout is not part of any public API and could theoretically change between macOS versions. D-Switch detects the layout at runtime by probing for valid touch identifier and position fields across a range of candidate struct sizes. If detection fails, position checking is skipped and timing alone is used (with conservative thresholds). If the framework itself is unavailable, gesture detection silently disables and the keyboard shortcut remains fully functional.

**Conflict with system gestures:** A four-finger *tap* is not assigned to any system gesture by default, so there should be no conflicts. Four-finger *swipes* (Mission Control, desktop switching) involve movement that exceeds the tap threshold.

## Customization

All preferences live in the menu bar (no separate Preferences window) and persist via `UserDefaults`:

- **Shortcut** — record a new global hotkey via *Change Shortcut…*. The recorder requires at least one modifier (⌘/⌃/⌥/⇧) to avoid bare-letter shortcuts hijacking ordinary typing. Esc cancels. If macOS rejects the shortcut, D-Switch keeps the previous shortcut and shows a warning.
- **Four-Finger Tap** — toggle the trackpad trigger on or off without affecting the keyboard shortcut.
- **Cursor Lands At** — choose between *Topmost Window (Smart)* (the AX-driven four-tier landing described above) and *Display Center* (always the geometric center of the target display).
- **Ring Animation** — three presets: *Subtle* (close to the original feel), *Standard* (default; larger and longer than the original), *Prominent* (largest and slowest, useful on busy displays). Stroke widths scale with the ring diameter so the proportions stay consistent.
- **Launch at Login** — toggle in the menu to register/unregister the app via `SMAppService.mainApp` (ServiceManagement). The checkmark reflects the current state; the user can also manage it in System Settings → General → Login Items. macOS may decline registration if the bundle is not in `/Applications`; in that case D-Switch shows an alert and the toggle stays off.

### Where Preferences Are Stored

Preferences are written through `UserDefaults.standard` under the bundle identifier `com.dswitch.app`, which macOS persists at:

```
~/Library/Preferences/com.dswitch.app.plist
```

Stored keys include the recorded shortcut, the *Cursor Lands At* mode, the *Ring Animation* preset, and whether the four-finger tap trigger is enabled. *Launch at Login* state is managed by macOS via `SMAppService` and is not stored in this plist.

Because macOS caches defaults in memory through `cfprefsd`, prefer the `defaults` CLI over editing the plist directly:

```
defaults read com.dswitch.app                  # inspect
defaults write com.dswitch.app <key> <value>   # change
defaults delete com.dswitch.app                # reset all
```

## Known Limitations

- If another app registers the same global shortcut, D-Switch shows a warning and remains usable via the menu bar and trackpad gesture.
- **Four-finger tap uses a private framework** (MultitouchSupport). While this framework has been stable across many macOS versions, Apple could change or remove it in a future release. If that happens, the gesture stops working but the app continues to function via the keyboard shortcut.
- **No trackpad on desktop Macs** (Mac mini, Mac Studio, Mac Pro without Magic Trackpad): the gesture is unavailable; the keyboard shortcut works normally.
- The visual hint uses the system accent color. If your accent color has low contrast against your wallpaper, the hint may be less visible.
- Single-display setups: both triggers show a one-time hint and then do nothing (by design).
