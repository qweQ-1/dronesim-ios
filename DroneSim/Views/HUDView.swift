import Foundation
import UIKit

// MARK: - HUD

/// 飞行抬头显示：高度、速度、电量、姿态指示、模式。
final class HUDView: UIView {

    private let altitudeLabel = UILabel()
    private let altitudeCaption = UILabel()
    private let speedLabel = UILabel()
    private let speedCaption = UILabel()
    private let batteryBar = UIProgressView(progressViewStyle: .bar)
    private let batteryLabel = UILabel()
    private let attitudeIndicator = AttitudeIndicatorView()
    private let modeLabel = UILabel()
    private let toastLabel = UILabel()
    private let fpsLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        isUserInteractionEnabled = false

        configureLabel(altitudeLabel, size: 34, weight: .heavy, color: .white)
        configureLabel(speedLabel, size: 26, weight: .bold, color: .white)
        configureLabel(batteryLabel, size: 13, weight: .semibold, color: .white)
        configureLabel(modeLabel, size: 14, weight: .bold, color: .white)
        configureLabel(fpsLabel, size: 11, weight: .medium, color: UIColor.white.withAlphaComponent(0.6))

        altitudeCaption.text = "高度 m"
        altitudeCaption.font = .systemFont(ofSize: 12, weight: .medium)
        altitudeCaption.textColor = UIColor.white.withAlphaComponent(0.7)
        altitudeCaption.accessibilityIdentifier = "hud.altitude.caption" 

        speedCaption.text = "速度 km/h"
        speedCaption.font = .systemFont(ofSize: 11, weight: .medium)
        speedCaption.textColor = UIColor.white.withAlphaComponent(0.7)

        batteryBar.progressTintColor = UIColor(red: 0.3, green: 0.85, blue: 0.5, alpha: 1)
        batteryBar.trackTintColor = UIColor.white.withAlphaComponent(0.2)
        batteryBar.layer.cornerRadius = 2
        batteryBar.clipsToBounds = true

        modeLabel.textAlignment = .center
        modeLabel.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        modeLabel.layer.cornerRadius = 8
        modeLabel.clipsToBounds = true
        modeLabel.text = "待命"

        toastLabel.textAlignment = .center
        toastLabel.font = .systemFont(ofSize: 20, weight: .bold)
        toastLabel.textColor = .white
        toastLabel.numberOfLines = 2
        toastLabel.alpha = 0

        attitudeIndicator.translatesAutoresizingMaskIntoConstraints = false

        addSubview(altitudeLabel)
        addSubview(altitudeCaption)
        addSubview(speedLabel)
        addSubview(speedCaption)
        addSubview(batteryBar)
        addSubview(batteryLabel)
        addSubview(attitudeIndicator)
        addSubview(modeLabel)
        addSubview(toastLabel)
        addSubview(fpsLabel)

        NSLayoutConstraint.activate([
            altitudeLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            altitudeLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            altitudeCaption.topAnchor.constraint(equalTo: altitudeLabel.bottomAnchor, constant: -2),
            altitudeCaption.centerXAnchor.constraint(equalTo: centerXAnchor),

            speedLabel.topAnchor.constraint(equalTo: altitudeCaption.bottomAnchor, constant: 6),
            speedLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            speedCaption.topAnchor.constraint(equalTo: speedLabel.bottomAnchor, constant: -1),
            speedCaption.centerXAnchor.constraint(equalTo: centerXAnchor),

            batteryBar.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 10),
            batteryBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            batteryBar.widthAnchor.constraint(equalToConstant: 90),
            batteryBar.heightAnchor.constraint(equalToConstant: 6),

            batteryLabel.topAnchor.constraint(equalTo: batteryBar.bottomAnchor, constant: 3),
            batteryLabel.leadingAnchor.constraint(equalTo: batteryBar.leadingAnchor),

            modeLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
            modeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            modeLabel.widthAnchor.constraint(equalToConstant: 96),
            modeLabel.heightAnchor.constraint(equalToConstant: 28),

            attitudeIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            attitudeIndicator.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -18),
            attitudeIndicator.widthAnchor.constraint(equalToConstant: 132),
            attitudeIndicator.heightAnchor.constraint(equalToConstant: 132),

            toastLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            toastLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -60),

            fpsLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            fpsLabel.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -4),
        ])
    }

    private func configureLabel(_ label: UILabel, size: CGFloat, weight: UIFont.Weight, color: UIColor) {
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        // 阴影，保证在明亮天空下也看得清
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOpacity = 0.8
        label.layer.shadowRadius = 3
        label.layer.shadowOffset = .zero
    }

    /// 更新 HUD 数据。
    func update(altitude: Float, speedKmh: Float, battery: Float,
                roll: Float, pitch: Float, mode: String, fps: Int) {
        altitudeLabel.text = String(format: "%.1f", altitude)
        speedLabel.text = String(format: "%.0f", speedKmh)
        batteryBar.setProgress(battery, animated: false)
        batteryLabel.text = "电量 \(Int(battery * 100))%"
        batteryBar.progressTintColor = battery > 0.3
            ? UIColor(red: 0.3, green: 0.85, blue: 0.5, alpha: 1)
            : UIColor(red: 0.95, green: 0.35, blue: 0.3, alpha: 1)
        modeLabel.text = mode
        attitudeIndicator.setAttitude(roll: roll, pitch: pitch)
        fpsLabel.text = "\(fps) FPS"
    }

    /// 显示一条居中提示。
    func showToast(_ text: String, duration: TimeInterval = 1.8) {
        toastLabel.text = text
        toastLabel.alpha = 0
        UIView.animate(withDuration: 0.2) { self.toastLabel.alpha = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            UIView.animate(withDuration: 0.35) { self.toastLabel.alpha = 0 }
        }
    }
}

// MARK: - 姿态指示器

/// 简易姿态仪：一个会随横滚/俯仰倾斜的圆形地平仪。
final class AttitudeIndicatorView: UIView {
    private let horizon = CALayer()
    private let bezel = CAShapeLayer()
    private let pip = CALayer()
    private let bankPointer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        isUserInteractionEnabled = false

        bezel.fillColor = UIColor.black.withAlphaComponent(0.25).cgColor
        bezel.strokeColor = UIColor.white.withAlphaComponent(0.45).cgColor
        bezel.lineWidth = 1.5
        layer.addSublayer(bezel)

        horizon.backgroundColor = UIColor.systemBlue.cgColor
        layer.addSublayer(horizon)

        pip.backgroundColor = UIColor.systemYellow.cgColor
        layer.addSublayer(pip)

        bankPointer.fillColor = UIColor.white.cgColor
        layer.addSublayer(bankPointer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let r = min(bounds.width, bounds.height) / 2
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        bezel.path = UIBezierPath(arcCenter: center, radius: r,
                                  startAngle: 0, endAngle: 2 * .pi, clockwise: true).cgPath
        pip.frame = CGRect(x: center.x - 5, y: center.y - 1, width: 10, height: 2)

        // 顶部刻度指针
        let path = UIBezierPath()
        path.move(to: CGPoint(x: center.x - 7, y: center.y - r + 2))
        path.addLine(to: CGPoint(x: center.x, y: center.y - r + 11))
        path.addLine(to: CGPoint(x: center.x + 7, y: center.y - r + 2))
        path.close()
        bankPointer.path = path.cgPath
    }

    /// 设置姿态。roll / pitch 单位为弧度。
    func setAttitude(roll: Float, pitch: Float) {
        let r = min(bounds.width, bounds.height) / 2
        let pitchOffset = CGFloat(pitch / (Float.pi / 3)) * r * 0.75
        // 绕中心旋转（横滚）+ 缩放。
        // CALayer 的 setAffineTransform 只接受 CGAffineTransform（2D），
        // 不能用 CATransform3D。
        let rotation = CGAffineTransform(rotationAngle: -CGFloat(roll))
        let scale = CGAffineTransform(scaleX: 1.35, y: 1.35)
        horizon.setAffineTransform(rotation.concatenating(scale))
        horizon.frame = bounds.offsetBy(dx: 0, dy: pitchOffset)
    }
}
