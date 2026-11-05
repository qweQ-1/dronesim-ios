import Foundation
import Metal
import QuartzCore   // CAMetalDrawable
import simd

// MARK: - 渲染器

/// Metal 渲染器。
///
/// 为了流畅做的关键设计：
/// - 所有 GPU 资源在 `prepareWorld()` 里一次性分配，帧循环内零堆分配；
/// - 地形/树木/建筑/塔柱各用**一次实例化 draw call**，整张地图只有 5 次 draw call；
/// - 天空用一个全屏三角形在最后绘制，避免排序开销；
/// - 顶点数据用 `storageModeShared`（iOS 统一内存），CPU 侧零拷贝上传；
/// - 用 `CAMetalLayer` 三缓冲，iOS 上 Metal 层自动与屏幕刷新率同步。
final class MetalRenderer {

    // MARK: 资源
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    private var terrainPipeline: MTLRenderPipelineState?
    private var objectPipeline: MTLRenderPipelineState?
    private var instancedPipeline: MTLRenderPipelineState?
    private var skyPipeline: MTLRenderPipelineState?

    private var terrainVB: MTLBuffer?
    private var terrainIB: MTLBuffer?
    private var terrainIndexCount: Int = 0
    private var droneVB: MTLBuffer?
    private var droneIB: MTLBuffer?
    private var droneIndexCount: Int = 0

    private var propMeshes: [PropMesh] = []
    private var propInstanceBuffers: [MTLBuffer] = []
    private var propInstanceCounts: [Int] = []

    private var depthTexture: MTLTexture?
    /// 物体用：写深度，less 比较。
    private var depthStencilState: MTLDepthStencilState?
    /// 天空用：不写深度，lessEqual 比较。
    private var skyDepthStencilState: MTLDepthStencilState?

    // MARK: 尺寸
    private(set) var drawableSize: CGSize = .zero
    private let pixelFormat: MTLPixelFormat = .bgra8Unorm

    // MARK: 相机
    private var viewProjection = matrix_identity_float4x4
    private var invViewProjection = matrix_identity_float4x4
    private var cameraPosition: SIMD3<Float> = .zero

    // MARK: 光照
    private var sunDirection: SIMD3<Float> = simd_normalize(SIMD3<Float>(0.42, 0.72, 0.34))

    // MARK: 统计
    private(set) var drawCallCount: Int = 0
    private(set) var triangleCount: Int = 0

    // MARK: 并发保护
    //
    // 世界资源在后台线程构建（prepareWorld），在主线程渲染（render），
    // 用一把锁保证不会交叉访问。
    private let worldLock = NSLock()

    // MARK: 帧内 uniform 存储
    // Metal 的 setVertexBuffer 需要一个稳定的地址，因此 uniform 存在这里而不是局部变量。
    private var terrainUniforms = TerrainUniforms(
        viewProjection: matrix_identity_float4x4,
        model: matrix_identity_float4x4,
        lightDir: SIMD4<Float>(0, 1, 0, 0),
        cameraPos: SIMD4<Float>(0, 0, 0, 0),
        params: SIMD4<Float>(0, 0, 0, 0)
    )
    private var objectUniforms = ObjectUniforms(
        viewProjection: matrix_identity_float4x4,
        model: matrix_identity_float4x4,
        lightDir: SIMD4<Float>(0, 1, 0, 0),
        cameraPos: SIMD4<Float>(0, 0, 0, 0)
    )
    private var instancedUniforms = InstancedUniforms(
        viewProjection: matrix_identity_float4x4,
        lightDir: SIMD4<Float>(0, 1, 0, 0),
        cameraPos: SIMD4<Float>(0, 0, 0, 0),
        params: SIMD4<Float>(0, 0, 0, 0),
        count: 0
    )
    private var skyInvViewProjection = matrix_identity_float4x4
    private var skyCameraPosition: SIMD3<Float> = .zero
    private var skyTime: Float = 0

    // MARK: 数据结构

    /// 实例数据：model 矩阵 + 颜色。必须与着色器里的 `InstanceData` 布局一致。
    struct InstanceData {
        var model: simd_float4x4
        var tint: SIMD4<Float>
    }

    struct PropMesh {
        var vertexBuffer: MTLBuffer
        var indexBuffer: MTLBuffer
        var indexCount: Int
    }

    // MARK: - 初始化

    init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device, let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = queue
        commandQueue.label = "com.qweq-1.dronesim.queue"

        buildPipelines()
        guard terrainPipeline != nil, objectPipeline != nil, instancedPipeline != nil, skyPipeline != nil else {
            return nil
        }
    }

    // MARK: - 管线

    private func buildPipelines() {
        // 着色器从源码字符串编译，避免依赖 .metal 编译单元与 XcodeGen 的配合。
        guard let terrainLib = try? device.makeLibrary(source: Shaders.terrainSource, options: nil),
              let objectLib = try? device.makeLibrary(source: Shaders.objectSource, options: nil) else {
            return
        }

        let terrainDesc = MTLRenderPipelineDescriptor()
        terrainDesc.vertexFunction = terrainLib.makeFunction(name: "terrainVertex")
        terrainDesc.fragmentFunction = terrainLib.makeFunction(name: "terrainFragment")
        terrainDesc.vertexDescriptor = Self.makeVertexDescriptor(includeUV: true)
        terrainDesc.colorAttachments[0].pixelFormat = pixelFormat
        terrainDesc.depthAttachmentPixelFormat = .depth32Float
        terrainPipeline = try? device.makeRenderPipelineState(descriptor: terrainDesc)

        let objectDesc = MTLRenderPipelineDescriptor()
        objectDesc.vertexFunction = objectLib.makeFunction(name: "objectVertex")
        objectDesc.fragmentFunction = objectLib.makeFunction(name: "objectFragment")
        objectDesc.vertexDescriptor = Self.makeVertexDescriptor(includeUV: false)
        objectDesc.colorAttachments[0].pixelFormat = pixelFormat
        objectDesc.depthAttachmentPixelFormat = .depth32Float
        objectPipeline = try? device.makeRenderPipelineState(descriptor: objectDesc)

        let instDesc = MTLRenderPipelineDescriptor()
        instDesc.vertexFunction = objectLib.makeFunction(name: "instancedVertex")
        instDesc.fragmentFunction = objectLib.makeFunction(name: "objectFragment")
        instDesc.vertexDescriptor = Self.makeVertexDescriptor(includeUV: false)
        instDesc.colorAttachments[0].pixelFormat = pixelFormat
        instDesc.depthAttachmentPixelFormat = .depth32Float
        instancedPipeline = try? device.makeRenderPipelineState(descriptor: instDesc)

        let skyDesc = MTLRenderPipelineDescriptor()
        skyDesc.vertexFunction = objectLib.makeFunction(name: "skyVertex")
        skyDesc.fragmentFunction = objectLib.makeFunction(name: "skyFragment")
        skyDesc.vertexDescriptor = nil
        skyDesc.colorAttachments[0].pixelFormat = pixelFormat
        skyDesc.depthAttachmentPixelFormat = .depth32Float
        skyPipeline = try? device.makeRenderPipelineState(descriptor: skyDesc)
    }

    /// 顶点描述符。属性顺序必须与 `MeshVertex` 字段顺序一致：
    /// position(0) / normal(1) / color(2) / uv(3)
    ///
    /// ⚠️ 缓冲槽位约定（很重要）：
    /// - buffer 0 = uniform（着色器常量）
    /// - buffer 1 = 顶点数据
    /// - buffer 2 = 实例数据
    ///
    /// Metal 里 vertex buffer 和 vertex descriptor 的 bufferIndex 共用同一批槽位，
    /// 如果把 uniform 和顶点数据都放进 index 0，后者会覆盖前者，渲染结果会是乱码。
    private static func makeVertexDescriptor(includeUV: Bool) -> MTLVertexDescriptor {
        let desc = MTLVertexDescriptor()
        desc.attributes[0].format = .float3
        desc.attributes[0].offset = MemoryLayout<SIMD3<Float>>.stride
        desc.attributes[0].bufferIndex = Self.vertexBufferIndex
        desc.attributes[1].format = .float3
        desc.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride * 2
        desc.attributes[1].bufferIndex = Self.vertexBufferIndex
        desc.attributes[2].format = .float4
        desc.attributes[2].offset = MemoryLayout<SIMD3<Float>>.stride * 2 + MemoryLayout<SIMD4<Float>>.stride
        desc.attributes[2].bufferIndex = Self.vertexBufferIndex
        if includeUV {
            desc.attributes[3].format = .float2
            desc.attributes[3].offset = MemoryLayout<SIMD3<Float>>.stride * 2
                + MemoryLayout<SIMD4<Float>>.stride
            desc.attributes[3].bufferIndex = Self.vertexBufferIndex
        }
        desc.layouts[Self.vertexBufferIndex].stride = MemoryLayout<MeshVertex>.stride
        desc.layouts[Self.vertexBufferIndex].stepFunction = .perVertex
        return desc
    }

    /// 缓冲槽位常量。
    static let uniformBufferIndex = 0
    static let vertexBufferIndex = 1
    static let instanceBufferIndex = 2

    // MARK: - 世界构建

    /// 一次性构建世界几何与实例数据。
    ///
    /// 可以在后台线程调用；与 render() 之间用 worldLock 互斥。
    func prepareWorld(terrainSize: Float, terrainResolution: Int, seed: UInt64) {
        worldLock.lock()
        defer { worldLock.unlock() }

        let field = TerrainField(size: terrainSize, seed: seed)

        let terrainMesh = GeometryBuilder.terrain(field: field, resolution: terrainResolution)
        terrainVB = makeBuffer(vertices: terrainMesh.vertices)
        terrainIB = makeBuffer(indices: terrainMesh.indices)
        terrainIndexCount = terrainMesh.indices.count

        let droneMesh = GeometryBuilder.droneMesh()
        droneVB = makeBuffer(vertices: droneMesh.vertices)
        droneIB = makeBuffer(indices: droneMesh.indices)
        droneIndexCount = droneMesh.indices.count

        buildProps(field: field, seed: seed)
    }

    private func makeBuffer(vertices: [MeshVertex]) -> MTLBuffer? {
        guard !vertices.isEmpty else { return nil }
        return device.makeBuffer(bytes: vertices,
                                 length: vertices.count * MemoryLayout<MeshVertex>.stride,
                                 options: .storageModeShared)
    }

    private func makeBuffer(indices: [UInt16]) -> MTLBuffer? {
        guard !indices.isEmpty else { return nil }
        return device.makeBuffer(bytes: indices,
                                 length: indices.count * MemoryLayout<UInt16>.stride,
                                 options: .storageModeShared)
    }

    private func buildProps(field: TerrainField, seed: UInt64) {
        propMeshes.removeAll()
        propInstanceBuffers.removeAll()
        propInstanceCounts.removeAll()

        var rng = SeededRandom(seed: seed &+ 0x9E37)

        // --- 树 ---
        let tree = GeometryBuilder.treeMesh(seed: seed &+ 11)
        propMeshes.append(PropMesh(vertexBuffer: makeBuffer(vertices: tree.vertices)!,
                                    indexBuffer: makeBuffer(indices: tree.indices)!,
                                    indexCount: tree.indices.count))

        var treeInstances: [InstanceData] = []
        treeInstances.reserveCapacity(420)
        for _ in 0..<420 {
            let angle = rng.nextFloat(in: 0..<(2 * .pi))
            let radius = rng.nextFloat(in: 12...(field.size * 0.46))
            let x = cos(angle) * radius
            let z = sin(angle) * radius
            let y = field.height(x: x, z: z)
            guard y > 0.4 else { continue }
            let scale = rng.nextFloat(in: 0.75...1.45)
            let rot = rng.nextFloat(in: 0..<(2 * .pi))
            var model = matrix_identity_float4x4
            model.columns.0 = SIMD4<Float>(cos(rot) * scale, 0, -sin(rot) * scale, 0)
            model.columns.1 = SIMD4<Float>(0, scale, 0, 0)
            model.columns.2 = SIMD4<Float>(sin(rot) * scale, 0, cos(rot) * scale, 0)
            model.columns.3 = SIMD4<Float>(x, y, z, 1)
            let shade = rng.nextFloat(in: 0.82...1.12)
            treeInstances.append(InstanceData(model: model,
                                               tint: SIMD4<Float>(shade, shade * 1.02, shade * 0.94, 1)))
        }
        propInstanceBuffers.append(makeInstanceBuffer(treeInstances))
        propInstanceCounts.append(treeInstances.count)

        // --- 建筑 ---
        let building = GeometryBuilder.buildingMesh(seed: seed &+ 23)
        propMeshes.append(PropMesh(vertexBuffer: makeBuffer(vertices: building.vertices)!,
                                    indexBuffer: makeBuffer(indices: building.indices)!,
                                    indexCount: building.indices.count))

        var buildingInstances: [InstanceData] = []
        buildingInstances.reserveCapacity(46)
        for _ in 0..<46 {
            let angle = rng.nextFloat(in: 0..<(2 * .pi))
            let radius = rng.nextFloat(in: 30...(field.size * 0.42))
            let x = cos(angle) * radius
            let z = sin(angle) * radius
            let y = field.height(x: x, z: z)
            var model = matrix_identity_float4x4
            model.columns.3 = SIMD4<Float>(x, y - 0.5, z, 1)
            buildingInstances.append(InstanceData(model: model, tint: SIMD4<Float>(1, 1, 1, 1)))
        }
        propInstanceBuffers.append(makeInstanceBuffer(buildingInstances))
        propInstanceCounts.append(buildingInstances.count)

        // --- 塔柱（障碍）---
        let pillar = GeometryBuilder.pillarMesh(radius: 0.9, height: 18.0)
        propMeshes.append(PropMesh(vertexBuffer: makeBuffer(vertices: pillar.vertices)!,
                                    indexBuffer: makeBuffer(indices: pillar.indices)!,
                                    indexCount: pillar.indices.count))

        var pillarInstances: [InstanceData] = []
        pillarInstances.reserveCapacity(24)
        for _ in 0..<24 {
            let angle = rng.nextFloat(in: 0..<(2 * .pi))
            let radius = rng.nextFloat(in: 20...(field.size * 0.40))
            let x = cos(angle) * radius
            let z = sin(angle) * radius
            let y = field.height(x: x, z: z)
            let h = rng.nextFloat(in: 8.0...26.0)
            var model = matrix_identity_float4x4
            model.columns.1 = SIMD4<Float>(0, h / 18.0, 0, 0)
            model.columns.3 = SIMD4<Float>(x, y, z, 1)
            pillarInstances.append(InstanceData(model: model, tint: SIMD4<Float>(1, 1, 1, 1)))
        }
        propInstanceBuffers.append(makeInstanceBuffer(pillarInstances))
        propInstanceCounts.append(pillarInstances.count)
    }

    private func makeInstanceBuffer(_ instances: [InstanceData]) -> MTLBuffer {
        if instances.isEmpty {
            return device.makeBuffer(length: MemoryLayout<InstanceData>.stride,
                                     options: .storageModeShared)!
        }
        return device.makeBuffer(bytes: instances,
                                 length: instances.count * MemoryLayout<InstanceData>.stride,
                                 options: .storageModeShared)!
    }

    // MARK: - 尺寸

    func resize(drawableSize: CGSize) {
        guard drawableSize != self.drawableSize, drawableSize.width > 0, drawableSize.height > 0 else { return }
        self.drawableSize = drawableSize

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: Int(drawableSize.width),
            height: Int(drawableSize.height),
            mipmapped: false)
        desc.usage = .renderTarget
        desc.storageMode = .private
        depthTexture = device.makeTexture(descriptor: desc)

        let objectState = MTLDepthStencilDescriptor()
        objectState.isDepthWriteEnabled = true
        objectState.depthCompareFunction = .less
        depthStencilState = device.makeDepthStencilState(descriptor: objectState)

        let skyState = MTLDepthStencilDescriptor()
        skyState.isDepthWriteEnabled = false
        skyState.depthCompareFunction = .lessEqual
        skyDepthStencilState = device.makeDepthStencilState(descriptor: skyState)
    }

    // MARK: - 相机

    /// 设置相机。forward 指向视线方向，up 为参考上方向。
    func setCamera(position: SIMD3<Float>, forward: SIMD3<Float>, up: SIMD3<Float>,
                   fovDegrees: Float, aspect: Float, near: Float = 0.05, far: Float = 900) {
        cameraPosition = position
        let f = normalize(forward)
        let r = normalize(cross(up, f))
        let u = cross(f, r)

        let view = simd_float4x4(columns: (
            SIMD4<Float>(r.x, u.x, -f.x, 0),
            SIMD4<Float>(r.y, u.y, -f.y, 0),
            SIMD4<Float>(r.z, u.z, -f.z, 0),
            SIMD4<Float>(-dot(r, position), -dot(u, position), dot(f, position), 1)
        ))

        let aspectRatio = aspect > 0 ? aspect : 1
        let proj = MetalRenderer.perspectiveMatrix(
            fovY: fovDegrees * .pi / 180,
            aspect: aspectRatio,
            near: near,
            far: far
        )

        viewProjection = proj * view
        invViewProjection = viewProjection.inverse
    }

    func setSunDirection(_ dir: SIMD3<Float>) {
        sunDirection = normalize(dir)
    }

    // MARK: - 绘制

    /// 渲染一帧。
    func render(dronePosition: SIMD3<Float>, droneAttitude: simd_quatf,
                time: Float, in view: CAMetalDrawable, depthAttachment: MTLTexture?) {
        drawCallCount = 0
        triangleCount = 0

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = view.texture
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].storeAction = .store
        passDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0.55, green: 0.66, blue: 0.78, alpha: 1)

        // 深度附件必须存在，否则深度测试失效（物体会互相穿插）
        let depth = depthAttachment ?? depthTexture
        if let depth {
            passDesc.depthAttachment.texture = depth
            passDesc.depthAttachment.loadAction = .clear
            passDesc.depthAttachment.storeAction = .dontCare
            passDesc.depthAttachment.clearDepth = 1.0
        }

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc) else { return }

        // 读取世界资源（可能正在后台线程构建）。
        // 只在拷贝引用时持锁，不把锁带到 GPU 提交阶段，避免拖慢帧率。
        worldLock.lock()
        let terrain = (vertexBuffer: terrainVB, indexBuffer: terrainIB, indexCount: terrainIndexCount)
        let drone = (vertexBuffer: droneVB, indexBuffer: droneIB, indexCount: droneIndexCount)
        let props = propMeshes
        let propBuffers = propInstanceBuffers
        let propCounts = propInstanceCounts
        worldLock.unlock()

        // 深度状态（Xcode 26 里 MTLRenderPipelineDescriptor.depthStencilDescriptor 已移除，
        // 改成在 encoder 上单独设置）
        if let depthState = depthStencilState {
            encoder.setDepthStencilState(depthState)
        }

        // --- 场景物体（先画，写深度）---
        if let instancedPipeline {
            encoder.setRenderPipelineState(instancedPipeline)
            instancedUniforms = InstancedUniforms(
                viewProjection: viewProjection,
                lightDir: SIMD4<Float>(sunDirection, 0),
                cameraPos: SIMD4<Float>(cameraPosition, 0),
                params: SIMD4<Float>(0.0022, 0, 0, 0),
                count: 0
            )
            withUnsafeBytes(of: &instancedUniforms) { buf in
                encoder.setVertexBytes(buf.baseAddress!, length: buf.count, index: 0)
                encoder.setFragmentBytes(buf.baseAddress!, length: buf.count, index: 0)
            }

            for i in props.indices {
                let count = propCounts[i]
                guard count > 0 else { continue }
                let mesh = props[i]
                encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: Self.vertexBufferIndex)
                encoder.setVertexBuffer(propBuffers[i], offset: 0, index: Self.instanceBufferIndex)
                encoder.drawIndexedPrimitives(type: .triangle,
                                              indexCount: mesh.indexCount,
                                              indexType: .uint16,
                                              indexBuffer: mesh.indexBuffer,
                                              indexBufferOffset: 0,
                                              instanceCount: count)
                drawCallCount += 1
                triangleCount += (mesh.indexCount / 3) * count
            }
        }

        // --- 无人机 ---
        if let objectPipeline, let vb = drone.vertexBuffer, let ib = drone.indexBuffer {
            encoder.setRenderPipelineState(objectPipeline)
            objectUniforms = ObjectUniforms(
                viewProjection: viewProjection,
                model: makeModelMatrix(position: dronePosition, attitude: droneAttitude),
                lightDir: SIMD4<Float>(sunDirection, 0),
                cameraPos: SIMD4<Float>(cameraPosition, 0)
            )
            encoder.setVertexBuffer(vb, offset: 0, index: Self.vertexBufferIndex)
            withUnsafeBytes(of: &objectUniforms) { buf in
                encoder.setVertexBytes(buf.baseAddress!, length: buf.count, index: Self.uniformBufferIndex)
                encoder.setFragmentBytes(buf.baseAddress!, length: buf.count, index: 0)
            }
            encoder.drawIndexedPrimitives(type: .triangle,
                                          indexCount: drone.indexCount,
                                          indexType: .uint16,
                                          indexBuffer: ib,
                                          indexBufferOffset: 0)
            drawCallCount += 1
            triangleCount += drone.indexCount / 3
        }

        // --- 地形 ---
        if let terrainPipeline, let vb = terrain.vertexBuffer, let ib = terrain.indexBuffer {
            encoder.setRenderPipelineState(terrainPipeline)
            terrainUniforms = TerrainUniforms(
                viewProjection: viewProjection,
                model: matrix_identity_float4x4,
                lightDir: SIMD4<Float>(sunDirection, 0),
                cameraPos: SIMD4<Float>(cameraPosition, 0),
                params: SIMD4<Float>(0.0021, time, 0, 0)
            )
            encoder.setVertexBuffer(vb, offset: 0, index: Self.vertexBufferIndex)
            withUnsafeBytes(of: &terrainUniforms) { buf in
                encoder.setVertexBytes(buf.baseAddress!, length: buf.count, index: Self.uniformBufferIndex)
                encoder.setFragmentBytes(buf.baseAddress!, length: buf.count, index: 0)
            }
            encoder.drawIndexedPrimitives(type: .triangle,
                                          indexCount: terrain.indexCount,
                                          indexType: .uint16,
                                          indexBuffer: ib,
                                          indexBufferOffset: 0)
            drawCallCount += 1
            triangleCount += terrain.indexCount / 3
        }

        // --- 天空（最后画，深度写关闭）---
        if let skyPipeline {
            encoder.setRenderPipelineState(skyPipeline)
            if let skyState = skyDepthStencilState {
                encoder.setDepthStencilState(skyState)
            }
            skyInvViewProjection = invViewProjection
            skyCameraPosition = cameraPosition
            skyTime = time
            // 用 withUnsafeBytes 显式传指针：
            // setVertexBuffer 有多个重载，直接传 &var 会被 Swift 解析成 MTLBuffer? 版本而报错。
            // 用 setVertexBytes / setFragmentBytes 按字节数传：
            // setVertexBuffer 的指针重载在 Xcode 26 里会被解析到 MTLBuffer 版本而编译失败。
            withUnsafeBytes(of: &skyInvViewProjection) { buf in
                encoder.setVertexBytes(buf.baseAddress!, length: buf.count, index: 0)
            }
            withUnsafeBytes(of: &skyCameraPosition) { buf in
                encoder.setVertexBytes(buf.baseAddress!, length: buf.count, index: 1)
            }
            withUnsafeBytes(of: &sunDirection) { buf in
                encoder.setFragmentBytes(buf.baseAddress!, length: buf.count, index: 0)
            }
            withUnsafeBytes(of: &skyCameraPosition) { buf in
                encoder.setFragmentBytes(buf.baseAddress!, length: buf.count, index: 1)
            }
            withUnsafeBytes(of: &skyTime) { buf in
                encoder.setFragmentBytes(buf.baseAddress!, length: buf.count, index: 2)
            }
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            drawCallCount += 1
        }

        encoder.endEncoding()
        commandBuffer.present(view)
        commandBuffer.commit()
    }

    // MARK: - 矩阵

    /// 右手系透视投影矩阵（列主序，Metal 的 NDC 深度范围是 [0, 1]）。
    static func perspectiveMatrix(fovY: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let y = 1 / tan(fovY * 0.5)
        let x = y / aspect
        let z = far / (near - far)
        let w = (near * far) / (near - far)
        return simd_float4x4(columns: (
            SIMD4<Float>(x, 0, 0, 0),
            SIMD4<Float>(0, y, 0, 0),
            SIMD4<Float>(0, 0, z, -1),
            SIMD4<Float>(0, 0, w, 0)
        ))
    }

    private func makeModelMatrix(position: SIMD3<Float>, attitude: simd_quatf) -> simd_float4x4 {
        let r = attitude.act(SIMD3<Float>(1, 0, 0))
        let u = attitude.act(SIMD3<Float>(0, 1, 0))
        let f = attitude.act(SIMD3<Float>(0, 0, -1))
        return simd_float4x4(columns: (
            SIMD4<Float>(r.x, r.y, r.z, 0),
            SIMD4<Float>(u.x, u.y, u.z, 0),
            SIMD4<Float>(f.x, f.y, f.z, 0),
            SIMD4<Float>(position.x, position.y, position.z, 1)
        ))
    }
}

// MARK: - Uniform 结构体
// ⚠️ 布局必须与 Metal 侧逐字段一致。
//
// Metal 的 `float3` 大小 12 字节但对齐 16；Swift 的 `SIMD3<Float>` 是 16 字节。
// 两者混用会导致 offset 全部错位（fogDensity 在 Metal 是 140，在 Swift 是 144）。
// 因此这里统一只用 float4 / simd_float4x4，保证两侧 offset 完全一致。
// DroneSimTests 里有 MemoryLayout 断言守着这个约定。

struct TerrainUniforms {
    var viewProjection: simd_float4x4   // offset 0
    var model: simd_float4x4            // offset 64
    var lightDir: SIMD4<Float>          // offset 128  (xyz = 方向)
    var cameraPos: SIMD4<Float>         // offset 144  (xyz = 位置)
    var params: SIMD4<Float>            // offset 160  (x = fogDensity, y = time)
}

struct ObjectUniforms {
    var viewProjection: simd_float4x4   // offset 0
    var model: simd_float4x4            // offset 64
    var lightDir: SIMD4<Float>          // offset 128  (xyz = 方向)
    var cameraPos: SIMD4<Float>         // offset 144  (xyz = 位置)
}

struct InstancedUniforms {
    var viewProjection: simd_float4x4   // offset 0
    var lightDir: SIMD4<Float>          // offset 64
    var cameraPos: SIMD4<Float>         // offset 80
    var params: SIMD4<Float>            // offset 96   (x = fogDensity)
    var count: UInt32                   // offset 112
}
