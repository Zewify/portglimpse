# PortGlimpse — design

Date: 2026-09-30.
Status: approved in conversation, awaiting review of this written spec.
Visual design: the "PortGlimpse menu" canvas at https://claude.ai/artifact/3FWxVQjj2aQJy6uZsGpBg2 (private to the owner), boards "Menu panel", "Row states", "Menu bar icon options" and "Pop-out window".

## Purpose

PortGlimpse is a free Mac menu bar app that answers "what is listening on this port, which project is it, and can I stop it" without `lsof -i :3000` and `kill -9`.
It is for developers, and it is a Zewify product.
Success means a developer can find and stop a stale dev server in two clicks and one confirmation, and can tell five `node` processes apart by their project folder.

## Decisions already made

- Free, with no in-app purchase and no Pro tier.
- Distributed outside the Mac App Store, as a notarized download installed and updated with one `curl` command.
- The source is public at `github.com/zewify/portglimpse`.
- It is a viewer with a kill button, never a process manager: no starting, restarting, logs or remote machines.
- Kill always asks for confirmation first.

### Why not the Mac App Store

A spike on 2026-09-30 tested a signed, sandboxed probe against a real `node` server.
In the sandbox, listing sockets through the kernel's TCP socket table worked, including root-owned ones, and reading a process's working directory worked.
Sending a signal failed with `Operation not permitted`, and `NSRunningApplication` cannot see command-line processes.
Killing only worked through a user-installed script in `~/Library/Application Scripts/`, which needs a one-time setup step.
The owner chose direct distribution instead, since the audience is developers and it removes the sandbox entirely.

## Scope of 1.0

### The panel

Clicking the menu bar icon opens a panel (a `MenuBarExtra` in window style, not an `NSMenu`), because the kill confirmation lives inside the row.
The panel has three sections, top to bottom.

1. **Dev servers**, always expanded.
2. **Apps & system**, collapsed by default, with its row count on the header.
3. **Other users · view only**, shown only while "Show all users' ports" is on.

A footer holds the "Show all users' ports" checkbox, a Settings submenu and Quit.
The checkbox state persists across launches.
When Dev servers is empty, it says "Nothing listening. Your ports are free."

### Rows

There is one row per process, not per port.
The row shows the process's lowest port as a label (`:3000`), any further ports under it (`+ :33060`), the command and the folder.
The command is the process's arguments shortened to something recognizable (`next dev`, `vite`, `redis-server`), not the bare executable name (`node`).
The folder is the process's working directory with the home folder shown as `~`.
Port labels are flat, non-interactive tags, deliberately unlike buttons.

Hovering a Dev servers row reveals: Open in browser (`http://localhost:<port>`), Copy PID, Reveal folder in Finder, Kill.
Apps & system rows offer Copy PID and Kill only.
Other users' rows offer no actions and show the owner (`root`) with a lock glyph; they show the PID in place of a folder.

Right-clicking a row offers "Always show as dev" or "Always hide in Apps & system", remembered by executable path.

### Kill flow

1. Kill turns the row into `Kill <command> on :<port>?` with Cancel and Kill buttons, both 30 px tall and flat.
2. Kill sends `SIGTERM` and the row reads `Stopping <command>…`.
3. If the process has exited within 3 seconds, the row disappears.
4. Otherwise the row reads `<command> didn't stop` with "Force kill it? Unsaved work in it is lost." and Cancel / Force kill; Force kill sends `SIGKILL`.
5. If the signal fails (the process already exited, or it belongs to another user), the row states the reason in one line; there is no alert window.

Escape or clicking elsewhere cancels a pending confirmation.
Processes owned by other users can never be signalled, and the Core refuses such a request even if the UI asks.

### Classification

A process owned by the current user is a **dev server** when its executable is outside every `.app` bundle and outside `/System`, `/usr/libexec`, `/usr/sbin` and `/sbin`.
Every other process owned by the current user goes under **Apps & system**.
Processes owned by any other user go under **Other users**.
A right-click override beats the rule.
The probe's real results are the reference cases: `node`, `bun`, `mysqld` and `redis-server` are dev servers; DBeaver, `figma_agent`, Google Drive, ControlCenter and `rapportd` are Apps & system; `launchd` and Tailscale are Other users.
Known gaps, accepted for 1.0: Postgres.app and Docker containers land in Apps & system until overridden.

### Pop-out window

A button in the panel header ("Open in a window") opens the same list in a window of its own, and the panel closes.
The button brings the window forward when it is already open; there is never more than one.

- It always stays on top of other windows, on every desktop (Space) and over full-screen apps, like picture-in-picture.
- Because it is always on top it needs no Dock icon, and PortGlimpse stays out of the Dock and ⌘-Tab.
- Its header is PortGlimpse's dark header with the window's close, minimise and zoom buttons inside it, and no grey title bar; it is dragged by that header.
- It holds the same sections, rows, kill flow, right-click overrides and footer as the panel, and refreshes every second while open.
- Its default size is 420 × 480 and its minimum 300 × 240; it remembers its size and position, and starts closed on each launch.
- ⌘W or its close button closes it; PortGlimpse keeps running in the menu bar.

It adapts to its width.

- From 360 points wide, rows are identical to the panel's.
- Below 360 points, rows are compact: port and command only, with the folder in a tooltip, and only the Kill icon on hover.
- In compact rows the kill question wraps onto its own line above Cancel and Kill.
- At every width, Open in browser, Copy PID and Reveal in Finder are also in the row's right-click menu.
- The list scrolls within whatever height the window has.

### Menu bar icon

The icon is the app icon's tile in full colour, the amber colon keycap on its dark tile, drawn at 18 points the same way as TickThock's menu bar icon so the two read as siblings (chosen on 2026-09-30 over the earlier white template outline).
Next to it is the number of dev servers; with none, the icon fades to 40 % and shows no number.
The count can be hidden in Settings.

### Settings

Settings is a submenu in the panel footer, not a window.

- Launch at login, on by default, through `SMAppService.mainApp`.
- Show the count in the menu bar, on by default.
- Check for updates, on by default.

There is deliberately no refresh-interval setting.

### Visual language

It follows TickThock's dark palette and type, in dark appearance regardless of the system setting.
Tokens come from `zewify/src/tickthock/styles/global.css` (dark block): page `#16130f`, panel `#201b17`, raised `#2a241f`, text `#f6ede3`, soft text `#d8cbbd`, muted `#a8998a`, lines `#342c25` / `#4a3f35`, amber `#f48e48`, amber face `#ffb067 → #ee8237`, text on amber `#1b1815`, amber tint `#2c211a` / `#4d3424`.
Type is Bricolage Grotesque for the title, Figtree for text and IBM Plex Mono for ports; the fonts ship in the app bundle, with licences checked before bundling.
The amber gradient appears only on the Kill and Force kill buttons; dev port labels use the amber tint.

## Architecture

The layout mirrors TickThock: Swift 6, SwiftUI, XcodeGen (`project.yml`, with the generated `.xcodeproj` gitignored), and a thin app over a Swift package.

### `PortGlimpseCore` (Swift package, no AppKit)

Each unit below has one job and is tested on its own.

- **`SocketScanner`** returns `[Listener]` (port, protocol family, PID) for TCP sockets in `LISTEN`.
  It has two sources behind one protocol.
  The primary source walks the current user's processes with `proc_listallpids`, `PROC_PIDLISTFDS` and `PROC_PIDFDSOCKETINFO`, which are public API.
  The "Show all" source runs `/usr/sbin/netstat -anv -p tcp` and parses its text, which names processes owned by other users without root (the spike confirmed `launchd` and Tailscale).
  Parsing `netstat`'s text was chosen over reading the `net.inet.tcp.pcblist_n` sysctl directly, because that sysctl's record layout is undocumented and a wrong offset fails silently, while text parsing is pinned by a test against a real capture.
  If it fails or returns nothing while the user has listeners, the Other users section shows "Can't read other users' ports on this macOS version" and the rest keeps working.
- **`ProcessInspector`** returns a `ProcessDetails` (executable path, arguments via `KERN_PROCARGS2`, working directory via `PROC_PIDVNODEPATHINFO`, owner UID) for a PID, with every field optional because a process can exit mid-read.
- **`CommandLabel`** turns arguments into the short command shown on a row, with rules for common runtimes (`node …/next dev` → `next dev`, `python -m http.server` → `http.server`, a bare binary → its name).
- **`Classifier`** assigns each process to a `Section`, applying overrides.
- **`OverrideStore`** persists right-click overrides as JSON in Application Support, keyed by executable path.
- **`Terminator`** performs the kill flow above as an `async` state sequence (`stopping`, `stopped`, `stillRunning`, `failed(reason)`) and refuses PIDs not owned by the current user.
- **`Snapshot`** combines the above into the ordered rows the panel shows, grouping ports by PID.

### The app

- `PortGlimpseApp`: `MenuBarExtra` with the icon and count, the panel view and the Settings submenu.
- A `PanelModel` polls `Snapshot` once a second while the panel or the pop-out window is showing, and stops when neither is; both views read the same model.
- A `FloatingWindowController` owns the one pop-out window: an `NSWindow` at the floating level that joins all Spaces and full-screen apps, with a transparent, full-size title bar.
  The menu bar count refreshes every 10 seconds while the panel is closed, a single cheap scan.
- `UpdateChecker`: once a day, when enabled, it requests `https://api.github.com/repos/zewify/portglimpse/releases/latest` and compares the tag with the running version.
  A newer release adds an "Update available: <version>" row to the footer whose button copies the install command.
  Network failures are silent.

### Data flow

Poll tick → `SocketScanner` → `ProcessInspector` per PID → `CommandLabel` and `Classifier` → `Snapshot` → `PanelModel` → view.
Kill: row → `Terminator` → state updates on the row → the next poll removes the row.

## Distribution

### Releases

A version tag (`v1.0.0`) runs a GitHub Actions workflow on a macOS runner.
It builds Release, signs with a Developer ID Application certificate, notarizes with `notarytool`, staples, zips the `.app` with `ditto`, and publishes the zip and its SHA-256 to GitHub Releases as `github-actions[bot]`.
Signing secrets live in repository secrets: the certificate as a base64 `.p12` with its password, and an App Store Connect API key for notarization.

### Install and update

`curl -fsSL https://zewify.com/portglimpse/install.sh | sh`:

1. Finds the latest release through the GitHub API.
2. Downloads the zip and checks its SHA-256.
3. Quits a running PortGlimpse, then installs to `/Applications` when writable (admin accounts can write there without `sudo`), else to `~/Applications`.
4. Launches it.

Running the same command again is the update.
The script is POSIX `sh`, idempotent, never uses `sudo`, and prints what it did.
Uninstalling is documented on the site: turn off Launch at login, quit, then delete the app and its Application Support folder.

### Website

The zewify repo gains a `/portglimpse/` product page built like `/tickthock/`, and serves `install.sh` at `/portglimpse/install.sh`.
It explains install, update, uninstall and what PortGlimpse can and cannot see, and links to the GitHub repo.
All printed facts (version, minimum macOS, repo URL) live in that page's data file, as `src/data/site.ts` does for the others.
The page must pass the existing `tests/dist.test.mjs` identity denylist.

## Identity

- Zewify must never identify the person who builds it.
- The repo lives in the `zewify` GitHub organization, created on 2026-09-30, whose membership is private.
- Commits are authored as `Zewify <dev@zewify.com>`, set in the repo's own git config.
- Releases are published by GitHub Actions.
- Issues are disabled; the website names the contact route.
- The app bundle ID is `com.zewify.portglimpse`, and nothing in the app, repo or site names a person.
- A known residual: pushes appear in the pushing account's public GitHub activity feed.

## Platform

macOS 14 or later, matching TickThock, on Apple silicon and Intel as a universal binary.

## Testing

- Core unit tests for `CommandLabel`, `Classifier`, `OverrideStore`, `Snapshot` and `Terminator`, from recorded fixtures of real process and socket data.
- An integration test that starts a real TCP server on a free port in a child process, asserts `SocketScanner` finds it with the right PID and working directory, kills it through `Terminator`, and asserts the port is free.
- An integration test that starts a child ignoring `SIGTERM` and asserts `Terminator` reports `stillRunning` and then stops it with `SIGKILL`.
- A test that parses a real `netstat -anv -p tcp` capture, including a process name with a space, and a live test that finds the test server through `netstat`.
- The install script is tested against a local fake release (a file server and a zip), covering the fresh install, the update and the `~/Applications` fallback.
- UI is checked by hand against the canvas before each release, at 2560×1440 and a laptop width.

## Prerequisites before implementation

- Create a Developer ID Application certificate for team `GHVX6RBQ64`.
- Create an App Store Connect API key for notarization.
- Create the `zewify/portglimpse` repo, public, with issues disabled.

## Out of scope for 1.0

- Docker container names in place of `com.docker.backend`.
- "Tell me when :3000 frees up".
- A global hotkey to open the panel.
- A Homebrew cask in a `zewify/homebrew-tap` repo.
- Light appearance.
- UDP listeners.
