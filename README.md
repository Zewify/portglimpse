# PortGlimpse

PortGlimpse is a free Mac menu bar app that shows what is listening on your ports, which project each server belongs to, and lets you stop one after confirming.

## What it shows

- **Dev servers** — your own servers, with their command (`next dev`, `vite`) and project folder.
- **Apps & system** — ports opened by apps and macOS services, collapsed by default.
- **Other users** — ports owned by root or other accounts, view only, when "Show all users' ports" is on.

Right-click a row to always show a program as a dev server, or always hide it.

## Pop-out window

"Open in a window" in the panel header opens an always-on-top, resizable window with the same list.
Keep it beside your editor while you work.

## Install

PortGlimpse needs macOS 14 or later.
Installation instructions live at https://zewify.com/portglimpse/.

## Build from source

You need Xcode and XcodeGen (`brew install xcodegen`).

- `./scripts/test.sh` runs the tests and builds the app.
- `./scripts/install-local.sh` builds a Release copy into `/Applications` and opens it.

## Privacy

PortGlimpse reads the list of listening ports and process details from macOS on your Mac.
It sends nothing anywhere; the only network request is an optional daily check for a newer release on GitHub.

## Licence

PortGlimpse is source available, not open source.
The source is published so you can read exactly what the app does, and build it for yourself.
Zewify keeps all rights to it; no licence to copy, modify or redistribute it is granted.

The bundled fonts — Bricolage Grotesque, Figtree and IBM Plex Mono — are under the SIL Open Font License; their licences are in `App/Resources/Fonts`.
