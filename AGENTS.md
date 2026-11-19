# AGENTS.md

Guidance for AI agents (and humans) working on LaunchCon.

## What this is

A native macOS app for managing `launchd` jobs, inspired by soma-zone's
LaunchControl. Swift + AppKit, programmatic UI (no storyboards/nibs), no
third-party dependencies. See `README.md` for product intent.

## Naming

- Internal/target/bundle: **LaunchCon** (`com.psybers.LaunchCon`)
- User-facing display name: **LaunchCon**
- Source dir `LaunchCon/`, tests `LaunchConTests/`

## Build & test

The Xcode project is **generated, not checked in**. After adding/removing
source files, regenerate:

```sh
xcodegen generate
xcodebuild -scheme LaunchCon -configuration Debug build
xcodebuild -scheme LaunchCon -configuration Debug test   # XCTest suite
```

Run the app: `open` the `.app` in DerivedData
(`~/Library/Developer/Xcode/DerivedData/LaunchCon-*/Build/Products/Debug/`),
or ⌘R in Xcode. The app must run **inside the GUI session** — `gui/<uid>`
domain queries fail from SSH/agent shells.

## Architecture

- `LaunchCon/Core/` — UI-free logic: `Launchctl` (async `Process` wrapper),
  output parsers (`JobListParser`, `DomainPrintParser`,
  `ServicePrintParser`, `DisabledListParser`), `Plist`/`PlistDocument`,
  `JobValidator` (diagnostics), `LogTail`, `JobKeySchema`.
- `LaunchCon/App/` — AppKit controllers. `main.swift` uses explicit
  `NSApplication.shared` + delegate + `app.run()` — **do not** switch back
  to `@main` (it silently never instantiated the delegate and no window
  appeared).
- `JobStore` merges `launchctl` results with plists discovered on disk;
  groups map to `LaunchdDomain`s. All launchctl work is async off-main.

## Service types (sidebar groups)

`JobStore.defaultGroups()` defines the sidebar, matching LaunchControl's
taxonomy (plus "All" on top, which unions every directory):

| Group             | Directory                                                        | Domain queried        |
|-------------------|------------------------------------------------------------------|-----------------------|
| All               | all plist dirs below                                             | `gui/<uid>`           |
| User Agents       | `~/Library/LaunchAgents`                                         | `gui/<uid>`           |
| Global Agents     | `/Library/LaunchAgents`                                          | `gui/<uid>`           |
| Global Daemons    | `/Library/LaunchDaemons`                                         | none (system, needs root) |
| System Agents     | `/System/Library/LaunchAgents`                                   | `gui/<uid>`           |
| System Daemons    | `/System/Library/LaunchDaemons`                                  | none (system)         |
| Server Daemons    | `/Applications/Server.app/Contents/ServerRoot/System/Library/LaunchDaemons` | none (system) |
| Homebrew          | `$(brew --prefix)/Homebrew/Library/{LaunchAgents,LaunchDaemons}` (`/opt/homebrew`, `/usr/local`) | none |

Notes:

- Agent groups query the live `gui/<uid>` domain; `JobStore` intersects
  results with the group's discovered plist labels, so Apple's ~460 session
  services don't swamp the list. System/daemon groups are plist-discovery
  only — `launchctl print system` requires root.
- `LaunchdDomain.bootstrapDomain(forPlistAt:)` derives the load domain from
  the plist path (`*LaunchDaemons` → `system`, else `gui/<uid>`), which is
  what makes mixed groups like "All" work.
- Homebrew formula services that aren't materialized as plists (visible via
  `brew services list`) are not yet surfaced — that needs `brew services`
  integration.

## Sidebar filters

`DomainSidebarController` has a "Filters" section with six checkboxes
(Loaded, Unloaded, Disabled, Enabled, Running, Stopped), all checked by
default. Unchecked filters land in `JobStore.disabledFilters`; `visibleJobs`
removes any job matching an unchecked `JobFilter` (predicates overlap — e.g.
a running job is also loaded), then applies the label `filterText` search.
This is independent of the service-type group selection.

## Hard-won gotchas

- **`launchctl list <domain>` doesn't exist on modern macOS.** Use
  `launchctl print <domain>` and parse the `services = {}` block
  (`DomainPrintParser`). Plain `launchctl list` only covers the caller's
  session.
- **Pipe-buffer deadlock:** `launchctl print gui/<uid>` emits >64KB.
  `Launchctl.launchctl` drains stdout/stderr concurrently — keep it that
  way; reading after `waitUntilExit` hangs forever.
- **Main window split view is a plain `NSSplitView`, not
  `NSSplitViewController`.** The latter's constraint-driven layout could
  not be made to honor initial pane widths (outer panes swallowed the
  window). The three pane VCs are children of a plain container VC with
  their views as direct `NSSplitView` subviews; `NSSplitViewDelegate`
  `constrainMin/MaxCoordinate` keep minimum widths while dragging, and only
  the job list has a flexible width so it absorbs window resizes.
- **`windowDidLoad` never fires** for the programmatically created
  `NSWindowController`. Initial split positions are applied via
  `applyInitialSplitPositionsIfNeeded()` — called from `AppDelegate` after
  `showWindow` and by an `NSWindow.didResizeNotification` observer.
- **`NSSplitView` initial pane sizes come from the subviews' existing
  frames**, and each `setPosition` re-lays out the *other* dividers from
  their stored positions — set the rightmost divider first, then the left
  (see `applyInitialSplitPositions`).
- **`usesAutomaticRowHeights` breaks cell width:** it makes `NSTableView`
  size view-based cells by their *fitting* width, so long text overflows
  into neighboring columns. `JobListController` uses a fixed `rowHeight`
  instead — all rows are single-line.
- **Window sizing:** assign `contentViewController` *before*
  `setContentSize`/`center`, and set `translatesAutoresizingMaskIntoConstraints
  = false` on scroll views or the window collapses to a strip.
- **`NSScrollView` document alignment:** a document shorter than the clip
  view is bottom-aligned. `JobDetailController.embedInScroll` wraps content
  in a container with `height >= clipView.height`; the stack needs a
  low-hugging spacer subview or `.gravity` distribution stuffs all surplus
  height into the first arranged view.
- **Plist dirty checking:** never use a one-way dirty flag — rebuild the
  dictionary from controls and deep-compare against `savedContents` via
  `Plist.valuesEqual` (bool vs int matters; check `CFBooleanGetTypeID`).
  Bool keys absent from the plist must stay absent (don't write `false`).
- **Editor validation:** `JobEditorViewController.save()` returns `Bool`;
  the unsaved-changes alert keeps the window open if it fails.

## Safety rules

- No destructive launchctl ops against system domains; daemon loads need
  root and will fail — surface the error, don't work around it.
- `/System` plists are on a sealed volume — read-only.
- The app is intentionally **unsandboxed** (launchctl IPC).
- Preserve unknown plist keys when editing — never silently drop data.

## Conventions

- **Do not `git commit` until explicitly asked.** Leave changes in the
  working tree; the user reviews and decides when to commit.
- Swift 5 mode, macOS 13+ deployment target.
- UI built in code with Auto Layout; prefer `NSStackView` for rows.
- Errors surface as `NSAlert`; launchctl failures throw `LaunchctlError`.
- Tests are XCTest in a single file (`LaunchConTests.swift`) with fixture-
  based parser tests — add fixtures mirroring real `launchctl` output.
