import SwiftUI

final class AnPinimeAppDelegate: NSObject, UIApplicationDelegate {
    static var orientationMask: UIInterfaceOrientationMask = .portrait
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.orientationMask
    }
}

@MainActor
enum PlayerOrientation {
    static func setLandscape(_ landscape: Bool, scene: UIWindowScene?) {
        let mask: UIInterfaceOrientationMask = landscape ? .landscape : .portrait
        AnPinimeAppDelegate.orientationMask = mask
        guard let scene else { return }
        var controller = scene.windows.first(where: \.isKeyWindow)?.rootViewController
        if #available(iOS 16, *) {
            controller?.setNeedsUpdateOfSupportedInterfaceOrientations()
            while let presented = controller?.presentedViewController {
                controller = presented
                controller?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: landscape ? .landscapeRight : .portrait))
        } else {
            UIDevice.current.setValue((landscape ? UIInterfaceOrientation.landscapeRight : .portrait).rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
}

/// Requests rotation once the full-screen presentation is actually on screen.
struct LandscapePresentation: UIViewControllerRepresentable {
    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            PlayerOrientation.setLandscape(true, scene: view.window?.windowScene)
        }
    }
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ uiViewController: Controller, context: Context) { }
    static func dismantleUIViewController(_ uiViewController: Controller, coordinator: ()) {
        let scene = uiViewController.view.window?.windowScene
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        PlayerOrientation.setLandscape(false, scene: scene)
    }
}

/// Rotation keeps the same native player and its playback position attached.
struct VideoOrientationPresentation: UIViewControllerRepresentable {
    let landscape: Bool
    final class Controller: UIViewController {
        var landscape = false
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            PlayerOrientation.setLandscape(landscape, scene: view.window?.windowScene)
        }
    }
    func makeUIViewController(context: Context) -> Controller { let c = Controller(); c.landscape = landscape; return c }
    func updateUIViewController(_ controller: Controller, context: Context) {
        guard controller.landscape != landscape else { return }
        controller.landscape = landscape
        PlayerOrientation.setLandscape(landscape, scene: controller.view.window?.windowScene)
    }
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        if controller.landscape { PlayerOrientation.setLandscape(false, scene: controller.view.window?.windowScene) }
    }
}
