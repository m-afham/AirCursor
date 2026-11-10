import SwiftUI
import AirCursorCore

/// "A new version is available": what's new, and how to install it.
struct UpdateView: View {
    static let windowTitle = "AirCursor Update"

    @EnvironmentObject private var controller: AppController
    @EnvironmentObject private var updates: UpdateController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    if let update = updates.available {
                        Text("AirCursor \(update.version.description) is available")
                            .font(.title3.weight(.semibold))
                        Text("You have \(updates.currentVersion).")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("AirCursor is up to date")
                            .font(.title3.weight(.semibold))
                        Text("You have the latest version, \(updates.currentVersion).")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let update = updates.available {
                let notes = ReleaseNotes.summary(from: update.release.body)
                if !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What’s new").font(.headline)
                        ForEach(notes, id: \.self) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("•")
                                Text(line).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Button("Full release notes") { updates.openReleaseNotes() }
                            .buttonStyle(.link)
                            .padding(.top, 2)
                    }
                }

                if updates.canInstallAutomatically {
                    Text(UpdateInstaller.isAdHocSigned
                         ? "AirCursor installs the update and restarts. This one time, macOS needs you to allow AirCursor again: in Accessibility, remove AirCursor with the − button, then switch it back on. The guided tour shows you where. Later updates keep your permissions."
                         : "AirCursor installs the update and restarts. Your permissions carry over.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("To install").font(.headline)
                        step(1, "Click Download. AirCursor.zip goes to your Downloads folder.")
                        step(2, "Open the zip, then quit AirCursor from its menu bar icon.")
                        step(3, "Drag the new AirCursor into Applications and choose Replace.")
                        step(4, "Open it. If the pointer doesn’t move, switch AirCursor off and on in Privacy & Security › Accessibility.")
                    }
                    .font(.callout)
                }

                installStatus
            }

            HStack {
                if updates.available != nil {
                    Button("Skip This Version") {
                        updates.skip()
                        dismiss()
                    }
                    .disabled(isInstalling)
                    Spacer()
                    Button("Later") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .disabled(isInstalling)
                    if updates.canInstallAutomatically {
                        Button("Install & Relaunch") { updates.install() }
                            .keyboardShortcut(.defaultAction)
                            .disabled(isInstalling)
                    } else {
                        Button("Download") { updates.download() }
                            .keyboardShortcut(.defaultAction)
                    }
                } else {
                    Spacer()
                    Button("OK") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(22)
        .frame(width: 440)
        .onAppear { controller.windowVisibilityChanged() }
        .onDisappear { controller.windowVisibilityChanged() }
    }

    private var isInstalling: Bool {
        if case .working = updates.installPhase { return true }
        return false
    }

    @ViewBuilder private var installStatus: some View {
        switch updates.installPhase {
        case .idle:
            EmptyView()
        case .working(let message):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(message).foregroundStyle(.secondary)
            }
        case .failed(let message):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Download Instead") { updates.download() }
                    .controlSize(.small)
            }
            .font(.callout)
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(n).").monospacedDigit().foregroundStyle(.secondary)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
