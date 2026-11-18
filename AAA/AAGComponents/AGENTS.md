# AAGComponents

通用约定见[仓库根 AGENTS.md](../../AGENTS.md)。

## 组件边界

- 组件放在 `Sources/<Feature>/`，由调用方注入领域值、文案或视图内容。Today 指标行合并标题、时间和数值供 VoiceOver 朗读，Feature 持有整行导航。组件保持独立于 Feature、ViewModel 和用例。
- 组件专用文案维护在本包的 `Resources/Localizable.xcstrings`，通过本包 `Bundle.module` 的生成符号读取。指标行标题和通用空状态由调用方传入 `LocalizedStringResource`，沿用调用方的资源归属。
- Today 指标图表显示调用方传入的时间区间及实际测量点。全天档按本地日历标出时刻，小时档按实际经过的时间等距标记，一小时档每 15 分钟一个刻度。辅助字号减少横轴标签，各数据点仍播报测量时间和指标单位。血氧按百分比显示。首页心率分布保留可朗读的区间与占比，进度条隐藏于无障碍树以避免重复播报。

## 验证

- 修改文案或资源后构建 `BeatSense`，核对 `AAGComponents_AAGComponents.bundle` 中的六种译文。修改指标行或图表时，在 Today 验证各指标详情导航、空样本与单点图表，以及 VoiceOver 的时间与数值朗读。
