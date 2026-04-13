# D-Switch

A small macOS menu-bar utility that moves the mouse cursor between displays with a keyboard shortcut or a four-finger trackpad tap.

## Usage

- **Cmd+Shift+M** — keyboard shortcut
- **Four-finger tap** on the trackpad

Both triggers move the cursor to the next display, focus the topmost window, and show a brief ring animation so you can instantly locate the cursor.

With two displays, each trigger toggles between them. With three or more, it cycles in spatial order (left-to-right, then top-to-bottom).

## Build & Run

Requires macOS 14+ and Xcode Command Line Tools (`xcode-select --install`).

```sh
make build   # Compile the .app bundle
make run     # Build and launch
make clean   # Remove build artifacts
```

The app bundle is created at `build/D-Switch.app`.

## Permissions

Core functionality works without special permissions. For the best experience, grant **Accessibility** permission in **System Settings > Privacy & Security > Accessibility** — this allows D-Switch to focus windows and locate text carets on the target display.

## Menu Bar

- **Move Cursor Now** — same as the keyboard shortcut
- **Auto-Focus Window** — toggle automatic window focusing
- **Quit** — exit D-Switch

## How I Built It

The entire app — every line of Swift, the Makefile, the README — was written by Claude Code (Anthropic's AI coding agent) through conversational prompts. No Xcode project, no SwiftUI, no third-party dependencies. Just `swiftc` compiling raw Swift files into a self-contained `.app` bundle.

The icon was also AI-generated using Nano Banana (Gemini image generation), then converted to `.icns` with `sips` + `iconutil`.

## Technical Details

See [technology.md](technology.md) for implementation details on cursor positioning, gesture detection, display ordering, and architecture.
