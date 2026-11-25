import 'package:material_ui/material_ui.dart';
import 'package:party_core/party_core.dart';

import '../../core/discovery/lan_discovery.dart';
import '../../core/state/app_controller.dart';
import '../../core/theme/party_theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Future<void> _editNickname() async {
    final textCtrl = TextEditingController(text: widget.controller.nickname);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PartyColors.bgCard,
        title: const Text('设置聚会昵称'),
        content: TextField(
          controller: textCtrl,
          autofocus: true,
          maxLength: 12,
          decoration: const InputDecoration(
            labelText: '你的昵称',
            hintText: '例如：小明 / 阿杰',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, textCtrl.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      await widget.controller.updateNickname(result);
    }
  }

  Future<void> _showLanJoinSheet() async {
    final discovery = LanDiscoveryService();
    await discovery.startScanning();
    final ipCtrl = TextEditingController();

    if (!mounted) {
      await discovery.dispose();
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PartyColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.wifi_tethering, color: PartyColors.gold),
                  SizedBox(width: 8),
                  Text(
                    '加入局域网 / 热点房间',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '请先连上房主的手机热点或同一个 Wi-Fi，下方会自动搜索附近所有桌游房间（狼人杀 / 掼蛋）。',
                style: TextStyle(color: PartyColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              if (discovery.isSupported)
                StreamBuilder<List<DiscoveredLanRoom>>(
                  stream: discovery.roomsStream,
                  initialData: discovery.currentRooms,
                  builder: (context, snap) {
                    final rooms = snap.data ?? const [];
                    if (rooms.isEmpty) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: PartyColors.bgCard,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: PartyColors.border),
                        ),
                        child: const Row(
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '正在搜索同一局域网/热点下的房间…\n（如路由器拦截广播，可直接输入下方房主 IP）',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: PartyColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return Column(
                      children: rooms
                          .map(
                            (r) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(
                                  Icons.meeting_room,
                                  color: PartyColors.gold,
                                ),
                                title: Text(
                                  '${r.hostName}的${r.gameName}房 (${r.roomCode})',
                                ),
                                subtitle: Text(
                                  '${r.ip}:${r.port} · ${r.playerCount}/${r.maxPlayers}人',
                                ),
                                trailing: ElevatedButton(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    widget.controller.joinLanRoom(r.wsUrl);
                                  },
                                  child: const Text('加入'),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                )
              else
                const Text(
                  '当前为浏览器环境，不支持 UDP 自动发现，请直接输入房主屏幕上显示的局域网地址：',
                  style: TextStyle(color: PartyColors.gold, fontSize: 13),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: ipCtrl,
                decoration: const InputDecoration(
                  labelText: '手动输入房主地址（兜底直连）',
                  hintText: '例如：192.168.43.1:8765 或 ws://192.168.1.5:8765/ws',
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    final raw = ipCtrl.text.trim();
                    if (raw.isEmpty) return;
                    Navigator.pop(ctx);
                    widget.controller.joinLanRoom(raw);
                  },
                  icon: const Icon(Icons.login),
                  label: const Text('直接连接该地址'),
                ),
              ),
            ],
          ),
        );
      },
    );

    await discovery.dispose();
  }

  Future<void> _showOnlineSheet(GameType gameType) async {
    final serverCtrl =
        TextEditingController(text: widget.controller.onlineServerUrl);
    final codeCtrl = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PartyColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.cloud_outlined, color: PartyColors.seerCyan),
                  const SizedBox(width: 8),
                  Text(
                    '联网模式 · ${gameType.displayName}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: serverCtrl,
                decoration: const InputDecoration(
                  labelText: 'PartyBox 服务器地址',
                  hintText: 'ws://127.0.0.1:8080/ws 或 wss://your-domain/ws',
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    widget.controller.createOnlineRoom(
                      serverUrl: serverCtrl.text,
                      gameType: gameType,
                    );
                  },
                  icon: const Icon(Icons.add_circle_outline),
                  label: Text('创建${gameType.displayName}联网房间'),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  children: [
                    Expanded(child: Divider(color: PartyColors.border)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '或者输入房间号加入',
                        style: TextStyle(
                          color: PartyColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: PartyColors.border)),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: codeCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '4 位房间号',
                        hintText: '例如：4829',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () {
                      if (codeCtrl.text.trim().isEmpty) return;
                      Navigator.pop(ctx);
                      widget.controller.joinOnlineRoom(
                        serverUrl: serverCtrl.text,
                        roomCode: codeCtrl.text,
                      );
                    },
                    child: const Text('加入'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showWerewolfDemoPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: PartyColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '选择狼人杀单人体验板子（AI 陪玩）',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            _DemoPresetTile(
              title: '6 人速局（2狼 2民 预女）',
              subtitle: '无警长 · 快速熟悉面杀流程',
              onTap: () {
                Navigator.pop(ctx);
                widget.controller.startLocalDemo(preset: WerewolfConfig.preset6());
              },
            ),
            _DemoPresetTile(
              title: '9 人标准局（3狼 3民 预女猎）',
              subtitle: '无警长 · 含猎人开枪',
              onTap: () {
                Navigator.pop(ctx);
                widget.controller.startLocalDemo(preset: WerewolfConfig.preset9());
              },
            ),
            _DemoPresetTile(
              title: '12 人预女猎白（默认含警长竞选）',
              subtitle: '4狼 4民 预女猎白 · 体验上警/投票/1.5票/移交警徽',
              highlight: true,
              onTap: () {
                Navigator.pop(ctx);
                widget.controller.startLocalDemo(
                  preset: WerewolfConfig.preset12Idiot(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showGuandanDemoPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: PartyColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '选择掼蛋单人体验模式（1人 + 3位AI）',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              '你与 3号 AI 搭档红队，对战 2号/4号 蓝队。体验逢人配、同花顺压5炸、接风与进贡还贡！',
              style: TextStyle(color: PartyColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            _DemoPresetTile(
              title: '经典升级赛（从 2 打起，过 A 夺冠）',
              subtitle: '双下+3级 · 单下+2级 · 开启进贡/还贡/双大王抗贡',
              highlight: true,
              onTap: () {
                Navigator.pop(ctx);
                widget.controller.startGuandanDemo(
                  config: const GuandanConfig(startLevel: 2, targetLevel: 14),
                );
              },
            ),
            _DemoPresetTile(
              title: '快速过 A 决胜局（直接打 A）',
              subtitle: '红桃 A 逢人配 · 一局定胜负快速爽玩',
              onTap: () {
                Navigator.pop(ctx);
                widget.controller.startGuandanDemo(
                  config: const GuandanConfig(startLevel: 14, targetLevel: 14),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showOneNightDemoPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: PartyColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '选择一夜终极狼人体验板子（AI 陪玩）',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              '只有一夜，全员参与推理不淘汰，小心你的身份牌被强盗或捣蛋鬼悄悄换掉！',
              style: TextStyle(color: PartyColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            _DemoPresetTile(
              title: '3 人迷你局（6 张牌 · 3 张底牌）',
              subtitle: '2狼 + 预言家 + 强盗 + 捣蛋鬼 + 村民',
              onTap: () {
                Navigator.pop(ctx);
                widget.controller
                    .startOneNightDemo(preset: OneNightConfig.preset3());
              },
            ),
            _DemoPresetTile(
              title: '5 人经典局（8 张牌 · 推荐）',
              subtitle: '2狼 + 预言家 + 强盗 + 捣蛋鬼 + 酒鬼 + 失眠者 + 村民',
              highlight: true,
              onTap: () {
                Navigator.pop(ctx);
                widget.controller
                    .startOneNightDemo(preset: OneNightConfig.preset5());
              },
            ),
            _DemoPresetTile(
              title: '7 人进阶局（10 张牌 · 含爪牙与皮匠）',
              subtitle: '2狼 + 爪牙 + 2守夜人 + 预言家 + 强盗 + 捣蛋鬼 + 失眠者 + 皮匠',
              onTap: () {
                Navigator.pop(ctx);
                widget.controller
                    .startOneNightDemo(preset: OneNightConfig.preset7());
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: const LinearGradient(
                          colors: [PartyColors.gold, Color(0xFFD97706)],
                        ),
                      ),
                      child: const Icon(
                        Icons.casino_rounded,
                        color: Color(0xFF1A1400),
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PartyBox',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                          ),
                          Text(
                            '聚会桌游盒 · 联网 & 热点无线联机',
                            style: TextStyle(
                              color: PartyColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: _editNickname,
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: PartyColors.bgCard,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: PartyColors.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.person_outline,
                              size: 16,
                              color: PartyColors.gold,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              ctrl.nickname,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.edit,
                              size: 13,
                              color: PartyColors.textMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                if (ctrl.isBusy)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  // Card 1: Guandan (NEW!)
                  _GameHeroCard(
                    badgeText: '新上线 · 4人双副牌搭档',
                    badgeColor: PartyColors.guardGreen,
                    icon: Icons.style_rounded,
                    gradientColors: const [Color(0xFF103630), Color(0xFF0E1B24)],
                    borderColor: PartyColors.guardGreen.withValues(alpha: 0.55),
                    title: '掼蛋 · 聚会无线牌局',
                    description:
                        '108 张双副牌、1/3 红队 vs 2/4 蓝队、红桃逢人配百搭、同花顺压 5 炸、天王炸、接风、双下 +3 级与进贡还贡抗贡。',
                    primaryButtonLabel: '局域网 / 热点建房（4人无网打掼蛋）',
                    onLanHost: () =>
                        ctrl.startLanHost(gameType: GameType.guandan),
                    onLanJoin: _showLanJoinSheet,
                    onOnline: () => _showOnlineSheet(GameType.guandan),
                    demoLabel: '单人快速体验掼蛋（AI 搭档与对手）',
                    onDemo: _showGuandanDemoPicker,
                  ),

                  const SizedBox(height: 16),

                  // Card 2: Werewolf
                  _GameHeroCard(
                    badgeText: '已上线 · 6–12人面杀模式',
                    badgeColor: PartyColors.gold,
                    icon: Icons.nightlight_round,
                    gradientColors: const [Color(0xFF232F55), Color(0xFF131B31)],
                    borderColor: PartyColors.gold.withValues(alpha: 0.45),
                    title: '狼人杀 · 智能聚会法官',
                    description:
                        '长按防偷窥发牌、天黑语音播报、狼人互认刀口、12人局默认警长竞选、断线秒重连。大家线下畅聊，手机自动控场！',
                    primaryButtonLabel: '局域网 / 手机热点建房（无网也能玩）',
                    onLanHost: () =>
                        ctrl.startLanHost(gameType: GameType.werewolf),
                    onLanJoin: _showLanJoinSheet,
                    onOnline: () => _showOnlineSheet(GameType.werewolf),
                    demoLabel: '单人快速体验狼人杀（AI 陪玩 · 含 12 人警长局）',
                    onDemo: _showWerewolfDemoPicker,
                  ),
                  // Card 3: One Night Ultimate Werewolf (NEW!)
                  const SizedBox(height: 16),
                  _GameHeroCard(
                    badgeText: '新上线 · 3–10人 · 10分钟快局',
                    badgeColor: PartyColors.witchPurple,
                    icon: Icons.dark_mode,
                    gradientColors: const [Color(0xFF2B1B4D), Color(0xFF141129)],
                    borderColor: PartyColors.witchPurple.withValues(alpha: 0.55),
                    title: '一夜终极狼人 · 换牌推理',
                    description:
                        'N+3 发牌含 3 张底牌、11 种经典角色（独狼/爪牙/预言家/强盗/捣蛋鬼/酒鬼/失眠者/皮匠/猎人），只有一夜全员参与无淘汰！',
                    primaryButtonLabel: '局域网 / 热点建房（无网开一夜狼）',
                    onLanHost: () =>
                        ctrl.startLanHost(gameType: GameType.oneNight),
                    onLanJoin: _showLanJoinSheet,
                    onOnline: () => _showOnlineSheet(GameType.oneNight),
                    demoLabel: '单人快速体验一夜狼（AI 陪玩 · 3/5/7人局）',
                    onDemo: _showOneNightDemoPicker,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GameHeroCard extends StatelessWidget {
  const _GameHeroCard({
    required this.badgeText,
    required this.badgeColor,
    required this.icon,
    required this.gradientColors,
    required this.borderColor,
    required this.title,
    required this.description,
    required this.primaryButtonLabel,
    required this.onLanHost,
    required this.onLanJoin,
    required this.onOnline,
    required this.demoLabel,
    required this.onDemo,
  });

  final String badgeText;
  final Color badgeColor;
  final IconData icon;
  final List<Color> gradientColors;
  final Color borderColor;
  final String title;
  final String description;
  final String primaryButtonLabel;
  final VoidCallback onLanHost;
  final VoidCallback onLanJoin;
  final VoidCallback onOnline;
  final String demoLabel;
  final VoidCallback onDemo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        border: Border.all(color: borderColor, width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              Icon(icon, color: badgeColor),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: const TextStyle(
              color: PartyColors.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onLanHost,
              icon: const Icon(Icons.wifi_tethering),
              label: Text(primaryButtonLabel),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onLanJoin,
                  icon: const Icon(Icons.radar, size: 18),
                  label: const Text('加入局域网房'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onOnline,
                  icon: const Icon(Icons.cloud_outlined, size: 18),
                  label: const Text('联网模式'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: onDemo,
              icon: const Icon(
                Icons.smart_toy_outlined,
                color: PartyColors.seerCyan,
              ),
              label: Text(
                demoLabel,
                style: const TextStyle(
                  color: PartyColors.seerCyan,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoPresetTile extends StatelessWidget {
  const _DemoPresetTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlight = false,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: highlight ? PartyColors.gold : PartyColors.border,
        ),
      ),
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: PartyColors.textSecondary, fontSize: 12),
        ),
        trailing: const Icon(Icons.play_arrow_rounded, color: PartyColors.gold),
        onTap: onTap,
      ),
    );
  }
}
