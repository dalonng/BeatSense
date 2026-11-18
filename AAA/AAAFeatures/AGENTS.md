# AAAFeatures

本文件适用于 `AAA/AAAFeatures/`。通用工程与验证约定见[仓库根 AGENTS.md](../../AGENTS.md)。

## 入口与依赖

- 本包承载所有顶层业务 UI。`Sources/` 下的 `App/`、`Today/`、`Trends/` 各自包含 `Screen/` 和 `ViewModel/`，分别存放本模块的页面和页面级 ViewModel。根 Tab 由 `App/Screen/AppScreen.swift` 管理。共享服务与同步协调器由 App 入口创建，经 `AppScreen` 注入。
- 业务用例归 `AACUseCases`，不依赖 ViewModel 的业务视图组件归 `AAGComponents`。
- Today 通过 `AACUseCases.RefreshTodayHealth` 接收刷新结果，转换为页面状态。App 入口共享的 `AppleHealthReading` 和 `SynchronizeHealthHistory` 由 `AppScreen` 注入用例。
- 页面与导航文案放在本包的 `Resources/Localizable.xcstrings`，使用 Xcode 为 `Bundle.module` 生成的 `LocalizedStringResource` 符号。组件专用译文随组件维护，权限用途文案维护在 App target 的 `InfoPlist.xcstrings`。

## Today

- `TodayViewModel` 在 `MainActor` 上管理页面状态和刷新 ID，`TodayScreen` 通过 `.task(id:)` 持有加载任务。用例逐项回传结果，通过刷新身份和任务取消状态保护界面。每个指标的详情按需读取当前本地日的已核对样本。即使首页摘要相同，详情也随该指标的新一轮同步更新。
- 系统授权请求由用户点击连接触发。独立呈现各指标的空样本与查询失败，单项失败时仍展示其他指标。静息心率和 HRV 共用卡片，各自展示个人基线状态，并保留独立的刷新状态。界面消费已核对的健康样本，应用重新激活时重新验证。Today 的设置保存健康历史保留天数。见 [健康样本与个人基线](../../docs/adr/0003-health-history-and-personal-baselines.md)。

## 验证

- 修改 Today 状态流时，在现有 iOS 模拟器上运行 `AAAFeatures` 包的 Swift Testing suite。直接用 `xcodebuild` 跑包测试时，传入 `STRING_CATALOG_GENERATE_SYMBOLS=YES`。测试复用 `AppleHealthReading` 替身和 `HealthHistoryStore(inMemory: true)`，重点覆盖显式授权、空样本、部分失败和取消后的状态。
- 系统授权和真实样本行为按 [README 的真机验证步骤](../../README.md#verify-apple-health-on-a-device)验收。
