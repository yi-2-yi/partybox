import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:party_core/party_core.dart';

import '../../../core/state/app_controller.dart';
import '../../../core/theme/party_theme.dart';

Color oneNightRoleColor(OneNightRole role) => switch (role) {
      OneNightRole.werewolf => PartyColors.wolfRed,
      OneNightRole.minion => const Color(0xFFF43F5E),
      OneNightRole.tanner => const Color(0xFFF59E0B),
      OneNightRole.seer => PartyColors.seerCyan,
      OneNightRole.robber => PartyColors.witchPurple,
      OneNightRole.troublemaker => const Color(0xFFEC4899),
      OneNightRole.drunk => const Color(0xFFFB923C),
      OneNightRole.insomniac => PartyColors.guardGreen,
      OneNightRole.mason => const Color(0xFF60A5FA),
      OneNightRole.hunter => const Color(0xFFEAB308),
      OneNightRole.villager => PartyColors.textSecondary,
    };

class OneNightTablePage extends StatefulWidget {
  const OneNightTablePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<OneNightTablePage> createState() => _OneNightTablePageState();
}

class _OneNightTablePageState extends State<OneNightTablePage> {
  final Set<String> _selectedPlayerIds = {};
  final Set<int> _selectedCenterIndices = {};
  String? _lastStepKey;

  Timer? _discussTimer;
  int _discussSecondsLeft = 300;
  bool _timerRunning = false;

  @override
  void dispose() {
    _discussTimer?.cancel();
    super.dispose();
  }

  void _syncStepReset(String stepKey, int defaultDiscussSeconds) {
    if (_lastStepKey != stepKey) {
      _lastStepKey = stepKey;
      _selectedPlayerIds.clear();
      _selectedCenterIndices.clear();
      if (!stepKey.startsWith('dayDiscuss')) {
        _discussTimer?.cancel();
        _timerRunning = false;
      } else {
        _discussSecondsLeft = defaultDiscussSeconds;
      }
    }
  }

  void _toggleTimer() {
    if (_timerRunning) {
      _discussTimer?.cancel();
      setState(() => _timerRunning = false);
      return;
    }
    setState(() => _timerRunning = true);
    _discussTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_discussSecondsLeft <= 1) {
        t.cancel();
        setState(() {
          _discussSecondsLeft = 0;
          _timerRunning = false;
        });
      } else {
        setState(() => _discussSecondsLeft--);
      }
    });
  }

  void _showSecretNotesDialog({
    required OneNightRole initialRole,
    required int seatNumber,
    required List<String> notes,
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _OneNightRolePeekCard(
              role: initialRole,
              seatNumber: seatNumber,
              nightNotes: notes,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final snap = ctrl.snapshot!;
    final gs = snap.gameState!;

    final phase = OneNightPhase.fromName(gs['phase'] as String);
    final config = OneNightConfig.fromJson(
      Map<String, dynamic>.from(gs['config'] as Map),
    );
    final activeWakeRoleName = gs['activeWakeRole'] as String?;
    final activeWakeRole = activeWakeRoleName == null
        ? null
        : OneNightRole.fromName(activeWakeRoleName);
    final wakeIndex = (gs['wakeIndex'] as num?)?.toInt() ?? 0;
    final wakeTotal = (gs['wakeTotal'] as num?)?.toInt() ?? 0;
    final isDecoy = gs['isDecoyStep'] as bool? ?? false;
    final isMyNightTurn = gs['isMyNightTurn'] as bool? ?? false;
    final isLoneWolf = gs['isLoneWolf'] as bool? ?? false;

    _syncStepReset('${phase.name}_$wakeIndex', config.discussSeconds);

    final meMap = Map<String, dynamic>.from(gs['me'] as Map);
    final myId = meMap['playerId'] as String;
    final mySeat = (meMap['seatNumber'] as num).toInt();
    final myInitialRole = OneNightRole.fromName(meMap['initialRole'] as String);
    final myConfirmed = meMap['confirmedRole'] as bool? ?? false;
    final myHasVoted = meMap['hasVoted'] as bool? ?? false;
    final myNotes = ((meMap['nightNotes'] as List?) ?? const []).cast<String>();

    final players = (gs['players'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final votedIds = ((gs['votedIds'] as List?) ?? const []).cast<String>().toSet();

    final canSelectPlayers = _canSelectPlayers(
      phase: phase,
      isMyNightTurn: isMyNightTurn,
      activeWakeRole: activeWakeRole,
      myHasVoted: myHasVoted,
    );
    final canSelectCenters = _canSelectCenters(
      phase: phase,
      isMyNightTurn: isMyNightTurn,
      activeWakeRole: activeWakeRole,
      isLoneWolf: isLoneWolf,
    );

    final isNight = phase == OneNightPhase.nightStep;
    final bgTop = isNight ? const Color(0xFF0A0618) : const Color(0xFF15122B);

    return Scaffold(
      backgroundColor: bgTop,
      appBar: AppBar(
        backgroundColor: bgTop,
        leading: IconButton(
          icon: const Icon(Icons.exit_to_app),
          tooltip: '退出房间',
          onPressed: ctrl.leaveRoom,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              phase == OneNightPhase.nightStep && activeWakeRole != null
                  ? '一夜狼 · ${activeWakeRole.displayName} (${wakeIndex + 1}/$wakeTotal)'
                  : '一夜终极狼人 · ${phase.displayName}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            Text(
              '$mySeat号 · 共 ${players.length} 人 + 3 张底牌',
              style: const TextStyle(fontSize: 12, color: PartyColors.witchPurple),
            ),
          ],
        ),
        actions: [
          if (phase != OneNightPhase.roleReveal &&
              phase != OneNightPhase.gameOver)
            TextButton.icon(
              onPressed: () => _showSecretNotesDialog(
                initialRole: myInitialRole,
                seatNumber: mySeat,
                notes: myNotes,
              ),
              icon: const Icon(Icons.visibility_outlined, size: 17),
              label: const Text('我的记忆', style: TextStyle(fontSize: 12)),
            ),
          IconButton(
            icon: Icon(
              ctrl.ttsEnabled ? Icons.volume_up : Icons.volume_off,
              color: ctrl.ttsEnabled ? PartyColors.gold : PartyColors.textMuted,
            ),
            onPressed: ctrl.toggleTts,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: [
              if (ctrl.latestEvent != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: PartyColors.witchPurple.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: PartyColors.witchPurple.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isNight ? Icons.dark_mode : Icons.auto_awesome,
                        color: PartyColors.gold,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          ctrl.latestEvent!.message,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: PartyColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              Expanded(
                child: phase == OneNightPhase.gameOver
                    ? _buildGameOverView(gs, players, snap.isHost)
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        children: [
                          if (phase == OneNightPhase.roleReveal) ...[
                            _OneNightRolePeekCard(
                              role: myInitialRole,
                              seatNumber: mySeat,
                              nightNotes: myNotes,
                            ),
                            const SizedBox(height: 14),
                          ],

                          // 3 Center Cards Row (底牌 A / B / C)
                          Row(
                            children: List.generate(3, (idx) {
                              final selected =
                                  _selectedCenterIndices.contains(idx);
                              return Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    right: idx < 2 ? 8 : 0,
                                  ),
                                  child: InkWell(
                                    onTap: canSelectCenters
                                        ? () => _onTapCenterCard(
                                              idx,
                                              activeWakeRole!,
                                            )
                                        : null,
                                    borderRadius: BorderRadius.circular(14),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 140),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                        horizontal: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? PartyColors.goldSoft
                                            : PartyColors.bgCard,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: selected
                                              ? PartyColors.gold
                                              : canSelectCenters
                                                  ? PartyColors.witchPurple
                                                  : PartyColors.border,
                                          width: selected ? 2 : 1,
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          Icon(
                                            Icons.help_outline_rounded,
                                            color: selected
                                                ? PartyColors.gold
                                                : PartyColors.witchPurple,
                                            size: 22,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            OneNightEngine.centerLabels[idx],
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: selected
                                                  ? PartyColors.gold
                                                  : PartyColors.textPrimary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),

                          const SizedBox(height: 14),

                          // Player Seat Grid
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              childAspectRatio: 1.05,
                            ),
                            itemCount: players.length,
                            itemBuilder: (ctx, idx) {
                              final p = players[idx];
                              final pid = p['playerId'] as String;
                              final isMe = pid == myId;
                              final selectable = canSelectPlayers && !isMe;
                              final selected = _selectedPlayerIds.contains(pid);

                              return InkWell(
                                onTap: selectable
                                    ? () => _onTapPlayer(
                                          pid,
                                          phase: phase,
                                          activeWakeRole: activeWakeRole,
                                        )
                                    : null,
                                borderRadius: BorderRadius.circular(14),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 140),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? PartyColors.goldSoft
                                        : PartyColors.bgCard,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: selected
                                          ? PartyColors.gold
                                          : selectable
                                              ? PartyColors.seerCyan
                                                  .withValues(alpha: 0.6)
                                              : isMe
                                                  ? PartyColors.gold
                                                      .withValues(alpha: 0.45)
                                                  : PartyColors.border,
                                      width: selected ? 2 : 1,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            '${p['seatNumber']}号',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: PartyColors.gold,
                                            ),
                                          ),
                                          const Spacer(),
                                          if ((phase == OneNightPhase.roleReveal &&
                                                  (p['confirmedRole'] as bool? ??
                                                      false)) ||
                                              (phase == OneNightPhase.dayVote &&
                                                  votedIds.contains(pid)))
                                            const Icon(
                                              Icons.check_circle,
                                              size: 14,
                                              color: PartyColors.guardGreen,
                                            ),
                                        ],
                                      ),
                                      CircleAvatar(
                                        radius: 17,
                                        backgroundColor: PartyColors.bgElevated,
                                        child: Text(
                                          (p['name'] as String)
                                              .characters
                                              .first,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: PartyColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        isMe ? '${p['name']}(我)' : '${p['name']}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
              ),

              if (phase != OneNightPhase.gameOver)
                _buildBottomPanel(
                  phase: phase,
                  isHost: snap.isHost,
                  isDecoy: isDecoy,
                  isMyNightTurn: isMyNightTurn,
                  isLoneWolf: isLoneWolf,
                  activeWakeRole: activeWakeRole,
                  myConfirmed: myConfirmed,
                  myHasVoted: myHasVoted,
                  myNotes: myNotes,
                  players: players,
                  votedIds: votedIds,
                ),
            ],
          ),
        ),
      ),
    );
  }

  bool _canSelectPlayers({
    required OneNightPhase phase,
    required bool isMyNightTurn,
    required OneNightRole? activeWakeRole,
    required bool myHasVoted,
  }) {
    if (phase == OneNightPhase.dayVote) return !myHasVoted;
    if (phase != OneNightPhase.nightStep || !isMyNightTurn) return false;
    return activeWakeRole == OneNightRole.seer ||
        activeWakeRole == OneNightRole.robber ||
        activeWakeRole == OneNightRole.troublemaker;
  }

  bool _canSelectCenters({
    required OneNightPhase phase,
    required bool isMyNightTurn,
    required OneNightRole? activeWakeRole,
    required bool isLoneWolf,
  }) {
    if (phase != OneNightPhase.nightStep || !isMyNightTurn) return false;
    if (activeWakeRole == OneNightRole.werewolf) return isLoneWolf;
    return activeWakeRole == OneNightRole.seer ||
        activeWakeRole == OneNightRole.drunk;
  }

  void _onTapPlayer(
    String pid, {
    required OneNightPhase phase,
    required OneNightRole? activeWakeRole,
  }) {
    setState(() {
      _selectedCenterIndices.clear();
      if (phase == OneNightPhase.nightStep &&
          activeWakeRole == OneNightRole.troublemaker) {
        if (_selectedPlayerIds.contains(pid)) {
          _selectedPlayerIds.remove(pid);
        } else if (_selectedPlayerIds.length < 2) {
          _selectedPlayerIds.add(pid);
        }
      } else {
        if (_selectedPlayerIds.contains(pid)) {
          _selectedPlayerIds.clear();
        } else {
          _selectedPlayerIds
            ..clear()
            ..add(pid);
        }
      }
    });
  }

  void _onTapCenterCard(int idx, OneNightRole activeWakeRole) {
    setState(() {
      _selectedPlayerIds.clear();
      if (activeWakeRole == OneNightRole.seer) {
        if (_selectedCenterIndices.contains(idx)) {
          _selectedCenterIndices.remove(idx);
        } else if (_selectedCenterIndices.length < 2) {
          _selectedCenterIndices.add(idx);
        }
      } else {
        if (_selectedCenterIndices.contains(idx)) {
          _selectedCenterIndices.clear();
        } else {
          _selectedCenterIndices
            ..clear()
            ..add(idx);
        }
      }
    });
  }

  Widget _buildBottomPanel({
    required OneNightPhase phase,
    required bool isHost,
    required bool isDecoy,
    required bool isMyNightTurn,
    required bool isLoneWolf,
    required OneNightRole? activeWakeRole,
    required bool myConfirmed,
    required bool myHasVoted,
    required List<String> myNotes,
    required List<Map<String, dynamic>> players,
    required Set<String> votedIds,
  }) {
    final ctrl = widget.controller;
    Widget content;

    switch (phase) {
      case OneNightPhase.roleReveal:
        final confirmedCount =
            players.where((p) => p['confirmedRole'] as bool? ?? false).length;
        content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '已确认初始身份：$confirmedCount / ${players.length} 人',
              style:
                  const TextStyle(color: PartyColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: myConfirmed
                    ? null
                    : () => ctrl.sendGameAction(OneNightActionType.confirmRole),
                icon: Icon(myConfirmed ? Icons.check : Icons.done_all),
                label: Text(myConfirmed ? '已确认，等待其他玩家…' : '我已记住初始身份，准备天黑'),
              ),
            ),
          ],
        );

      case OneNightPhase.nightStep:
        if (!isMyNightTurn || activeWakeRole == null) {
          content = Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.bedtime_outlined,
                    color: PartyColors.textSecondary),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    isDecoy
                        ? '天黑请闭眼，请保持安静等待下一角色…'
                        : '天黑请闭眼，当前为【${activeWakeRole?.displayName ?? "其他角色"}】行动时间。',
                    style: const TextStyle(
                      color: PartyColors.textSecondary,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ],
            ),
          );
        } else {
          content = _buildNightActorControls(
            role: activeWakeRole,
            isLoneWolf: isLoneWolf,
            myNotes: myNotes,
          );
        }

      case OneNightPhase.dayDiscuss:
        final mins = (_discussSecondsLeft ~/ 60).toString().padLeft(2, '0');
        final secs = (_discussSecondsLeft % 60).toString().padLeft(2, '0');
        content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.timer_outlined, color: PartyColors.gold),
                const SizedBox(width: 8),
                Text(
                  '推理倒计时：$mins:$secs',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _toggleTimer,
                  child: Text(_timerRunning ? '暂停' : '开始计时'),
                ),
              ],
            ),
            if (myNotes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '提示：点右上角「我的记忆」可私密回顾夜晚线索（小心别被旁边看到）',
                  style: const TextStyle(
                    fontSize: 12,
                    color: PartyColors.textSecondary,
                  ),
                ),
              ),
            if (isHost)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () =>
                      ctrl.sendGameAction(OneNightActionType.startVote),
                  icon: const Icon(Icons.how_to_vote),
                  label: const Text('结束讨论，开启全员同步投票'),
                ),
              )
            else
              const Text(
                '大家自由推理发言，房主将统一开启同步投票。',
                style: TextStyle(color: PartyColors.textSecondary, fontSize: 13),
              ),
          ],
        );

      case OneNightPhase.dayVote:
        content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '全员同步投票 · 已投 ${votedIds.length} / ${players.length} 人（不可投自己）',
              style: const TextStyle(color: PartyColors.gold, fontSize: 13),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (myHasVoted || _selectedPlayerIds.length != 1)
                    ? null
                    : () => ctrl.sendGameAction(OneNightActionType.castVote, {
                          'targetId': _selectedPlayerIds.first,
                        }),
                icon: const Icon(Icons.how_to_vote),
                label: Text(
                  myHasVoted
                      ? '已投票，等待其他玩家…'
                      : (_selectedPlayerIds.isEmpty
                          ? '请点击上方一名其他玩家投票'
                          : '确认投给 ${_seatLabel(players, _selectedPlayerIds.first)}'),
                ),
              ),
            ),
          ],
        );

      case OneNightPhase.gameOver:
        content = const SizedBox.shrink();
    }

    final showHostOverride = isHost &&
        phase != OneNightPhase.dayDiscuss &&
        phase != OneNightPhase.gameOver;

    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: const BoxDecoration(
          color: PartyColors.bgSurface,
          border: Border(top: BorderSide(color: PartyColors.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            content,
            if (showHostOverride) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: PartyColors.textMuted,
                  ),
                  onPressed: () =>
                      ctrl.sendGameAction(OneNightActionType.hostAdvance),
                  icon: const Icon(Icons.skip_next, size: 16),
                  label: Text(
                    isDecoy ? '跳过底牌空过等待' : '房主手动推进',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNightActorControls({
    required OneNightRole role,
    required bool isLoneWolf,
    required List<String> myNotes,
  }) {
    final ctrl = widget.controller;
    final latestNote = myNotes.isNotEmpty ? myNotes.last : null;

    switch (role) {
      case OneNightRole.werewolf:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (latestNote != null)
              Text(
                latestNote,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: PartyColors.wolfRed,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            const SizedBox(height: 10),
            if (isLoneWolf)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => ctrl.sendGameAction(
                        OneNightActionType.nightAct,
                        const {},
                      ),
                      child: const Text('不看底牌'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _selectedCenterIndices.length == 1
                          ? () => ctrl.sendGameAction(
                                OneNightActionType.nightAct,
                                {'centerIndex': _selectedCenterIndices.first},
                              )
                          : null,
                      child: const Text('偷看选中底牌'),
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => ctrl.sendGameAction(
                    OneNightActionType.nightAct,
                    const {},
                  ),
                  child: const Text('已确认狼队友，闭眼'),
                ),
              ),
          ],
        );

      case OneNightRole.minion:
      case OneNightRole.mason:
      case OneNightRole.insomniac:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (latestNote != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: PartyColors.goldSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  latestNote,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: PartyColors.gold,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => ctrl.sendGameAction(
                  OneNightActionType.nightAct,
                  const {},
                ),
                child: const Text('已记住信息，闭眼'),
              ),
            ),
          ],
        );

      case OneNightRole.seer:
        final readyPlayer = _selectedPlayerIds.length == 1;
        final readyCenter = _selectedCenterIndices.length == 2;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '预言家：点击上方【1名其他玩家】或【2张底牌】进行查验',
              style: TextStyle(color: PartyColors.seerCyan, fontSize: 13),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: PartyColors.seerCyan,
                  foregroundColor: const Color(0xFF041A24),
                ),
                onPressed: (readyPlayer || readyCenter)
                    ? () {
                        if (readyPlayer) {
                          ctrl.sendGameAction(OneNightActionType.nightAct, {
                            'mode': 'player',
                            'targetId': _selectedPlayerIds.first,
                          });
                        } else {
                          ctrl.sendGameAction(OneNightActionType.nightAct, {
                            'mode': 'center',
                            'centerIndices': _selectedCenterIndices.toList(),
                          });
                        }
                      }
                    : null,
                child: Text(
                  readyPlayer
                      ? '查验选中的玩家'
                      : (readyCenter ? '查验选中的 2 张底牌' : '请选择查验目标'),
                ),
              ),
            ),
          ],
        );

      case OneNightRole.robber:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '强盗：选择 1 名其他玩家交换身份牌并查看你的新身份',
              style: TextStyle(color: PartyColors.witchPurple, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => ctrl.sendGameAction(
                      OneNightActionType.nightAct,
                      const {},
                    ),
                    child: const Text('不换牌'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _selectedPlayerIds.length == 1
                        ? () => ctrl.sendGameAction(
                              OneNightActionType.nightAct,
                              {'targetId': _selectedPlayerIds.first},
                            )
                        : null,
                    child: const Text('交换并查看新牌'),
                  ),
                ),
              ],
            ),
          ],
        );

      case OneNightRole.troublemaker:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '捣蛋鬼：选择 2 名其他玩家盲换身份牌（已选 ${_selectedPlayerIds.length}/2）',
              style: const TextStyle(color: Color(0xFFEC4899), fontSize: 13),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => ctrl.sendGameAction(
                      OneNightActionType.nightAct,
                      const {},
                    ),
                    child: const Text('不换牌'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _selectedPlayerIds.length == 2
                        ? () => ctrl.sendGameAction(
                              OneNightActionType.nightAct,
                              {'targetIds': _selectedPlayerIds.toList()},
                            )
                        : null,
                    child: const Text('确认盲换两人'),
                  ),
                ),
              ],
            ),
          ],
        );

      case OneNightRole.drunk:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '酒鬼：必须点击上方 1 张中间底牌与自己盲换（不查看）',
              style: TextStyle(color: Color(0xFFFB923C), fontSize: 13),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selectedCenterIndices.length == 1
                    ? () => ctrl.sendGameAction(
                          OneNightActionType.nightAct,
                          {'centerIndex': _selectedCenterIndices.first},
                        )
                    : null,
                child: const Text('确认与该底牌盲换'),
              ),
            ),
          ],
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildGameOverView(
    Map<String, dynamic> gs,
    List<Map<String, dynamic>> players,
    bool isHost,
  ) {
    final winnerTeam = gs['winnerTeam'] as String? ?? 'good';
    final winnerSummary = gs['winnerSummary'] as String? ?? '';
    final eliminated = ((gs['eliminatedPlayerIds'] as List?) ?? const [])
        .cast<String>()
        .toSet();
    final centerCards = ((gs['centerCards'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final replayLogs =
        ((gs['nightReplayLogs'] as List?) ?? const []).cast<String>();

    final headline = switch (winnerTeam) {
      'good' => '好人阵营获胜！',
      'wolf' => '狼人阵营获胜！',
      'tanner' => '皮匠独自获胜！',
      _ => '好人与皮匠共同获胜！',
    };
    final accent = winnerTeam == 'wolf'
        ? PartyColors.wolfRed
        : winnerTeam == 'tanner'
            ? const Color(0xFFF59E0B)
            : PartyColors.gold;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [accent.withValues(alpha: 0.22), PartyColors.bgCard],
            ),
            border: Border.all(color: accent, width: 1.6),
          ),
          child: Column(
            children: [
              Icon(Icons.emoji_events, size: 42, color: accent),
              const SizedBox(height: 8),
              Text(
                headline,
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                winnerSummary,
                textAlign: TextAlign.center,
                style: const TextStyle(color: PartyColors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '全员身份揭晓（初始 → 最终）',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ...players.map((p) {
          final pid = p['playerId'] as String;
          final wasSwapped = p['wasSwapped'] as bool? ?? false;
          final isOut = eliminated.contains(pid);
          final finalRole =
              OneNightRole.fromName(p['finalRole'] as String? ?? 'villager');
          final votedId = p['votedTargetId'] as String?;

          return Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              leading: CircleAvatar(
                backgroundColor:
                    oneNightRoleColor(finalRole).withValues(alpha: 0.2),
                child: Text(
                  '${p['seatNumber']}',
                  style: TextStyle(
                    color: oneNightRoleColor(finalRole),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              title: Text(
                '${p['name']} · ${p['initialRoleName']} → ${p['finalRoleName']}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${votedId != null ? "投给了 ${_seatLabel(players, votedId)}" : "未投票"}${wasSwapped ? " · 已被换牌!" : ""}',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: isOut
                  ? const Chip(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: PartyColors.wolfRedSoft,
                      label: Text(
                        '出局',
                        style: TextStyle(
                          color: PartyColors.wolfRed,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  : null,
            ),
          );
        }),
        const SizedBox(height: 14),
        const Text(
          '3 张中间底牌揭晓',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Row(
          children: centerCards
              .map(
                (c) => Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        children: [
                          Text(
                            c['label'] as String,
                            style: const TextStyle(
                              fontSize: 11,
                              color: PartyColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            c['roleName'] as String,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: PartyColors.gold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 14),
        const Text(
          '夜晚换牌真相复盘',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: replayLogs.isEmpty
                  ? [
                      const Text(
                        '昨夜平安无事，未发生换牌。',
                        style: TextStyle(color: PartyColors.textSecondary),
                      )
                    ]
                  : replayLogs
                      .map(
                        (line) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            line,
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: PartyColors.textSecondary,
                            ),
                          ),
                        ),
                      )
                      .toList(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (isHost)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: widget.controller.returnToLobby,
              icon: const Icon(Icons.replay),
              label: const Text('返回大厅再来一局'),
            ),
          ),
      ],
    );
  }

  String _seatLabel(List<Map<String, dynamic>> players, String playerId) {
    for (final p in players) {
      if (p['playerId'] == playerId) {
        return '${p['seatNumber']}号 ${p['name']}';
      }
    }
    return playerId;
  }
}

class _OneNightRolePeekCard extends StatefulWidget {
  const _OneNightRolePeekCard({
    required this.role,
    required this.seatNumber,
    required this.nightNotes,
  });

  final OneNightRole role;
  final int seatNumber;
  final List<String> nightNotes;

  @override
  State<_OneNightRolePeekCard> createState() => _OneNightRolePeekCardState();
}

class _OneNightRolePeekCardState extends State<_OneNightRolePeekCard> {
  bool _revealed = false;

  void _set(bool v) {
    if (_revealed != v) setState(() => _revealed = v);
  }

  @override
  Widget build(BuildContext context) {
    final accent = oneNightRoleColor(widget.role);
    return GestureDetector(
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onLongPressStart: (_) => _set(true),
      onLongPressEnd: (_) => _set(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: _revealed
              ? LinearGradient(
                  colors: [accent.withValues(alpha: 0.28), PartyColors.bgCard],
                )
              : const LinearGradient(
                  colors: [Color(0xFF271B4A), Color(0xFF13122B)],
                ),
          border: Border.all(
            color: _revealed ? accent : PartyColors.witchPurple,
            width: _revealed ? 2 : 1.4,
          ),
        ),
        child: _revealed
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.role.displayName,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${widget.seatNumber}号 初始身份 · ${widget.role.campName}',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.role.description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: PartyColors.textPrimary,
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                  if (widget.nightNotes.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Divider(color: PartyColors.border),
                    ...widget.nightNotes.map(
                      (n) => Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '• $n',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: PartyColors.gold,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.fingerprint,
                    size: 40,
                    color: PartyColors.witchPurple,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${widget.seatNumber}号 一夜狼身份牌（已隐藏）',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '长按查看初始身份与夜晚线索，松手立即隐藏',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: PartyColors.textSecondary,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
