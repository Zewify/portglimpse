import PortGlimpseCore
import SwiftUI

/// One process: its ports, command and folder, and the kill flow in place.
/// `compact` is the pop-out window's layout below 360 points wide.
struct RowView: View {
    let row: Row
    let model: PanelModel
    var compact = false
    @State private var hovering = false

    var body: some View {
        Group {
            if compact { compactBody } else { fullBody }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering && row.section != .otherUsers ? Theme.raised : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { rowMenu }
    }

    private var fullBody: some View {
        HStack(alignment: .center, spacing: 14) {
            ports
            content
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 9)
        .frame(minHeight: 52)
    }

    /// Port and command only; the folder moves to a tooltip, only Kill shows on hover,
    /// and a question wraps onto its own line above its buttons.
    @ViewBuilder private var compactBody: some View {
        switch model.phase(of: row) {
        case .confirming:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    PortTag(port: row.ports[0], section: row.section)
                    Text(verbatim: row.killQuestion)
                        .font(Theme.body(13, .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    Spacer()
                    Button("Cancel") { model.cancel(row) }.buttonStyle(PanelButtonStyle(.ghost))
                    Button("Kill") { model.confirmKill(row) }.buttonStyle(PanelButtonStyle(.primary))
                }
            }
            .padding(8)
        case .stillRunning:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    PortTag(port: row.ports[0], section: row.section)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "\(row.command) didn’t stop").font(Theme.body(13, .bold)).foregroundStyle(Theme.text)
                        Text("Force kill it? Unsaved work in it is lost.").font(Theme.body(12)).foregroundStyle(Theme.softText)
                    }
                }
                HStack(spacing: 6) {
                    Spacer()
                    Button("Cancel") { model.cancel(row) }.buttonStyle(PanelButtonStyle(.ghost))
                    Button("Force kill") { model.confirmForceKill(row) }.buttonStyle(PanelButtonStyle(.primary))
                }
            }
            .padding(8)
        case .idle, .stopping, .failed:
            HStack(spacing: 10) {
                PortTag(port: row.ports[0], section: row.section)
                compactText
                Spacer(minLength: 0)
                if model.phase(of: row) == .idle {
                    if row.section == .otherUsers {
                        ownerBadge
                    } else if hovering {
                        IconButton(symbol: "xmark.circle", label: "Kill", destructive: true) { model.askKill(row) }
                    }
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .frame(minHeight: 40)
            .help([row.folder, row.workerSummary].compactMap { $0 }.joined(separator: " · "))
        }
    }

    @ViewBuilder private var compactText: some View {
        switch model.phase(of: row) {
        case .stopping:
            Text(verbatim: "Stopping…").font(Theme.body(13)).foregroundStyle(Theme.muted)
        case .failed(let reason):
            Text(verbatim: "Couldn’t kill. \(reason)").font(Theme.body(12)).foregroundStyle(Theme.softText).lineLimit(2)
        default:
            HStack(spacing: 5) {
                Text(verbatim: row.command)
                    .font(Theme.body(14, .bold))
                    .foregroundStyle(row.section == .dev ? Theme.text : Theme.softText)
                    .lineLimit(1)
                if !row.workerPIDs.isEmpty {
                    Text(verbatim: "+\(row.workerPIDs.count)")
                        .font(Theme.body(12, .semibold))
                        .foregroundStyle(Theme.muted)
                        .fixedSize()
                }
            }
        }
    }

    private var ports: some View {
        VStack(alignment: .leading, spacing: 6) {
            PortTag(port: row.ports[0], section: row.section)
            if row.ports.count > 1 {
                Text(verbatim: "+ " + row.ports.dropFirst().map { ":\($0)" }.joined(separator: " "))
                    .font(.custom("IBM Plex Mono", size: 11).weight(.medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
        }
        .frame(width: 72, alignment: .leading)
    }

    @ViewBuilder private var content: some View {
        switch model.phase(of: row) {
        case .idle:
            details
            Spacer(minLength: 0)
            if row.section == .otherUsers {
                ownerBadge
            } else if hovering {
                actions
            }
        case .confirming:
            Text(verbatim: row.killQuestion)
                .font(Theme.body(13, .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Cancel") { model.cancel(row) }.buttonStyle(PanelButtonStyle(.ghost))
            Button("Kill") { model.confirmKill(row) }.buttonStyle(PanelButtonStyle(.primary))
        case .stopping:
            Text(verbatim: "Stopping \(row.command)…").font(Theme.body(13)).foregroundStyle(Theme.muted)
            Spacer(minLength: 0)
        case .stillRunning:
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "\(row.command) didn’t stop").font(Theme.body(14, .bold)).foregroundStyle(Theme.text)
                    Text("Force kill it? Unsaved work in it is lost.").font(Theme.body(12)).foregroundStyle(Theme.softText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    Button("Cancel") { model.cancel(row) }.buttonStyle(PanelButtonStyle(.ghost))
                    Button("Force kill") { model.confirmForceKill(row) }.buttonStyle(PanelButtonStyle(.primary))
                }
            }
        case .failed(let reason):
            Text(verbatim: "Couldn’t kill \(row.command). \(reason)")
                .font(Theme.body(13))
                .foregroundStyle(Theme.softText)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: row.command)
                .font(Theme.body(14, .bold))
                .foregroundStyle(row.section == .dev ? Theme.text : Theme.softText)
                .lineLimit(1)
            // The worker count stays whole while a long folder shortens in the middle.
            HStack(spacing: 4) {
                Text(verbatim: row.section == .otherUsers ? "PID \(row.pid)" : (row.folder ?? "PID \(row.pid)"))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let workers = row.workerSummary {
                    Text(verbatim: "·")
                    Text(verbatim: workers).lineLimit(1).fixedSize()
                }
            }
            .font(Theme.body(12))
            .foregroundStyle(Theme.muted)
        }
    }

    private var actions: some View {
        HStack(spacing: 2) {
            if row.section == .dev {
                IconButton(symbol: "arrow.up.right.square", label: "Open localhost:\(row.ports[0])") { model.openInBrowser(row) }
            }
            IconButton(symbol: "doc.on.doc", label: "Copy PID \(row.pid)") { model.copyPID(row) }
            if row.section == .dev, row.folder != nil {
                IconButton(symbol: "folder", label: "Reveal in Finder") { model.revealFolder(row) }
            }
            IconButton(symbol: "xmark.circle", label: "Kill", destructive: true) { model.askKill(row) }
        }
    }

    private var ownerBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock").font(.system(size: 11, weight: .semibold))
            Text(verbatim: row.owner ?? "another user").font(Theme.body(12, .semibold))
        }
        .foregroundStyle(Theme.muted)
        .padding(.trailing, 6)
        .help("Owned by \(row.owner ?? "another user")")
    }

    /// The row's actions (the only way to reach them in a compact row), then placement.
    /// Other users' rows get no menu at all.
    @ViewBuilder private var rowMenu: some View {
        if row.section != .otherUsers {
            if row.section == .dev {
                Button("Open localhost:\(String(row.ports[0]))") { model.openInBrowser(row) }
            }
            Button("Copy PID \(String(row.pid))") { model.copyPID(row) }
            if row.section == .dev, row.folder != nil {
                Button("Reveal in Finder") { model.revealFolder(row) }
            }
            Button("Kill…") { model.askKill(row) }
            if row.executablePath != nil {
                Divider()
                Button("Always show as dev") { model.setPlacement(.dev, for: row) }
                    .disabled(model.placement(of: row) == .dev)
                Button("Always hide in Apps & system") { model.setPlacement(.appsAndSystem, for: row) }
                    .disabled(model.placement(of: row) == .appsAndSystem)
                if model.placement(of: row) != nil {
                    Button("Use automatic placement") { model.setPlacement(nil, for: row) }
                }
            }
        }
    }
}

/// A flat port label; deliberately unlike a button.
struct PortTag: View {
    let port: UInt16
    let section: PortGlimpseCore.Section

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Text(verbatim: ":\(port)")
            .font(Theme.mono(14))
            .monospacedDigit()
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .frame(minWidth: 52, minHeight: 24)
            .background(section == .dev ? Theme.amberTint : .clear, in: shape)
            .overlay(shape.strokeBorder(border))
    }

    private var foreground: Color {
        switch section {
        case .dev: Theme.amber
        case .appsAndSystem: Theme.capInk
        case .otherUsers: Theme.muted
        }
    }

    private var border: Color {
        switch section {
        case .dev: Theme.amberTintLine
        case .appsAndSystem: Theme.lineStrong
        case .otherUsers: Theme.line
        }
    }
}

/// A 30-point icon button that lights up on hover; Kill turns amber.
struct IconButton: View {
    let symbol: String
    let label: String
    var destructive = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 30)
                .foregroundStyle(hovering ? (destructive ? Theme.amber : Theme.text) : Theme.muted)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? (destructive ? Theme.amberTint : Theme.cap) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}
