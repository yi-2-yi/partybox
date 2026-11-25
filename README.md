# PartyBox（聚会桌游盒）

面向朋友线下聚会的跨平台桌游 App（支持 **Android / iOS / Web / Windows**），采用**可扩展多游戏插件架构**，支持**联网模式**与**局域网/手机热点无网联机模式**。

## 当前支持与规划

- ✅ **狼人杀（聚会面杀模式）**：支持 6 人速局 / 9 人标准 / 12 人预女猎白（默认开启警长竞选）/ 12 人预女猎守（默认开启警长竞选）及自定义板子；包含长按防偷窥身份牌、智能语音法官（TTS）、防听声辨位空过、警长竞选与 1.5 票权重、女巫/预言家/猎人/守卫/白痴完整技能、断线重连与终局复盘。
- ✅ **掼蛋（4人双搭档）**：支持 2 副牌 108 张、1/3 红队 vs 2/4 蓝队、红桃逢人配百搭自动识别、全部正宗牌型与炸弹阶梯（4炸 < 5炸 < 同花顺 < 6~10炸 < 天王炸）、接风、双下+3/单下+2/保级+1 升级、过 A 夺冠、进贡/还贡与双大王抗贡，以及智能提示和 AI 陪玩。
- 🔜 **一夜终极狼人（One Night）**：插件接口已预留（`GameType.oneNight`）。

## 项目结构

```text
party-games/
├── packages/
│   ├── party_core/     # 通用房间状态机、协议、GamePlugin 插件框架与狼人杀核心引擎（纯 Dart）
│   └── party_server/   # 联网模式 WebSocket 多房间服务器（复用 party_core）
└── apps/
    └── party_app/      # Flutter 跨平台客户端（Android / iOS / Web / Windows）
```

## 双模式联机说明

### 1. 局域网 / 手机热点模式（无外网、信号差推荐）
1. 任意一位朋友打开**手机热点**（不需要开启流量），或者所有人连接同一个室内 Wi-Fi。
2. 房主点击 **「局域网/热点建房」**，房主手机自动启动本地游戏主机并展示连接二维码与局域网 IP。
3. 其他朋友点击 **「加入局域网房间」**，App 会通过 UDP 局域网广播自动发现附近房间（若路由器屏蔽广播，可直接输入房主页面显示的 IP 地址加入）。

### 2. 联网模式
1. 启动 `packages/party_server`（本地调试或部署到任意支持 Dart / Docker 的云服务器）：
   ```bash
   cd packages/party_server
   dart run bin/server.dart
   ```
2. 在 App 中选择 **「联网游玩」**，填入服务器地址（如 `ws://你的服务器IP:8080/ws` 或 `wss://域名/ws`），创建房间获取 4 位房间号分享给朋友即可加入。

### 3. 单人快速体验（AI 机器人陪玩）
在首页点击 **「单人快速体验」**，可选 6 人 / 9 人 / 12 人（含警长）板子，系统会自动填充 AI 玩家并自动完成其他座位的行动与投票，方便随时验证与熟悉规则。

## Windows 本地开发与打包指南

### 环境准备
1. 安装 [Flutter SDK for Windows](https://docs.flutter.dev/get-started/install/windows) 并配置到 `PATH`。
2. （可选，编译 Android APK 用）安装 Android Studio 与 Android SDK。

### 常用命令
```bash
# 1. 运行核心引擎测试
cd packages/party_core
dart pub get
dart test

# 2. 运行联网服务器集成测试
cd ../party_server
dart pub get
dart test

# 3. 在 Windows 上直接运行 App（Chrome 浏览器或 Windows 桌面）
cd ../../apps/party_app
flutter pub get
flutter run -d chrome      # 或 flutter run -d windows

# 4. 编译安卓真机安装包（APK）
flutter build apk --release
# 生成的安装包位于: apps/party_app/build/app/outputs/flutter-apk/app-release.apk
```

### 给 iPhone（iOS）打包说明
由于苹果限制编译 `.ipa` 必须使用 macOS + Xcode，在 Windows 上可以通过 **GitHub Actions（macOS runner）** 或 **Codemagic** 自动拉取本仓库代码编译 iOS 版本，并通过 Apple TestFlight 分发给朋友安装。

## 如何扩展新游戏（例如一夜狼、掼蛋）
1. 在 `packages/party_core/lib/src/games/` 下新建游戏目录（如 `one_night/` 或 `guandan/`），实现 `GamePlugin<TState>` 接口。
2. 在 `GamePluginRegistry` 中注册新插件。
3. 在 `apps/party_app/lib/features/games/` 下添加对应的游戏界面即可复用全部大厅、联网、局域网/热点建房、断线重连与语音播报能力。
