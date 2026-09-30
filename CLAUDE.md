# PortGlimpse

A free Mac menu bar app that lists listening ports with their project folder and kills a process after confirmation; a Zewify product.
Design: `docs/superpowers/specs/2026-09-30-portglimpse-design.md`.
Plan: `docs/superpowers/plans/2026-09-30-portglimpse-app.md`.

## Layout

- `Core/` — the `PortGlimpseCore` Swift package: every rule, Foundation and Darwin only.
- `App/` — the thin SwiftUI menu bar app.

## Commands

- `./scripts/test.sh` — core tests, then an app build. Run before every commit; the exit code is the verdict.
- `./scripts/build.sh [Debug|Release]` — generates the project and builds; prints the app path.
- `./scripts/install-local.sh` — a Release build copied to `/Applications` and launched.
- `swift scripts/make-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset` — re-renders the app icon.
- `project.yml` is the XcodeGen spec; the `.xcodeproj` is generated and gitignored, so never edit or commit it.

## Rules that are not obvious

- Zewify rule: nothing in the app, repo, commits or docs may identify the person who builds it.
- Commits use the repo's configured author (`Zewify`); never override it and never add co-author trailers.
- The Core never imports AppKit or SwiftUI.
- Never run `lsof`; "Show all" reads `/usr/sbin/netstat -anv -p tcp`.
- The Core refuses to signal a process owned by another user, whatever the UI asks.
- The menu bar panel's open and close come from its window's key status (`PanelWindowObserver`), because a window-style `MenuBarExtra` keeps its view alive between openings.
- Distribution (Developer ID signing, notarization, `install.sh`, the zewify.com page) is the second plan and is not built yet.
