import SwiftUI

extension View {
    @ViewBuilder
    func cinemaGlass(cornerRadius: CGFloat = 24, interactive: Bool = false, selected: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if interactive {
                self.glassEffect(.regular.tint(selected ? .anpinimeAccent.opacity(0.35) : .clear).interactive(),
                                 in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(.white.opacity(selected ? 0.35 : 0.13)))
        }
    }
}
