import SwiftUI

/// Frosted-glass panel showing a mic icon, live transcript, and close button.
///
/// The panel grows vertically to fit the transcript text, with smooth
/// animations as words appear. Designed to be clearly readable at a glance.
struct MicIndicatorView: View {
    @ObservedObject var state: ListeningState
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top bar: mic icon + status + close button
            HStack(spacing: 10) {
                // Pulsing mic icon
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Circle()
                        .fill(.red.opacity(0.6 + state.audioLevel * 0.4))
                        .frame(width: 32 * (0.5 + state.audioLevel * 0.5),
                               height: 32 * (0.5 + state.audioLevel * 0.5))
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 32, height: 32)

                Text(state.transcript.isEmpty ? "Listening…" : "Dictating…")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))

                Spacer()

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 24, height: 24)
                        .background(.white.opacity(0.15), in: Circle())
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
            }

            // Transcript text area
            if !state.transcript.isEmpty {
                Text(state.transcript)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(6)
                    .truncationMode(.head)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: state.audioLevel)
        .animation(.easeOut(duration: 0.15), value: state.transcript)
    }
}
