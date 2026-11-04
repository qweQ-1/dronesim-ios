# 无人机模拟器 DroneSim

逼真流畅的 iOS 无人机飞行模拟游戏。Swift + Metal 原生渲染，无第三方依赖。

## 特性

- **拟真飞行动力学**：四旋翼推力/反扭矩模型、电机一阶响应延迟、气动阻力、下洗阻力、角阻尼、
  地面碰撞与恢复系数、电池功耗模型。
- **固定步长物理**：物理恒定 240Hz 推进，与渲染帧率解耦，帧率波动不影响手感。
- **三种相机视角**：追尾（随速度拉远）、机载 FPV、环绕。
- **多种操控模式**：自稳、纯手动（Acro）、定高、陀螺仪体感操控。
- **程序化世界**：地形（值噪声 fBm + 山体）、树林、建筑群、塔柱障碍，全部代码生成，零资源文件。
- **Metal 高效渲染**：实例化绘制整张地图仅 5 次 draw call，帧循环内零堆分配。

## 操作

| 区域 | 作用 |
| --- | --- |
| 左下摇杆 | 上下 = 油门，左右 = 偏航 |
| 右下摇杆 | 上下 = 俯仰，左右 = 横滚 |
| 右侧按钮 | 起飞/上锁、视角切换、自稳/手动、定高/手动、体感/摇杆、暂停、复位 |

## 构建

```bash
xcodegen generate
open DroneSim.xcodeproj
```

CI 通过 `ios-ci-workflows` 编译测试；`Unsigned IPA` 工作流可产出免签名 IPA 供侧载。

## 架构

```
DroneSim/
├── Sim/          纯 Swift 物理层（无 UIKit/Metal 依赖，可完整单测覆盖）
│   ├── Math.swift              向量与插值工具
│   ├── Quat.swift              四元数与机体坐标系
│   ├── DroneSpec.swift         机型参数、输入与状态定义
│   ├── FlightDynamics.swift    四旋翼动力学求解器
│   ├── StabilizedController.swift 自稳 / 定高控制器
│   └── FlightManager.swift     固定步长循环与状态机
├── Render/       Metal 渲染
│   ├── Geometry.swift          程序化几何生成
│   ├── Shaders.swift           运行时编译的着色器源码
│   └── MetalRenderer.swift     管线、缓冲、实例化绘制
├── Input/        虚拟摇杆与陀螺仪
└── Views/        Metal 视图、HUD、控制覆盖层
```

## 许可

MIT
