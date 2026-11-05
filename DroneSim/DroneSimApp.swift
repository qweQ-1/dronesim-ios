import UIKit

/// App 入口。
///
/// iOS 13+ 走 UIWindowScene：纯 AppDelegate + UIWindow 的老写法在 iOS 26 上
/// 可能启动成功但没有可见窗口（无障碍树会是空的），所以这里用 scene。
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .landscape
    }
}

/// 场景 delegate：创建窗口并挂上游戏主界面。
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = GameViewController()
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // 回到前台时恢复渲染循环
        (window?.rootViewController as? GameViewController)?.resumeRendering()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        (window?.rootViewController as? GameViewController)?.pauseRendering()
    }
}
