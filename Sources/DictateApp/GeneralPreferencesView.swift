import SwiftUI

/// Main content for the General preferences tab.
///
/// Displays keyboard shortcut configuration with liquid glass card design.
/// Follows the design patterns from MicIndicatorView.swift.
struct GeneralPreferencesView: View {
    @ObservedObject private var preferencesManager = PreferencesManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("General")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("Configure your dictation preferences")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 32)

                // Shortcut Recorder Card
                VStack(alignment: .leading, spacing: 16) {
                    Text("Keyboard Shortcut")
                        .font(.system(size: 15, weight: .semibold))

                    ShortcutRecorderView(preference: $preferencesManager.currentHotkey)

                    Button("Reset to Default") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            preferencesManager.resetToDefault()
                        }
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                .padding(20)
                .background(Material.thickMaterial)
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)

                // Footer help text
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Text("The keyboard shortcut triggers dictation globally across all applications. Choose a combination that doesn't conflict with your existing shortcuts.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 32)
        }
    }
}
