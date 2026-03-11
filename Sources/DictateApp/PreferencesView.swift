import SwiftUI

/// Enum for preferences tabs (extensible for future tabs).
enum PreferencesTab: String, CaseIterable {
    case general = "General"

    var icon: String {
        switch self {
        case .general: return "gearshape"
        }
    }
}

/// Root preferences view with custom tab bar and content area.
///
/// Uses liquid glass design with .regularMaterial background and custom tab bar.
/// Follows macOS 16 design patterns seen in MicIndicatorView.swift.
struct PreferencesView: View {
    @StateObject private var preferencesManager = PreferencesManager.shared
    @State private var selectedTab: PreferencesTab = .general

    var body: some View {
        VStack(spacing: 0) {
            // Custom tab bar
            PreferencesTabBar(selectedTab: $selectedTab)

            // Content area
            switch selectedTab {
            case .general:
                GeneralPreferencesView()
            }
        }
        .frame(width: 580, height: 460)
        .background(Material.regularMaterial)
    }
}

/// Custom tab bar for preferences window.
///
/// Mimics native macOS tab bar but with liquid glass styling.
struct PreferencesTabBar: View {
    @Binding var selectedTab: PreferencesTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PreferencesTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = tab
                    }
                }) {
                    Label(tab.rawValue, systemImage: tab.icon)
                        .font(.system(size: 13))
                        .foregroundColor(selectedTab == tab ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    selectedTab == tab
                        ? Color.white.opacity(0.1)
                        : Color.clear
                )
                .cornerRadius(6)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Material.ultraThinMaterial)
    }
}
