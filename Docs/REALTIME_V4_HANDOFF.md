# V4 实时功能接入说明

本变更基于 Draft PR #15 的 `d0147d738fb0bcfe6106458435d9ab781f59e263`，供接手团队通过独立 Draft PR 集成。应用最低支持 iOS 18 / watchOS 11。健康数字始终来自 HealthKit、Core Motion 或用户主动记录；界面不内置演示健康数据。

## 已加入的功能与入口

| 入口 | 实现 | 数据说明 |
|---|---|---|
| 今日、心脏 | 最近心率卡：测量时间、来源、本机查询时间及过期状态 | 新样本到达后更新；不承诺秒级采样 |
| 今日 | 此刻心情打卡与最近记录 | 用户自述；可选择写入 Apple 健康 `HKStateOfMind` 或只存本机受保护文件 |
| 今日 | 当前活动观察 | 用户主动开启期间由这台 iPhone 的 Core Motion 提供；本机步数与 HealthKit 跨设备日累计分开 |
| 压力 | 近期生理压力线索及原始样本时间 | 保留已有估算算法，读取新样本后重算；不推断情绪或疾病 |
| Apple Watch | 主动开始步行、跑步或其他训练，查看实时心率、时长，暂停、继续、结束并保存 | `HKWorkoutSession` + `HKLiveWorkoutBuilder`；结束与保存失败有单独状态 |

## 数据链路与文件

- `iOS/Services/HealthKitLiveUpdates.swift` 通过 `HKObserverQuery` 接收新样本事件，再用 `HKAnchoredObjectQuery` 对账并保存 anchor。后台通知要在应用启动时注册；后台频率受系统调度限制。删除样本后会重读该指标。
- `iOS/HealthIntelligenceApp.swift` 的 `UIApplicationDelegate` 在启动时建立订阅；前台恢复时补查。`HealthViewModel.readings[id]?.recordedAt` 是样本测量时间，`lastCheckedAtByMetric[id]` 是本机查询时间。日累计指标的 `recordedAt` 取最新参与样本的结束时间。
- `iOS/Services/MoodStore.swift` 实现用户主动心情记录，Apple 健康读写权限在需要时请求。本机记录放在 Application Support 并启用文件保护；本机历史可修改和删除。Apple 健康中的原样本由用户在健康 App 管理。
- `iOS/Services/LiveMotionStore.swift` 仅在用户按“开始观察”后订阅本机活动和步数，离开页面或 App 后台时停止。
- `Watch/WatchWorkoutManager.swift` 负责真实训练会话生命周期；`Watch/WatchWorkoutView.swift` 提供手表界面。训练未返回可确认的保存结果时，页面不会称“已保存”。
- `project.yml` 包含用途说明、Watch 配套 Bundle ID 与训练后台模式；`Configuration/iOS.entitlements` 包含 HealthKit Background Delivery。Muse 必须检查最终签名包中的 entitlement 与 Watch 训练后台模式。

## 接入与验收

1. 从本 PR 的精确 SHA 生成 Xcode 工程，运行 `cd Core && swift test`、iOS 与 Watch 模拟器无签名构建，以及 UI 截图测试。首次失败日志和实际 Xcode 版本要保留。
2. Muse 使用签名真机核对已有 Issue #3 的 HealthKit 授权崩溃。先验证授权、拒绝、无记录、部分授权，再测试后台投递、前台补查、Watch 未佩戴、手表断连、训练中途退出、训练保存失败。
3. 检查首页、心脏、压力和心情：旧样本重新查询后仍显示原测量时间；没有读数时显示空状态；本机活动停止后不继续标“步行中”；深浅色、大字号、VoiceOver 与减少动态效果可用。
4. 记录“测量→写入 HealthKit→App 显示”的实测时间分布及设备型号。Apple Watch 日间心率和跨设备同步不保证固定秒数。

## 下一批接入

- Watch 训练镜像至 iPhone，以及训练期间的锁屏 Live Activity。iOS 26+ 可评估 iPhone 独立训练会话与外部心率设备；iOS/watchOS 27+ 可接系统心率区间回调，需保留旧系统路径。
- 心情趋势与睡眠、活动并列观察；只展示关联，不写因果结论。
- 统一其余页面的样本过期状态与数据来源显示，并为小屏、深浅色和辅助功能字号补真实截图。
