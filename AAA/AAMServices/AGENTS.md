# AAMServices

通用约定见[仓库根 AGENTS.md](../../AGENTS.md)。HealthKit 适配器位于 `Sources/AppleHealth/`。

- `AppleHealthClient` 持有 App 共享的 `HKHealthStore`。查询、单位换算、锚点归档和系统错误映射留在本包，`AppleHealthReading` 返回 `AANModels` 值类型。
- 授权按 `AppleHealthReadScope` 分为测量、睡眠和全部读取，`toShare` 为空。多窗口请求复用已覆盖所需类型的授权面板，范围不同时等待面板关闭再检查剩余请求。系统授权请求结束后由实际查询结果决定数据可见性。
- Anchored 查询按指标和固定查询下界分页，携带新增的父 UUID、删除 UUID 和下一个锚点。心率与其他多值序列保留每个测量项的时间区间。留存边界由调用方应用。
- Today 睡眠按调用方传入的时间窗口直接查询 `sleepAnalysis`。跨界样本保留原始起止，并区分未分期睡眠、核心睡眠、深度睡眠、REM 和清醒。过滤卧床记录，来源标识不离开服务边界。窗口归属与阶段重叠处理由 Today 用例负责。
- 改查询、单位或授权类型后运行 `AAMServices` 包测试。真机验收包含时间限制、撤回读取权限和合并心率样本。见 [README](../../README.md#verify-apple-health-on-a-device)。
