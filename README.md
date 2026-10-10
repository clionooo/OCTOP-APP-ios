# Octop iOS

给飞牛 NAS 上跑的 [Octop](https://github.com/TencentCloud/Octop)（腾讯云开源的自托管 AI 助手）配的 iPhone 客户端。

纯 SwiftUI + WebKit，**零第三方依赖**，GitHub Actions 直接产出未签名 IPA，TrollStore（巨魔）一键安装。

## 功能

- **服务器地址管理**：填一次 `http://飞牛IP:8089` 就记住，支持多台服务器切换、测试连接、端口自动补 8089；**反代域名直连也支持**（`https://octop.example.com`，带子路径 `https://example.com/octop` 也行）
- **原生登录**：直接调 Octop 的 `POST /api/auth/login`，拿 JWT 存本机；服务端开了滑动验证码 / LDAP / OIDC 时一键切「网页方式登录」
- **控制台**：加载 Octop 官方 Web Dashboard，登录态由 App 注入，功能跟电脑上完全一致（对话、会话、知识库、管理、终端…）
- **Token 双向同步**：网页侧续期 token 会自动存回本机，网页侧登出会提示重新登录
- **体验细节**：下拉刷新、前进/后退/回首页、桌面模式（1280pt 视口）、页面缩放、深浅色跟随、保持屏幕常亮、文件上传/下载、在 Safari 打开

## 装到 iPhone（巨魔 TrollStore）

1. 到 **[Releases](../../releases/tag/ipa-latest)** 下载 `Octop-iOS-unsigned.ipa`（每次推代码自动更新，固定链接：`https://github.com/clionooo/OCTOP-APP-ios/releases/download/ipa-latest/Octop-iOS-unsigned.ipa`）
2. 用 Safari 或「文件」打开 IPA → 共享 → TrollStore；或者在 TrollStore 右上角 `+` 里选文件
3. 装完如果打不开：TrollStore → 设置 → **Install ldid**，再装一次

> 最低系统要求 **iOS 15.0**（巨魔支持 iOS 14.0 ~ 16.6.1 / 16.7 RC / 17.0）。
> 要在 iOS 14 上用，把 `project.yml` 里两处 `deploymentTarget` 改成 `"14.0"` 再推一次即可。

## 怎么用

1. 打开 App → 点右上角 **+** 填服务器地址，例如 `http://192.168.8.8:8089`（或反代域名 `https://octop.example.com`）
2. 点 **测试连接**（没写端口会自动补 8089）→ 保存
3. 点这台服务器 → 输入 Octop 的账号密码 → **登录**
4. 直接进控制台，之后每次打开都是已登录状态

## 自己构建

```
scripts/gen_icon.py     # 生成 App 图标（纯标准库，无 Pillow）
project.yml             # XcodeGen 工程描述
.github/workflows/build-ipa.yml
```

GitHub Actions（macOS runner）：

```
brew install xcodegen
python3 scripts/gen_icon.py
xcodegen generate
xcodebuild archive -project OctopIOS.xcodeproj -scheme OctopIOS \
  -configuration Release -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
# 从 .xcarchive/Products/Applications/OctopIOS.app 手工拼 Payload/ 打成 ipa
```

本地打包（需要 Mac + Xcode）同上。

## 说明

- Octop 的 Web Dashboard 是个完整的 React 应用（对话、知识库、终端、远程桌面……），App 用官方控制台承载，保证功能不缺、服务端升级不用改 App。
- 原生部分负责：地址管理、登录、token 生命周期、系统级体验。
- JWT 只存在本机（Keychain，Keychain 不可用时自动落 UserDefaults），不上传任何第三方。
- 明文 `http://` 地址已放行（ATS），局域网自签名 HTTPS 在设置里开「允许自签名证书」。

## License

MIT
