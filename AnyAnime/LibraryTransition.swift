import SwiftUI

/// Short native transitions keep the original artwork intact. No network or video
/// decoding is involved, and Reduce Motion uses a gentle crossfade instead.
struct LibraryTransition: View {
    let from: String
    let to: String
    let intro: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = Date()
    var duration: Double { reduceMotion ? 0.35 : (intro ? 1.8 : 1.05) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
            let progress = min(1, max(0, timeline.date.timeIntervalSince(started) / duration))
            GeometryReader { geometry in
                let side = min(240.0, geometry.size.width * 0.52)
                ZStack {
                    Color(red: 0.018, green: 0.012, blue: 0.04).ignoresSafeArea()
                    Circle().fill(Color.anpinimeAccent.opacity(0.18)).frame(width: side * 1.45, height: side * 1.45).blur(radius: 55)
                    if reduceMotion {
                        Image(to).resizable().scaledToFit().frame(width: side).opacity(progress).blendMode(.screen)
                    } else if intro {
                        let merge = min(1, progress / 0.65)
                        let eased = merge * merge * (3 - 2 * merge)
                        Image("AppLogo").resizable().scaledToFit().frame(width: side)
                            .offset(x: -side * 0.64 * (1 - eased), y: -18 * sin(merge * .pi))
                            .rotationEffect(.degrees(-12 * (1 - eased)))
                            .opacity(1 - max(0, progress - 0.72) / 0.28).blendMode(.screen)
                        Image("MovieLogo").resizable().scaledToFit().frame(width: side)
                            .offset(x: side * 0.64 * (1 - eased), y: 18 * sin(merge * .pi))
                            .rotationEffect(.degrees(12 * (1 - eased)))
                            .opacity(progress < 0.7 ? 1 : 0.65).blendMode(.screen)
                    } else {
                        let burst = min(1, max(0, (progress - 0.08) / 0.64))
                        Canvas { context, size in
                            let image = context.resolve(Image(from))
                            let tile = side / 6
                            for row in 0..<6 {
                                for column in 0..<6 {
                                    let dx = Double(column) - 2.5, dy = Double(row) - 2.5
                                    var piece = context
                                    piece.opacity = 1 - burst
                                    piece.translateBy(x: size.width / 2 + dx * side * 0.42 * burst,
                                                      y: size.height / 2 + dy * side * 0.38 * burst)
                                    piece.rotate(by: .degrees((dx * 13 - dy * 7) * burst))
                                    piece.clip(to: Path(CGRect(x: -side / 2 + Double(column) * tile,
                                                              y: -side / 2 + Double(row) * tile, width: tile, height: tile)))
                                    piece.draw(image, in: CGRect(x: -side / 2, y: -side / 2, width: side, height: side))
                                }
                            }
                        }.blendMode(.screen)
                        let reveal = min(1, max(0, (progress - 0.3) / 0.7))
                        Image(to).resizable().scaledToFit().frame(width: side)
                            .scaleEffect(0.82 + reveal * 0.18).opacity(reveal).blur(radius: (1 - reveal) * 5).blendMode(.screen)
                    }
                    VStack { Spacer(); Text(intro ? "ANPINIME" : (to == "MovieLogo" ? "ĐIỆN ẢNH" : "ANIME"))
                        .font(.system(size: 13, weight: .semibold, design: .rounded)).tracking(5)
                        .foregroundStyle(.white.opacity(0.7)).padding(.bottom, max(40, geometry.size.height * 0.18)) }
                }
            }
        }.allowsHitTesting(true).accessibilityLabel(intro ? "AnPinime đang mở" : "Đang chuyển thư viện")
    }
}
