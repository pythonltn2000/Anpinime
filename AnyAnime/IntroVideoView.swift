import SwiftUI
import AVFoundation

struct IntroVideoView: UIViewControllerRepresentable {
    let finished: () -> Void
    func makeUIViewController(context: Context) -> IntroVideoController { IntroVideoController(finished: finished) }
    func updateUIViewController(_ controller: IntroVideoController, context: Context) {}
    static func dismantleUIViewController(_ controller: IntroVideoController, coordinator: ()) { controller.stop() }
}

final class IntroVideoController: UIViewController {
    private let finished: () -> Void
    private var player: AVPlayer?
    private var surface: AVPlayerLayer?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var deadline: DispatchWorkItem?
    private var completed = false
    init(finished: @escaping () -> Void) { self.finished = finished; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let url = Bundle.main.url(forResource: "Intro", withExtension: "mp4") else { complete(); return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let player = AVPlayer(url: url); self.player = player
        let surface = AVPlayerLayer(player: player); self.surface = surface
        surface.videoGravity = .resizeAspect
        view.layer.addSublayer(surface)
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in self?.complete() }
        failureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in self?.complete() }
        let deadline = DispatchWorkItem { [weak self] in self?.complete() }; self.deadline = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: deadline)
        player.play()
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); surface?.frame = view.bounds }
    private func complete() { guard !completed else { return }; completed = true; stop(); DispatchQueue.main.async(execute: finished) }
    func stop() {
        deadline?.cancel(); deadline = nil
        player?.pause(); player?.replaceCurrentItem(with: nil)
        if let endObserver { NotificationCenter.default.removeObserver(endObserver); self.endObserver = nil }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver); self.failureObserver = nil }
    }
}
