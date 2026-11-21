# iOS V4 更新交付契约（GPT 原创设计，Draft）

## 目标与边界
- 允许持续迭代：版本检查、更新说明、明确的用户操作、跳转可信安装渠道。
- **不实现** App 内静默 IPA 安装、绕过 iOS 签名校验、自动重签名、后台自我替换。
- 当前 iPhone HealthKit P0 真机授权/签名/崩溃门禁优先；此文档不是已实现功能，也不表示签名 IPA 已就绪。
- Apple Watch 仍为 P5。此 PR 只增加独立文档，不触碰 Muse 的 Mac/Xcode、证书、现有 Swift 文件或 main。

## 推荐渠道
1. **TestFlight（优先）**：App 内展示可用更新，用户确认后打开 TestFlight；实际安装和更新由 TestFlight 完成。
2. **自签/Ad Hoc（备选）**：App 内打开受控 HTTPS 下载说明页；由用户使用与其证书/设备相容的受信任安装流程安装。网页提供 IPA 下载不等于 iOS 可以直接安装；不能把 Safari 打开 IPA 当成通用安装能力。
3. 不能声称任意个人开发者证书都可用 OTA manifest 安装；安装渠道须依据 Apple 实际分发许可和 provisioning profile 核实。

## 建议数据契约（仅规划）
服务端只发布经过验收的 JSON 清单，不直接提供签名材料：

```json
{
  "schemaVersion": 1,
  "channel": "testflight",
  "version": "4.0.0",
  "build": 100,
  "minimumSupportedBuild": 90,
  "releaseNotes": ["修复健康授权与界面问题"],
  "publishedAt": "2026-11-21T00:00:00Z",
  "installPageURL": "https://example.invalid/updates",
  "artifactSHA256": null
}
```

上面是 **示例结构**，版本号、日期和 URL 均非实际发布信息。生产端须用自己的 HTTPS 域名/可信 TestFlight 链接替换，不得发布示例 URL。只接受 HTTPS，校验允许的主机白名单；拒绝未知 schema、无效版本号、过旧清单、非预期渠道；不要使用用户输入的任意下载 URL。可选 manifest 签名校验，避免更新入口被劫持。清单只含发布元数据，不包含 HealthKit 记录、个人标识、证书或私钥。

## SwiftUI 交互契约
- 设置 → 关于 → 检查更新；可选首页轻提示，不弹阻断式强制更新弹窗。
- 显示当前版本、可用版本、更新说明、渠道和发布日期；用户明确点击「前往更新」后再打开链接。
- 状态：检查中、已是最新版、有新版本、网络失败、清单不可信、当前渠道不支持。
- 对网络失败显示重试，不改变 HealthKit 授权状态，不阻断健康数据读取。
- 支持 VoiceOver、动态字体、浅深色、简体中文、24 小时制；遵守 Reduce Motion。
- 检查频率有限制，支持用户手动检查；不要把远端更新检查和 HealthKit 读取耦合。

## 发布与回滚门禁
1. 固定 commit SHA，记录 GitHub Actions run、核心测试、iPhone 真机四路径、签名 entitlement 核验。
2. 构建/签名由 Muse 在 Mac 完成；记录脱敏构建日志、Bundle ID、版本/build、SHA256、安装渠道，不上传证书/P12、profile 私钥或健康数据。
3. 测试安装、启动、升级保留用户数据；校验版本/build 单调递增及数据库迁移；签名/Team ID/Keychain 权限变化须专项验证。
4. 通过后才更新 manifest；失败时停止推广，回退 manifest 到上一已验收版本。iOS 不保证可原位降级，数据迁移应向前兼容并保留恢复策略。
5. 更新渠道与签名 IPA 必须一一对应；模拟器成功不替代真机 PASS。

## 实施拆分与文件所有权
- GPT 独立后续 PR：UpdateManifest（纯解析/验证）、UpdateChecker（网络状态机）、UpdateView（SwiftUI）和单元测试；先核对最新集成 HEAD 及现有路径，再认领具体文件，避免与 PR #15–#18 同文件并行修改。
- Muse：仅在 GPT 提供固定 SHA 后运行 Xcode/设备验证、签名、截图、安装、回传原始证据。
- 本文档 PR 可单独审查，不应在 P0 真机门禁通过前被解释为「可用安装包」。
