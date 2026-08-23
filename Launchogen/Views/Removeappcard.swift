import SwiftUI

struct RemoveAppCard: View {
    let isFocused: Bool
    let onRemove: () -> Void
    let onDismiss: () -> Void

    @State private var appeared = false

    var body: some View {
        Button(action: {
            appeared = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                onRemove()
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: "minus.circle")
                    .font(.system(size: 16, weight: .semibold))
                Text("Remove from Launcher")
                    .font(.system(size: 14, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.23)) // system red
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(RemoveRowButtonStyle(isFocused: isFocused))
        .frame(width: 230)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(isFocused ? 0.6 : 0.25), lineWidth: isFocused ? 2 : 1)
                )
        )
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        .scaleEffect(appeared ? 1.0 : 0.85, anchor: .top)
        .opacity(appeared ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                appeared = true
            }
        }
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

private struct RemoveRowButtonStyle: ButtonStyle {
    let isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed || isFocused ? 0.14 : 0.0))
            )
    }
}

struct JiggleEffect: ViewModifier {
    let isActive: Bool
    @State private var rotate = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isActive ? (rotate ? 1.6 : -1.6) : 0))
            .animation(
                isActive
                    ? .easeInOut(duration: 0.14).repeatForever(autoreverses: true)
                    : .default,
                value: rotate
            )
            .onChange(of: isActive) { _, active in
                rotate = active
            }
            .onAppear {
                if isActive { rotate = true }
            }
    }
}

extension View {
    func jiggling(_ isActive: Bool) -> some View {
        modifier(JiggleEffect(isActive: isActive))
    }
}
