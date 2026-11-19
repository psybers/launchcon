# LaunchCon

A native macOS app for managing `launchd` jobs — launch agents and daemons — without living in `launchctl`.

This was vibe coded with Devin. I don't know Swift and had never made a macOS app, so it may be buggy. I want to keep it basic; the current feature set is probably the most I will add. Bug-fix PRs are welcome.

## Features

- **Job browser** — three-pane window with a service-type sidebar (All, User Agents, LaunchAgents, LaunchDaemons, System Agents, System Daemons), a searchable job list with live status (running PID, exit status, disabled, loaded/not loaded) that matches all job properties, a "Problems only" filter for jobs with diagnostics, and an inspector pane.
- **Job actions** — load, unload, enable, disable, start, and stop jobs from the context menu or the Job menu, with confirmations for destructive operations.
- **Property list editor** — schema-driven editor for common launchd keys (Program, ProgramArguments, RunAtLoad, KeepAlive, StartInterval, StartCalendarInterval, environment variables, paths, and more) plus a searchable key palette for finding and adding keys. Supports multiple calendar schedules, preserves unknown/complex keys, validates input, and offers to reload the job after saving.
- **New job creation** — Job → New Job… scaffolds a plist in `~/Library/LaunchAgents`.
- **Inspector tabs** — per-job detail view with:
  - **Info** — summary fields plus diagnostics (missing/unreadable plists, missing or mismatched labels, missing or non-executable programs, bad paths, invalid calendar intervals) with severity icons.
  - **State** — live `launchctl print` output: state, PID, run count, last exit code, program, paths, and more.
  - **Logs** — tail of `StandardOutPath`/`StandardErrorPath` with a source picker and automatic refresh.
  - **XML** — read-only plist XML view.

## Requirements

- macOS 13 or later
- Xcode (or just the Xcode command line tools)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

## Installing

The easiest way to install is via Homebrew:

```sh
brew trust --cask psybers/homebrew-tap/launchcon
brew install --cask psybers/homebrew-tap/launchcon
xattr -d com.apple.quarantine /Applications/LaunchCon.app
```

Note that if you don't remove the quarantine, the app won't run.  You can do
that with the above command, or by going into Settings and allowing the program
to run.

## Updating

```sh
brew upgrade psybers/tap/launchcon
xattr -d com.apple.quarantine /Applications/LaunchCon.app
```

## Building

The Xcode project is generated from `project.yml` and is not checked in.

```sh
# Generate the Xcode project
xcodegen generate

# Build from the command line
xcodebuild -scheme LaunchCon -configuration Debug build

# Or open in Xcode
open LaunchCon.xcodeproj
```

The built app lands in Xcode's DerivedData; the simplest way to run it is to open the project in Xcode and press Run (⌘R).

## Testing

```sh
xcodebuild -scheme LaunchCon -configuration Debug test
```

## Project layout

```
project.yml            XcodeGen spec (app + test targets)
LaunchCon/
  App/                 AppKit UI (windows, views, editor)
  Core/                launchctl wrapper, parsers, plist & validation logic
LaunchConTests/        XCTest suite for parsers, plist handling, validator, log tailing
```

## Notes

- The app is **not sandboxed** — `launchctl` IPC requires it.
- Daemon and system-domain operations generally need administrator privileges; the app surfaces launchctl errors rather than working around them.
- `/System` plists can't be modified on modern macOS (sealed system volume).
- Menu bar extras, auto-updates/notarization, and `log show` integration are intentionally out of scope — the feature set above is the target.
