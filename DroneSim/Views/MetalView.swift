import Foundation
import UIKit
import QuartzCore

/// 承载 Metal 渲染的视图。
final class MetalView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }

    var metalLayer: CAMetalLayer {
        // swiftlint:disable:next force_cast
        layer as! CAMetalLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        metalLayer.device = MTLCreateSystemDefaultDevice()
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = true
        // 三缓冲，交给系统去匹配屏幕刷新率。
        // 注意：displaySyncEnabled 在 iOS 上不可用（只有 macOS 有），
        // iOS 上 Metal 层本身就与屏幕刷新率同步，不要设置。
        metalLayer.maximumDrawableCount = 3
        metalLayer.presentsWithTransaction = false
    }

    /// 当前可用的 drawable。
    func currentDrawable() -> CAMetalDrawable? {
        metalLayer.nextDrawable()
    }

    /// drawable 尺寸（像素）。
    var drawableSize: CGSize {
        metalLayer.drawableSize
    }

    /// 设置 drawable 尺寸（跟随 view bounds 与屏幕缩放）。
    func updateDrawableSize() {
        let scale = window?.screen.scale ?? UIScreen.main.scale
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        if metalLayer.drawableSize != size {
            metalLayer.drawableSize = size
        }
    }
}
