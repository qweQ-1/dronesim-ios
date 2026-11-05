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

// 值噪声（二维），用于地表细节
static float hash2(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static float valueNoise2(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash2(i);
    float b = hash2(i + float2(1.0, 0.0));
    float c = hash2(i + float2(0.0, 1.0));
    float d = hash2(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float fbm2(float2 p) {
    float v = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 4; i++) {
        v += valueNoise2(p) * amp;
        p *= 2.07;
        amp *= 0.5;
    }
    return v;
}

fragment float4 terrainFragment(TerrainVertexOut in [[stage_in]],
                                constant TerrainUniforms& u [[buffer(0)]]) {
    float3 n = normalize(in.normal);
    float3 l = normalize(u.lightDir.xyz);
    float3 v = normalize(u.cameraPos.xyz - in.worldPos);
    float ndotl = max(dot(n, l), 0.0);

    // 细节法线扰动：让大片同色地面有质感
    float2 wp = in.worldPos.xz;
    float d1 = fbm2(wp * 0.35);
    float d2 = fbm2(wp * 1.7 + 11.0);
    float3 detailN = normalize(n + float3((d1 - 0.5) * 0.35, 0.0, (d2 - 0.5) * 0.35));
    float detailLight = max(dot(detailN, l), 0.0);

    // 高度 + 坡度的配色
    float slope = 1.0 - n.y;
    float3 c = in.color.rgb;
    // 低处偏水润的绿，中段偏黄绿，高处偏灰白（和顶点色叠加）
    c *= 0.85 + 0.30 * d1;
    c = mix(c, c * float3(1.06, 1.02, 0.92), d2);

    // 半兰伯特环境光 + 天空散射
    float hemi = 0.5 + 0.5 * n.y;
    float3 skyAmbient = mix(float3(0.22, 0.26, 0.20), float3(0.42, 0.52, 0.68), hemi);
    float3 ambient = skyAmbient * 0.75;

    // 太阳：主光 + 一点镜面（湿滑/岩石反光）
    float3 sunColor = float3(1.05, 0.98, 0.86);
    float3 diffuse = sunColor * ndotl * 0.95;
    diffuse *= 0.82 + 0.18 * detailLight;

    float3 h = normalize(l + v);
    float spec = pow(max(dot(detailN, h), 0.0), 24.0) * 0.10 * (1.0 - slope);
    spec += pow(max(dot(detailN, h), 0.0), 90.0) * 0.18 * smoothstep(0.3, 0.7, slope);

    float3 color = c * (ambient + diffuse) + float3(spec);

    // 斜坡上露出岩石色
    float rockMix = smoothstep(0.32, 0.62, slope);
    color = mix(color, float3(0.36, 0.34, 0.32) * (ambient + diffuse * 0.9), rockMix * 0.75);

    // 地表网格线：给速度一个视觉参照，远处淡出避免摩尔纹
    float dist = distance(in.worldPos, u.cameraPos.xyz);
    float gridFade = 1.0 - smoothstep(40.0, 130.0, dist);
    float2 g = abs(fract(in.uv) - 0.5);
    float line = 1.0 - smoothstep(0.455, 0.5, max(g.x, g.y));
    color += float3(0.30, 0.55, 0.72) * line * 0.20 * gridFade;

    // 大气透视：远处淡入天空色，并轻微偏蓝（瑞利散射的观感）
    float fog = 1.0 - exp(-dist * u.params.x);
    float3 fogColor = mix(float3(0.66, 0.75, 0.86), float3(0.72, 0.82, 0.92),
                          smoothstep(0.0, 400.0, dist));
    color = mix(color, fogColor, clamp(fog, 0.0, 0.94));

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
    float3 sd = normalize(sunDir);
    float h = clamp(dir.y, -1.0, 1.0);
    float sunDot = max(dot(dir, sd), 0.0);

    // 大气散射的近似：地平线暖白、天顶深蓝，太阳附近再暖一档
    float3 zenith  = float3(0.10, 0.28, 0.62);
    float3 horizon = float3(0.80, 0.87, 0.94);
    float t = pow(smoothstep(-0.10, 0.75, h), 0.62);
    float3 sky = mix(horizon, zenith, t);

    // 地平线以下（远处地面/雾）
    float3 below = float3(0.55, 0.58, 0.58);
    sky = mix(below, sky, smoothstep(-0.18, 0.02, h));

    // 太阳：锐利日面 + 内晕 + 大范围前向散射
    float disc = smoothstep(0.99955, 0.99985, sunDot);
    float innerGlow = pow(sunDot, 900.0) * 2.2;
    float midGlow = pow(sunDot, 24.0) * 0.35;
    float wideGlow = pow(sunDot, 3.0) * 0.14;
    float3 sunColor = float3(1.0, 0.95, 0.82);
    sky += sunColor * (innerGlow + midGlow + wideGlow);
    sky = mix(sky, float3(1.0, 0.99, 0.94), disc);

    // 云：两层不同速度和尺度的程序化云带，只在高空出现
    float highMask = smoothstep(0.02, 0.30, h);
    float c1 = sin(dir.x * 2.6 + time * 0.010) * cos(dir.z * 2.1 - time * 0.008);
    float c2 = sin(dir.x * 6.1 - time * 0.016 + 1.7) * cos(dir.z * 5.3 + time * 0.011);
    float cloud = smoothstep(0.20, 0.85, c1 * 0.75 + c2 * 0.35);
    float3 cloudColor = mix(float3(0.86, 0.88, 0.92), float3(1.0), sunDot);
    sky = mix(sky, cloudColor, cloud * highMask * 0.55);

    // 靠近太阳的云被照亮
    sky += sunColor * cloud * highMask * pow(sunDot, 6.0) * 0.5;

    return float4(sky, 1.0);
}
