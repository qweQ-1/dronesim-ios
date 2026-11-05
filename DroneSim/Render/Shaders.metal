#include <metal_stdlib>
using namespace metal;

// MARK: - 地形

struct TerrainVertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
    float4 color    [[attribute(2)]];
    float2 uv       [[attribute(3)]];
};

struct TerrainVertexOut {
    float4 position [[position]];
    float3 normal;
    float2 uv;
    float4 color;
    float3 worldPos;
};

struct TerrainUniforms {
    float4x4 viewProjection;
    float4x4 model;
    float4   lightDir;    // xyz = 方向
    float4   cameraPos;   // xyz = 位置
    float4   params;      // x = fogDensity, y = time
};

vertex TerrainVertexOut terrainVertex(TerrainVertexIn in [[stage_in]],
                                      constant TerrainUniforms& u [[buffer(0)]]) {
    TerrainVertexOut out;
    float4 world = u.model * float4(in.position, 1.0);
    out.worldPos = world.xyz;
    out.position = u.viewProjection * world;
    out.normal = normalize((u.model * float4(in.normal, 0.0)).xyz);
    out.uv = in.uv;
    out.color = in.color;
    return out;
}

fragment float4 terrainFragment(TerrainVertexOut in [[stage_in]],
                                constant TerrainUniforms& u [[buffer(0)]]) {
    float3 n = normalize(in.normal);
    float3 l = normalize(u.lightDir.xyz);
    float ndotl = max(dot(n, l), 0.0);

    // 半兰伯特环境光：背光面不至于死黑
    float hemi = 0.5 + 0.5 * n.y;
    float3 ambient = float3(0.30, 0.35, 0.42) * (0.60 + 0.40 * hemi);
    float3 diffuse = float3(1.0, 0.96, 0.88) * ndotl * 0.85;

    // 地表网格线：给速度一个视觉参照
    float2 g = abs(fract(in.uv) - 0.5);
    float line = 1.0 - smoothstep(0.455, 0.5, max(g.x, g.y));
    float3 gridColor = float3(0.28, 0.52, 0.70) * line * 0.22;

    float3 color = in.color.rgb * (ambient + diffuse) + gridColor;

    // 大气透视：远处淡入天空色
    float dist = distance(in.worldPos, u.cameraPos.xyz);
    float fog = 1.0 - exp(-dist * u.params.x);
    float3 fogColor = float3(0.62, 0.72, 0.82);
    color = mix(color, fogColor, clamp(fog, 0.0, 0.92));

    return float4(color, 1.0);
}

// MARK: - 通用物体

struct ObjVertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
    float4 color    [[attribute(2)]];
};

struct ObjVertexOut {
    float4 position [[position]];
    float3 normal;
    float4 color;
    float3 worldPos;
};

struct ObjectUniforms {
    float4x4 viewProjection;
    float4x4 model;
    float4   lightDir;    // xyz = 方向
    float4   cameraPos;   // xyz = 位置
};

vertex ObjVertexOut objectVertex(ObjVertexIn in [[stage_in]],
                                 constant ObjectUniforms& u [[buffer(0)]]) {
    ObjVertexOut out;
    float4 world = u.model * float4(in.position, 1.0);
    out.worldPos = world.xyz;
    out.position = u.viewProjection * world;
    out.normal = normalize((u.model * float4(in.normal, 0.0)).xyz);
    out.color = in.color;
    return out;
}

fragment float4 objectFragment(ObjVertexOut in [[stage_in]],
                               constant ObjectUniforms& u [[buffer(0)]]) {
    float3 n = normalize(in.normal);
    float3 l = normalize(u.lightDir.xyz);
    float ndotl = max(dot(n, l), 0.0);

    float hemi = 0.5 + 0.5 * n.y;
    float3 ambient = float3(0.28, 0.32, 0.38) * (0.60 + 0.40 * hemi);
    float3 diffuse = float3(1.0, 0.95, 0.86) * ndotl;

    float3 color = in.color.rgb * (ambient + diffuse * 0.90);

    // 高光
    float3 v = normalize(u.cameraPos.xyz - in.worldPos);
    float3 hv = normalize(l + v);
    float spec = pow(max(dot(n, hv), 0.0), 42.0) * 0.30;
    color += float3(spec);

    // 雾
    float dist = distance(in.worldPos, u.cameraPos.xyz);
    float fog = 1.0 - exp(-dist * 0.0022);
    color = mix(color, float3(0.62, 0.72, 0.82), clamp(fog, 0.0, 0.90));

    return float4(color, 1.0);
}

// MARK: - 实例化物体

struct InstanceData {
    float4x4 model;
    float4 tint;
};

struct InstancedUniforms {
    float4x4 viewProjection;
    float4   lightDir;    // xyz = 方向
    float4   cameraPos;   // xyz = 位置
    float4   params;      // x = fogDensity
    uint     count;
};

// 注意：实例数据是数组，必须用指针类型（`constant InstanceData*`），
// 用引用（`constant InstanceData&`）没法下标访问。
vertex ObjVertexOut instancedVertex(ObjVertexIn in [[stage_in]],
                                    constant InstancedUniforms& u [[buffer(0)]],
                                    constant InstanceData* instances [[buffer(2)]],
                                    uint iid [[instance_id]]) {
    ObjVertexOut out;
    float4 world = instances[iid].model * float4(in.position, 1.0);
    out.worldPos = world.xyz;
    out.position = u.viewProjection * world;
    out.normal = normalize((instances[iid].model * float4(in.normal, 0.0)).xyz);
    out.color = in.color * instances[iid].tint;
    return out;
}

// MARK: - 天空

struct SkyVertexOut {
    float4 position [[position]];
    float3 direction;
};

vertex SkyVertexOut skyVertex(uint vid [[vertex_id]],
                              constant float4x4& invViewProj [[buffer(0)]],
                              constant float3& cameraPos [[buffer(1)]]) {
    // 全屏三角形
    float2 pos = float2(float((vid << 1) & 2), float(vid & 2));
    float2 ndc = pos * 2.0 - 1.0;

    // 反投影得到视线方向
    float4 nearP = invViewProj * float4(ndc, 0.0, 1.0);
    float4 farP  = invViewProj * float4(ndc, 1.0, 1.0);
    float3 dir = normalize(farP.xyz / farP.w - nearP.xyz / nearP.w);

    SkyVertexOut out;
    out.position = float4(ndc, 1.0, 1.0);   // z = 1，最远
    out.direction = dir;
    return out;
}

fragment float4 skyFragment(SkyVertexOut in [[stage_in]],
                            constant float3& sunDir [[buffer(0)]],
                            constant float3& cameraPos [[buffer(1)]],
                            constant float& time [[buffer(2)]]) {
    float3 dir = normalize(in.direction);
    float h = clamp(dir.y, -1.0, 1.0);

    float3 zenith  = float3(0.16, 0.35, 0.66);
    float3 horizon = float3(0.72, 0.82, 0.90);
    float3 ground  = float3(0.42, 0.44, 0.42);

    float t = smoothstep(-0.05, 0.55, h);
    float3 sky = mix(horizon, zenith, t);
    sky = mix(ground, sky, smoothstep(-0.25, 0.0, h));

    // 太阳与光晕
    float sunDot = max(dot(dir, normalize(sunDir)), 0.0);
    float disc = smoothstep(0.9985, 0.9995, sunDot);
    float glow = pow(sunDot, 220.0) * 0.85 + pow(sunDot, 12.0) * 0.16;
    sky += float3(1.0, 0.94, 0.80) * glow;
    sky = mix(sky, float3(1.0, 0.98, 0.90), disc);

    // 廉价程序化云带
    float band = sin(dir.x * 3.0 + time * 0.02) * cos(dir.z * 2.6 - time * 0.015);
    float cloud = smoothstep(0.25, 0.85, band) * smoothstep(0.05, 0.45, h) * 0.10;
    sky = mix(sky, float3(1.0), cloud);

    return float4(sky, 1.0);
}
