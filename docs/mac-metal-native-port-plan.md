# Mesh2Splat macOS Metal 原生重构策划书

版本：0.1  
日期：2026-06-04  
目标项目：Mesh2Splat  
目标平台：macOS / Apple Silicon / Metal

## 1. 项目摘要

本文档用于规划 Mesh2Splat 的 macOS 原生高性能重构工作。目标不是让当前 OpenGL 版本在 Mac 上勉强运行，而是将项目重构为以 Metal、macOS 原生窗口系统、原生 GPU 资源管理和 Apple Silicon 性能优化为核心的一等平台版本。

当前项目依赖 OpenGL 4.5/4.6 能力，包括 GLSL 450/460 shader、compute shader、SSBO、atomic、indirect draw、以及基于 geometry shader 的 mesh-to-splat conversion pass。macOS 原生 OpenGL 最高只能提供 OpenGL 4.1，因此当前 OpenGL 渲染器无法在 macOS 上正常运行。

要实现真正的 macOS 原生版本，需要系统性迁移到 Metal，而不是简单修改 CMake 或降低 shader 版本。

推荐策略是：保留可复用的 CPU 侧代码，例如模型解析、场景数据、材质提取、相机、数学工具和文件 I/O；同时重写 GPU 渲染后端、shader、conversion pass、排序和 UI 后端。

## 2. 当前项目状态

当前项目主要包含：

- C++17 应用代码。
- GLFW / GLEW / OpenGL 窗口和上下文管理。
- OpenGL render pass，包括 mesh 渲染、mesh-to-splat 转换、gaussian splatting、排序、relighting、shadow 和 debug visualization。
- `src/shaders` 下的 GLSL shader。
- `thirdParty/RadixSort.hpp` 中的 GPU radix sort。
- 基于 OpenGL backend 的 ImGui UI。
- GLB / PLY 解析和场景管理工具。

本机 macOS 构建检查结果：

- 已通过 Homebrew 安装 CMake、GLFW、GLEW 和 pkg-config。
- 已给 CMakeLists 添加 macOS 链接分支，使项目可以在本机编译。
- 可执行文件可以成功生成。
- 运行失败，因为应用请求 OpenGL 4.5，而 macOS 只能创建 OpenGL 4.1 context。

项目中已确认的关键 OpenGL 需求：

- OpenGL context 请求：4.5 core profile。
- GLSL 版本：大量 `#version 460 core`，少量 `#version 450 core`。
- 使用 `glDispatchCompute`。
- 使用 `GL_SHADER_STORAGE_BUFFER`。
- conversion pass 使用 atomic counter。
- `converterGS.glsl` 使用 geometry shader。

## 3. 重构目标

目标交付物是一个 macOS 原生高性能 Mesh2Splat 应用，具备以下特性：

- 不依赖 OpenGL。
- 不依赖 GLEW。
- GLFW 可以移除或隔离，macOS 版本优先使用 AppKit + Metal。
- mesh conversion、GPU sorting、gaussian rendering 和高级渲染 pass 均使用 Metal 实现。
- 在 Apple Silicon GPU 上稳定高效运行。
- 尽量保留原 Mesh2Splat 的功能、视觉结果和工作流。
- 架构足够清晰，便于长期维护和继续扩展。

最低功能目标：

- 启动 macOS 原生窗口。
- 加载 `.glb` mesh。
- 上传 mesh、material、texture 到 Metal。
- 将 mesh surface 转换为 gaussian splats。
- 渲染 gaussian splats。
- 保存转换后的 `.ply` 文件。
- 提供基础 UI，用于加载、转换、可视化和导出。

高性能目标：

- conversion、sorting、rendering 均在 GPU 侧完成。
- 帧时间稳定。
- 尽量避免 CPU-GPU 同步 stall。
- GPU buffer 和 texture 复用，避免每帧大量分配。
- Command buffer 和 encoder 结构适合 Metal capture 分析。
- 提供性能统计和可复现 benchmark。

## 4. 设计原则

1. 将 macOS 视为一等平台，而不是兼容层。
2. 尽量保留 CPU 侧可复用逻辑。
3. 用 Metal 的显式资源和 encoder 模型替代 OpenGL state machine。
4. 先打通最小闭环，再恢复全部高级功能。
5. 先保证正确性，再用 Metal capture 和 GPU counters 做性能优化。
6. 不强行机械翻译 OpenGL 抽象，必要时采用更符合 Metal 的新设计。

## 5. 推荐架构

建议将重构后的项目拆成三层：

```text
Core
模型解析、mesh 数据、material、camera、scene、参数、数学工具

Renderer Backend
Metal device、buffer、texture、pipeline、command encoder、resource lifetime

Application Layer
macOS window、input、UI、文件选择、运行循环、profiling hooks
```

### 5.1 Core 层

职责：

- 资产解析。
- Mesh 和 material 数据结构。
- Scene 状态。
- Camera。
- 数学工具。
- Gaussian 数据定义。
- conversion / rendering 参数。

这一层尽量不依赖 OpenGL 或 Metal。

可复用候选：

- `src/parsers/*`
- `src/utils/Camera.*`
- `src/utils/utils.*` 中与 OpenGL 无关的部分
- `src/utils/SceneManager.*` 中与 OpenGL 无关的部分
- `thirdParty/tiny_gltf.h`
- `thirdParty/stb_*`
- `thirdParty/xatlas`

### 5.2 Metal Backend 层

职责：

- 持有 `MTLDevice` 和 `MTLCommandQueue`。
- 管理 buffer 分配与复用。
- 管理 texture 创建与上传。
- 管理 sampler。
- 创建 render pipeline。
- 创建 compute pipeline。
- 管理 depth / color render target。
- 管理 constant buffer、argument buffer 或绑定辅助逻辑。
- 管理 command buffer 和 encoder 生命周期。
- 处理 GPU 同步、fence 和 debug label。

这一层会替代当前大部分 `glUtils` 和 `ShaderRegistry`。

建议组件：

- `MetalDeviceContext`
- `MetalBuffer`
- `MetalTexture`
- `MetalPipelineCache`
- `MetalShaderLibrary`
- `MetalRenderTarget`
- `MetalFrameResources`
- `MetalResourceUploader`
- `MetalGpuTimer`

### 5.3 Application Layer

职责：

- macOS 应用生命周期。
- Window 创建。
- `MTKView` 或 `CAMetalLayer` 管理。
- 输入事件。
- 文件选择。
- UI 集成。
- 主循环和帧调度。

推荐实现：

- 使用 Objective-C++ 接入 AppKit 和 `MTKView`。
- 第一阶段继续使用 ImGui，但切换到 ImGui Metal backend。
- 后续如需更像原生软件，可再考虑 AppKit 或 SwiftUI UI。

## 6. OpenGL 到 Metal 映射

| 当前 OpenGL 概念 | Metal 替代方案 |
|---|---|
| GLFW OpenGL context | AppKit window + `MTKView` 或 `CAMetalLayer` |
| GLEW 函数加载 | 不需要 |
| `GLuint` buffer | `id<MTLBuffer>` |
| `glBufferData` | `newBufferWithLength` / buffer pool / blit upload |
| SSBO | MSL 中的 `device` buffer |
| Atomic counter buffer | `device atomic_uint*` 或 counter buffer |
| Texture object | `id<MTLTexture>` |
| FBO / renderbuffer | Render pass descriptor + `MTLTexture` attachment |
| Shader program | `MTLRenderPipelineState` 或 `MTLComputePipelineState` |
| Uniform | Constant buffer 或小型参数 buffer |
| `glDrawArrays` | `drawPrimitives` |
| `glDispatchCompute` | `dispatchThreadgroups` / `dispatchThreads` |
| Memory barrier | Encoder 边界、resource usage、fence、显式同步 |
| GLSL | Metal Shading Language |
| ImGui OpenGL backend | ImGui Metal backend |

## 7. Geometry Shader 替代策略

Metal 没有 OpenGL 风格的 geometry shader。当前 conversion path 使用：

- Vertex shader 传递顶点属性。
- Geometry shader 以三角形为单位计算 orthogonal UV、scale、quaternion。
- Rasterizer 在投影后的三角形上生成 fragment。
- Fragment shader 将 gaussian record append 到 SSBO。

最推荐的 Metal 初始替代方案是 procedural vertex shader。

### 7.1 Procedural Vertex Shader 方案

绘制 `3 * triangleCount` 个顶点。在 Metal vertex function 中：

```text
triangleIndex = vertex_id / 3
cornerIndex   = vertex_id % 3
```

Vertex shader 根据 `triangleIndex` 读取当前三角形的三个原始顶点，执行原本 `converterGS.glsl` 中的三角形级计算，然后输出当前 `cornerIndex` 对应的投影顶点。Rasterizer 继续在投影后的三角形上生成 fragment，从而保留原算法中“通过 rasterizer 对表面采样”的核心思路。

优点：

- 最接近当前 OpenGL 算法。
- 保留 rasterizer-driven surface sampling。
- 第一阶段不用完全重写采样逻辑。
- 风险低于 pure compute conversion。

缺点：

- 三角形级计算可能在三个 corner 上重复，需要后续优化。
- 需要设计适合 Metal 的 vertex buffer / index buffer 布局。
- Fragment 阶段 append gaussian buffer 需要谨慎处理 atomic 和容量上限。

### 7.2 Pure Compute Conversion 方案

后续可以考虑把 mesh-to-splat conversion 完全改为 compute pipeline：

- 一个或多个 threadgroup 处理 triangle。
- 显式计算 sampling density。
- Thread 直接生成 gaussian record。
- 使用 prefix sum 或 atomic append 分配输出位置。

优点：

- 更符合 Metal compute 模型。
- 对 workload 和 memory layout 的控制更强。
- 长期性能潜力更高。

缺点：

- 工程量更大。
- 算法变化更明显。
- 需要和原 rasterization-based 输出做严格验证。

建议：

- 第一阶段使用 procedural vertex + fragment append。
- 跑通并 profile 后，再决定是否值得实现 pure compute conversion。

## 8. 主要工作流

### 8.1 构建系统与工程结构

任务：

- 决定最终工程形态：CMake-only、Xcode project、或 CMake 生成 Xcode。
- 增加 Objective-C++ 支持。
- 增加 `.metal` shader 编译流程。
- 增加 macOS app bundle target。
- 增加 Metal library 和资源复制逻辑。
- 将当前 Windows/Linux OpenGL 版本隔离在 build flag 或独立后端下。

交付物：

- 可复现的 macOS 构建流程。
- 可启动的 `.app` 或命令行启动版本。
- 开发者构建说明。

### 8.2 macOS 原生应用壳

任务：

- 创建 AppKit application entry。
- 创建 `NSWindow`。
- 创建 `MTKView`。
- 接入 resize event。
- 使用 `MTKViewDelegate` 实现 frame loop。
- 实现鼠标和键盘输入。
- 接入文件选择。

交付物：

- 空白 Metal 窗口。
- Clear color render loop。
- 输入事件可在日志或 debug UI 中观察。

### 8.3 Metal 资源层

任务：

- 实现 buffer wrapper。
- 实现 texture wrapper。
- 实现 texture upload。
- 实现 sampler cache。
- 实现 frame resource allocator。
- 实现 render target manager。
- 实现 command buffer submission helper。
- 为 Metal capture 添加 debug label。

交付物：

- 稳定的资源生命周期。
- 每帧无失控 GPU 分配。
- Metal capture 中可看到命名清晰的 resource 和 encoder。

### 8.4 Shader 与 Pipeline 系统

任务：

- 将 shader registry 改为 Metal library 和 pipeline cache。
- 增加 render pipeline descriptor builder。
- 增加 compute pipeline descriptor builder。
- 定义 CPU / MSL 共享结构体。
- 明确矩阵布局和坐标系约定。
- 在构建或启动阶段进行 shader 编译校验。

交付物：

- Mesh render pipeline。
- Conversion pipeline。
- Gaussian render pipeline。
- Compute pipeline 创建能力。

### 8.5 Mesh 与 Material 上传

任务：

- 用 `MetalMesh` 替代 `GLMesh`。
- 定义 packed vertex layout。
- 上传 vertex / index buffer。
- 上传 base color、normal、metallic-roughness texture。
- 创建默认 fallback texture。
- 实现 material constant buffer。
- 验证 tangent、normal、UV、normalized UV 数据一致性。

交付物：

- `.glb` 加载后能生成 Metal GPU 资源。
- Mesh vertex / index buffer 在 GPU 上可用。
- 材质贴图可通过 test shader 或 debug UI 查看。

### 8.6 Mesh Render Pass

任务：

- 将 `meshRenderVS.glsl` 迁移到 MSL。
- 将 `meshRenderPS.glsl` 迁移到 MSL。
- 实现 camera constant。
- 实现 depth buffer。
- 实现 material sampling。
- 验证坐标系和 face winding。

交付物：

- 能用 Metal 渲染原始 mesh。
- Camera movement 可用。
- 基础材质视图可用。

### 8.7 Conversion Pass

任务：

- 将 `converterVS.glsl`、`converterGS.glsl`、`converterFS.glsl` 迁移到 Metal。
- 用 procedural vertex shader 替代 geometry shader。
- 实现 gaussian append buffer。
- 实现 atomic count buffer。
- 实现 conversion render target。
- 在 conversion fragment function 中实现 texture sampling。
- 实现 gaussian count readback。
- 验证生成的 gaussian record。

交付物：

- Mesh 在 GPU 上转换为 gaussian buffer。
- Gaussian count 正确且稳定。
- 可以从 Metal buffer 导出 `.ply`。

关键验证场景：

- 单三角形。
- Quad。
- Cube。
- Textured GLB。
- 带 normal map 的模型。
- Multi-mesh GLB。

### 8.8 Gaussian Render Pass

任务：

- 迁移 gaussian splatting vertex / fragment shader。
- 实现 gaussian buffer binding。
- 在 Metal 中实现 quad expansion。
- 实现 view / projection constant。
- 实现 albedo、normal、depth、material、overdraw 等 visualization mode。
- 实现 alpha blending 和 depth behavior。

交付物：

- 转换后的 gaussian data 可以渲染。
- Camera movement 可用。
- Debug view 可切换。

### 8.9 GPU Sorting

任务：

- 将 OpenGL compute radix sort 迁移到 Metal compute。
- 定义 key / value buffer。
- 生成 depth key。
- 排序 gaussian index 或 transformation data。
- 使用小规模固定输入验证排序正确性。
- 对大 gaussian count 做性能分析。

交付物：

- Alpha ordering 正确。
- 正常渲染路径不依赖 CPU fallback。
- 有不同 gaussian count 下的 benchmark 数据。

### 8.10 Relighting 与 Shadow

任务：

- 迁移 gaussian relighting pass。
- 迁移 point light data。
- 迁移或重新设计 cube shadow map。
- 迁移 gaussian point shadow compute pass。
- 验证 PBR 项和 normal map 行为。

交付物：

- Point light 交互可用。
- Shadow visualization 可用。
- Gaussian PBR shading 尽量与原版本一致。

### 8.11 UI

任务：

- 第一阶段集成 ImGui Metal backend。
- 重建 file selector 流程。
- 重建 conversion control。
- 重建 visualization control。
- 增加性能 overlay。
- 增加 GPU timing UI。
- 增加错误报告 UI。

交付物：

- 可以加载、转换、查看、导出。
- macOS 路径不再使用 ImGui OpenGL backend。

### 8.12 导出与文件 I/O

任务：

- 尽量保留已有 `.ply` export 逻辑。
- 增加 Metal buffer readback。
- 避免交互渲染过程中发生阻塞式 readback。
- 用外部 viewer 验证导出文件。

交付物：

- 可以保存转换后的 gaussian `.ply`。
- 导出的文件结构和数据范围正确。

### 8.13 性能工程

任务：

- 添加 Metal capture label。
- 添加 GPU timer 或 timestamp 统计。
- 添加 frame timing。
- 添加 benchmark scene。
- 减少 command buffer stall。
- 避免每帧资源分配。
- 优化 gaussian buffer memory layout。
- 评估 argument buffer 以减少 binding 开销。
- 评估 dynamic constant 的 triple buffering。

交付物：

- Benchmark report。
- Apple Silicon 上的性能目标。
- 已知瓶颈清单。

### 8.14 测试与验证

任务：

- 增加 CPU 侧 math / parsing 单元测试。
- 增加 shader validation scene。
- 为简单 mesh 增加 golden output 比较。
- 增加 gaussian count regression test。
- 增加 reference scene 截图。
- 增加性能回归 checklist。

交付物：

- 可复现的正确性检查。
- 手动视觉 QA checklist。
- 基准性能数据。

## 9. 里程碑计划

### Milestone 0：技术设计冻结

周期：3-5 天

产出：

- 最终架构决策。
- OpenGL 到 Metal 映射表。
- GPU 数据结构规格。
- Shader 迁移清单。
- 初始风险清单。

退出标准：

- 每个当前 render pass 都有目标 Metal 设计。
- Conversion pass 替代策略已确认。

### Milestone 1：原生 Metal 窗口

周期：3-5 天

产出：

- macOS app entry。
- `MTKView` render loop。
- 输入处理。
- Clear color 和 resize。

退出标准：

- 应用能稳定启动。
- Metal capture 可用。

### Milestone 2：Metal 基础设施

周期：1-2 周

产出：

- Resource wrapper。
- Shader library loading。
- Pipeline cache。
- Frame resource management。
- Debug label。

退出标准：

- 简单 render pipeline 和 compute pipeline 可以运行。
- Metal capture 中资源命名清晰。

### Milestone 3：Mesh 加载与渲染

周期：1-2 周

产出：

- `MetalMesh`。
- Texture upload。
- Basic mesh render pass。
- Camera integration。

退出标准：

- GLB 模型可以在 Metal 中正确渲染。
- 基础材质和 texture sampling 可用。

### Milestone 4：Mesh-To-Splat Conversion

周期：2-3 周

产出：

- Procedural vertex conversion pipeline。
- Gaussian append buffer。
- Atomic count。
- Conversion validation scene。
- 从 Metal buffer 导出 `.ply`。

退出标准：

- 简单 mesh 和 textured mesh 能生成可见 gaussian。
- Gaussian count 跨运行稳定。

### Milestone 5：Gaussian Rendering

周期：1-2 周

产出：

- Gaussian splatting render pass。
- Debug view。
- Camera interaction。
- Blending / depth behavior。

退出标准：

- 转换结果可见且可检查。
- 基础 view mode 可用。

### Milestone 6：GPU Sorting

周期：2-3 周

产出：

- Metal radix sort。
- Depth key generation。
- Sorted render path。
- Sorting benchmark。

退出标准：

- Transparent splat ordering 视觉正确。
- Sorting 保持 GPU-side。

### Milestone 7：高级渲染功能对齐

周期：2-4 周

产出：

- Relighting。
- Shadow pass。
- Deferred / debug mode。
- PBR validation。

退出标准：

- 原渲染器主要高级功能恢复，或者给出明确替代方案。

### Milestone 8：产品化与优化

周期：2-4 周

产出：

- UI polish。
- Error handling。
- Performance tuning。
- App packaging。
- Documentation。

退出标准：

- Mac 原生版本足够稳定，可以日常使用。
- 性能和质量已有文档记录。

## 10. 工作量估算

面向完整 macOS 原生高性能版本：

| 领域 | 预计代码改动 |
|---|---:|
| macOS app shell | 500-1,000 行 |
| Metal backend infrastructure | 1,500-3,000 行 |
| Render pass 重写 | 2,000-4,000 行 |
| Shader 迁移到 MSL | 2,000-3,500 行 |
| Conversion pipeline 重构 | 1,000-2,500 行 |
| Metal radix sort | 800-1,800 行 |
| UI 集成 | 500-1,500 行 |
| 测试、profiling、工具化 | 1,000-2,000 行 |

总体代码改动范围：

- 原型级：4,000-7,000 行。
- 功能完整的原生移植：8,000-14,000 行。
- 产品级、优化充分、文档完整版本：12,000-18,000 行。

时间估算：

- 单名有经验工程师全职：10-16 周。
- 两名有经验工程师全职：7-10 周。
- 若包含产品级 polish 和完整 benchmark：12-20 周。

## 11. 风险清单

| 风险 | 严重度 | 说明 | 缓解方案 |
|---|---|---|---|
| Conversion pass 行为变化 | 高 | Metal 没有 geometry shader | 第一阶段使用 procedural vertex 方案 |
| Radix sort 迁移复杂 | 高 | 排序影响正确性和性能 | 建立独立 sorting test |
| GLSL 到 MSL 语义差异 | 高 | matrix layout、坐标系、atomic、barrier 都可能不同 | 定义共享结构体和 golden test |
| GPU 同步 stall | 中 | readback 和 counter 可能阻塞 | 批量 readback，用 Metal capture 分析 |
| Texture/material 对齐问题 | 中 | GLB material 细节较多 | 使用已知 glTF sample asset 验证 |
| UI 迁移时间 | 中 | ImGui backend 替换不难，但集成仍需时间 | 第一阶段用 ImGui Metal backend |
| 同时维护 OpenGL 和 Metal 后端 | 中 | 双后端会增加复杂度 | 隔离 renderer backend |
| 性能回归 | 高 | Apple GPU 架构不同于桌面 OpenGL GPU | 尽早 profile，持续 benchmark |

## 12. 验证策略

正确性验证应从很小的场景开始。

推荐测试场景：

- 单三角形。
- 单 quad。
- 纯色 cube。
- 带 texture 的 cube。
- 带 base color texture 的 GLB。
- 带 normal map 的 GLB。
- 带 metallic-roughness texture 的 GLB。
- Multi-mesh GLB。
- 大规模高密度 mesh。

验证指标：

- Gaussian count。
- Gaussian position bounds。
- Normal direction sanity。
- Color / material range。
- 导出 PLY 可读性。
- 与 OpenGL 参考输出的视觉一致性。
- Frame time。
- Conversion time。
- Sort time。
- GPU memory usage。

## 13. 建议目录结构

一种可能的目标目录结构：

```text
src/
  app/
    macos/
      MacApp.mm
      MetalView.mm
      InputController.mm
  core/
    Camera.*
    Scene.*
    Mesh.*
    Material.*
    Gaussian.*
  io/
    GltfLoader.*
    PlyWriter.*
  renderer/
    Renderer.hpp
    RenderContext.hpp
  renderer/metal/
    MetalRenderer.mm
    MetalDeviceContext.mm
    MetalBuffer.mm
    MetalTexture.mm
    MetalPipelineCache.mm
    MetalMesh.mm
    passes/
      MetalMeshPass.mm
      MetalConversionPass.mm
      MetalGaussianPass.mm
      MetalSortPass.mm
      MetalShadowPass.mm
shaders/
  metal/
    Common.metal
    Mesh.metal
    Conversion.metal
    Gaussian.metal
    Sort.metal
    Shadow.metal
docs/
  mac-metal-native-port-plan.md
```

这个结构将可复用 core logic 与 Metal-specific implementation 分开，同时保留现有 pass 名称的可识别性。

## 14. 初始实现 Checklist

建议先打通最小可用闭环：

- 创建 macOS Metal app target。
- 渲染 clear color。
- 加载 GLB 到 CPU 数据结构。
- 上传 mesh vertices 和 textures。
- 渲染 mesh。
- 实现 procedural vertex conversion pipeline。
- 将 gaussian record append 到 Metal buffer。
- 读取 gaussian count。
- 渲染 gaussian splats。
- 导出 PLY。

这个闭环稳定后，再恢复：

- GPU sorting。
- 高级 debug view。
- PBR parity。
- Shadow。
- Performance UI。
- Packaging polish。

## 15. 推荐下一步

在正式写 Metal 代码前，建议先创建一份更细的迁移清单，每一行对应当前的一个 pass 或 shader：

```text
当前文件
当前 OpenGL API
当前 GLSL shader
Metal 替代方案
输入数据
输出数据
风险等级
预计工时
验证方法
```

这份清单可以作为后续实现 tracker。它能避免迁移变成无边界重写，也能让每个 pass 的进度、风险和验收标准更清晰。

