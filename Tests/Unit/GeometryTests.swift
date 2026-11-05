import XCTest
import simd
@testable import DroneSim

/// 几何生成与 GPU uniform 布局的单元测试。
final class GeometryTests: XCTestCase {

    func testTerrainHasExpectedVertexCount() {
        let field = TerrainField(size: 100, seed: 42)
        let mesh = GeometryBuilder.terrain(field: field, resolution: 16)
        XCTAssertEqual(mesh.vertices.count, 17 * 17)
        XCTAssertEqual(mesh.indices.count, 16 * 16 * 6)
        XCTAssertEqual(mesh.triangleCount, 16 * 16 * 2)
    }

    func testTerrainIndicesAreValid() {
        let field = TerrainField(size: 100, seed: 42)
        let mesh = GeometryBuilder.terrain(field: field, resolution: 16)
        for index in mesh.indices {
            XCTAssertLessThan(Int(index), mesh.vertices.count)
        }
    }

    func testTerrainIsDeterministic() {
        let field = TerrainField(size: 100, seed: 7)
        let a = GeometryBuilder.terrain(field: field, resolution: 8)
        let b = GeometryBuilder.terrain(field: field, resolution: 8)
        XCTAssertEqual(a.vertices.count, b.vertices.count)
        for i in 0..<a.vertices.count {
            XCTAssertEqual(a.vertices[i].position.x, b.vertices[i].position.x, accuracy: 1e-6)
            XCTAssertEqual(a.vertices[i].position.y, b.vertices[i].position.y, accuracy: 1e-6)
        }
    }

    func testTerrainNormalsAreUnitLength() {
        let field = TerrainField(size: 100, seed: 42)
        let mesh = GeometryBuilder.terrain(field: field, resolution: 8)
        for vertex in mesh.vertices {
            XCTAssertEqual(simd_length(vertex.normal), 1, accuracy: 1e-3)
        }
    }

    func testTerrainCenterIsFlattenedForTakeoff() {
        let field = TerrainField(size: 320, seed: 20261104)
        // 起飞点附近应该接近平地
        XCTAssertLessThan(abs(field.height(x: 0, z: 0)), 1.5)
        XCTAssertLessThan(abs(field.height(x: 3, z: 2)), 1.5)
    }

    func testDroneMeshIsValid() {
        let mesh = GeometryBuilder.droneMesh()
        XCTAssertGreaterThan(mesh.vertexCount, 0)
        XCTAssertGreaterThan(mesh.triangleCount, 0)
        for index in mesh.indices {
            XCTAssertLessThan(Int(index), mesh.vertexCount)
        }
    }

    func testDroneMeshSizeIsRealistic() {
        let mesh = GeometryBuilder.droneMesh()
        var minX = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        for v in mesh.vertices {
            minX = min(minX, v.position.x)
            maxX = max(maxX, v.position.x)
        }
        // 5 寸机轴距约 0.235m，桨尖到桨尖约 0.28m
        let span = maxX - minX
        XCTAssertGreaterThan(span, 0.15)
        XCTAssertLessThan(span, 0.40)
    }

    func testTreeAndBuildingMeshesAreValid() {
        let tree = GeometryBuilder.treeMesh(seed: 1)
        XCTAssertGreaterThan(tree.triangleCount, 0)
        for index in tree.indices {
            XCTAssertLessThan(Int(index), tree.vertexCount)
        }

        let building = GeometryBuilder.buildingMesh(seed: 2)
        XCTAssertGreaterThan(building.triangleCount, 0)
        for index in building.indices {
            XCTAssertLessThan(Int(index), building.vertexCount)
        }
    }

    func testSeededRandomIsDeterministic() {
        var a = SeededRandom(seed: 123)
        var b = SeededRandom(seed: 123)
        for _ in 0..<20 {
            XCTAssertEqual(a.next(), b.next())
        }
    }

    func testValueNoiseIsDeterministicAndBounded() {
        for i in 0..<50 {
            let x = Float(i) * 1.7
            let z = Float(i) * -0.9
            let a = valueNoise(x: x, z: z, seed: 5)
            let b = valueNoise(x: x, z: z, seed: 5)
            XCTAssertEqual(a, b)
            XCTAssertGreaterThanOrEqual(a, 0)
            XCTAssertLessThanOrEqual(a, 1)
        }
    }

    // MARK: GPU 布局约定
    //
    // Metal 与 Swift 的 float3 布局不同，uniform 结构体统一用 float4。
    // 这些断言防止有人改回 SIMD3/Float 混排。

    func testTerrainUniformsLayout() {
        XCTAssertEqual(MemoryLayout<TerrainUniforms>.size, 176)
        XCTAssertEqual(MemoryLayout<TerrainUniforms>.offset(of: \.viewProjection), 0)
        XCTAssertEqual(MemoryLayout<TerrainUniforms>.offset(of: \.model), 64)
        XCTAssertEqual(MemoryLayout<TerrainUniforms>.offset(of: \.lightDir), 128)
        XCTAssertEqual(MemoryLayout<TerrainUniforms>.offset(of: \.cameraPos), 144)
        XCTAssertEqual(MemoryLayout<TerrainUniforms>.offset(of: \.params), 160)
    }

    func testObjectUniformsLayout() {
        XCTAssertEqual(MemoryLayout<ObjectUniforms>.size, 160)
        XCTAssertEqual(MemoryLayout<ObjectUniforms>.offset(of: \.model), 64)
        XCTAssertEqual(MemoryLayout<ObjectUniforms>.offset(of: \.lightDir), 128)
        XCTAssertEqual(MemoryLayout<ObjectUniforms>.offset(of: \.cameraPos), 144)
    }

    func testInstancedUniformsLayout() {
        XCTAssertEqual(MemoryLayout<InstancedUniforms>.size, 128)
        XCTAssertEqual(MemoryLayout<InstancedUniforms>.offset(of: \.lightDir), 64)
        XCTAssertEqual(MemoryLayout<InstancedUniforms>.offset(of: \.cameraPos), 80)
        XCTAssertEqual(MemoryLayout<InstancedUniforms>.offset(of: \.params), 96)
        XCTAssertEqual(MemoryLayout<InstancedUniforms>.offset(of: \.count), 112)
    }

    func testInstanceDataLayoutMatchesShader() {
        // 着色器里 InstanceData { float4x4 model; float4 tint; }
        XCTAssertEqual(MemoryLayout<MetalRenderer.InstanceData>.size, 80)
        XCTAssertEqual(MemoryLayout<MetalRenderer.InstanceData>.offset(of: \.tint), 64)
    }

    func testMeshVertexLayoutMatchesVertexDescriptor() {
        // 着色器属性：position(0) float3 / normal(1) float3 / color(2) float4 / uv(3) float2
        XCTAssertEqual(MemoryLayout<MeshVertex>.offset(of: \.position), 0)
        XCTAssertEqual(MemoryLayout<MeshVertex>.offset(of: \.normal), 16)
        XCTAssertEqual(MemoryLayout<MeshVertex>.offset(of: \.color), 32)
        XCTAssertEqual(MemoryLayout<MeshVertex>.offset(of: \.uv), 48)
        XCTAssertEqual(MemoryLayout<MeshVertex>.stride, 64)
    }
}
