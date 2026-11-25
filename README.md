# yunfeng · iOS App（SwiftUI 工程）

一个把日常运维面板收进手机的小工具：**Sun-Panel 导航 + WireGuard + 日报 + weekiy 周报 + 背景管理**。

---

## 一、这份工程是什么

纯 SwiftUI（iOS 17+），无第三方依赖（除 WireGuard 可选引入）。目录结构：

```
云峰工作台-iOS/
├── .github/workflows/build-ipa.yml   # 云端自动出 ipa
├── project.yml                 # XcodeGen 工程描述（推荐）
├── 一键推送.bat                # Windows 双击即推仓库
├── README.md
├── YunfengHub/
│   ├── YunfengHubApp.swift     # 入口 + 根 TabView
│   ├── Models.swift            # 数据模型 / 本地持久化 / AppStore
│   ├── Services.swift          # 日报引擎 / 周报引擎 / WireGuardService / SunPanel
│   ├── BackgroundManager.swift # 背景管理（壁纸/模糊/色调/不透明度）
│   ├── Components.swift        # 玻璃卡片等通用组件
│   ├── NavigationHomeView.swift# 导航页（WebView + 快捷卡片）
│   ├── VPNView.swift           # WireGuard 界面
│   ├── DailyReportView.swift   # 日报
│   ├── WeeklyView.swift        # weekiy 周视图 / 周报
│   ├── BackgroundSettingsView.swift
│   ├── Info.plist              # 由 XcodeGen 按 project.yml 生成
│   └── YunfengHub.entitlements
└── 云峰工作台-原型.html         # 不在包里，单独一份
```

## 二、怎么编译（三种方式，选一）

### 方式 0：GitHub Actions 云编译（没 Mac 用这个）

工程里已放好 `.github/workflows/build-ipa.yml`，推上去就自动出 ipa。

**Windows 上**：解压后双击 `一键推送.bat`，按提示粘贴仓库地址即可。

**命令行**：

```bash
cd 云峰工作台-iOS
git init
git add .
git commit -m "init"
git branch -M main
git remote add origin https://github.com/你的用户名/yunfeng-hub.git
git push -u origin main
```

推完打开仓库 → **Actions** 标签 → `Build Unsigned IPA` → 等 5~8 分钟转绿
→ 进这次运行详情页，底部 **Artifacts** 下载 `YunfengHub-unsigned-ipa`（就是个 zip，解压得到 `YunfengHub-unsigned.ipa`）。

注意事项：
- 仓库设为 **Private** 也能跑，免费额度 2000 分钟/月，macOS runner 按 10 倍折算 → 实际约 200 分钟，够跑二三十次
- artifact 保留 30 天，过期就重跑一次 workflow
- 想手动重跑：Actions 页右侧 `Run workflow`
- 本地用命令行也能复现同一套逻辑：`xcodegen generate && xcodebuild -project ... CODE_SIGNING_ALLOWED=NO`

### 方式 A：XcodeGen（有 Mac，30 秒出工程）

```bash
brew install xcodegen
cd 云峰工作台-iOS
xcodegen generate
open YunfengHub.xcodeproj
```

然后在 Xcode 里把 Signing Team 选成你自己的 Apple ID。

### 方式 B：手工新建

1. Xcode → New Project → iOS App → 名字 `YunfengHub`，Interface **SwiftUI**，Language **Swift**
2. 删掉模板生成的 `ContentView.swift`
3. 把本目录 `YunfengHub/` 下的 9 个 `.swift` 拖进工程（勾选 Copy items if needed）
4. 工程设置搜索 `Bundle Identifier` 改成 `com.yunfeng.hub`
5. 加 `Info.plist` 键：`NSLocalNetworkUsageDescription`（访问内网服务需要）

## 二·五、用万能签把 ipa 装上（无开发者账号）

1. 把 `YunfengHub-unsigned.ipa` 传到手机（AirDrop / 微信文件传输助手都行）
2. 万能签里「导入 ipa」→ 选这个文件
3. 签名方式选：
   - **个人证书 / 免费证书**：用你自己的 Apple ID，7 天有效，到期重签
   - **企业证书**：装的人多容易被吊销（掉签），随时可能失效
4. 签完点安装，装好后第一次打开若提示「不受信任」：
   设置 → 通用 → VPN与设备管理 → 信任该描述文件
   iOS 16 以上还要开：设置 → 隐私与安全性 → **开发者模式**
5. 如果报「Unable to install」或图标灰掉 → 大概率是掉签，换证书重签

**关键提醒**：万能签签出来的 App，`NetworkExtension` 能力一定没有。所以 WireGuard 页面能打开、能存配置、能显示界面，但点连接不会真拨号——这不是签名的问题，是 Apple 的权限门槛。

## 三、各模块状态

| 模块 | 状态 | 说明 |
|---|---|---|
| 导航（Sun-Panel） | ✅ 可用 | WKWebView 内嵌打开，卡片列表可增删，跳转系统浏览器 |
| 备件系统 | ✅ 可用 | 第 3 个 Tab，直接内嵌 http://bj.kangkang.me/login.php |
| 写日报 | ✅ 可用 | 第 4 个 Tab，内嵌 http://rb.kangkang.me/login.php（原生日报视图保留在代码里，未挂 Tab） |
| 仪电周结 | ✅ 可用 | 第 5 个 Tab，内嵌 http://we.kangkang.me/index.php |
| 背景管理 | ✅ 可用 | 8 套渐变壁纸 + 相册自定义 + 模糊/色调/卡片透明度；入口在「导航」页右上角调色盘 |
| WireGuard | ✅ 配置管理可用 | 粘贴/导入 .conf → 分享给官方 WireGuard 导入；不在本机建隧道 |

导航卡片把内网 / 外网合成一张，按网络环境自动切地址（在 `192.168.10.x` 网段判为内网，否则走外网）；顶部胶囊可手动切「自动 / 内网 / 外网」，长按卡片可删除，右下角「添加入口」可加新的内网/外网地址对。

| 名称 | 内网 | 外网 |
|---|---|---|
| 导航面板 | http://192.168.10.69:3000 | http://sp.kangkang.me |
| 备件管理 | — | http://bj.kangkang.me/login.php |
| 日报神器 | — | http://rb.kangkang.me/login.php |
| 仪电周结 | — | http://we.kangkang.me/index.php |
| 在线监控 Kuma | http://192.168.10.69:3001 | http://kuma.kangkang.me |
| 容器日志 Dozzle | — | http://log.kangkang.me |
| 主机资源 Netdata | — | http://sys.kangkang.me |
| Home Assistant | http://192.168.10.69 | https://ha.yunfeng.pro |
| 群晖 NAS | http://192.168.10.252:5000 | — |
| PVE | https://192.168.10.240:8006 | — |

App 显示名为 `YUNFENG`，图标为深空渐变 + 山岳流云（`YunfengHub/Assets.xcassets/AppIcon.appiconset/Icon-1024.png`，1024×1024 无透明通道）。

## 四、WireGuard：变成「配置管理 + 交给官方 App」

本工程不再假装拨号。iOS 让第三方 App 自己建隧道，必须有：

1. 付费开发者账号（$99/年）
2. NetworkExtension → Packet Tunnel 能力
3. 单独的 Packet Tunnel Extension target + WireGuardKit

万能签／免费证书签不出这个能力，所以本 App 只做配置这一层，隧道交给官方 **WireGuard** App（免费、支持 on-demand、更稳）：

- **粘贴 .conf**：整段粘进去，自动解析 Endpoint / 私钥 / 对端公钥 / MTU / AllowedIPs
- **从文件导入**：选 `.conf` 文件
- **分享到 WireGuard**：生成标准 `.conf` 临时文件，走系统分享面板，选 WireGuard 即完成导入
- **复制文本**：粘到 WireGuard App 里手动新建

校验：只有密钥齐全的配置才能导出，缺密钥会明确提示，不会生成半截配置。

## 五、其它已知限制

- 首次启动会写入演示数据（3 条任务 / 6 个导航项 / 2 个 WireGuard 配置），可直接在界面里改
- 数据存在 Documents 目录 `yunfeng-hub.json`，删 App 即清空
- 导航页 WebView 只做浏览器内跳转，Home Assistant 这类需要登录态的站点建议直接用 Safari 打开（本工程里卡片点击是跳系统浏览器）
- 想把 HA 仪表盘原生嵌入也可以，但 HA 的 token 要自己处理，工程里没做

## 六、下一步可以加的

- 日报数据接 HA / 备件系统 API，自动拉当天工单
- weekiy 改成读真实 `DailyEntry` 按周聚合（`WeeklyEngine.stats()` 里已留注释）
- 桌面小组件（WidgetKit）显示周完成率
- iCloud 同步（把 JSON 挪到 NSUbiquitousContainer）
