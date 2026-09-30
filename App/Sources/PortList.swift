import PortGlimpseCore
import SwiftUI

/// The three sections, shared by the menu bar panel and the pop-out window.
struct PortList: View {
    @Bindable var model: PanelModel
    var compact = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                sectionLabel("Dev servers")
                if let problem = model.problem {
                    message(problem)
                } else if model.rows(in: .dev).isEmpty {
                    message("Nothing listening. Your ports are free.")
                }
                ForEach(model.rows(in: .dev)) { RowView(row: $0, model: model, compact: compact) }
            }
            .padding(8)

            Divider().overlay(Theme.line)
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    model.appsExpanded.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: model.appsExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 14)
                        Text("Apps & system").font(Theme.body(13, .bold))
                        Spacer()
                        Text(verbatim: "\(model.rows(in: .appsAndSystem).count)").font(Theme.mono(12)).foregroundStyle(Theme.muted)
                    }
                    .foregroundStyle(Theme.softText)
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(model.appsExpanded ? "Expanded" : "Collapsed")
                if model.appsExpanded {
                    ForEach(model.rows(in: .appsAndSystem)) { RowView(row: $0, model: model, compact: compact) }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            if model.showAll {
                Divider().overlay(Theme.line)
                VStack(alignment: .leading, spacing: 2) {
                    sectionLabel("Other users · view only")
                    if let problem = model.otherUsersProblem { message(problem) }
                    ForEach(model.rows(in: .otherUsers)) { RowView(row: $0, model: model, compact: compact) }
                }
                .padding(8)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Theme.body(11, .bold))
            .tracking(0.9)
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(Theme.body(13))
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 14)
    }
}
