# iOS V4 更新交付契约（GPT 原创设计，Draft）

## 目标与边界
- 允许持续迭代：版本检查、更新说明、明确的用户操作、跳转可信安装渠道。
- **不实现** App 内静默 IPA 安装、绕过 iOS 签名校验、自动重签名、后台自我替换。
- iPhone HealthKit 旧包崩溃已有 2026-11-17 用户真机修复确认（Issue #3）；新构建仍须独立验证签名/授权四路径。此文档不表示签名 IPA 已就绪。
- Apple Watch 仍为 P5。此 PR 已包含独立的 HealthUpdateManifest Swift 解析/验证源码和单元测试，以及本设计文档；未接入 App 页面、网络更新检查或安装能力。不触碰 Muse 的 Mac/Xcode、证书、现有共享 SwiftUI 文件或 main。

## 推荐渠道
1. **TestFlight（优先）**：App 内展示可用更新，用户确认后打开 TestFlight；实际安装和更新由 TestFlight 完成。
2. **自签/Ad Hoc（备选）**：App 内打开受控 HTTPS 下载说明页；由用户使用与其证书/设备相容的受信任安装流程安装。网页提供 IPA 下载不等于 iOS 可以直接安装；不能把 Safari 打开 IPA 当成通用安装能力。
3. 不能声称任意个人开发者证书都可用 OTA manifest 安装；安装渠道须依据 Apple 实际分发许可和 provisioning profile 核实。

## 更新清单数据契约（解析器已提交，服务端发布未实现）
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

上面是 **示例结构**，版本号、日期和 URL 均非实际发布信息。生产端须用自己的 HTTPS 域名/可信 TestFlight 链接替换，不得发布示例 URL。只接受 HTTPS，校验允许的主机白名单；拒绝未知 schema、无效版本号、非预期渠道；清单时效与防回放校验尚未实现，必须在上线前补齐；不要使用用户输入的任意下载 URL。建议上线前实现独立的 manifest 签名及防回放校验；当前仅有 HTTPS URL 主机白名单验证，不应宣称已防止清单被篡改。清单只含发布元数据，不包含 HealthKit 记录、个人标识、证书或私钥。

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
- GPT 已在本 PR 提交 HealthUpdateManifest（纯解析/验证）及对应单元测试，本 PR 的 `e7cad5348b4421eb084d62495c22ca85dd1c97f0` 已有 GitHub Actions #44911828890 completed/success 记录；该结果只覆盖工作流实际执行的 CI 门禁，不证明 iPhone 真机授权、签名或 IPA 安装。GPT 后续独立实现 UpdateChecker（网络状态机）、UpdateView（SwiftUI）及测试；先核对最新集成 HEAD 及现有路径，再认领具体文件，避免与 PR #15–#18 同文件并行修改。
- Muse：仅在 GPT 提供固定 SHA 后运行 Xcode/设备验证、签名、截图、安装、回传原始证据。
- 本文档 PR 可单独审查，不应在 P0 真机门禁通过前被解释为「可用安装包」。

## 2026-11-22 证据更新（GPT）
- 本 PR 已核对的 HEAD：`e7cad5348b4421eb084d62495c22ca85dd1c97f0`；对应 [Source Verification #44911828890](https://github.com/zsh199410/health-intelligence-pro/actions/runs/44911828890) 为 `completed/success`。这是该提交的 CI 证据，不能代替真机测试。
- 当前依然缺少该版本的签名 IPA、iPhone 安装启动、HealthKit 四路径授权/拒绝/重启/升级回归及 entitlement 脱敏核验。此前旧包通过不自动覆盖新包。
- PR #15 基于 main，PR #18 基于 #15 的集成分支；集成时应按 base/head 依赖顺序复核，不得将各 Draft PR 当成相互独立的 main 补丁直接合并。
- GPT 独占本 PR 三个文件；Muse 仅负责运行 Mac/Xcode、真机、截图与脱敏日志，不在此分支或这些路径并行修改。Apple Watch 仍 P5。
