import OrbitKit
import SwiftUI

/// A white SF Symbol on a colored rounded square, like the icons in System Settings.
struct ModuleIcon: View {
    let symbolName: String
    let tint: ModuleTint
    var size: CGFloat = 32

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(tint.color.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

extension ModuleTint {
    var color: Color {
        switch self {
        case .blue: .blue
        case .green: .green
        case .indigo: .indigo
        case .orange: .orange
        case .pink: .pink
        case .purple: .purple
        case .red: .red
        case .teal: .teal
        case .yellow: .yellow
        case .gray: .gray
        }
    }
}
