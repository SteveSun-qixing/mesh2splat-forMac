# SwiftUI 前端接入架构设计

本文档描述未来 SwiftUI 前端如何接入当前 macOS Metal 运行时。目标是在不破坏现有 `AppKit + MTKView + RendererInterface` 边界的前提下，把菜单、文件打开、参数面板和状态展示迁移到 SwiftUI，同时继续让 C++/Objective-C++ renderer 独占 Metal 资源和渲染循环。

## 当前事实

当前 macOS 入口位于 `src/app/macos`：

- `MacApp.mm` 创建 `NSApplication`、主菜单、`NSWindow`，并把 `Mesh2SplatMetalView` 放入窗口 content view。
- `MetalView.hpp/.mm` 定义 `Mesh2SplatMetalView : MTKView`。
- `Mesh2SplatMetalView` 负责 Metal view 配置、输入事件、菜单 action、打开文件面板、窗口标题刷新。
- `Mesh2SplatMetalViewDelegate : NSObject <MTKViewDelegate>` 持有 `std::unique_ptr<mesh2splat::renderer::Renderer>`。
- `RendererInterface.hpp` 是 App 层与 renderer 的主要边界，提供 `initialize`、`loadMeshFile`、`resize`、参数设置、状态查询、`draw`。

当前调用链如下：

```text
NSApplication / NSWindow
  -> Mesh2SplatMetalView : MTKView
      -> Mesh2SplatMetalViewDelegate : MTKViewDelegate
          -> mesh2splat::renderer::Renderer
              -> MetalRenderer
                  -> Metal passes / buffers / command scheduler
```

未来 SwiftUI 不应直接调用 `MetalRenderer`、Metal pass、buffer 或 shader cache，而是继续站在 `RendererInterface` 之上。

## 目标分层

SwiftUI 接入后建议形成四层：

```text
SwiftUI Views
  参数面板、工具栏、文件命令、状态 HUD、布局

Swift App Model
  ObservableObject / @MainActor ViewModel，持有前端状态快照和用户命令

Objective-C++ Bridge
  NSView/MTKView host，拥有 C++ Renderer，转换 Swift 类型和 C++ 类型

C++ Renderer
  RendererInterface + MetalRenderer，拥有 Metal 资源、渲染和转换任务
```

职责边界：

| 层 | 拥有什么 | 不应做什么 |
|---|---|---|
| SwiftUI Views | 布局、按钮、菜单、绑定控件 | 不持有 C++ 指针，不接触 Metal command buffer |
| Swift App Model | 可观察状态、用户命令、错误提示、文件 URL | 不直接 include C++ 头，不在 `body` 内触发 renderer 副作用 |
| ObjC++ Bridge | `MTKView`、`Renderer` 生命周期、输入转换、状态快照 | 不承担复杂 UI 布局，不把 SwiftUI 状态塞入 renderer 内部 |
| C++ Renderer | GPU 资源、转换、排序、绘制、统计 | 不依赖 SwiftUI/AppKit UI 控件 |

## 推荐组件

### `Mesh2SplatApp`

SwiftUI `App` 入口，替代当前手写 `NSApplicationDelegate` 主入口。它负责创建主窗口、菜单命令和共享 model：

```swift
@main
struct Mesh2SplatApp: App {
    @StateObject private var documentModel = Mesh2SplatDocumentModel()

    var body: some Scene {
        WindowGroup {
            MainContentView(model: documentModel)
        }
        .commands {
            Mesh2SplatCommands(model: documentModel)
        }
    }
}
```

短期迁移时也可以保留现有 `MacApp.mm`，只把窗口 content view 替换为 `NSHostingView(rootView:)`。这适合渐进集成，但最终建议由 SwiftUI `App` 管理窗口和 commands。

### `MetalViewportRepresentable`

SwiftUI 使用 `NSViewRepresentable` 包装现有 `MTKView`：

```swift
struct MetalViewportRepresentable: NSViewRepresentable {
    @ObservedObject var model: Mesh2SplatDocumentModel

    func makeNSView(context: Context) -> Mesh2SplatRendererView {
        let view = Mesh2SplatRendererView(frame: .zero)
        model.attachRendererHost(view.rendererHost)
        return view
    }

    func updateNSView(_ nsView: Mesh2SplatRendererView, context: Context) {
        nsView.rendererHost.apply(model.pendingRendererCommands())
    }

    static func dismantleNSView(_ nsView: Mesh2SplatRendererView, coordinator: Coordinator) {
        nsView.rendererHost.shutdown()
    }
}
```

这里的 `Mesh2SplatRendererView` 可以先由当前 `Mesh2SplatMetalView` 演进而来，但建议逐步移除菜单 action 和文件面板职责，只保留：

- `MTKView` 初始化和 pixel format 配置。
- `MTKViewDelegate` 回调转发。
- mouse/keyboard/scroll 输入采集。
- first responder 管理。
- 对外暴露一个稳定的 `rendererHost` 对象。

`updateNSView` 不能每次 SwiftUI body 刷新都无条件重设 renderer 参数；应使用 model 中的命令队列或 dirty flags，只发送真正变化的参数。

### `RendererHost`

`RendererHost` 是 Objective-C++ 层对象，替代当前内嵌在 `MetalView.mm` 中的 view delegate 作为长期桥接点。它持有 `std::unique_ptr<Renderer>`，并以 Objective-C/Swift 可调用方法暴露能力：

```objc
@interface Mesh2SplatRendererHost : NSObject <MTKViewDelegate>
- (instancetype)initWithMTKView:(MTKView*)view;
- (BOOL)loadMeshAtURL:(NSURL*)url error:(NSError**)error;
- (void)setViewMode:(NSInteger)viewMode;
- (void)setGaussianVisualizationMode:(NSInteger)mode;
- (void)setGaussianScale:(float)scale;
- (BOOL)setConversionSamplesPerTriangle:(uint32_t)samples error:(NSError**)error;
- (Mesh2SplatRendererSnapshot*)snapshot;
- (void)shutdown;
@end
```

命名上可以使用 Objective-C 类对 Swift 暴露；内部实现文件保持 `.mm`，可以 include `RendererInterface.hpp`。Swift 只看 Objective-C header，不直接看 C++。

### `Mesh2SplatDocumentModel`

SwiftUI model 是 `@MainActor ObservableObject`，负责 UI 可观察状态：

```swift
@MainActor
final class Mesh2SplatDocumentModel: ObservableObject {
    @Published var loadedFileURL: URL?
    @Published var viewMode: RenderViewMode = .combined
    @Published var gaussianScale: Float = 1.0
    @Published var conversionQuality: ConversionQuality = .x4
    @Published var isConverting = false
    @Published var gaussianCount: UInt32 = 0
    @Published var diagnostics: String = ""
    @Published var stats = RendererStatsSnapshot()
}
```

Model 保存的是“前端状态快照”，不是 renderer 的真实所有权。真实所有权仍在 `RendererHost`。SwiftUI 控件修改 model 后，由 model 或 representable coordinator 把变化转换为 bridge 命令。

## 文件打开

推荐由 SwiftUI commands 或 toolbar 触发文件选择：

1. 用户点击 Open 或按 `Command-O`。
2. SwiftUI model 调用 `NSOpenPanel`，限制 `.glb`、`.gltf`。
3. 用户选择文件后，model 调用 `rendererHost.loadMeshAtURL`。
4. bridge 内部调用 `Renderer::loadMeshFile(url.path)`。
5. load 成功表示 CPU 解析和 GPU 上传已完成，conversion command 已提交或已进入 fallback mesh-only 状态。
6. 后续 `draw` 中的 `finalizePendingConversion` 会收割异步 conversion 结果，状态快照再反馈给 SwiftUI。

状态语义建议：

- `loadMeshAtURL` 返回 `true`：文件已被 renderer 接受，UI 可显示文件名。
- `isConverting == true`：gaussian conversion 仍在 GPU 上进行，UI 显示进度不确定的 activity indicator。
- `convertedGaussianCount > 0`：gaussian 输出可用。
- `lastDiagnostic` 非空：显示在 diagnostics 面板或 alert 中，但不要阻塞渲染。

短期可以复用当前 `NSOpenPanel` 逻辑；迁移后文件面板应从 `MTKView` 移到 SwiftUI command/model，避免 view 既处理输入又处理文档工作流。

## 参数控制

SwiftUI 参数面板应该映射到 `RendererInterface` 当前已有 API：

| UI 控件 | Swift 状态 | Renderer API | 备注 |
|---|---|---|---|
| View mode segmented control | `.combined/.mesh/.gaussians` | `setViewMode` / `viewMode` | 对应当前快捷键 `1/2/3` |
| Gaussian visualization picker | `.final/.albedo/.depth/...` | `setGaussianVisualizationMode` | 当前 renderer 已有接口，AppKit UI 尚未暴露 |
| Gaussian scale slider/stepper | `0.1...8.0` | `setGaussianScale` / `gaussianScale` | renderer 内部已 clamp 到 `[0.1, 8.0]` |
| Conversion quality segmented control | `1x/4x/9x` | `setConversionSamplesPerTriangle` | renderer 会 normalize 到 `1/4/9` |
| Stats panel | `RendererStatsSnapshot` | `rendererStats` | 建议低频采样，避免每帧触发 SwiftUI 全量刷新 |

参数发送策略：

- 离散控件变化时立即发送命令。
- slider 拖动可以更新 SwiftUI 本地值，但对 renderer 做 debounce 或只在 editing ended 时提交，除非实时反馈确实需要。
- conversion quality 会触发重新转换，UI 应在调用成功后进入 converting 状态。
- 若 `setConversionSamplesPerTriangle` 返回 false，model 应恢复上一个 UI 值并展示错误。

不要让 SwiftUI 控件直接在 `body` 中调用 bridge 方法。所有副作用应放在 button action、`onChange`、commands handler 或 model 方法中。

## 状态观察

`RendererInterface` 目前是 pull model：前端调用 `rendererStats()`、`lastDiagnostic()`、`loadedMeshPath()`、`isConvertingGaussians()`、`convertedGaussianCount()` 获得状态。因此 SwiftUI 也建议先采用“低频拉取快照”，而不是把 renderer 改造成回调发布者。

推荐实现：

- `RendererHost.snapshot()` 返回不可变 Objective-C snapshot 对象。
- `Mesh2SplatDocumentModel` 使用 `Timer`、`Task` 或 display-linked tick 每 5-10 Hz 拉取一次 snapshot。
- `drawInMTKView` 后也可以通知 host 标记 snapshot dirty，但 SwiftUI 发布仍回到主线程。
- 只有值发生变化时才更新 `@Published`，减少 SwiftUI 重绘。

Snapshot 建议包含：

```text
loadedFileURL / loadedPath
viewMode
gaussianVisualizationMode
gaussianScale
conversionSamplesPerTriangle
isConverting
convertedGaussianCount
lastDiagnostic
RendererStats
```

`RendererStats` 已经在 C++ 内部用 mutex 保护 timing state；但 `loadedMeshPath`、`lastDiagnostic`、`viewMode` 等普通字段当前没有跨线程保护。因此第一版 SwiftUI bridge 应约定所有 renderer API，包括 snapshot 读取，都在主线程或同一 serial queue 调用。

## 线程与渲染循环

当前 `MTKView` 配置为：

- `preferredFramesPerSecond = 60`
- `enableSetNeedsDisplay = NO`
- `paused = NO`
- `framebufferOnly = YES`

`MTKViewDelegate.drawInMTKView` 每帧调用：

```text
currentDrawable/currentRenderPassDescriptor
  -> Renderer::draw(descriptor, drawable, inputState, deltaTime)
  -> InputState.beginFrame()
```

`MetalRenderer::draw` 内部会：

- 等待 frame semaphore。
- `beginFrame` 并收割 pending conversion。
- 用 `InputState` 更新 camera。
- 更新 frame uniform。
- 需要时提交 gaussian sort。
- 编码 mesh/gaussian render pass。
- `presentDrawable` 并 commit command buffer。
- command buffer completed handler 中记录 stats 并释放 frame semaphore。

SwiftUI 不应替代这条渲染循环。SwiftUI 的职责是嵌入 `MTKView`，并在用户参数变化时向 bridge 投递命令。

线程规则建议：

1. Renderer 对象只在 `RendererHost` 内创建和销毁。
2. `RendererHost` 默认绑定主线程；`MTKViewDelegate`、输入事件和 SwiftUI command 都走主线程。
3. GPU conversion completion handler 可以在 Metal 回调线程执行，但只写入 `PendingGaussianConversion` 的 atomic 字段；真正替换 scene/gaussian buffer 仍在下一次 `draw` 的 `finalizePendingConversion` 中发生。
4. 如果未来需要后台解析大文件，应把 CPU 解析结果封装为 command，再回到 renderer queue 上传 Metal 资源；不要从后台线程直接调用 `Renderer::loadMeshFile`，除非 renderer 明确加锁并声明线程安全。
5. SwiftUI `@Published` 更新必须回到 `MainActor`。

这种约束牺牲了一点并发灵活性，但能保持 renderer 状态和 `InputState` 简单可靠。

## 输入事件

当前 camera 输入依赖 `core::InputState`：

- key down/up 写入 `keysDown`。
- mouse down/up 写入 `mouseButtonsDown`。
- mouse move/drag 累计 `mouseDeltaX/Y`。
- scroll 累计 `scrollDeltaX/Y`。
- 每帧绘制后调用 `beginFrame()` 清空 delta。

SwiftUI 的 `NSViewRepresentable` 不应把鼠标拖拽改成 SwiftUI gesture 后再翻译给 renderer，因为 SwiftUI gesture 的事件节奏和 responder 行为会影响相机控制。建议保留 `MTKView` 子类处理 `NSEvent`，并继续维护 `InputState`。

迁移时应把当前快捷键一分为二：

- App command 快捷键：`Command-O`、菜单 view mode、质量切换，由 SwiftUI commands 处理。
- Viewport 输入：相机移动、鼠标拖拽、滚轮，由 `MTKView` 处理并写入 `InputState`。

当 `MTKView` 进入窗口后仍应调用 `makeFirstResponder`，否则键盘相机输入可能被 SwiftUI 控件截获。参数面板中的文本框、slider 等获得焦点时，应允许它们正常接收输入；viewport 点击后再恢复 first responder。

## 与 C++ renderer 的边界

SwiftUI 只能依赖 Objective-C/Swift-friendly API。C++ renderer 边界保持在以下位置：

```text
Swift
  -> Objective-C header
      -> Objective-C++ implementation (.mm)
          -> RendererInterface.hpp
              -> MetalRenderer
```

Bridge 需要做的类型转换：

| Swift/ObjC 类型 | C++ 类型 |
|---|---|
| `URL` / `NSURL` | `std::string filePath` |
| Swift enum raw value / `NSInteger` | `RenderViewMode`、`GaussianVisualizationMode` |
| `Float` | `float` |
| `UInt32` | `uint32_t` |
| snapshot object | `RendererStats` + renderer getters |
| `NSError**` | `false` + `lastDiagnostic` 或 bridge 自定义错误 |

Bridge 不应暴露：

- `id<MTLCommandBuffer>`、`MTLRenderPassDescriptor`、`CAMetalDrawable` 给 SwiftUI。
- `MetalRenderer` 具体类。
- `MetalSceneResources`、`MetalGaussianBuffer`、pipeline cache 等后端资源。
- 可变 C++ 引用或裸指针。

建议未来把当前 `Mesh2SplatMetalViewDelegate` 中的 renderer 操作提取成独立 host，这样 `MTKView` 只是 host 的渲染表面，而 SwiftUI model 可以安全地持有 host 的 Objective-C 引用。

## 错误与诊断

当前 renderer 使用 `bool` 返回值和 `lastDiagnostic()` 传递错误。SwiftUI 接入时建议统一为：

- Bridge 方法返回 `Bool`。
- 失败时填充 `NSError`，message 来源优先使用 `lastDiagnostic()`，其次使用 bridge 自己的上下文。
- Model 把错误写入 `@Published var diagnostics`，同时按需弹 alert。
- Renderer stats 作为常驻诊断面板，不要放在窗口标题中作为唯一状态。

窗口标题可以由 SwiftUI 使用 loaded file name 和 view mode 生成；renderer status title 不再由 `MTKView` 直接设置。

## 迁移步骤

1. 新增 Objective-C++ `RendererHost`，把当前 `Mesh2SplatMetalViewDelegate` 的 renderer 生命周期和参数方法迁入 host。
2. 精简 `Mesh2SplatMetalView`，保留 `MTKView` 配置、输入事件和 first responder。
3. 增加 Swift `NSViewRepresentable` 包装 `Mesh2SplatMetalView`。
4. 增加 `ObservableObject` model，先接入打开文件、view mode、gaussian scale、conversion quality。
5. 增加 snapshot 拉取，把 gaussian count、conversion 状态、stats、diagnostics 显示到 SwiftUI。
6. 把现有 AppKit 菜单 action 迁移到 SwiftUI commands。
7. 最后将 `MacApp.mm` 入口替换为 SwiftUI `App`，或只保留极薄的 `NSHostingView` 启动桥。

每一步都应保持 `Mesh2SplatMetal` 能启动、加载 `.glb/.gltf`、渲染 preview/mesh/gaussians，并且不要求 renderer 知道 SwiftUI 的存在。

## 开放问题

- 是否需要多窗口或多文档。如果需要，每个窗口必须拥有独立 `RendererHost`、`MTKView` 和 renderer 实例。
- 大文件解析是否要异步化。当前 `loadMeshFile` 同步解析并上传资源，然后提交 conversion；UI 可能短暂阻塞。
- 是否要把 `lastDiagnostic` 改成结构化事件日志。SwiftUI 面板更适合展示多条 timestamped diagnostics。
- 是否要新增 renderer command queue。如果未来允许后台线程驱动 renderer，需要在 `RendererInterface` 层明确线程安全策略。

## 接受标准

SwiftUI 接入实现完成时应满足：

- SwiftUI 代码不 include C++ header。
- SwiftUI 代码不接触 Metal command buffer、render pass descriptor、drawable。
- `RendererInterface` 仍是 App 层与 renderer 的唯一 C++ 边界。
- 文件打开、参数控制、状态展示都通过 `RendererHost` 和 snapshot 完成。
- 渲染循环仍由 `MTKViewDelegate.drawInMTKView` 驱动。
- `InputState.beginFrame()` 仍在每帧 draw 之后调用，鼠标/滚轮 delta 不跨帧累积。
- renderer 资源创建、替换和销毁不发生在 SwiftUI `body` 更新期间。
