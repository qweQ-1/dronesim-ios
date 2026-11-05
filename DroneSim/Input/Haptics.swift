import Foundation
import UIKit

/// 触感反馈。
///
/// 真机上用 Taptic Engine；模拟器或没有触感的设备上静默忽略。
enum Haptics {

    enum ImpactStyle {
        case light
        case medium
        case heavy
    }

    /// 撞击反馈（按钮按下、摇杆接管）。
    static func impact(_ style: ImpactStyle) {
        let generator: UIImpactFeedbackGenerator
        switch style {
        case .light: generator = UIImpactFeedbackGenerator(style: .light)
        case .medium: generator = UIImpactFeedbackGenerator(style: .medium)
        case .heavy: generator = UIImpactFeedbackGenerator(style: .heavy)
        }
        generator.impactOccurred()
    }

    /// 通知反馈（模式切换成功/失败）。
    static func notify(success: Bool) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(success ? .success : .warning)
    }

    /// 选择反馈（按钮点按）。
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
