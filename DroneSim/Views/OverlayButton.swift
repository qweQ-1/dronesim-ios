import Foundation
import UIKit

/// 半透明圆形按钮，带 SF Symbol 图标与文字。
final class OverlayButton: UIView {
    /// 点击回调。
    var onTap: (() -> Void)?

    private let titleLabel = UILabel()
    private let iconView = UIImageView()

    init(title: String, symbol: String) {
        super.init(frame: .zero)
        setup(title: title, symbol: symbol)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup(title: "", symbol: "")
    }

    private func setup(title: String, symbol: String) {
        backgroundColor = UIColor.black.withAlphaComponent(0.38)
        layer.cornerRadius = 23
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.28).cgColor

        iconView.image = UIImage(systemName: symbol)
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 9, weight: .semibold)
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.9)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -6),
            iconView.widthAnchor.constraint(equalToConstant: 17),
            iconView.heightAnchor.constraint(equalToConstant: 17),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 1),
        ])
    }

    func setTitle(_ title: String) {
        titleLabel.text = title
        // 标题变了要同步更新无障碍标签，否则 UI 测试读到的是旧文本。
        if isAccessibilityElement {
            accessibilityLabel = title
        }
    }

    /// 无障碍标识（UI 测试用）。
    func setIdentifier(_ identifier: String) {
        accessibilityIdentifier = identifier
        isAccessibilityElement = true
        // 必须标成 button 角色，XCUITest 的 app.buttons[...] 才找得到。
        accessibilityTraits = .button
        accessibilityLabel = titleLabel.text
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        // 按下时视觉反馈，让玩家知道按钮响应了
        UIView.animate(withDuration: 0.08) {
            self.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            self.backgroundColor = UIColor.white.withAlphaComponent(0.30)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        UIView.animate(withDuration: 0.12) {
            self.transform = .identity
            self.backgroundColor = UIColor.black.withAlphaComponent(0.38)
        }
        Haptics.selection()
        onTap?()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        UIView.animate(withDuration: 0.12) {
            self.transform = .identity
            self.backgroundColor = UIColor.black.withAlphaComponent(0.38)
        }
    }
}
