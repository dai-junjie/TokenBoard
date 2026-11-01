# TokenBoard

macOS 菜单栏额度看板。此发布分支仅支持 TeamBuddy（原 Labforge），不包含米醋。

## 下载与安装

在 [GitHub Releases](https://github.com/dai-junjie/TokenBoard/releases) 下载 `TokenBoard.dmg`，打开后将 `TokenBoard.app` 拖到 Applications。支持 macOS 14 及以上，安装包同时支持 Apple Silicon 和 Intel Mac。

首次点击“登录 TeamBuddy”或“打开 TeamBuddy 控制台”，使用原账号登录并完成网页验证，关闭窗口即可刷新。新站启用了 Turnstile，不能仅通过账号密码直接添加。WebKit 保存登录态，应用在同一会话中请求 JSON 接口，不抓取网页文字，也不导出网站访问令牌。会话过期后需重新登录。

安装包使用临时签名，尚未经过 Apple 公证。macOS 可能阻止首次打开；请在系统设置 → 隐私与安全性中允许打开。

## 日常使用

- 菜单栏直接显示个人和团队已用 / 上限、本周期消耗、成员专用额度及下次重置时间，避免重复展示剩余额度。
- 团队消耗榜默认展开，显示本周期前 5 名；本人以蓝色圆角边框和“我”标记突出显示。并列消耗并列名次，前 5 名以外不推算个人排名。
- 金额按平台货币配置换算；周期以团队重置时间为准，不等于自然日。
- 每 5 分钟自动刷新，也可点击“立即刷新”。失败保留本次运行中上次成功数据并提示错误。
- “打开 TeamBuddy 控制台”和“复制 API 地址”位于同一行。模型及 API Key 在控制台查看。

网站：https://teambuddy.dev 。API Base URL：`https://api.teambuddy.dev/v1`。复制地址只写入剪贴板，不修改其他客户端配置。

数据来自 `/api/team/my-quotas` 和 `/api/team/overview`。全站 `/api/rankings` 已禁用，完整团队用量接口对普通成员无权限，因此只展示团队概览返回的前 5 名。旧模型监测和全站榜不再展示。

若内嵌网页加载或验证失败，可点击窗口下方“重新加载”或“在浏览器打开”；外部浏览器与应用登录态独立，在外部浏览器登录不会登录菜单栏。

## 构建与验证

```bash
swift build
swift run LabforgeVerify
./scripts/build_dmg.sh
```

安装包生成于 `dist/TokenBoard.dmg`。打包脚本使用独立源码副本构建通用二进制，不包含本地旧版默认账号密码。

## 发布

在 `release/1.0` 分支维护 1.0 版本。先更新 `Packaging/Info.plist` 中的版本号和构建号，再提交并推送分支及对应标签：

```bash
git push -u origin release/1.0
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions 会验证 TeamBuddy 数据解析、构建并检查通用 DMG，再创建同名 GitHub Release，附上 `TokenBoard.dmg` 和 SHA-256 校验文件。标签版本须与 `CFBundleShortVersionString` 一致。发布说明来自 `.github/release-notes.md`。
