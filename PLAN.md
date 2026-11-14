# LaunchController (LaunchCon) — Build Plan

A macOS app (Swift + AppKit) that manages launchd jobs: list services, see status,
load/unload/enable/disable/start/stop them, and eventually edit plists, view logs,
and validate job definitions — inspired by soma-zone's LaunchControl.

**Naming convention:** the product/target/bundle is `LaunchCon`; the user-facing
display name (window titles, About panel, menu bar) is `LaunchController`.

## Conventions for the implementing agent

- **Build tool:** Xcode project generated via XcodeGen (`project.yml`) so the repo
  stays scriptable. Alternative: Swift Package Manager executable + `NSApplicationMain`
  if XcodeGen is unavailable.
- **Language:** Swift 5.9+, AppKit (no SwiftUI), macOS 13+ deployment target.
- **Architecture:**
  - `LaunchCon/Core/` — pure logic, no UI: launchctl wrappers, plist models,
    plist parsing/serialization, validators.
  - `LaunchCon/App/` — AppKit UI: windows, split views, outline views, inspectors.
  - `LaunchCon/Resources/` — assets, Info.plist bits, entitlements.
- **Rule:** every phase ends with a buildable, runnable app. Commit after each
  phase (or at least after each working feature) before starting the next.
- **Verification:** after each phase run `xcodebuild -scheme LaunchCon
  -configuration Debug build` (or `swift build` for SPM) and, for UI phases,
  launch the app and confirm the feature manually. No automated UI tests in
  early phases; add unit tests for `Core` logic as it grows.
- Never run destructive launchctl commands (`bootout`, `remove`) against real
  system domains during development — test against `gui/$UID` and a sandboxed
  test plist the app itself installs.

## Phase 0 — Project scaffold

Goal: empty AppKit app that builds and launches.

1. Create repo layout:
   ```
   project.yml
   LaunchCon/
     App/
       AppDelegate.swift
       MainWindowController.swift
     Core/
     Resources/
   LaunchConTests/
   ```
2. Write `project.yml` (XcodeGen) defining an app target `LaunchCon`
   (bundle id `com.psybers.LaunchCon`, macOS 13+), a unit-test target, and
   AppKit settings (`INFOPLIST_KEY_NSPrincipalClass = NSApplication`).
3. Implement `AppDelegate` with a minimal `applicationDidFinishLaunching` that
   creates `MainWindowController` and shows a window titled "LaunchController"
   containing an empty `NSTextField` saying "LaunchController".
4. Build and run. Verify a window appears.
5. Enable signing for local dev (`CODE_SIGN_IDENTITY = "-"` or "Sign to Run
   Locally") so launchctl IPC works.

**Done when:** `xcodebuild build` succeeds and the app launches to a window.

## Phase 1 — launchctl integration layer (Core)

Goal: a typed, testable wrapper around launchctl and job plists — no UI yet.

1. Create `Core/LaunchdDomain.swift` — enum for domains:
   `system`, `system/<path>`, `gui/<uid>`, `gui/<uid>/<path>`, `user/<uid>`,
   `login/<asid>`, `pid/<pid>`, `session/<asid>`; compute current uid/asid.
2. Create `Core/Job.swift` — model for a launchd job: label, program/arguments,
   runAtLoad, keepAlive, stdout/stderr paths, plist path, domain, loaded state,
   PID (if running), last exit status.
3. Create `Core/Launchctl.swift` — async wrapper (`Process` + pipes) exposing:
   - `list(domain:) -> [Job]` — parse `launchctl list [-x] [domain]` output
     (columns: PID / Status / Label). `-x` gives debug info.
   - `print(plistPath:) -> [String: Any]` — parse `launchctl print` output or
     fall back to reading the plist file directly.
   - `load(plistPath:domain:)`, `unload(label:domain:)`, `enable`, `disable`,
     `kickstart -k`, `kill`, `bootstrap`, `bootout` — as typed methods with
     `enum LaunchctlError`.
   - Every command must capture stdout/stderr and throw on non-zero exit.
4. Create `Core/Plist.swift` — read/write `.plist` files via
   `PropertyListSerialization`, plus helpers to locate job plists in
   `~/Library/LaunchAgents`, `/Library/LaunchAgents`, `/Library/LaunchDaemons`,
   `/System/Library/LaunchAgents`, `/System/Library/LaunchDaemons`.
5. Add unit tests in `LaunchConTests` for plist parsing and `list` output
   parsing using a fixture string (do NOT depend on the live system in tests).

**Done when:** unit tests pass and a debug menu item "Dump Jobs" prints parsed
jobs to the console.

## Phase 2 — Job list UI

Goal: main window shows all jobs grouped/filterable, with status.

1. `MainWindowController` uses an `NSSplitViewController`: sidebar (domain
   picker + filter field), content (job list).
2. Content: `NSOutlineView` or `NSTableView` with columns: Label, PID, Status,
   Domain, Path. Color-code: running (green dot), loaded-not-running (gray),
   invalid/disabled (red).
3. Sidebar `NSTableView`/`NSPopUpButton`: choose domain (User Agents,
   Daemons, System — at minimum `gui/$UID` and `/Library` paths).
4. `JobListController` (new `App/` file): owns an `ObservableSnapshot`-style
   array, loads jobs via `Launchctl.list`, merges with plist discovery from
   `Core/Plist.swift` so un-loaded-but-installed jobs appear (disabled state).
5. Filter field: substring match on label + a few properties (keep simple:
   label only in this phase).
6. Selection drives a detail placeholder pane (right side, third split pane)
   showing raw plist path and loaded state for now.

**Done when:** app lists real jobs from `launchctl list gui/$UID` and the
user domain; filtering works; selection shows basic info.

## Phase 3 — Job actions

Goal: load/unload/enable/disable/start/stop from the UI.

1. Add an action toolbar / context menu: Load, Unload, Enable, Disable,
   Start (kickstart), Stop (kill), Refresh.
2. Route through `Core/Launchctl`; after each action re-fetch affected job(s)
   and update the list (optimistic UI optional — simple re-fetch is fine).
3. Disable/enable operate on the plist in `~/Library/LaunchAgents` (user
   jobs); for system jobs show an alert that SIP/sealed system prevents
   modification on Big Sur+.
4. Confirmation dialog for destructive actions (unload, bootout, remove).
5. Surface `LaunchctlError` as `NSAlert`.

**Done when:** user can toggle a test agent (`com.example.test`) through
load → run → unload entirely from the GUI.

## Phase 4 — Plist editor (Standard Editor, MVP)

Goal: edit a selected job's plist keys in a structured form.

1. `PlistDocument`-style model: load plist into ordered key/value pairs
   (`[(String, Any)]` preserving order is nice-to-have; `NSDictionary` is OK).
2. `JobEditorViewController`: `NSStackView`-based form generated from a
   schema table (`Core/JobKeySchema.swift`) — each row: key name, control
   type (text field, checkbox, popup for enums, path picker for paths,
   dictionary editor for `EnvironmentVariables`), current value.
3. Schema covers the common keys first: `Label`, `ProgramArguments`,
   `Program`, `RunAtLoad`, `KeepAlive`, `StartInterval`, `StartCalendarInterval`,
   `WorkingDirectory`, `StandardOutPath`, `StandardErrorPath`,
   `EnvironmentVariables`, `UserName`, `GroupName`, `ProcessType`,
   `LowPriorityIO`, `Nice`, `AbandonProcessGroup`.
4. Save writes plist atomically (`write(to:options:.atomic)`), then prompts
   "Reload job?" which unloads + loads if currently loaded.
5. "New Job…" menu item creates a minimal plist in `~/Library/LaunchAgents`.

**Done when:** editing `KeepAlive`/`RunAtLoad` on a test agent persists to
disk and reflects in `launchctl print`.

## Phase 5 — Job state & logs views

Goal: per-job detail pane with state info and log output.

1. State view: parse `launchctl print gui/$UID/<label>` output — show
   state, PID, last exit code, runs count, properties — as a key/value table.
   (Store a parser in `Core/LaunchctlPrintParser.swift` with fixture tests.)
2. Log view: `NSTextView` in a scroll view. Sources, in order of preference:
   - read `StandardOutPath`/`StandardErrorPath` files (tail last N lines,
     auto-refresh via `DispatchSource` file watcher or timer)
   - `log show --predicate 'subsystem == ...'` is out of scope initially;
     note as future work.
3. Layout: inspector/detail pane with segmented control: Info / State / Logs /
   XML.

**Done when:** selecting a job shows live-updating stdout/stderr for a test
agent that writes to a file.

## Phase 6 — Validation & diagnostics

Goal: analyze a job and report problems like LaunchControl does.

1. `Core/JobValidator.swift`: checks — missing plist file, unreadable plist,
   missing `Label`, label ≠ filename, program not executable, bad
   `StartCalendarInterval`, `KeepAlive`+`RunAtLoad` conflicts, stdout/stderr
   paths unwritable, env var issues, deprecated keys.
2. Each check returns `Diagnostic(severity, message, fixHint)`.
3. UI: diagnostics listed at top of detail pane with warning icon; clicking a
   diagnostic highlights the offending key in the editor.

**Done when:** deliberately broken test plist produces correct diagnostics.

## Phase 7 — Search & filtering (full)

1. Extend filter to all job properties + diagnostics state ("show only
   problematic jobs").
2. Searchable key palette (`NSPopover` or inspector section): all launchd keys
   with descriptions, draggable onto editor — implement basic click-to-add
   first; drag-drop is polish.

## Phase 8 — QuickLaunch menu bar extra (optional/later)

1. `NSStatusItem` menu extra listing a user-configurable subset of jobs with
   status dots and load/unload/start/stop actions; grouped jobs act together.
2. Settings window for choosing which jobs appear.

## Phase 9 — Polish & distribution (later)

- Sparkle auto-updates, notarization, DMG packaging, icon, about window.
- `launchctl blame`, endpoint security for file watching — evaluate as needed.

## Suggested milestone order (if building incrementally)

| Milestone | Phases | Demoable result |
|-----------|--------|-----------------|
| M1 | 0–2 | Browse real launchd jobs with status |
| M2 | 3 | Full load/unload/start/stop control |
| M3 | 4 | Edit and create job plists |
| M4 | 5–6 | State, logs, diagnostics — debugging parity |
| M5 | 7–9 | Palette, menu bar, distribution |

## Explicit non-goals for early phases

- No editing of `/System` or sealed system plists (impossible on Big Sur+).
- No `log show` integration in Phase 5 (file-based logs only).
- No SwiftUI, no third-party deps beyond XcodeGen (or none if using SPM).
- No sandbox entitlements initially — launchctl IPC requires unsandboxed app.
