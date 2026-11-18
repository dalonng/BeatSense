# AGENTS.md

本文件为 AI 编码助手提供 BeatSense 仓库的协作约定。默认使用中文沟通，代码符号沿用项目的英文命名。
协作原则迁移自 Vocsy；项目路径、命令和约束以 BeatSense 的实际工程配置为依据。

## 核心工程原则

1. **架构与领域优先**：计划阶段应以理想架构为目标，明确业务目标、领域边界、模块职责、依赖方向和数据流，形成符合领域规律、面向长期维护且可持续演进的设计后再进入编码；不得以短期实现便利牺牲整体设计。设计必须完整，实现应当克制：不做推测性抽象，抽象延迟到第二个真实用例出现时才引入，单一场景直接实现。
2. **追求优雅的代码模块**：模块应高内聚、低耦合，通过精简且稳定的接口封装内部复杂度，使职责、命名、依赖和扩展方式清晰自然；代码按单一职责拆分，单个文件不得超过 500 行，接近上限时应优先重构模块边界。
3. **保持边界与数据流清晰**：协议模型、领域模型、持久化模型和视图模型不得相互泄漏；数据必须在边界处完成校验和独立转换，避免跨层共享可变状态。
4. **安全与隔离默认开启**：所有功能均应明确系统权限与用户数据隔离边界；涉及多用户、多账号或多租户场景时，明确认证、授权和数据隔离边界；遵循最小权限原则，任何外部输入均视为不可信，敏感信息不得进入代码、日志或响应。
5. **面向并发与故障设计**：服务与异步任务应主动考虑幂等性、竞态、事务边界、超时、取消、重试、背压和资源释放；不得通过无边界重试、吞错或隐式共享状态掩盖问题。
6. **保障完整前端体验**：前端应控制渲染成本、异步状态和并发请求，保持清晰的 UI 结构；用户流程必须覆盖加载、空状态、错误、重试、反馈和可访问性。
7. **复用稳定的业务语义**：优先复用已有模块和能力，但不要仅因代码外形相似而过早抽象；确需重复时，必须注释说明其独立演进或暂不抽象的原因。新增依赖前先核查项目源码、Tuist 配置和 Apple 原生框架能否满足需求，不得臆断已有能力不足——先查阅文档和类型定义；确需引入时优先成熟且维护良好的库，不重复实现通用功能。
8. **为未来维护者保留上下文**：代码、注释、测试和架构文档是跨越时间的协作媒介。非显然的设计决策、兼容约束、已知缺陷和临时方案，必须记录原因、影响范围、潜在风险及移除条件；技术债务应关联可追踪任务，关键架构决策应同步到 ADR，禁止留下缺少上下文的 `TODO`。
9. **确保变更可验证、可观测、可回滚**：每项改动都应行为可测试、运行状态可观测、故障可定位，并兼顾向后兼容和回滚路径；错误与日志必须保留诊断上下文，但不得泄露敏感信息。
10. **删除优于兼容**：内部路径重构时直接删除过时实现，禁止新增兼容层、deprecated shim 或双写逻辑；对外契约（稳定 API、持久化数据格式、数据库迁移等）的兼容性按协议契约单独评估，属于合同义务而非迁就旧代码。

执行时同时遵守以下协作约定：

- 小改动直接实施；跨模块改动先说明涉及的入口、状态归属、数据流和验证方式。
- 修改本地 Swift Package 前，先读该包的 `AGENTS.md`（如存在）。跨包改动逐包读取。
- 控制变更范围，不顺手升级依赖、迁移架构或格式化整个仓库。保留工作区已有修改，不覆盖其他人的工作。
- 重要行为变化同步更新 README；首次产生需要长期保留的架构决策时再创建 `docs/adr/`，记录背景、决策、取舍和影响。
- 结论必须有验证依据。未运行的检查、环境阻塞和需要真机验证的项目应明确列出。

## 项目地图

- `BeatSense/` 负责 SwiftUI 应用装配与 App 资源。iPhone 与 iPad 共用一个 target，最低支持 iOS 27。
- 本地 Swift Package 位于 `AAA/`，包名前缀顺序即架构顺序。`AAAFeatures` 承载所有顶层业务 UI，包括根导航、业务页面和页面级 ViewModel。`AACUseCases` 存放所有业务用例，`AAGComponents` 存放不依赖 ViewModel 的业务视图组件。其余包职责见 [README](README.md#local-swift-packages)，架构决策见 [`docs/adr/`](docs/adr/)。
- 工程配置从 `Project.swift` 和 `Tuist/ProjectDescriptionHelpers/` 进入。使用 Xcode 27，Tuist 等工具版本以 `mise.toml` 为准。

## 工程与生成文件

- 修改 Tuist manifest、helper，或添加源码、资源后，重新生成工程并确认 target membership。
- 工程采用 Xcode JSON 格式，生成文件为 `BeatSense.xcodeproj/project.xcproj`。不直接编辑生成的 `.xcodeproj`、`.xcworkspace` 或 `Derived/`，这些文件不应提交。
- 应用源码与资源分别由 `BeatSense/Sources/**`、`BeatSense/Resources/**` 纳入 target；产品资源放在应用资源目录，不将设计参考目录整体加入构建。
- Info.plist 由 Tuist 默认配置扩展并结合构建设置生成；权限文案及元数据应在实际生成入口维护，不直接修改产物。
- AppIcon 名称为 `BeatSense`，与 `BeatSense.icon` 文件名对应。更换图标时检查生成工程、产物 Info.plist 和编译资源，避免重复图标输入。
- `AAODesignSystem.AppColors` 使用系统语义色。应用根 Tab 使用系统背景和系统蓝交互色，随系统外观调整。全局 `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` 显式为空，启用全局命名色前先添加对应颜色资产。
- 本机签名通过 Git 忽略的 `.env.local` 中的 `TUIST_DEVELOPMENT_TEAM` 配置，经 mise 注入 Tuist；修改后重新生成工程。模拟器构建不要求签名或该变量。
- 优先使用已有能力。新增依赖时修改相应工程配置，不直接修改生成工程，也不引入无关版本漂移。
- 本地包的源码、资源、产品和测试入口在各自 `Package.swift` 维护；应用级接线在 `AppPackages.swift` 维护，不把包源码直接纳入 App target 的 sources glob。
- 保持本地包依赖无环。空壳 Swift Package 仅保留必要依赖和至少一个可编译的 `.swift` 源文件，占位声明使用 `private`。
- 当前只使用本地 Swift Package。引入远程依赖时，维护 `.package.resolved` 中的版本。各包的 `.build/`、`.swiftpm/` 和用户状态不提交。
- 迁入的服务不会自行成为产品功能。没有配置后端、App Store ID 或遥测 endpoint 时不得回退到 Vocsy、Holovita 等其他产品的配置。

## 开发与验证

从仓库根目录运行以下命令；已激活 mise 时可直接使用 `just`：

```sh
./Scripts/setup.sh          # 安装固定版本工具并生成工程
mise exec -- just --list    # 查看当前实际支持的命令
mise exec -- just generate  # 生成工程，不自动打开 Xcode
mise exec -- just open      # 生成并打开 BeatSense.xcworkspace
mise exec -- just verify    # 确认 project.xcproj 存在且 Xcode 可读取工程
mise exec -- just build     # 先格式化、再生成并构建无签名 Simulator Debug 版本
mise exec -- just lint      # 使用 .swiftlint.yml 检查
mise exec -- just format    # 原地格式化应用、AAA 本地包与 Tuist 配置
```

- `just verify` 执行工程存在性检查和 `xcodebuild -list`，不检查 Swift 编译，也不执行 plist 语法检查，不能代替 `just build`。
- `just build` 依赖会写文件的 `format`。存在无关工作区修改时，先检查格式化范围；需要只读验证时先运行局部 lint，再执行 `justfile` 中的生成与构建命令。
- 构建目标为 `generic/platform=iOS Simulator`，默认 DerivedData 为 `Derived/Build`。构建成功只证明编译与打包，不代表模拟器交互、真机行为或图标外观通过验收。
- 构建前的 `Check Swift Formatting and Lint` 脚本在 sandbox 中只读执行 SwiftFormat、SwiftLint；任一检查失败都会阻止编译，不要通过关闭 sandbox 或检查步骤绕过问题。
- 局部格式化使用 `.swiftformat`，例如 `mise exec -- swiftformat <file.swift> --config .swiftformat --cache ignore`；只读检查增加 `--lint`，避免产生无关差异。
- `AAMServices`、`AAMStorages` 和 `AAAFeatures` 提供 Swift Package 的 Swift Testing 测试入口。App target 目前没有独立测试 target。
- `just format` 与 `just lint` 覆盖应用、`AAA/` 本地包与 Tuist 配置，跳过 SwiftPM 的 `.build/` 和 `.swiftpm/`。App 构建阶段的只读检查覆盖应用和 Tuist 配置。改包时按修改范围验证包的构建或测试。
- Swift 代码改动检查格式、lint 并构建；工程配置或资源改动额外检查生成结果与实际打包。根据行为变化选择模拟器或真机验证。
- 验证时优先复用现有模拟器或使用可用的真机。确需新建模拟器时，先征得用户同意。
- 纯文档修改检查路径、命令和内容一致性即可，无需为此构建应用。

## 健康数据与隐私

- HealthKit 只读接入心率、静息心率、血氧、呼吸频率、HRV 和睡眠分析。Today 的睡眠时长、时段和各阶段用时由可见睡眠片段即时计算。不得在文档、界面或验收结论中将占位页面描述为已有数据能力。
- 接入健康数据时同时检查 target capability、entitlement、系统权限文案和授权流程，只请求功能实际需要的数据类型。
- 缺少健康样本、权限受限、设备不支持与查询失败应按实际可辨识状态处理；不要把无数据直接解释为用户拒绝授权，也不要用虚构样本填充生产流程。
- 查询、聚合与持久化应有明确的数据边界，处理时间范围、时区、单位和缺失值；耗时工作不阻塞主线程，异步结果在任务取消或页面状态变化后不得回写过期状态。
- 健康样本、推导结果和用户身份信息均按敏感数据处理；未经明确产品需求，不引入上传、外部分析或额外数据留存。
- 涉及系统授权与真实健康样本的行为需要适当设备验收；模拟器构建不能替代真实数据验证。

## 本地化与界面

- 业务界面文案维护在所属 UI 包的 `Resources/Localizable.xcstrings`。页面与导航文案归 `AAAFeatures`，组件专用文案归 `AAGComponents`。SwiftUI 使用 Xcode 生成的 `LocalizedStringResource` 符号，生成符号绑定各包的 `Bundle.module`。
- 需要 `String` 时使用 `String(localized: .key)`。新增支持语言时，同步更新 `AppSettings.localizations`，供 App 的 `CFBundleLocalizations` 与 Xcode 已知地区使用。
- 本地化符号在编译时自动生成，不提交生成源码，不维护自定义本地化生成器。
- 当前文案覆盖 en、de、es、fr、ja、zh-Hans；新增文案检查相应语言，保持 key 的业务语义与译文一致。
- 使用系统应用语言，不自行增加 App 内语言覆盖；语言变化不能通过强制重建根视图丢弃业务状态。
- 新界面延续现有 SwiftUI 结构和配色约定，验证动态字体、VoiceOver 标签、加载与错误反馈，以及不同语言和 iPhone、iPad 布局。

## Swift、数据与并发

- 使用 Xcode 27 随附的 Swift 6.4 工具链。本地 Swift Package 统一声明 `swift-tools-version: 6.4`。App target 保持 `SWIFT_VERSION = 6.0`（Swift 6 语言模式），启用 approachable concurrency 与默认 `MainActor` 隔离。`.swiftformat` 的版本设置用于格式化解析。
- 应用和本地 Swift Package 不使用 Combine 框架及其 API，包括通过 SwiftUI 等模块访问的 `Publisher`、`@Published` 和 `AnyCancellable`。界面状态使用 Swift Observation 和 SwiftUI 状态属性。系统通知优先使用 Foundation 的类型化 `NotificationCenter` 消息，异步事件流使用 `AsyncSequence`。
- 使用结构化控制流。用 `guard` 提前处理边界条件，用枚举表达互斥状态并通过 `switch` 处理，保持错误与副作用的执行路径清晰可追踪。
- 默认使用结构化并发。顺序操作直接 `await`，固定数量的独立操作用 `async let`，动态并行用 `withTaskGroup` 或 `withThrowingTaskGroup` 并控制并发规模。页面任务优先由 SwiftUI 的 `.task` 或 `.task(id:)` 持有。
- 延续相邻文件的 Swift 命名和组织方式，优先使用现代 Apple 框架与 Swift 6 并发能力。
- 结合默认 MainActor 隔离明确 UI 状态与后台计算的归属；共享可变状态应有明确所有者，异步函数不天然代表后台执行。
- 创建非结构化任务时明确任务持有者、取消时机和错误处理。使用 `Task.detached` 时说明所需的隔离边界及取消方式。禁止用 `@unchecked Sendable`、`nonisolated(unsafe)` 或静默吞错掩盖生命周期和并发问题。
- 调整持久化结构时考虑已有安装中的数据与迁移，不能以清空用户数据或设置作为默认修复手段。
- 诊断日志只记录必要上下文，不输出健康样本、个人信息、密钥或其他敏感内容；需要日志时优先使用系统 `Logger`。
- `.env.local`、签名材料和发布凭据不写入代码、文档、测试样本或提交内容。

## 交付约定

- 结束前检查 diff，确认只包含任务所需变更，并保持用户原有修改完整。
- 测试失败应说明具体命令、原因及影响；不要把未完成检查写成通过，也不要扩大修改范围来掩盖无关问题。
- 最终回复简述修改文件、核心变更、验证结果及仍需真机或环境验证的内容。
- 未经用户要求不创建 commit、推送或上传构建；若要求提交，使用明确描述变更意图的提交信息。
- 本文件名为 `AGENTS.md`，作为仓库根目录的协作指引维护。
