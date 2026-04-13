# How I Built It

D-Switch 完全由 Claude Code 通过对话生成，没有手写一行代码。以下是过程记录。

## 第一版：键盘快捷键

我写了一份详细的 prompt，描述了我想要的产品形态——一个 macOS 菜单栏小工具，按 Cmd+Shift+M 在多个显示器之间跳转光标。Claude Code 一次性生成了完整的可运行实现。

```txt
Please implement a macOS menu-bar app (Swift, macOS 14+) that moves the mouse cursor between displays with a global shortcut, with the following requirements:

1. Core behavior
- Register a global shortcut: Cmd+Shift+M.
- When triggered, move the mouse cursor from the current display to the "next" display.
- If there are exactly two displays, this should simply toggle between them.
- If there are more than two displays, cycle through displays in a stable order.
- The app must detect which display currently contains the mouse cursor, then move it to the target display.

2. Cursor positioning behavior
- By default, preserve the cursor's relative position when moving between displays.
  Example: if the cursor is at 30% from the left and 40% from the top of the current display, place it at 30% / 40% of the target display.
- Clamp the final position to the visible bounds of the target display so the cursor never lands outside the usable area.
- If preserving relative position is not possible for edge cases, fall back to the center of the target display.
- Use proper macOS display coordinate handling so this works with mixed display arrangements, negative coordinates, and vertically stacked displays.

3. Display model and ordering
- Use NSScreen / CoreGraphics display APIs to enumerate displays.
- Establish a deterministic display order for cycling:
  - Prefer ordering by on-screen spatial position (left-to-right, then top-to-bottom),
  - and use a stable tiebreaker if needed.
- Correctly handle:
  - one display (do nothing gracefully),
  - two displays,
  - three or more displays,
  - different resolutions,
  - Retina and non-Retina displays,
  - displays arranged above/below or with negative coordinates.

4. Global shortcut behavior
- Cmd+Shift+M is the default shortcut.
- Use a robust global hotkey implementation suitable for a macOS menu bar utility.
- If registering the shortcut fails (for example due to system or app conflict), the app should:
  - log a clear warning,
  - remain usable from the menu bar,
  - and show the current shortcut in the menu.
- Structure the code so the shortcut can be made user-configurable later, but user customization does not need to be implemented in v1.

5. Visual feedback and cursor hint
- After the cursor moves, show a clear but tasteful visual hint on the target display near the final cursor location so the user can instantly locate the cursor.
- This hint is an important part of the product experience, not an optional flourish.
- The effect should feel lightweight and polished:
  - a subtle circular ring / halo / spotlight around the final cursor position,
  - soft fade in/out,
  - slight scale animation is acceptable,
  - total duration around 0.6–0.9 seconds,
  - must not steal focus,
  - must not block interaction.
- The goal is immediate cursor discoverability, especially in multi-monitor setups.
- Avoid flashy effects, large overlays, or anything that feels like a debug indicator.
- Implement this using a non-activating floating panel / overlay window if appropriate.
- The animation should feel native, calm, and intentional.

6. App form factor
- The app runs as an LSUIElement menu-bar-only app (no Dock icon).
- Provide a menu bar icon with a compact menu containing:
  - App name
  - Current shortcut: Cmd+Shift+M
  - "Move Cursor Now"
  - "Launch at Login" (optional if easy; otherwise leave a TODO)
  - "Quit"
- "Move Cursor Now" should trigger the same behavior as the shortcut.

7. Permissions and system behavior
- Use the correct macOS APIs to move the cursor programmatically.
- Handle accessibility / input-related permission requirements gracefully:
  - detect likely permission issues if possible,
  - provide helpful logging / messaging,
  - do not crash if permissions are missing.
- The app should behave safely and predictably if permissions are denied.

8. Architecture and code quality
- Use Swift and modern macOS app architecture appropriate for macOS 14+.
- Keep the code modular and easy to extend.
- Suggested components:
  - App / MenuBar entry
  - HotkeyManager
  - DisplayManager
  - CursorMover
  - OverlayFeedbackManager
- Write clean, production-style code with comments only where helpful.
- Avoid unnecessary third-party dependencies unless they significantly simplify robust global hotkey handling.

9. Build and project structure
- Use Swift Package Manager if practical for the app structure; Xcode project is acceptable if needed for a proper macOS app target.
- Include all files needed to build and run locally.
- Provide a Makefile with at least:
  - build
  - run
  - clean
- If additional setup is required due to macOS app packaging constraints, explain it clearly in the README.

10. Documentation
- Include a concise README.md that explains:
  - what the app does,
  - how to build and run it,
  - permission considerations,
  - known limitations,
  - how display ordering works,
  - how the cursor positioning behavior works.

11. Output expectations
- Produce a complete, runnable implementation rather than a stub.
- At the end, summarize:
  - project structure,
  - key implementation decisions,
  - any limitations,
  - and exact steps to build/run/test locally.

Please build this as a small, polished macOS utility rather than a rough MVP or proof of concept. Keep the feature scope intentionally narrow, but make the implementation quality, interaction details, and visual finish feel careful and production-minded.
```

## 第二版：改用触控板四指轻拍

用了一段时间后，我发现 Cmd+Shift+M 的问题：三键组合按起来不顺手，而且容易和其他应用的快捷键冲突。跟 Claude Code 讨论后，我提出改用触控板四指轻拍来触发——这个手势 macOS 没有分配给任何系统功能，不存在冲突，而且比键盘快捷键更自然。

```txt
12. Trackpad gesture interaction
- The primary interaction should be a trackpad gesture instead of a keyboard shortcut.
- Use a four-finger single tap on the trackpad as the default trigger.
- When the user performs a four-finger tap, move the mouse cursor from the current display to the next display.
- For a two-display setup, this should toggle directly between the two displays.
- For 3+ displays, cycle through displays in a deterministic order based on display arrangement.
- The gesture should feel immediate and low-friction, with as little cognitive and physical overhead as possible.
- Do not require multi-step gesture modes, directional follow-up gestures, or any modal interaction for v1.
- The product goal is simplicity: one deliberate gesture, one cursor jump.

13. Trackpad gesture recognition behavior
- Implement the gesture recognition in a way that minimizes accidental triggers and avoids fighting common system gestures as much as possible.
- The app should distinguish this interaction from ordinary scrolling, swiping, and navigation gestures.
- Prefer a deliberate four-finger tap over any swipe-based default interaction.
- If direct implementation of a reliable custom four-finger tap is constrained by macOS APIs, structure the code so gesture handling can be swapped or adapted later without redesigning the app architecture.
- If needed, document any implementation limitations clearly in the README.

14. Product quality bar for the interaction
- The four-finger tap should feel like a native, lightweight utility interaction rather than a workaround or demo gesture.
- Keep the interaction extremely simple and fast.
- Avoid over-designing the gesture system.
- The app should prioritize reliability, calm behavior, and repeatable muscle memory over novelty.
- After each successful cursor jump, show the cursor hint near the destination so the user can instantly locate the cursor on the new display.
```
