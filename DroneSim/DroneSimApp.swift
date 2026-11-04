import SwiftUI

@main
struct DroneSimApp: App {
    var body: some Scene {
        WindowGroup {
            GameViewControllerRepresentable()
                .ignoresSafeArea()
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
        }
    }
}

/// 用 UIKit 桥接 SwiftUI（Metal 视图用 UIViewController 更直接）。
struct GameViewControllerRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> GameViewController {
        GameViewController()
    }

    func updateUIViewController(_ uiViewController: GameViewController, context: Context) {}
}
