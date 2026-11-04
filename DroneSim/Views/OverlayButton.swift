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
        layer.cornerRadius = 26
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
            iconView.widthAnchor.constraint(equalToConstant: 19),
            iconView.heightAnchor.constraint(equalToConstant: 19),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 1),
        ])
    }

    func setTitle(_ title: String) {
        titleLabel.text = title
    }

    /// 无障碍标识（UI 测试用）。
    func setIdentifier(_ identifier: String) {
        accessibilityIdentifier = identifier
        isAccessibilityElement = true
        accessibilityLabel = titleLabel.text
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        onTap?()
    }
}
