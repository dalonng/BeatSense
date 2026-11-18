# AAMStorages

通用约定见[仓库根 AGENTS.md](../../AGENTS.md)。健康历史入口位于 `Sources/HealthHistory/`。

- `HealthHistoryStore` 负责保护目录及延迟打开数据库。文件排除备份，使用完整文件保护并关闭 CloudKit。
- `HealthHistoryDatabase` 串行提交样本、删除和 anchor，核对同步代次和已有 anchor。每个指标完整核对后才开放读取。取消或保存失败回滚当前批次。
- `HealthHistorySchemaV1` 定义磁盘模型。查询按样本结束时间及稳定身份排序。基线保存校验同步代次和样本版本，领域值从持久化模型独立转换。
- 变更 schema 时保持已有数据库可打开。旧 Today 快照由 HealthKit 重新回填，首轮核对通过后清退快照目录。见 [健康样本与个人基线](../../docs/adr/0003-health-history-and-personal-baselines.md)。
- 使用 iOS 模拟器测试写入、回滚、清理和重开。改存储路径或保护选项时在真机验证锁屏和解锁后的恢复。
