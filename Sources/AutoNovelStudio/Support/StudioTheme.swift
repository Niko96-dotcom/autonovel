import SwiftUI

enum StudioTheme {
    static let accent = Color(red: 0.88, green: 0.24, blue: 0.18)
    static let ink = Color(red: 0.12, green: 0.11, blue: 0.10)
    static let amber = accent
    static let plum = Color(red: 0.37, green: 0.17, blue: 0.20)
    static let moss = Color(red: 0.22, green: 0.44, blue: 0.31)
    static let success = moss
    static let heroGradient = LinearGradient(
        colors: [ink.opacity(0.98), Color(red: 0.22, green: 0.11, blue: 0.10), accent.opacity(0.86)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let hairline = Color.primary.opacity(0.10)
}

extension View {
    func studioCard(padding: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(StudioTheme.hairline, lineWidth: 1)
            }
    }
}

struct SectionEyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.3)
            .foregroundStyle(StudioTheme.accent)
    }
}

struct StatusPill: View {
    let text: String
    let color: Color
    var animated = false

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: animated ? color.opacity(0.8) : .clear, radius: 5)
            Text(text)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12), in: Capsule())
        .foregroundStyle(color)
    }
}
