# Apple Silicon 性能与验证计划

本文档用于规划 Mesh2Splat macOS / Metal 原生版本后续的性能验证与稳定性工作。目标不是一次性给出性能结论，而是建立可复现、可比较、可持续执行的验证体系，覆盖 Metal capture、GPU counters、CPU/GPU frame timing、conversion / sort / render benchmark、资源内存统计、CPU-GPU stall 排查和测试数据规模。

## 目标

- 建立 Apple Silicon 上的性能基线，后续每次优化都能和基线比较。
- 区分 conversion、sort、render、upload、readback、UI/frame loop 的成本。
- 用 Metal capture 和 GPU counters 定位 GPU 端瓶颈，而不是只看总 FPS。
- 量化 buffer / texture / heap / transient resource 的内存占用和峰值。
- 尽早发现 CPU-GPU 同步 stall、资源反复分配、隐式 readback、command buffer 堵塞等稳定性问题。
- 形成固定 benchmark 数据规模，覆盖小模型、常规模型、压力模型和长时间稳定性运行。

## 总体原则

- 先正确性，后性能；任何性能数据必须对应一个已知正确的视觉或导出结果。
- 每个 benchmark 记录输入数据、构建配置、机器型号、macOS 版本、分辨率、gaussian 数量、运行时间、平均值、P95/P99 和异常帧。
- profiling build 可以打开 label、counter、debug marker 和统计采样；release benchmark 必须关闭会明显改变时序的重型诊断。
- 所有 Metal resource、command buffer、encoder、pipeline 都应带可读 label，方便 Xcode Metal capture 分段查看。
- 避免用单帧数据下结论；交互式路径至少采样 300 帧，稳定性路径至少运行 15 分钟，压力路径按规模递增。

## 验证阶段

| 阶段 | 何时构建 | 何时运行 | 主要输出 |
|---|---|---|---|
| P0 启动与正确性基线 | 每次 Metal 目标或 Core/IO 接口变动后 | 本地 smoke run，加载最小 mesh/ply | 能启动、能加载、无明显渲染错误 |
| P1 Frame timing 基线 | conversion、sort、render 任一闭环可运行后 | 每次性能相关改动前后 | CPU/GPU 分段耗时、总 frame time、异常帧 |
| P2 Metal capture | 新 pass 接入、encoder 结构调整、资源绑定改动后 | 捕获代表性 1-3 帧 | pass 顺序、资源依赖、pipeline 状态、GPU event |
| P3 GPU counters | 视觉正确且 capture 可读后 | 每个主要 pass 独立采样 | occupancy、threadgroup、bandwidth、tile/memory 指标 |
| P4 Benchmark 套件 | scripted run 或可重复命令可用后 | 每个里程碑、合并前、性能优化后 | conversion/sort/render 分项数据和趋势 |
| P5 内存与资源统计 | buffer/texture 管理层稳定后 | 加载、转换、渲染、导出全过程 | resident size、allocated size、峰值、资源生命周期 |
| P6 Stall 与长稳测试 | readback、导出、动态加载、UI 操作路径可用后 | 压力数据和长时间交互 | stall 位置、掉帧原因、泄漏和累积抖动 |

## Metal Capture 计划

### 捕获目标

- 启动后一帧：确认 drawable、depth target、clear、present 和 frame loop 正常。
- mesh upload 后第一帧：确认 texture、material、vertex/index buffer 绑定正确。
- conversion 帧：确认 conversion pass 的 render/compute encoder、counter buffer、append buffer、barrier 边界。
- sort 帧：确认 radix sort 或替代排序 pass 的 dispatch 规模、temporary buffer 和 read/write 依赖。
- gaussian render 帧：确认 blending、depth、pipeline、instance/vertex 数据绑定和 overdraw 热点。
- 导出或 readback 帧：确认 readback 是否集中、是否阻塞主线程或等待 command buffer。

### 捕获要求

- 每个 command buffer 使用阶段化 label，例如 `Frame`, `Conversion`, `Sort`, `GaussianRender`, `Readback`。
- 每个 encoder 使用 pass 级 label；每个 buffer / texture 使用用途、规模和帧资源编号命名。
- capture 文件记录对应 git commit、构建配置、输入资产、视口分辨率和 gaussian 数量。
- 捕获前先跑 30-60 帧预热，避免 shader pipeline 首次编译和资源首次分配污染数据。

### 运行时机

- 新增或重写一个 Metal pass 后立即捕获一次。
- 修改 resource lifetime、buffer pool、texture upload 或 encoder 顺序后捕获一次。
- benchmark 发现 P95/P99 异常、GPU 时间突增或视觉闪烁时捕获问题帧。

## GPU Counters 计划

### 关注指标

- compute pass：thread occupancy、threadgroup size 合理性、SIMD group 利用率、device memory bandwidth、atomic contention。
- render pass：fragment workload、blend cost、overdraw、tile memory 压力、depth/stencil 行为。
- sort pass：global memory read/write 带宽、temporary buffer 读写次数、dispatch 间同步成本。
- conversion pass：atomic append/counter 热点、采样密度变化、buffer 写入连续性。

### 执行方式

- 先对小数据捕获 counters，确认指标可读且 pass label 清晰。
- 再用中/大数据重复采样，观察瓶颈是否随 triangle count、gaussian count、分辨率线性增长。
- counters 结果只和同一机器、同一 macOS、同一构建配置比较。
- 对每个重点 pass 至少保留一个 baseline capture，后续优化以同一数据集复测。

### 运行时机

- conversion、sort、render 各自视觉正确后开始。
- 每次改变 shader threadgroup size、buffer layout、atomic 策略、blend/depth 状态后复测。
- 每个发布候选版本至少跑一次中数据 counters 和一次大数据 counters。

## CPU/GPU Frame Timing

### 需要记录的 CPU 时间

- frame begin 到 command buffer commit。
- asset load 和 parse。
- resource upload 准备与 staging copy。
- conversion 调度成本。
- sort 调度成本。
- render command encoding。
- UI / input / camera update。
- readback request、readback completion、export 写盘。

### 需要记录的 GPU 时间

- conversion pass。
- sort pass。
- gaussian render pass。
- mesh preview / debug pass。
- blit upload / blit readback。
- full frame GPU elapsed。

### 统计口径

- 记录 warmup 后的平均、median、P95、P99、max。
- 标记异常帧原因：pipeline compile、resource allocation、readback、window resize、asset switch、OS background load。
- frame timing UI 只显示轻量滚动统计；benchmark 输出完整 CSV/JSON。

### 运行时机

- P1 起就要持续运行；它是后续所有优化的基本仪表盘。
- 任意改动 command buffer、frame resources、resource upload、readback、排序或渲染 shader 后都要复测。
- 合并前至少跑一次固定相机路径的 300 帧采样。

## Conversion / Sort / Render Benchmark

### 分项 benchmark

- conversion only：固定 mesh 输入，只运行 mesh-to-gaussian conversion，记录生成 gaussian 数量、GPU 时间、CPU encoding 时间和 readback 成本。
- sort only：输入固定 gaussian buffer 和相机路径，只运行 key generation / sort / reorder，记录不同 gaussian 数量下的排序耗时。
- render only：输入固定 gaussian buffer，不重新 conversion，不重新 sort 或使用固定排序结果，记录不同分辨率、不同 gaussian 数量下的渲染耗时。
- full pipeline：load -> upload -> conversion -> sort -> render -> optional export，记录端到端耗时和峰值内存。

### 推荐数据规模

| 规模 | Mesh triangle | Gaussian count | Texture | 用途 |
|---|---:|---:|---|---|
| XS | 1k-10k | 10k-100k | 无或 1 张 1K | smoke test、调试 capture |
| S | 10k-100k | 100k-500k | 1-4 张 1K/2K | 日常回归、快速 benchmark |
| M | 100k-500k | 0.5M-2M | 多材质 2K | 常规性能基线 |
| L | 0.5M-2M | 2M-8M | 多材质 2K/4K | 压力测试、内存趋势 |
| XL | 2M+ | 8M+ | 多 4K 贴图 | 长稳和极限容量，不作为日常门禁 |

### 运行矩阵

- 分辨率：1280x720、1920x1080、2560x1440；如设备允许再加原生 Retina drawable scale。
- 相机：静止视角、固定轨道、近距离高 overdraw、快速移动。
- 模式：conversion only、sort only、render only、full pipeline。
- 输出：CSV/JSON 数据、简短 Markdown 摘要、必要时附 Metal capture 名称。

### 运行时机

- S 规模：每次性能相关 PR 或合并前运行。
- M 规模：每个阶段收敛后运行，作为正式基线。
- L 规模：资源管理、排序、渲染核心改动后运行。
- XL 规模：发布候选、内存策略重构、长稳排查时运行。

## Resource Memory Stats

### 统计对象

- vertex / index / material buffer。
- gaussian buffer、sort key/value buffer、temporary sort buffer。
- conversion counter / append buffer。
- uniform / constant / frame ring buffer。
- texture、sampler、depth/color render target。
- staging upload buffer、readback buffer、transient blit resource。
- future heap / buffer pool / texture pool 分配。

### 统计字段

- resource label、类型、用途、storage mode、hazard tracking mode。
- requested size、allocated size、resident size 或可近似统计的 committed size。
- 创建帧、释放帧、复用次数、峰值同时存在数量。
- load、conversion、sort、render、export 各阶段峰值。

### 风险信号

- 每帧创建和释放大 buffer / texture。
- temporary sort buffer 随相机或视口变化反复重建。
- readback buffer 与 GPU 写入 buffer 共享生命周期不清晰。
- drawable resize 后旧 render target 未及时释放。
- gaussian count 变化导致 buffer 抖动式扩容。

### 运行时机

- Metal resource wrapper 和 scene resource 管理稳定后开始接入。
- 新增资源类型或改变 buffer layout 后更新统计字段。
- 每次 L/XL 压力测试都记录内存峰值和运行结束后的资源回收状态。

## 避免 CPU-GPU Stall

### 重点排查点

- CPU 在每帧等待 command buffer 完成。
- 为了获取 gaussian count、排序状态或导出结果执行同步 readback。
- 复用仍被 GPU 使用的 frame buffer、counter buffer 或 staging buffer。
- 每帧重新创建 pipeline、depth target、大型 temporary buffer。
- 过早访问 shared buffer 中 GPU 尚未写完的数据。
- present、drawable acquisition 或窗口 resize 导致帧循环堵塞。

### 规避策略

- 使用多帧 ring buffer 管理 frame constants、counter、staging 和 readback。
- readback 采用异步 completion，UI 显示上一帧或上一任务结果。
- conversion count 等小数据也避免热路径同步等待，必要时延迟一帧消费。
- pipeline 和大资源提前创建或懒加载后缓存，benchmark 前预热。
- 将 upload、conversion、sort、render 的资源依赖通过 encoder 边界和清晰 ownership 表达，避免 CPU 侧硬等。
- 对导出路径单独建任务队列，不阻塞交互渲染帧。

### 验证方法

- CPU frame timing 中标记 wait 点和等待时长。
- Metal capture 中检查 command buffer 是否串行等待过长、是否有不必要 blit/readback。
- Instruments 或 Xcode GPU tools 中确认主线程没有周期性等待 GPU completion。
- 长稳测试观察 P99 和 max frame time 是否随时间恶化。

## 稳定性运行

- 快速稳定性：S 规模，固定相机路径，5 分钟。
- 常规稳定性：M 规模，交互相机和窗口 resize，15 分钟。
- 压力稳定性：L/XL 规模，转换、排序、渲染、导出循环，30-60 分钟。
- 资源稳定性：重复加载不同资产 20 次，检查内存峰值是否回落。
- 导出稳定性：连续 conversion -> export -> reload，检查数据一致性和 readback 阻塞。

## 构建与运行门禁

| 改动类型 | 需要构建 | 需要运行 | 需要 profiling |
|---|---|---|---|
| docs-only | 不要求构建 | 不要求运行 | 不要求 |
| Core/IO 数据结构 | `Mesh2SplatMetal`，相关 smoke test | XS/S load smoke | 如影响 gaussian layout，运行 frame timing |
| Metal resource 管理 | `Mesh2SplatMetal` | S full pipeline | memory stats + Metal capture |
| conversion shader/pass | `Mesh2SplatMetal` | XS/S conversion only + full pipeline | capture + counters + M benchmark |
| sort shader/pass | `Mesh2SplatMetal` | S/M sort only + camera path | counters + P95/P99 timing |
| gaussian render shader/pass | `Mesh2SplatMetal` | S/M render only + overdraw camera | capture + counters + resolution matrix |
| readback/export | `Mesh2SplatMetal` | conversion -> export -> reload | stall audit + memory stats |
| release candidate | clean `Mesh2SplatMetal` build | S/M/L full matrix + long run | counters + memory + stall summary |

## 记录模板

每次正式性能记录建议包含：

```text
Date:
Commit:
Machine:
macOS:
Build config:
Resolution:
Dataset:
Triangle count:
Gaussian count:
Scenario:
Warmup frames:
Measured frames:
CPU frame avg / P95 / P99:
GPU frame avg / P95 / P99:
Conversion GPU:
Sort GPU:
Render GPU:
Peak resource memory:
Readback stalls:
Capture / counters file:
Notes:
```

## 后续落地顺序

1. 先补齐 pass/resource labels 和轻量 CPU frame timing，保证日常开发能看到基本分段。
2. 接入 GPU timestamp 或等价 GPU timing，形成 conversion、sort、render 的稳定统计口径。
3. 为 XS/S/M 数据建立固定 benchmark 场景和相机路径。
4. 接入 resource memory stats，先覆盖显式 Metal buffer/texture，再扩展到 pool/heap。
5. 用 Metal capture 审核每个主 pass 的 encoder 顺序、资源依赖和不必要同步。
6. 在视觉正确后加入 GPU counters 基线，针对 conversion atomic、sort bandwidth、render overdraw 分别优化。
7. 最后补 L/XL 压力和长稳门禁，作为发布候选前的稳定性证据。
