import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:party_core/party_core.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/state/app_controller.dart';
import '../../core/theme/party_theme.dart';

class LobbyPage extends StatelessWidget {
  const LobbyPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final snap = controller.snapshot!;
    final isGuandan = snap.gameType == GameType.guandan;
    final isOneNight = snap.gameType == GameType.oneNight;
    final wwConfig =
        (!isGuandan && !isOneNight) ? WerewolfConfig.fromJson(snap.gameConfig) : null;
    final gdConfig = isGuandan ? GuandanConfig.fromJson(snap.gameConfig) : null;
    final onConfig = isOneNight ? OneNightConfig.fromJson(snap.gameConfig) : null;
    final requiredPlayers = isGuandan
        ? 4
        : isOneNight
            ? onConfig!.requiredPlayers
            : wwConfig!.totalPlayers;

    final endpoint = controller.endpointInfo;
    final isHost = snap.isHost;
    final me = snap.me;

    final canStart = snap.players.length == requiredPlayers &&
        snap.players.every((p) => p.isHost || p.isReady);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '离开房间',
          onPressed: () => controller.leaveRoom(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${snap.gameType.displayName}大厅 · 房号 ${snap.roomCode}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            Text(
              endpoint?.label ?? '房间已连接',
              style: const TextStyle(fontSize: 12, color: PartyColors.gold),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: controller.ttsEnabled ? '关闭语音播报' : '开启语音播报',
            icon: Icon(
              controller.ttsEnabled ? Icons.volume_up : Icons.volume_off,
              color:
                  controller.ttsEnabled ? PartyColors.gold : PartyColors.textMuted,
            ),
            onPressed: controller.toggleTts,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              // Share Card (LAN QR / Online Room Code)
              if (endpoint?.lanWsUrl != null &&
                  endpoint?.mode == ConnectionMode.lanHost)
                _LanHostShareCard(
                  wsUrl: endpoint!.lanWsUrl!,
                  roomCode: snap.roomCode,
                )
              else if (endpoint?.mode == ConnectionMode.online)
                _OnlineShareCard(roomCode: snap.roomCode),

              const SizedBox(height: 14),

              // Game-specific Configuration Card
              if (isGuandan)
                _GuandanConfigCard(
                  config: gdConfig!,
                  isHost: isHost,
                  onChanged: controller.updateGuandanConfig,
                )
              else if (isOneNight)
                _OneNightConfigCard(
                  config: onConfig!,
                  isHost: isHost,
                  onChanged: controller.updateOneNightConfig,
                )
              else
                _WerewolfConfigCard(
                  config: wwConfig!,
                  isHost: isHost,
                  onChanged: controller.updateConfig,
                ),

              const SizedBox(height: 14),

              // Players List
              Row(
                children: [
                  Text(
                    '已入座玩家（${snap.players.length} / $requiredPlayers）',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (isHost &&
                      endpoint?.mode != ConnectionMode.localDemo &&
                      snap.players.length < requiredPlayers)
                    TextButton.icon(
                      onPressed: () => controller.addBot(
                        count: requiredPlayers - snap.players.length,
                      ),
                      icon: const Icon(Icons.smart_toy_outlined, size: 16),
                      label: const Text('补齐测试占位'),
                    ),
                ],
              ),
              if (isGuandan)
                const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 6),
                  child: Text(
                    '座位分队规则：1号 & 3号 为红队（对家），2号 & 4号 为蓝队（对家）',
                    style: TextStyle(
                      fontSize: 12,
                      color: PartyColors.textSecondary,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: isGuandan ? 2 : 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: isGuandan ? 1.65 : 1.05,
                ),
                itemCount: requiredPlayers,
                itemBuilder: (ctx, index) {
                  final seatNum = index + 1;
                  final player = snap.players
                      .where((p) => p.seatNumber == seatNum)
                      .firstOrNull;
                  return _SeatCard(
                    seatNumber: seatNum,
                    player: player,
                    isMe: player != null && player.id == snap.yourPlayerId,
                    teamTag: isGuandan
                        ? (seatNum.isOdd ? '红队' : '蓝队')
                        : null,
                    teamColor: isGuandan
                        ? (seatNum.isOdd
                            ? PartyColors.wolfRed
                            : PartyColors.seerCyan)
                        : null,
                  );
                },
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          decoration: const BoxDecoration(
            color: PartyColors.bgSurface,
            border: Border(top: BorderSide(color: PartyColors.border)),
          ),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: isHost
                  ? SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: canStart ? controller.startGame : null,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(
                          canStart
                              ? (isGuandan
                                  ? '开始发牌（4人掼蛋 · 打 ${GuandanState.levelLabel(gdConfig!.startLevel)} 起）'
                                  : isOneNight
                                      ? '开始发牌（${onConfig!.requiredPlayers}人一夜狼 · ${onConfig.roles.length}张牌）'
                                      : '开始发牌（${wwConfig!.totalPlayers}人${wwConfig.enableSheriff ? " · 含警长" : ""}）')
                              : '等待人数满 $requiredPlayers 人且全员准备（当前 ${snap.players.length} 人）',
                        ),
                      ),
                    )
                  : SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: controller.toggleReady,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: (me?.isReady ?? false)
                              ? PartyColors.bgElevated
                              : PartyColors.gold,
                          foregroundColor: (me?.isReady ?? false)
                              ? PartyColors.textPrimary
                              : const Color(0xFF1A1400),
                        ),
                        icon: Icon(
                          (me?.isReady ?? false)
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                        ),
                        label: Text(
                          (me?.isReady ?? false) ? '已准备（点击取消）' : '点击准备',
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OneNightConfigCard extends StatelessWidget {
  const _OneNightConfigCard({
    required this.config,
    required this.isHost,
    required this.onChanged,
  });

  final OneNightConfig config;
  final bool isHost;
  final ValueChanged<OneNightConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final presets = [
      ('3人迷你局 (6牌)', OneNightConfig.preset3()),
      ('5人经典局 (8牌)', OneNightConfig.preset5()),
      ('7人进阶局 (10牌)', OneNightConfig.preset7()),
    ];

    final counts = <OneNightRole, int>{};
    for (final r in config.roles) {
      counts[r] = (counts[r] ?? 0) + 1;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.dark_mode,
                  color: PartyColors.witchPurple,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  '一夜狼角色牌组（${config.requiredPlayers}人 + 3张底牌 = ${config.roles.length}张）',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: presets.map((entry) {
                final (label, preset) = entry;
                final selected = config.presetId == preset.presetId;
                return ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  selectedColor: PartyColors.witchPurple.withValues(alpha: 0.25),
                  labelStyle: TextStyle(
                    color: selected
                        ? PartyColors.gold
                        : PartyColors.textPrimary,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 12.5,
                  ),
                  onSelected: isHost ? (_) => onChanged(preset) : null,
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: OneNightRole.values.map((role) {
                final count = counts[role] ?? 0;
                if (!isHost && count == 0) return const SizedBox.shrink();
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: PartyColors.bgSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: count > 0
                          ? PartyColors.witchPurple.withValues(alpha: 0.55)
                          : PartyColors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${role.displayName} ×$count',
                        style: TextStyle(
                          fontSize: 12,
                          color: count > 0
                              ? PartyColors.textPrimary
                              : PartyColors.textMuted,
                        ),
                      ),
                      if (isHost) ...[
                        const SizedBox(width: 6),
                        _MiniStepBtn(
                          icon: Icons.remove,
                          onTap: count > 0
                              ? () {
                                  final next = List<OneNightRole>.from(config.roles);
                                  next.remove(role);
                                  if (next.length >= 6) {
                                    onChanged(config.copyWith(
                                      presetId: 'custom',
                                      roles: next,
                                    ));
                                  }
                                }
                              : null,
                        ),
                        const SizedBox(width: 4),
                        _MiniStepBtn(
                          icon: Icons.add,
                          onTap: config.roles.length < 13 && count < 3
                              ? () {
                                  final next = [...config.roles, role];
                                  onChanged(config.copyWith(
                                    presetId: 'custom',
                                    roles: next,
                                  ));
                                }
                              : null,
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuandanConfigCard extends StatelessWidget {
  const _GuandanConfigCard({
    required this.config,
    required this.isHost,
    required this.onChanged,
  });

  final GuandanConfig config;
  final bool isHost;
  final ValueChanged<GuandanConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final startOptions = [
      (2, '经典从 2 打起'),
      (10, '快速从 10 打起'),
      (14, '直接打 A 决胜'),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.style, color: PartyColors.guardGreen, size: 18),
                SizedBox(width: 8),
                Text(
                  '掼蛋规则配置（4人 · 2副牌108张）',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: startOptions.map((opt) {
                final (lvl, label) = opt;
                final selected = config.startLevel == lvl;
                return ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  selectedColor: PartyColors.goldSoft,
                  labelStyle: TextStyle(
                    color: selected ? PartyColors.gold : PartyColors.textPrimary,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 12.5,
                  ),
                  onSelected: isHost
                      ? (_) => onChanged(config.copyWith(startLevel: lvl))
                      : null,
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            const Divider(color: PartyColors.border),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('开启进贡 / 还贡（含双大王抗贡）',
                  style: TextStyle(fontSize: 13.5)),
              subtitle: const Text(
                '双下或单下时，下一局由败方进贡最大非逢人配牌，赢家还贡 ≤10 牌',
                style: TextStyle(fontSize: 11.5, color: PartyColors.textSecondary),
              ),
              value: config.enableTribute,
              onChanged: isHost
                  ? (v) => onChanged(config.copyWith(enableTribute: v))
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _LanHostShareCard extends StatelessWidget {
  const _LanHostShareCard({required this.wsUrl, required this.roomCode});

  final String wsUrl;
  final String roomCode;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: wsUrl,
                version: QrVersions.auto,
                size: 92,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.wifi_tethering,
                          color: PartyColors.gold, size: 18),
                      SizedBox(width: 6),
                      Text(
                        '局域网/热点主机已开启',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '朋友连上你的热点或同一 Wi-Fi 后，点「加入局域网房」自动发现，或手动输入：',
                    style: TextStyle(
                      color: PartyColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: wsUrl));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制局域网连接地址')),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: PartyColors.bgSurface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: PartyColors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              wsUrl,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                color: PartyColors.gold,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.copy,
                              size: 14, color: PartyColors.gold),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnlineShareCard extends StatelessWidget {
  const _OnlineShareCard({required this.roomCode});
  final String roomCode;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.cloud_done, color: PartyColors.seerCyan),
        title: Text(
          '联网房间号：$roomCode',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        subtitle: const Text('把 4 位房间号告诉朋友即可联网加入'),
        trailing: IconButton(
          icon: const Icon(Icons.copy, color: PartyColors.gold),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: roomCode));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已复制房间号')),
            );
          },
        ),
      ),
    );
  }
}

class _WerewolfConfigCard extends StatelessWidget {
  const _WerewolfConfigCard({
    required this.config,
    required this.isHost,
    required this.onChanged,
  });

  final WerewolfConfig config;
  final bool isHost;
  final ValueChanged<WerewolfConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final presets = [
      ('6人速局', WerewolfConfig.preset6()),
      ('9人预女猎', WerewolfConfig.preset9()),
      ('12人预女猎白(警长)', WerewolfConfig.preset12Idiot()),
      ('12人预女猎守(警长)', WerewolfConfig.preset12Guard()),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tune, color: PartyColors.gold, size: 18),
                const SizedBox(width: 8),
                Text(
                  '板子与规则配置（${config.totalPlayers}人局）',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: presets.map((entry) {
                final (label, preset) = entry;
                final selected = config.presetId == preset.presetId;
                return ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  selectedColor: PartyColors.goldSoft,
                  labelStyle: TextStyle(
                    color: selected ? PartyColors.gold : PartyColors.textPrimary,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 12.5,
                  ),
                  onSelected: isHost ? (_) => onChanged(preset) : null,
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: WerewolfRole.values.map((role) {
                final count = config.roleCounts[role] ?? 0;
                if (!isHost && count == 0) return const SizedBox.shrink();
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: PartyColors.bgSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: count > 0
                          ? PartyColors.gold.withValues(alpha: 0.4)
                          : PartyColors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${role.displayName} ×$count',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: count > 0
                              ? PartyColors.textPrimary
                              : PartyColors.textMuted,
                        ),
                      ),
                      if (isHost) ...[
                        const SizedBox(width: 6),
                        _MiniStepBtn(
                          icon: Icons.remove,
                          onTap: count > 0
                              ? () => _updateRole(role, count - 1)
                              : null,
                        ),
                        const SizedBox(width: 4),
                        _MiniStepBtn(
                          icon: Icons.add,
                          onTap: count < 6
                              ? () => _updateRole(role, count + 1)
                              : null,
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            const Divider(color: PartyColors.border),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('警长竞选（12人局默认开启）',
                  style: TextStyle(fontSize: 13.5)),
              subtitle: const Text(
                '首日天亮前上警竞选，警长拥有 1.5 票并可移交/撕毁警徽',
                style:
                    TextStyle(fontSize: 11.5, color: PartyColors.textSecondary),
              ),
              value: config.enableSheriff,
              onChanged: isHost
                  ? (v) => onChanged(config.copyWith(enableSheriff: v))
                  : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('女巫首夜可自救', style: TextStyle(fontSize: 13.5)),
              value: config.witchSelfSaveFirstNight,
              onChanged: isHost
                  ? (v) =>
                      onChanged(config.copyWith(witchSelfSaveFirstNight: v))
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  void _updateRole(WerewolfRole role, int nextCount) {
    final nextMap = Map<WerewolfRole, int>.from(config.roleCounts);
    if (nextCount <= 0) {
      nextMap.remove(role);
    } else {
      nextMap[role] = nextCount;
    }
    final nextTotal = nextMap.values.fold<int>(0, (s, c) => s + c);
    onChanged(
      config.copyWith(
        presetId: 'custom',
        roleCounts: nextMap,
        enableSheriff: nextTotal >= 12 ? true : config.enableSheriff,
      ),
    );
  }
}

class _MiniStepBtn extends StatelessWidget {
  const _MiniStepBtn({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: PartyColors.bgElevated,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          size: 14,
          color: onTap == null ? PartyColors.textMuted : PartyColors.gold,
        ),
      ),
    );
  }
}

class _SeatCard extends StatelessWidget {
  const _SeatCard({
    required this.seatNumber,
    required this.player,
    required this.isMe,
    this.teamTag,
    this.teamColor,
  });

  final int seatNumber;
  final PlayerInfo? player;
  final bool isMe;
  final String? teamTag;
  final Color? teamColor;

  @override
  Widget build(BuildContext context) {
    final occupied = player != null;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: occupied ? PartyColors.bgCard : PartyColors.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMe
              ? PartyColors.gold
              : teamColor != null
                  ? teamColor!.withValues(alpha: 0.55)
                  : occupied
                      ? PartyColors.border
                      : PartyColors.border.withValues(alpha: 0.4),
          width: isMe ? 1.6 : 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                teamTag != null ? '$seatNumber号 · $teamTag' : '$seatNumber号',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: teamColor ?? PartyColors.gold,
                ),
              ),
              if (player?.isHost == true)
                const Icon(Icons.star, size: 14, color: PartyColors.gold)
              else if (player?.isReady == true)
                const Icon(
                  Icons.check_circle,
                  size: 14,
                  color: PartyColors.guardGreen,
                ),
            ],
          ),
          const SizedBox(height: 6),
          CircleAvatar(
            radius: 17,
            backgroundColor: occupied
                ? (player!.isConnected
                    ? PartyColors.bgElevated
                    : PartyColors.wolfRedSoft)
                : PartyColors.bgDeep,
            child: Text(
              occupied ? player!.name.characters.first : '+',
              style: TextStyle(
                color: occupied ? PartyColors.textPrimary : PartyColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            occupied ? player!.name : '空位',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: occupied ? PartyColors.textPrimary : PartyColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
