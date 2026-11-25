# 健康中枢 Pro 研发交接 · 2026-11-25

## 版本与发布状态

工程版本为 2.0.0（Build 20）。核对时 GitHub `main` 为 `5468011281f46c897e8315245fb4a56a9a15be47`。本轮睡眠修复源码提交为 `65a44bb0bfb3b864d13e721eac56661c75d72e78`，已推送至 `codex/p0-sleep-session`。交接文档另行提交。没有合并现有草稿或向 main 推送。[基线](https://github.com/zsh199410/health-intelligence-pro/commit/5468011281f46c897e8315245fb4a56a9a15be47) · [本轮分支](https://github.com/zsh199410/health-intelligence-pro/tree/codex/p0-sleep-session)

Muse 登记已安装并通过用户闪退复测的历史包为 2.0.0（Build 20），源自 `0e395f0` 和 IPA Run 4。Muse 核对的**历史未签名包** SHA256 为 `6da42fd8369c807c6a991d13f291914a02279b34643ea8fc51a3c8db5d6d54c1`。保留该已验收安装包作为回滚版本。此记录覆盖 iPhone 闪退复测，完整授权路径、睡眠准确性及 Watch 安装仍需独立验收。[Muse 记录](https://github.com/zsh199410/health-intelligence-pro/issues/2#issuecomment-7123328144) · [历史 IPA Run 4](https://github.com/zsh199410/health-intelligence-pro/actions/runs/43983795123)

本轮源码尚未导出 IPA。当前 Linux 实例缺少 Apple SDK、Xcode 和签名环境。最近成功的历史未签名 IPA Run 7 对应 `d7eb2ad7df9ae879b9016f16ac97d7e861c1a67e`，早于本轮修复；其产物不可作为本轮交付。[历史 IPA Run 7](https://github.com/zsh199410/health-intelligence-pro/actions/runs/45085638678)

## 实现与验证

- iPhone 和 Apple Watch 使用同一组最近睡眠样本计算摘要，并从同一会话取得起止时间。独立的较早睡眠不再计入摘要；重叠的长样本不再因其内部有短样本而被截断或拆开。
- `Core/Sources/HealthCore/SleepSession.swift` 更新会话选择。`iOS/Services/HealthViewModel.swift` 和 `Watch/WatchHealthStore.swift` 接入共享计算。`Core/Tests/HealthCoreTests/SleepSessionTests.swift` 新增两项回归覆盖。现有跨来源冲突的分期优先级仍需和 Apple 健康真机数据核对。
- Linux Swift 6.2.1 基线 20 项 XCTest 通过，修复后 22 项通过，失败 0。iOS、watchOS 和 UI 测试 Swift 源码语法解析通过，`Scripts/verify_source.py` 通过，静态视觉样稿 HTTP 200。Apple SDK 编译、模拟器 UI 回归及真机复测待完成。
- 分支 push 已启动 macOS 验证。PR 创建请求被 GitHub GraphQL 以 Forbidden 拒绝，分支已可供审查。PR #23 对应的历史 Run 202 记录了 hosted runner 未取得任务及 GitHub 内部错误，需用有效 runner 重新确认授权代码和构建。[本轮 Run 205](https://github.com/zsh199410/health-intelligence-pro/actions/runs/45551360874) · [历史 Run 202](https://github.com/zsh199410/health-intelligence-pro/actions/runs/45222862926) · [草稿 PR 创建入口](https://github.com/zsh199410/health-intelligence-pro/compare/main...codex/p0-sleep-session?expand=1)
- 云环境已安装并验证 Swift 工具链。已保存 `install_script` 与 `start_skill` 到环境草稿，待在环境设置审核、保存和发布。

## 现有工作与分工

五个指定 PR 在核对时均为草稿。#19 是安全更新与 IPA 分发契约，#20 是 Muse 的大字体截图测试修复，#21 是心血管恢复详情，#22 是七屏原创视觉审核规范，#23 是 HealthKit 授权失败回退和重试。本轮选择独立睡眠会话修复，避免覆盖各草稿的功能和设计范围。[#19](https://github.com/zsh199410/health-intelligence-pro/pull/19) · [#20](https://github.com/zsh199410/health-intelligence-pro/pull/20) · [#21](https://github.com/zsh199410/health-intelligence-pro/pull/21) · [#22](https://github.com/zsh199410/health-intelligence-pro/pull/22) · [#23](https://github.com/zsh199410/health-intelligence-pro/pull/23)

Issue #2 正文的首次可安装门槛有历史用户确认与 Muse 包记录，后续评论仍登记新版本的视觉、权限、数据准确性及签名证据要求。原生 Watch 安装独立验收。针对本轮新候选，继续使用 [发布门禁](DELIVERY_GATES.md) 和 [Issue #2](https://github.com/zsh199410/health-intelligence-pro/issues/2)。

## 接续顺序

1. **Muse / macOS**：对分支的确切 SHA 完成 iOS 和 watchOS 无签名编译及模拟器回归。检查 #23 的授权回退在无数据、部分授权、撤权后重连和跳过流程的表现，再在独立集成分支与睡眠修复合并验证。
2. **Muse / 真机**：用 iPhone 16 Pro Max 和 Watch S12 与 Apple 健康对照正常整夜、分段睡眠、午睡、跨午夜和多来源样本，同时记录来源、采样时间、时区、单位、分期与夜间读取窗口。回传脱敏证据。后续仍需审计聚合指标的统计窗口、失败与空数据、刷新缓存、以及跨语言环境下中文时间和单位格式。
3. **Muse / IPA**：运行 iPhone 无签名导出工作流或等效本地 Xcode 构建，核对 Payload、版本、Build 和 SHA256。用户本地签名后验收安装、启动和 HealthKit。正式交付附实际 IPA、中文更新说明、源码 SHA、包 SHA256、签名和测试状态、已知问题与历史包回滚方式。Watch 单独验证签名、嵌入与安装。
4. **GPT / P1 与 P3**：审查 #21、#22 的原创设计和算法，推进数据来源矩阵、真实测量与推断区分、无障碍以及健康报告。优先复核睡眠和恢复，之后分批推进压力、能量、负荷和风险提示。未进行新增页面或全面健康功能验收。
5. **GPT 与 Muse / P2**：按 Issue #2 最新范围保留主动 iPhone 摄像头 PPG 与 S12 多源分析。GPT 审查采集、质量拒绝、温控、隐私与 PRV／ECG-HRV 区分。Muse 通过同步参考设备记录误差和拒测率。P2 尚未实现，血压、血糖、尿酸和疾病诊断不能通过这些信号虚构推算。
6. **GPT 与工程 / P4**：以 #19 的契约为起点审查清单签名、防回放、完整性、版本兼容及回滚。按 iOS 签名和安装机制验收，当前没有新的更新器代码。
