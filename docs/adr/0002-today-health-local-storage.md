# 0002 Today 使用 SwiftData 保存最新快照

> HealthKit 读取和存储的当前实现见 [健康样本与个人基线](0003-health-history-and-personal-baselines.md)。本文保留原方案背景。

## 决策

- Today 完成实时查询后，将本次可见的最新血氧、呼吸频率、静息心率、HRV 和心率摘要组成一个值类型快照。心率摘要沿用已有抽样时间线和分布，原始心率序列不落盘。
- App 为各窗口注入同一个 `TodayHealthStore`。存储包延迟打开数据库，在 SwiftData 的 model actor 内显式提交单条快照。刷新按开始时的单调时钟排序，旧请求无法恢复已被新请求替换或清除的结果。
- 每次刷新整体替换上一份快照。无可见数据或无法完成授权检查时删除记录。Today 展示实时查询结果，因此撤回某项权限后，下一次刷新不会回显旧值。存储错误由日志记录错误码，之后的刷新会再次尝试。
- SQLite 放在应用沙盒的专用 Application Support 子目录，目录设置完整文件保护并排除备份。SwiftData 显式关闭 CloudKit。[Apple 健康数据审核指南](https://developer.apple.com/app-store/review/guidelines/#health-and-health-research)

## 取舍与迁移

快照整体读写，无需在数据库内按单个测量值查询。V1 使用一个 SwiftData 记录和独立的 Codable 持久化格式，保持领域模型与磁盘格式独立。趋势或历史留存需要单独的数据模型与留存范围。

现有安装此前只有内存数据，首次开启存储时创建 V1 schema。后续修改 schema 或快照编码时保留 V1 定义并迁移，存储初始化失败时保留磁盘内容。

V2 快照在原 JSON 顶层追加可选的静息心率字段。V2 读取旧快照时将缺失字段解码为空，下一次刷新按 V2 写入。V1 读取器可忽略这个字段。SwiftData 继续使用原 schema。

## 验证

包测试覆盖落盘后重新打开、部分结果替换、清空和旧刷新乱序。Today 测试覆盖部分查询失败和取消。实际 HealthKit 读取、权限撤回和锁屏文件保护需在签名真机上验收。
