# AACUseCases

通用约定见[仓库根 AGENTS.md](../../AGENTS.md)。

- `Sources/Health/SynchronizeHealthHistory.swift` 持有跨窗口共享的前台同步任务。同步按指标隔离失败，首轮完成前通过存储控制数据可见性。修改留存窗口时拦截旧批次。
- `SynchronizeHealthMetric` 在 HealthKit 与存储之间传递锚点批次，同一锚点使用固定查询范围。时间由本地日历计算，样本按测量结束时间使用左闭右开的区间。
- `Sources/Today/RefreshTodayHealth.swift` 只在显式连接操作中请求授权，在 MainActor 逐项提交仍适用于当前刷新身份的结果。首次从 Today 连接可一起请求睡眠和定量指标。已有定量授权时只在睡眠卡补充请求睡眠权限，Trends 与历史同步的授权检查仅覆盖五项定量指标。
- `ReadTodayHealth` 从已核对样本生成最近七天的指标和心率摘要。静息心率和 HRV 使用前 28 个完整本地日。持久化基线与当天比较分别计算。
- 修改刷新语义后运行 `AAAFeatures` 的 Today 测试。复用 `AppleHealthReading` 替身和 SwiftData 内存库，覆盖权限、空样本、部分失败、过期取消、留存和百分位。
