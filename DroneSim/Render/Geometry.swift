import Foundation
import simd

// MARK: - 网格数据

/// 顶点格式：位置(3) + 法线(3) + 颜色(4) + UV(2)
/// 字段顺序与 Metal 顶点描述符一致，且全部成员都是 16 字节对齐，
/// 保证 Swift 侧 `MemoryLayout<MeshVertex>` 与 GPU 侧布局完全一致。
struct MeshVertex {
    var position: SIMD3<Float>   // offset 0
    var normal: SIMD3<Float>     // offset 16
    var color: SIMD4<Float>      // offset 32
    var uv: SIMD2<Float>         // offset 48
}

// MARK: - 地形场

/// 地形高度场：地形网格与物体摆放共用同一套采样函数，保证物体贴地。
struct TerrainField {
    let size: Float
    let seed: UInt64

    private var half: Float { size * 0.5 }

    func height(x: Float, z: Float) -> Float {
        let h = fbm(x: x * 0.012 + 40, z: z * 0.012 + 40, seed: seed, octaves: 4)
        let r = (x * x + z * z).squareRoot() / half
        let flatten = smoothstep(0.0, 0.18, r)
        let hills = (h - 0.5) * 46.0 * flatten
        let mountains = smoothstep(0.55, 1.0, r) * fbm(x: x * 0.004, z: z * 0.004, seed: seed, octaves: 3) * 85.0
        return hills + mountains
    }

    /// 有限差分求法线。
    func normal(x: Float, z: Float) -> SIMD3<Float> {
        let e = max(size / 512, 0.5)
        let hL = height(x: x - e, z: z)
        let hR = height(x: x + e, z: z)
        let hD = height(x: x, z: z - e)
        let hU = height(x: x, z: z + e)
        return normalize(SIMD3<Float>(hL - hR, 2 * e, hD - hU))
    }

    private func fbm(x: Float, z: Float, seed: UInt64, octaves: Int) -> Float {
        var sum: Float = 0
        var amp: Float = 1
        var freq: Float = 1
        var norm: Float = 0
        for _ in 0..<octaves {
            sum += valueNoise(x: x * freq, z: z * freq, seed: seed) * amp
            norm += amp
            amp *= 0.5
            freq *= 2.03
        }
        return sum / max(norm, 0.0001)
    }
}

// MARK: - 几何生成

/// 程序化生成世界几何（无外部资源，所有模型都在代码里生成）。
enum GeometryBuilder {

    // MARK: 地形

    /// 生成一片带起伏与山丘的地形。
    static func terrain(field: TerrainField, resolution: Int) -> SimpleMesh {
        var vertices: [MeshVertex] = []
        var indices: [UInt16] = []
        vertices.reserveCapacity((resolution + 1) * (resolution + 1))

        let step = field.size / Float(resolution)
        let half = field.size * 0.5

        for iz in 0...resolution {
            for ix in 0...resolution {
                let x = -half + Float(ix) * step
                let z = -half + Float(iz) * step
                let y = field.height(x: x, z: z)
                let n = field.normal(x: x, z: z)

                // 颜色：按高度与坡度混合草地/岩石/雪
                let slope = 1 - n.y
                let grass = SIMD3<Float>(0.24, 0.42, 0.19)
                let grassDry = SIMD3<Float>(0.38, 0.45, 0.20)
                let rock = SIMD3<Float>(0.42, 0.40, 0.38)
                let snow = SIMD3<Float>(0.88, 0.90, 0.94)

                var c = lerp(grass, grassDry, clamp(y * 0.02 + 0.15, 0, 1))
                c = lerp(c, rock, clamp((slope - 0.22) * 3.2, 0, 1))
                c = lerp(c, snow, clamp((y - 42) / 28.0, 0, 1))

                vertices.append(MeshVertex(
                    position: SIMD3<Float>(x, y, z),
                    normal: n,
                    color: SIMD4<Float>(c.x, c.y, c.z, 1),
                    uv: SIMD2<Float>(x, z)
                ))
            }
        }

        let stride = resolution + 1
        for iz in 0..<resolution {
            for ix in 0..<resolution {
                let i0 = UInt16(iz * stride + ix)
                let i1 = UInt16(iz * stride + ix + 1)
                let i2 = UInt16((iz + 1) * stride + ix)
                let i3 = UInt16((iz + 1) * stride + ix + 1)
                indices.append(contentsOf: [i0, i2, i1, i1, i2, i3])
            }
        }

        return SimpleMesh(vertices: vertices, indices: indices)
    }

    // MARK: 无人机模型

    /// 无人机机模型：中心机身 + 四个机臂 + 电机 + 桨叶 + 摄像头 + 起落架。
    static func droneMesh() -> SimpleMesh {
        var vertices: [MeshVertex] = []
        var indices: [UInt16] = []

        func addBox(center: SIMD3<Float>, size: SIMD3<Float>,
                    color: SIMD4<Float>, rotation: simd_quatf = simd_quatf()) {
            appendBox(&vertices, &indices, center: center, size: size, color: color, rotation: rotation)
        }

        // 中心机架
        addBox(center: SIMD3<Float>(0, 0, 0), size: SIMD3<Float>(0.085, 0.022, 0.13),
               color: SIMD4<Float>(0.10, 0.11, 0.13, 1))
        // 电池
        addBox(center: SIMD3<Float>(0, 0.030, 0.005), size: SIMD3<Float>(0.062, 0.026, 0.10),
               color: SIMD4<Float>(0.16, 0.17, 0.20, 1))
        // 摄像头
        addBox(center: SIMD3<Float>(0, -0.022, -0.055), size: SIMD3<Float>(0.026, 0.026, 0.020),
               color: SIMD4<Float>(0.13, 0.14, 0.16, 1))
        addBox(center: SIMD3<Float>(0, -0.022, -0.070), size: SIMD3<Float>(0.020, 0.020, 0.010),
               color: SIMD4<Float>(0.05, 0.06, 0.08, 1))

        let armColor = SIMD4<Float>(0.12, 0.13, 0.15, 1)
        let motorColor = SIMD4<Float>(0.55, 0.42, 0.12, 1)
        let positions: [SIMD3<Float>] = [
            SIMD3<Float>(0.083, 0, -0.083),
            SIMD3<Float>(-0.083, 0, -0.083),
            SIMD3<Float>(-0.083, 0, 0.083),
            SIMD3<Float>(0.083, 0, 0.083),
        ]
        for p in positions {
            let dir = normalize(p)
            let mid = dir * 0.041
            let angle = atan2(dir.x, dir.z)
            addBox(center: SIMD3<Float>(mid.x, 0, mid.z),
                   size: SIMD3<Float>(0.014, 0.008, 0.090),
                   color: armColor,
                   rotation: simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0)))
            addBox(center: SIMD3<Float>(p.x, 0.012, p.z),
                   size: SIMD3<Float>(0.017, 0.026, 0.017),
                   color: motorColor)
            addBox(center: SIMD3<Float>(p.x, 0.028, p.z),
                   size: SIMD3<Float>(0.115, 0.0018, 0.020),
                   color: SIMD4<Float>(0.55, 0.58, 0.62, 0.75))
            addBox(center: SIMD3<Float>(p.x, -0.028, p.z),
                   size: SIMD3<Float>(0.010, 0.030, 0.010),
                   color: SIMD4<Float>(0.20, 0.20, 0.22, 1))
        }

        return SimpleMesh(vertices: vertices, indices: indices)
    }

    // MARK: 树木

    /// 树（树干 + 两层锥形树冠），低模。
    static func treeMesh(seed: UInt64) -> SimpleMesh {
        var rng = SeededRandom(seed: seed)
        var vertices: [MeshVertex] = []
        var indices: [UInt16] = []

        let height = rng.nextFloat(in: 3.2...6.8)
        let trunkR = 0.10 + rng.nextFloat(in: 0...0.07)
        let crownH = height * 0.62
        let crownR = 0.85 + rng.nextFloat(in: 0...0.7)

        appendCylinder(&vertices, &indices, radius: trunkR, height: height * 0.45,
                       segments: 6, color: SIMD4<Float>(0.30, 0.22, 0.15, 1), baseY: 0)
        appendCone(&vertices, &indices, radius: crownR, height: crownH,
                   segments: 7, color: SIMD4<Float>(0.16, 0.36, 0.15, 1), baseY: height * 0.30)
        appendCone(&vertices, &indices, radius: crownR * 0.72, height: crownH * 0.75,
                   segments: 7, color: SIMD4<Float>(0.20, 0.44, 0.18, 1), baseY: height * 0.58)

        return SimpleMesh(vertices: vertices, indices: indices)
    }

    // MARK: 建筑

    /// 建筑物（带窗户的方盒）。
    static func buildingMesh(seed: UInt64) -> SimpleMesh {
        var rng = SeededRandom(seed: seed)
        var vertices: [MeshVertex] = []
        var indices: [UInt16] = []

        let w = rng.nextFloat(in: 3.0...7.0)
        let d = rng.nextFloat(in: 3.0...7.0)
        let h = rng.nextFloat(in: 6.0...26.0)

        appendBox(&vertices, &indices, center: SIMD3<Float>(0, h * 0.5, 0),
                  size: SIMD3<Float>(w, h, d), color: SIMD4<Float>(0.42, 0.42, 0.44, 1))

        let floors = max(Int(h / 3.2), 1)
        let cols = max(Int(w / 1.8), 1)
        let windowColor = SIMD4<Float>(0.16, 0.26, 0.34, 1)
        for f in 0..<floors {
            for c in 0..<cols {
                let wx = -w * 0.5 + (w / Float(cols)) * (Float(c) + 0.5)
                let wy = Float(f) * (h / Float(floors)) + h / Float(floors) * 0.55
                let ww = w / Float(cols) * 0.55
                let wh = h / Float(floors) * 0.45
                appendBox(&vertices, &indices, center: SIMD3<Float>(wx, wy, d * 0.5 + 0.01),
                          size: SIMD3<Float>(ww, wh, 0.02), color: windowColor)
                appendBox(&vertices, &indices, center: SIMD3<Float>(wx, wy, -d * 0.5 - 0.01),
                          size: SIMD3<Float>(ww, wh, 0.02), color: windowColor)
            }
        }
        appendBox(&vertices, &indices, center: SIMD3<Float>(0, h + 0.18, 0),
                  size: SIMD3<Float>(w + 0.3, 0.36, d + 0.3),
                  color: SIMD4<Float>(0.33, 0.33, 0.35, 1))

        return SimpleMesh(vertices: vertices, indices: indices)
    }

    // MARK: 柱子

    /// 圆柱体（塔、桩）。
    static func pillarMesh(radius: Float, height: Float) -> SimpleMesh {
        var vertices: [MeshVertex] = []
        var indices: [UInt16] = []
        appendCylinder(&vertices, &indices, radius: radius, height: height, segments: 10,
                       color: SIMD4<Float>(0.46, 0.44, 0.42, 1), baseY: 0)
        return SimpleMesh(vertices: vertices, indices: indices)
    }

    // MARK: 图元

    static func appendBox(_ vertices: inout [MeshVertex], _ indices: inout [UInt16],
                          center: SIMD3<Float>, size: SIMD3<Float>,
                          color: SIMD4<Float>, rotation: simd_quatf = simd_quatf()) {
        let hx = size.x * 0.5, hy = size.y * 0.5, hz = size.z * 0.5
        let base: [SIMD3<Float>] = [
            SIMD3(-hx, -hy, -hz), SIMD3(hx, -hy, -hz), SIMD3(hx, hy, -hz), SIMD3(-hx, hy, -hz),
            SIMD3(-hx, -hy, hz), SIMD3(hx, -hy, hz), SIMD3(hx, hy, hz), SIMD3(-hx, hy, hz),
        ]
        let faces: [(Int, Int, Int, Int, SIMD3<Float>)] = [
            (0, 3, 2, 1, SIMD3(0, -1, 0)),
            (4, 5, 6, 7, SIMD3(0, 1, 0)),
            (0, 4, 7, 3, SIMD3(-1, 0, 0)),
            (1, 2, 6, 5, SIMD3(1, 0, 0)),
            (0, 1, 5, 4, SIMD3(0, 0, -1)),
            (3, 7, 6, 2, SIMD3(0, 0, 1)),
        ]
        for (a, b, c, d, n) in faces {
            let rn = rotation.act(normalize(n))
            let idx = [a, b, c, d].map { i -> UInt16 in
                let p = rotation.act(base[i]) + center
                vertices.append(MeshVertex(position: p, normal: rn,
                                           color: color, uv: SIMD2<Float>(0, 0)))
                return UInt16(vertices.count - 1)
            }
            indices.append(contentsOf: [idx[0], idx[1], idx[2], idx[0], idx[2], idx[3]])
        }
    }

    static func appendCylinder(_ vertices: inout [MeshVertex], _ indices: inout [UInt16],
                               radius: Float, height: Float, segments: Int,
                               color: SIMD4<Float>, baseY: Float) {
        let start = UInt16(vertices.count)
        for i in 0..<segments {
            let a = Float(i) / Float(segments) * 2 * .pi
            let x = cos(a) * radius, z = sin(a) * radius
            let n = SIMD3<Float>(cos(a), 0, sin(a))
            vertices.append(MeshVertex(position: SIMD3(x, baseY, z), normal: n,
                                       color: color, uv: SIMD2(Float(i) / Float(segments), 0)))
            vertices.append(MeshVertex(position: SIMD3(x, baseY + height, z), normal: n,
                                       color: color, uv: SIMD2(Float(i) / Float(segments), 1)))
        }
        for i in 0..<segments {
            let a = UInt16(start + UInt16(i) * 2)
            let b = UInt16(start + UInt16((i + 1) % segments) * 2)
            indices.append(contentsOf: [a, b, a + 1, b, b + 1, a + 1])
        }
        let topCenter = UInt16(vertices.count)
        vertices.append(MeshVertex(position: SIMD3(0, baseY + height, 0), normal: SIMD3(0, 1, 0),
                                   color: color, uv: SIMD2(0.5, 0.5)))
        for i in 0..<segments {
            let a = UInt16(start + UInt16(i) * 2 + 1)
            let b = UInt16(start + UInt16((i + 1) % segments) * 2 + 1)
            indices.append(contentsOf: [topCenter, b, a])
        }
    }

    static func appendCone(_ vertices: inout [MeshVertex], _ indices: inout [UInt16],
                           radius: Float, height: Float, segments: Int,
                           color: SIMD4<Float>, baseY: Float) {
        let start = UInt16(vertices.count)
        for i in 0..<segments {
            let a = Float(i) / Float(segments) * 2 * .pi
            let x = cos(a) * radius, z = sin(a) * radius
            let n = normalize(SIMD3<Float>(cos(a), height, sin(a)))
            vertices.append(MeshVertex(position: SIMD3(x, baseY, z), normal: n,
                                       color: color, uv: SIMD2(Float(i) / Float(segments), 0)))
        }
        let apexIdx = UInt16(vertices.count)
        vertices.append(MeshVertex(position: SIMD3(0, baseY + height, 0), normal: SIMD3(0, 1, 0),
                                   color: color, uv: SIMD2(0.5, 1)))
        for i in 0..<segments {
            let a = UInt16(start + UInt16(i))
            let b = UInt16(start + UInt16((i + 1) % segments))
            indices.append(contentsOf: [a, b, apexIdx])
        }
    }
}

// MARK: - 网格容器

/// 简单网格（顶点 + 索引）。
struct SimpleMesh {
    var vertices: [MeshVertex]
    var indices: [UInt16]

    var vertexCount: Int { vertices.count }
    var triangleCount: Int { indices.count / 3 }
}

// MARK: - 噪声与随机

/// 确定性随机数（xorshift64*）。
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545F4914F6CDD1D
    }

    mutating func nextFloat(in range: ClosedRange<Float>) -> Float {
        let t = Float(next() >> 11) / Float(1 << 53)
        return range.lowerBound + t * (range.upperBound - range.lowerBound)
    }

    mutating func nextFloat(in range: Range<Float>) -> Float {
        let t = Float(next() >> 11) / Float(1 << 53)
        return range.lowerBound + t * (range.upperBound - range.lowerBound)
    }
}

/// 二维值噪声（双线性插值），确定性。
func valueNoise(x: Float, z: Float, seed: UInt64) -> Float {
    let xi = floor(x), zi = floor(z)
    let xf = x - xi, zf = z - zi
    let u = xf * xf * (3 - 2 * xf)
    let v = zf * zf * (3 - 2 * zf)
    let ix = Int(xi), iz = Int(zi)

    let n00 = hashNoise(ix, iz, seed)
    let n10 = hashNoise(ix + 1, iz, seed)
    let n01 = hashNoise(ix, iz + 1, seed)
    let n11 = hashNoise(ix + 1, iz + 1, seed)

    let a = n00 + (n10 - n00) * u
    let b = n01 + (n11 - n01) * u
    return a + (b - a) * v
}

func hashNoise(_ x: Int, _ y: Int, _ seed: UInt64) -> Float {
    var h = UInt64(bitPattern: Int64(x &* 374761393 &+ y &* 668265263))
    h ^= seed
    h ^= h >> 13
    h = h &* 1274126177
    h ^= h >> 16
    return Float(h >> 11) / Float(1 << 53)
}
