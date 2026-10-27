# TokenBoard

macOS 菜单栏额度看板。1.0 版本支持 Labforge，可以查看剩余额度、今日 Token 用量、模型可用性和今日排行榜。

## 下载与安装

在 [GitHub Releases](https://github.com/dai-junjie/TokenBoard/releases) 下载 `TokenBoard.dmg`，打开后将 `TokenBoard.app` 拖到 Applications。支持 macOS 14 及以上，安装包同时支持 Apple Silicon 和 Intel Mac。

首次打开后，在“设置”中填写自己的 Labforge 用户名和密码。账号保存在本机，发布的安装包使用空账号模板。

安装包使用临时签名，尚未经过 Apple 公证。macOS 可能阻止首次打开；请在系统设置 → 隐私与安全性中允许打开。

## 日常使用

| 我想知道什么 | 在哪里看 |
| --- | --- |
| 今天还能用多少？ | “个人团队日额度”和“团队今日剩余额度”，按剩余 / 总额度显示 |
| 今天用了多少 Token？ | “今日已用 Token” |
| 哪些模型目前可用？ | 展开“模型测试详情”，查看分组详情 |
| 今日用量排名如何？ | 展开“今日排行榜”，可在设置中关闭 |
| 数据怎么更新？ | 每 5 分钟自动刷新，也可点击“立即刷新” |

设置中的“默认展开模型测试详情”会保存偏好；菜单内临时展开或收起只影响本次查看。刷新失败时保留上次成功数据，并显示错误提示。

## 构建与验证

开发前复制空账号模板。本地默认账号文件不纳入 Git：

```bash
cp Sources/LabforgeCore/DefaultLabforgeCredentials.swift.example Sources/LabforgeCore/DefaultLabforgeCredentials.swift
swift build
swift run LabforgeVerify
./scripts/build_dmg.sh
```

安装包生成于 `dist/TokenBoard.dmg`。打包脚本在独立的源码副本中构建，并使用空账号模板。

## 发布

在 `release/1.0` 分支维护 1.0 版本。先更新 `Packaging/Info.plist` 中的版本号和构建号，再提交并推送分支及对应标签：

```bash
git push -u origin release/1.0
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions 会验证 Labforge、构建并检查通用 DMG，再创建同名 GitHub Release，附上 `TokenBoard.dmg` 和 SHA-256 校验文件。标签版本须与 `CFBundleShortVersionString` 一致。发布说明来自 `.github/release-notes.md`。
