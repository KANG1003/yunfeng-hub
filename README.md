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
| 日报 | ✅ 可用 | 任务勾选 + 三种模板（标准 / 简洁 / 向上汇报）+ 复制 / 存档 |
| weekiy | ✅ 可用 | 周条 + 完成率进度条 + 周报一键生成 |
| 背景管理 | ✅ 可用 | 8 套渐变壁纸 + 相册自定义 + 模糊/色调/卡片透明度，设置持久化 |
| WireGuard | ⚠️ 界面完成，隧道未接 | 见下文第四节 |

默认导航入口（首次启动写入，可在界面里改）：

| 名称 | 地址 |
|---|---|
| 导航面板 | http://sp.kangkang.me |
| 备件管理 | http://bj.kangkang.me/login.php |
| 日报神器 | http://rb.kangkang.me/login.php |
| 仪电周结 | http://we.kangkang.me/index.php |
| 在线监控 Kuma | http://kuma.kangkang.me |
| 容器日志 Dozzle | http://log.kangkang.me |
| 主机资源 Netdata | http://sys.kangkang.me |

App 显示名为 `yunfeng`，图标为深空渐变 + 山岳流云（`YunfengHub/Assets.xcassets/AppIcon.appiconset/Icon-1024.png`，1024×1024 无透明通道）。

## 四、WireGuard 要真拨号，还差三步

工程里 `WireGuardService` 已经把「配置解析 / 状态机 / 计时 / 流量展示」写好，`connect()` 里留了两处 `TODO`。真跑起来需要：

1. **引入 WireGuardKit**
   Xcode → Package Dependencies → `https://github.com/WireGuard/wireguard-apple`
   依赖指向 `WireGuardKit` 产品。

2. **新建 Packet Tunnel Extension**
   File → New → Target → Network Extension，类型选 Packet Tunnel。
   把 `WireGuardKit` 的 `WireGuardProvider` 逻辑接到你自己的 `NEPacketTunnelProvider` 子类里，
   配置通过 App Group（`group.com.yunfeng.hub`）传给扩展。

3. **开发者后台开能力**
   - 主 App 与 Extension 两个 Bundle ID 都要勾 **Network Extensions → Packet Tunnel**
   - 两个 ID 都要挂同一个 App Group
   - Entitlements 里取消注释 `com.apple.developer.networking.networkextension`

> 没有 $99 开发者账号时，只能用个人免费证书签名，**NetworkExtension 能力不可用**，隧道拨不起来——这是 Apple 的硬限制，绕不过去。

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
