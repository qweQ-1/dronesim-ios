import Foundation
import Metal
import UIKit
import simd

// MARK: - 主视图控制器

/// 游戏主界面：Metal 渲染 + 触控输入 + HUD。
final class GameViewController: UIViewController {

    // MARK: 子视图
    private let metalView = MetalView()
    private let hudView = HUDView()
    private let controlOverlay = ControlOverlayView()

    // MARK: 引擎
    private var renderer: MetalRenderer?
    private let flight = FlightManager()
    private let inputController = FlightInputController()

    // MARK: 状态
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var fpsCounter = 0
    private var fpsWindowStart: CFTimeInterval = 0
    private var currentFps = 0

    /// 相机模式。
    private enum CameraMode: Int {
        case chase
        case fpv
        case orbit
    }
    private var cameraMode: CameraMode = .chase
    private var orbitAngle: Float = 0

    /// 高度保持开关。
    private var altitudeHold = false
    /// 暂停。
    private var isPaused = false

    /// 场景参数。
    private let terrainSize: Float = 320
    private let terrainResolution = 192
    private let worldSeed: UInt64 = 20261104

    // MARK: 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        guard let renderer = MetalRenderer() else {
            showFatalError("此设备不支持 Metal 渲染")
            return
        }
        self.renderer = renderer
        renderer.prepareWorld(terrainSize: terrainSize,
                             terrainResolution: terrainResolution,
                             seed: worldSeed)
        renderer.setSunDirection(normalize(SIMD3<Float>(0.42, 0.72, 0.34)))

        // 视图
        metalView.translatesAutoresizingMaskIntoConstraints = false
        hudView.translatesAutoresizingMaskIntoConstraints = false
        controlOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(metalView)
        view.addSubview(controlOverlay)
        view.addSubview(hudView)
        NSLayoutConstraint.activate([
            metalView.topAnchor.constraint(equalTo: view.topAnchor),
            metalView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            metalView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            metalView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            controlOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            controlOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            controlOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            hudView.topAnchor.constraint(equalTo: view.topAnchor),
            hudView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hudView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hudView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        // 按钮动作
        controlOverlay.bindActions(
            arm: { [weak self] in self?.armOrDisarm() },
            camera: { [weak self] in self?.toggleCamera() },
            mode: { [weak self] in self?.toggleStabilized() },
            altitude: { [weak self] in self?.toggleAltitudeHold() },
            motion: { [weak self] in self?.toggleMotion() },
            pause: { [weak self] in self?.togglePause() },
            reset: { [weak self] in self?.respawn() }
        )

        // 飞行事件
        flight.onArmedChange = { [weak self] armed in
            guard let self else { return }
            if armed {
                self.hudView.showToast("电机解锁")
                self.inputController.resetThrottle(to: 0.42)
            } else {
                self.hudView.showToast("已上锁")
                self.inputController.resetThrottle(to: 0)
            }
            self.refreshButtonTitles()
        }
        flight.onCrash = { [weak self] impact in
            self?.hudView.showToast(String(format: "坠机！冲击 %.1f m/s", impact))
        }

        inputController.startMotion()
        hudView.showToast("点击「起飞」开始", duration: 2.5)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        metalView.updateDrawableSize()
        renderer?.resize(drawableSize: metalView.drawableSize)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startDisplayLink()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopDisplayLink()
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    // MARK: 帧循环

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(onFrame))
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
        startTime = CACurrentMediaTime()
        fpsWindowStart = startTime
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func onFrame() {
        let now = CACurrentMediaTime()
        let elapsed = now - startTime

        fpsCounter += 1
        if now - fpsWindowStart >= 0.5 {
            currentFps = Int(Double(fpsCounter) / (now - fpsWindowStart))
            fpsCounter = 0
            fpsWindowStart = now
        }

        if !isPaused {
            let mode: AltitudeMode = altitudeHold
                ? .hold(altitude: flight.altitude.targetAltitude)
                : .manual
            inputController.updateInput(altitudeMode: mode)
            flight.input = inputController.input
            flight.update(timestamp: Float(now - startTime))
        }

        render(elapsed: Float(elapsed))
        updateHUD()
    }

    // MARK: 渲染

    private func render(elapsed: Float) {
        guard let renderer else { return }
        guard let drawable = metalView.currentDrawable() else { return }

        let state = flight.state
        let dronePos = SIMD3<Float>(state.position.x, state.position.y, state.position.z)
        let attitude = simd_quatf(ix: state.attitude.x, iy: state.attitude.y,
                                  iz: state.attitude.z, r: state.attitude.w)

        let (camPos, camForward, camUp, fov) = cameraParameters(dronePos: dronePos, attitude: attitude)
        let aspect = metalView.drawableSize.width / max(metalView.drawableSize.height, 1)
        renderer.setCamera(position: camPos, forward: camForward, up: camUp,
                           fovDegrees: fov, aspect: aspect)
        renderer.render(dronePosition: dronePos, droneAttitude: attitude,
                        time: elapsed, in: drawable, depthAttachment: nil)
    }

    /// 计算相机参数。
    private func cameraParameters(dronePos: SIMD3<Float>,
                                  attitude: simd_quatf) -> (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>, Float) {
        let state = flight.state
        let forward = attitude.act(SIMD3<Float>(0, 0, -1))
        let up = attitude.act(SIMD3<Float>(0, 1, 0))
        let worldUp = SIMD3<Float>(0, 1, 0)

        switch cameraMode {
        case .fpv:
            let offset = attitude.act(SIMD3<Float>(0, 0.03, 0.06))
            return (dronePos + offset, forward, up, 92)

        case .orbit:
            orbitAngle += 0.004
            let radius: Float = 6.5
            let pos = SIMD3<Float>(dronePos.x + cos(orbitAngle) * radius,
                                   dronePos.y + 2.2,
                                   dronePos.z + sin(orbitAngle) * radius)
            let dir = normalize(dronePos - pos)
            return (pos, dir, worldUp, 60)

        case .chase:
            let speedFactor = min(state.airspeed / 12.0, 1.0)
            let distance: Float = 2.6 + speedFactor * 2.2
            let height: Float = 0.85 + speedFactor * 0.5
            let flatForward = normalize(SIMD3<Float>(forward.x, 0, forward.z))
            let camPos = dronePos - flatForward * distance + worldUp * height
            let dir = normalize(dronePos + worldUp * 0.15 - camPos)
            return (camPos, dir, worldUp, 68)
        }
    }

    // MARK: HUD

    private func updateHUD() {
        let state = flight.state
        let frame = BodyFrame(quaternion: state.attitude)
        let roll = atan2(frame.right.y, frame.up.y)
        let pitch = asin(clamp(frame.forward.y, -1, 1))

        let modeText: String
        switch state.mode {
        case .disarmed: modeText = "待命"
        case .stabilized: modeText = altitudeHold ? "自稳·定高" : "自稳"
        case .manual: modeText = "手动"
        case .crashed: modeText = "坠机"
        }

        hudView.update(
            altitude: max(state.altitude, 0),
            speedKmh: state.airspeed * 3.6,
            battery: state.batteryFraction(spec: flight.dynamics.spec),
            roll: roll,
            pitch: pitch,
            mode: modeText,
            fps: currentFps
        )
    }

    private func refreshButtonTitles() {
        controlOverlay.setButtonTitles(armed: flight.isArmed,
                                      stabilized: flight.stabilizedEnabled,
                                      altitudeHold: altitudeHold,
                                      motion: inputController.useMotion,
                                      paused: isPaused)
    }

    private func showFatalError(_ message: String) {
        let label = UILabel()
        label.text = message
        label.textColor = .white
        label.font = .systemFont(ofSize: 18, weight: .bold)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    // MARK: 触摸
    //
    // 摇杆自己处理触摸（见 VirtualJoystick 的 point(inside:)，按屏幕左右半区分配），
    // 按钮自己处理 touchesEnded，所以这里不需要再转发事件。

    // MARK: 动作

    func toggleAltitudeHold() {
        altitudeHold.toggle()
        if altitudeHold {
            flight.altitude.targetAltitude = max(flight.state.altitude, 1.0)
            hudView.showToast("定高模式：\(String(format: "%.1f", flight.altitude.targetAltitude)) m")
        } else {
            hudView.showToast("手动油门")
        }
        refreshButtonTitles()
    }

    func toggleCamera() {
        cameraMode = CameraMode(rawValue: (cameraMode.rawValue + 1) % 3) ?? .chase
        let names = ["追尾视角", "机载视角", "环绕视角"]
        hudView.showToast(names[cameraMode.rawValue])
    }

    func toggleStabilized() {
        flight.stabilizedEnabled.toggle()
        hudView.showToast(flight.stabilizedEnabled ? "自稳开启" : "自稳关闭（手动）")
        refreshButtonTitles()
    }

    func toggleMotion() {
        inputController.useMotion.toggle()
        if inputController.useMotion {
            inputController.resetMotionReference()
            hudView.showToast("体感操控已开启")
        } else {
            hudView.showToast("体感操控已关闭")
        }
        refreshButtonTitles()
    }

    func armOrDisarm() {
        if flight.isArmed {
            flight.disarm()
        } else {
            flight.arm()
        }
        refreshButtonTitles()
    }

    func respawn() {
        flight.respawn()
        hudView.showToast("已复位")
        refreshButtonTitles()
    }

    func togglePause() {
        isPaused.toggle()
        hudView.showToast(isPaused ? "已暂停" : "继续")
        refreshButtonTitles()
    }
}
