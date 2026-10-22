import SwiftUI
import ImageIO

extension Color {
    static let anpinimeAccent = Color(red: 0.69, green: 0.45, blue: 1)
}

/// GIF is composited with screen blending by LoadingView so black disappears
/// into the dark app background without changing the supplied animation.
struct AnimatedListLoader: UIViewRepresentable {
    private static let animation: UIImage? = {
        guard let url = Bundle.main.url(forResource: "Code_Generated_Image", withExtension: "gif"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        var frames: [UIImage] = []
        var duration = 0.0
        for index in 0..<CGImageSourceGetCount(source) {
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                           kCGImageSourceThumbnailMaxPixelSize: 420,
                                           kCGImageSourceCreateThumbnailWithTransform: true]
            guard let frame = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else { continue }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double
                ?? gif?[kCGImagePropertyGIFDelayTime] as? Double ?? 0.08
            duration += max(0.02, delay)
            frames.append(UIImage(cgImage: frame))
        }
        return UIImage.animatedImage(with: frames, duration: duration)
    }()

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView(image: Self.animation)
        view.contentMode = .scaleAspectFit
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.accessibilityLabel = "Đang tải"
        return view
    }
    func updateUIView(_ uiView: UIImageView, context: Context) { }
    static func dismantleUIView(_ uiView: UIImageView, coordinator: ()) { uiView.stopAnimating() }
}
