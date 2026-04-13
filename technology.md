# Technical Details

## Architecture

```
Sources/
  main.swift                   App entry point
  AppDelegate.swift            Menu bar setup, orchestration
  HotkeyManager.swift          Carbon-based global hotkey
  GestureManager.swift         Multitouch four-finger tap detection
  DisplayManager.swift         Screen enumeration and ordering
  CursorMover.swift            Coordinate math and cursor warping
  WindowFocusManager.swift     Detect + activate topmost window on target display
  OverlayFeedbackManager.swift Visual feedback overlay
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

## Known Limitations

- **Shortcut is fixed** at Cmd+Shift+M. User customization is not yet implemented (the code is structured for it).
- **Launch at Login** is listed but not yet wired up. You can add D-Switch to Login Items manually in System Settings.
- If another app registers the same global shortcut, D-Switch logs a warning and remains usable via the menu bar and trackpad gesture.
- **Four-finger tap uses a private framework** (MultitouchSupport). While this framework has been stable across many macOS versions, Apple could change or remove it in a future release. If that happens, the gesture stops working but the app continues to function via the keyboard shortcut.
- **No trackpad on desktop Macs** (Mac mini, Mac Studio, Mac Pro without Magic Trackpad): the gesture is unavailable; the keyboard shortcut works normally.
- The visual hint uses the system accent color. If your accent color has low contrast against your wallpaper, the hint may be less visible.
- Single-display setups: both triggers do nothing (by design).
