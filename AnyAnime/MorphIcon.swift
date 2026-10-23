import SwiftUI
import UIKit

/// Morphicons' generated paths are rendered natively, without a WebView per icon.
struct MorphIcon: UIViewRepresentable {
    let name: String
    var size: CGFloat = 22
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeUIView(context: Context) -> MorphIconSurface { MorphIconSurface() }
    func updateUIView(_ view: MorphIconSurface, context: Context) { view.show(name, animated: !reduceMotion) }
    @available(iOS 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MorphIconSurface, context: Context) -> CGSize? {
        CGSize(width: size, height: size)
    }
}

final class MorphIconSurface: UIView {
    private struct Asset: Decodable {
        let icons: [String: [[Double]]]
        let transitions: [String: [[[Double]]]]
    }
    private static let asset: Asset? = {
        guard let url = Bundle.main.url(forResource: "Morphicons", withExtension: "json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Asset.self, from: data)
    }()
    private let drawing = CAShapeLayer()
    private var symbol = ""
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        drawing.fillColor = UIColor.clear.cgColor
        drawing.strokeColor = UIColor.white.cgColor
        drawing.lineWidth = 1.8; drawing.lineCap = .round; drawing.lineJoin = .round
        layer.addSublayer(drawing)
        isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = min(bounds.width, bounds.height) / 24
        drawing.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        drawing.position = CGPoint(x: (bounds.width - 24 * scale) / 2, y: (bounds.height - 24 * scale) / 2)
    }
    func show(_ name: String, animated: Bool) {
        guard symbol != name, let target = Self.asset?.icons[name] else { return }
        let previous = symbol; symbol = name
        let currentPath = drawing.presentation()?.path ?? drawing.path
        let interrupted = drawing.animation(forKey: "morph") != nil
        drawing.removeAnimation(forKey: "morph")
        let frames = Self.asset?.transitions[previous + ":" + name]
        let last = frames?.last ?? target
        CATransaction.begin(); CATransaction.setDisableActions(true)
        drawing.path = Self.path(last); CATransaction.commit()
        guard animated, !previous.isEmpty else { return }
        if let frames, !interrupted {
            let animation = CAKeyframeAnimation(keyPath: "path")
            animation.values = frames.map(Self.path)
            animation.duration = Double(frames.count - 1) / 60
            animation.calculationMode = .linear
            drawing.add(animation, forKey: "morph")
        } else if let currentPath {
            let animation = CABasicAnimation(keyPath: "path")
            animation.fromValue = currentPath; animation.toValue = drawing.path
            animation.duration = 0.24; animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            drawing.add(animation, forKey: "morph")
        }
    }
    private static func path(_ paths: [[Double]]) -> CGPath {
        let result = CGMutablePath()
        for points in paths where points.count >= 4 {
            result.move(to: CGPoint(x: points[0], y: points[1]))
            for index in stride(from: 2, to: points.count - 1, by: 2) {
                result.addLine(to: CGPoint(x: points[index], y: points[index + 1]))
            }
        }
        return result
    }
}
