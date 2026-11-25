import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:party_core/party_core.dart';

import '../../../core/state/app_controller.dart';
import '../../../core/theme/party_theme.dart';
import 'role_card_widget.dart';

class WerewolfTablePage extends StatefulWidget {
  const WerewolfTablePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<WerewolfTablePage> createState() => _WerewolfTablePageState();
}

class _WerewolfTablePageState extends State<WerewolfTablePage> {
  String? _selectedTargetId;
  bool _witchPoisonMode = false;
  WerewolfPhase? _lastPhase;

  // Speaking timer for face-to-face Day Discussion
  Timer? _discussTimer;
  int _discussSecondsLeft = 90;
  bool _discussTimerRunning = false;

  @override
  void dispose() {
    _discussTimer?.cancel();
    super.dispose();
  }

  void _syncPhaseReset(WerewolfPhase currentPhase) {
    if (_lastPhase != currentPhase) {
      _lastPhase = currentPhase;
      _selectedTargetId = null;
      _witchPoisonMode = false;
      if (currentPhase != WerewolfPhase.dayDiscuss) {
        _discussTimer?.cancel();
        _discussTimerRunning = false;
        _discussSecondsLeft = 90;
      }
    }
  }

  void _toggleDiscussTimer() {
    if (_discussTimerRunning) {
      _discussTimer?.cancel();
      setState(() => _discussTimerRunning = false);
      return;
    }
    if (_discussSecondsLeft <= 0) {
      _discussSecondsLeft = 90;
    }
    setState(() => _discussTimerRunning = true);
    _discussTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_discussSecondsLeft <= 1) {
        t.cancel();
        setState(() {
          _discussSecondsLeft = 0;
          _discussTimerRunning = false;
        });
      } else {
        setState(() => _discussSecondsLeft--);
      }
    });
  }

  void _resetDiscussTimer() {
    _discussTimer?.cancel();
    setState(() {
      _discussSecondsLeft = 90;
      _discussTimerRunning = false;
    });
  }

  void _showQuickRolePeek({
    required WerewolfRole myRole,
    required int mySeat,
    required List<String> teammateLabels,
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RolePeekCard(
              role: myRole,
              seatNumber: mySeat,
              teammateLabels: teammateLabels,
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
    final phase = WerewolfPhase.fromName(gs['phase'] as String);
    _syncPhaseReset(phase);

    final dayNumber = (gs['dayNumber'] as num?)?.toInt() ?? 0;
    final isNight = gs['isNight'] as bool? ?? false;
    final isDecoy = gs['isDecoyNightStep'] as bool? ?? false;

    final meMap = Map<String, dynamic>.from(gs['me'] as Map);
    final myId = meMap['playerId'] as String;
    final mySeat = (meMap['seatNumber'] as num).toInt();
    final myRole = WerewolfRole.fromName(meMap['role'] as String);
    final myAlive = meMap['isAlive'] as bool? ?? true;
    final myCanVote = meMap['canVote'] as bool? ?? true;
    final myConfirmedRole = meMap['confirmedRole'] as bool? ?? false;

    final players = (gs['players'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final teammateWolfIds =
        ((gs['teammateWolfIds'] as List?) ?? const []).cast<String>().toSet();
    final teammateLabels = players
        .where(
          (p) =>
              teammateWolfIds.contains(p['playerId']) &&
              p['playerId'] != myId,
        )
        .map((p) => '${p['seatNumber']}号 ${p['name']}')
        .toList();

    final sheriffId = gs['sheriffId'] as String?;
    final sheriffCandidates =
        ((gs['sheriffCandidates'] as List?) ?? const []).cast<String>().toSet();
    final sheriffSignupDecidedIds =
        ((gs['sheriffSignupDecidedIds'] as List?) ?? const []).cast<String>().toSet();
    final sheriffVotedIds =
        ((gs['sheriffVotedIds'] as List?) ?? const []).cast<String>().toSet();
    final dayVotedIds =
        ((gs['dayVotedIds'] as List?) ?? const []).cast<String>().toSet();
    final votePkCandidates =
        ((gs['votePkCandidates'] as List?) ?? const []).cast<String>().toSet();
    final votePkRound = (gs['votePkRound'] as num?)?.toInt() ?? 0;

    final canSelectSeat = _canSelectSeatInPhase(
      phase: phase,
      myId: myId,
      myRole: myRole,
      myAlive: myAlive,
      myCanVote: myCanVote,
      gs: gs,
      sheriffCandidates: sheriffCandidates,
      sheriffVotedIds: sheriffVotedIds,
      dayVotedIds: dayVotedIds,
    );

    final bgTop = isNight ? const Color(0xFF060916) : const Color(0xFF131D38);

    return Scaffold(
      backgroundColor: bgTop,
      appBar: AppBar(
        backgroundColor: bgTop,
        leading: IconButton(
          icon: const Icon(Icons.exit_to_app),
          tooltip: '退出房间',
          onPressed: () => ctrl.leaveRoom(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dayNumber == 0
                  ? '狼人杀 · ${phase.displayName}'
                  : '第 $dayNumber ${isNight ? "夜" : "天"} · ${phase.displayName}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            Text(
              '$mySeat号 · ${myAlive ? "存活" : "已出局"}${sheriffId == myId ? " · 警长" : ""}',
              style: const TextStyle(fontSize: 12, color: PartyColors.gold),
            ),
          ],
        ),
        actions: [
          if (phase != WerewolfPhase.roleReveal && phase != WerewolfPhase.gameOver)
            TextButton.icon(
              onPressed: () => _showQuickRolePeek(
                myRole: myRole,
                mySeat: mySeat,
                teammateLabels: teammateLabels,
              ),
              icon: const Icon(Icons.visibility_outlined, size: 17),
              label: const Text('看身份', style: TextStyle(fontSize: 12)),
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
              // Narrator Banner
              if (ctrl.latestEvent != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isNight
                        ? const Color(0xFF151E3A)
                        : PartyColors.goldSoft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isNight
                          ? PartyColors.border
                          : PartyColors.gold.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isNight ? Icons.nightlight_round : Icons.wb_sunny,
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

              // Main Content Area
              Expanded(
                child: phase == WerewolfPhase.gameOver
                    ? _buildGameOverView(gs, players, snap.isHost)
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        children: [
                          if (phase == WerewolfPhase.roleReveal) ...[
                            RolePeekCard(
                              role: myRole,
                              seatNumber: mySeat,
                              teammateLabels: teammateLabels,
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Seat Table Grid
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              childAspectRatio: 1.0,
                            ),
                            itemCount: players.length,
                            itemBuilder: (ctx, idx) {
                              final p = players[idx];
                              final pid = p['playerId'] as String;
                              final alive = p['isAlive'] as bool? ?? true;
                              final isSelectable = canSelectSeat &&
                                  _isPlayerSelectableTarget(
                                    phase: phase,
                                    target: p,
                                    myId: myId,
                                    gs: gs,
                                    sheriffCandidates: sheriffCandidates,
                                    votePkCandidates: votePkCandidates,
                                    votePkRound: votePkRound,
                                  );

                              final wolfPicks = gs['wolfSelections'] is Map
                                  ? Map<String, dynamic>.from(
                                      gs['wolfSelections'] as Map,
                                    )
                                  : const <String, dynamic>{};
                              final wolvesTargetingThis = wolfPicks.entries
                                  .where((e) => e.value == pid)
                                  .length;

                              return _TableSeatTile(
                                player: p,
                                isMe: pid == myId,
                                isSelected: _selectedTargetId == pid,
                                isSelectable: isSelectable,
                                isWolfTeammate:
                                    myRole.isWolf && teammateWolfIds.contains(pid),
                                isSheriffCandidate:
                                    (phase == WerewolfPhase.sheriffSignup ||
                                            phase == WerewolfPhase.sheriffVote) &&
                                        sheriffCandidates.contains(pid),
                                hasConfirmed:
                                    phase == WerewolfPhase.roleReveal &&
                                        (p['confirmedRole'] as bool? ?? false),
                                hasVoted: (phase == WerewolfPhase.dayVote &&
                                        dayVotedIds.contains(pid)) ||
                                    (phase == WerewolfPhase.sheriffVote &&
                                        sheriffVotedIds.contains(pid)),
                                wolfTargetCount: wolvesTargetingThis,
                                onTap: isSelectable
                                    ? () {
                                        setState(() {
                                          _selectedTargetId =
                                              _selectedTargetId == pid ? null : pid;
                                        });
                                        if (phase == WerewolfPhase.nightWolf &&
                                            myRole.isWolf &&
                                            alive) {
                                          ctrl.sendGameAction(
                                            WerewolfActionType.wolfSelect,
                                            {'targetId': _selectedTargetId},
                                          );
                                        }
                                      }
                                    : null,
                              );
                            },
                          ),
                        ],
                      ),
              ),

              // Bottom Phase Action Panel
              if (phase != WerewolfPhase.gameOver)
                _buildBottomActionPanel(
                  phase: phase,
                  isHost: snap.isHost,
                  isDecoy: isDecoy,
                  myId: myId,
                  myRole: myRole,
                  myAlive: myAlive,
                  myCanVote: myCanVote,
                  myConfirmedRole: myConfirmedRole,
                  gs: gs,
                  players: players,
                  sheriffCandidates: sheriffCandidates,
                  sheriffSignupDecidedIds: sheriffSignupDecidedIds,
                  sheriffVotedIds: sheriffVotedIds,
                  dayVotedIds: dayVotedIds,
                ),
            ],
          ),
        ),
      ),
    );
  }

  bool _canSelectSeatInPhase({
    required WerewolfPhase phase,
    required String myId,
    required WerewolfRole myRole,
    required bool myAlive,
    required bool myCanVote,
    required Map<String, dynamic> gs,
    required Set<String> sheriffCandidates,
    required Set<String> sheriffVotedIds,
    required Set<String> dayVotedIds,
  }) {
    return switch (phase) {
      WerewolfPhase.nightGuard => myAlive && myRole == WerewolfRole.guard,
      WerewolfPhase.nightWolf => myAlive && myRole == WerewolfRole.werewolf,
      WerewolfPhase.nightWitch =>
        myAlive && myRole == WerewolfRole.witch && _witchPoisonMode,
      WerewolfPhase.nightSeer => myAlive &&
          myRole == WerewolfRole.seer &&
          !(gs['currentNightSeerChecked'] as bool? ?? false),
      WerewolfPhase.sheriffVote =>
        !sheriffCandidates.contains(myId) && !sheriffVotedIds.contains(myId),
      WerewolfPhase.sheriffBadgeTransfer =>
        gs['pendingBadgeTransferFromId'] == myId,
      WerewolfPhase.hunterShoot => gs['pendingHunterId'] == myId,
      WerewolfPhase.dayVote =>
        myAlive && myCanVote && !dayVotedIds.contains(myId),
      _ => false,
    };
  }

  bool _isPlayerSelectableTarget({
    required WerewolfPhase phase,
    required Map<String, dynamic> target,
    required String myId,
    required Map<String, dynamic> gs,
    required Set<String> sheriffCandidates,
    required Set<String> votePkCandidates,
    required int votePkRound,
  }) {
    final tid = target['playerId'] as String;
    final alive = target['isAlive'] as bool? ?? true;

    return switch (phase) {
      WerewolfPhase.nightGuard =>
        alive && tid != (gs['guardLastTargetId'] as String?),
      WerewolfPhase.nightWolf => alive,
      WerewolfPhase.nightWitch => alive,
      WerewolfPhase.nightSeer => alive && tid != myId,
      WerewolfPhase.sheriffVote => sheriffCandidates.contains(tid),
      WerewolfPhase.sheriffBadgeTransfer => alive,
      WerewolfPhase.hunterShoot => alive,
      WerewolfPhase.dayVote =>
        alive && (votePkRound == 0 || votePkCandidates.contains(tid)),
      _ => false,
    };
  }

  Widget _buildBottomActionPanel({
    required WerewolfPhase phase,
    required bool isHost,
    required bool isDecoy,
    required String myId,
    required WerewolfRole myRole,
    required bool myAlive,
    required bool myCanVote,
    required bool myConfirmedRole,
    required Map<String, dynamic> gs,
    required List<Map<String, dynamic>> players,
    required Set<String> sheriffCandidates,
    required Set<String> sheriffSignupDecidedIds,
    required Set<String> sheriffVotedIds,
    required Set<String> dayVotedIds,
  }) {
    final ctrl = widget.controller;

    Widget content;
    switch (phase) {
      case WerewolfPhase.roleReveal:
        final confirmedCount =
            players.where((p) => p['confirmedRole'] as bool? ?? false).length;
        content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '已确认身份：$confirmedCount / ${players.length} 人',
              style: const TextStyle(color: PartyColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: myConfirmedRole
                    ? null
                    : () => ctrl.sendGameAction(WerewolfActionType.confirmRole),
                icon: Icon(myConfirmedRole ? Icons.check : Icons.done_all),
                label: Text(myConfirmedRole ? '已确认，等待其他玩家…' : '我已记住身份，准备天黑'),
              ),
            ),
          ],
        );

      case WerewolfPhase.nightGuard:
        if (myAlive && myRole == WerewolfRole.guard) {
          content = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _selectedTargetId == null
                    ? '点击上方存活玩家选择今晚守护目标（不能连守同一人）'
                    : '已选中守护目标：${_seatLabel(players, _selectedTargetId!)}',
                style: const TextStyle(fontSize: 13, color: PartyColors.guardGreen),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => ctrl.sendGameAction(
                        WerewolfActionType.guardProtect,
                        {'targetId': null},
                      ),
                      child: const Text('今晚空守'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _selectedTargetId == null
                          ? null
                          : () => ctrl.sendGameAction(
                                WerewolfActionType.guardProtect,
                                {'targetId': _selectedTargetId},
                              ),
                      child: const Text('确认守护'),
                    ),
                  ),
                ],
              ),
            ],
          );
        } else {
          content = _sleepPrompt(isDecoy);
        }

      case WerewolfPhase.nightWolf:
        if (myAlive && myRole == WerewolfRole.werewolf) {
          final confirmedIds =
              ((gs['wolfConfirmedIds'] as List?) ?? const []).cast<String>().toSet();
          final iConfirmed = confirmedIds.contains(myId);
          content = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _selectedTargetId == null
                    ? '点击上方座位与狼队友商议刀口，或选择空刀'
                    : '已选定袭击目标：${_seatLabel(players, _selectedTargetId!)}',
                style: const TextStyle(
                  fontSize: 13,
                  color: PartyColors.wolfRed,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: iConfirmed
                          ? null
                          : () => ctrl.sendGameAction(
                                WerewolfActionType.wolfConfirm,
                                {'targetId': null},
                              ),
                      child: const Text('空刀'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: PartyColors.wolfRed,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: (iConfirmed || _selectedTargetId == null)
                          ? null
                          : () => ctrl.sendGameAction(
                                WerewolfActionType.wolfConfirm,
                                {'targetId': _selectedTargetId},
                              ),
                      child: Text(iConfirmed ? '已确认，等待狼队友…' : '确认袭击'),
                    ),
                  ),
                ],
              ),
            ],
          );
        } else {
          content = _sleepPrompt(isDecoy);
        }

      case WerewolfPhase.nightWitch:
        if (myAlive && myRole == WerewolfRole.witch && gs['witchInfo'] != null) {
          final info = Map<String, dynamic>.from(gs['witchInfo'] as Map);
          final antidoteUsed = info['antidoteUsed'] as bool? ?? false;
          final poisonUsed = info['poisonUsed'] as bool? ?? false;
          final wolfTargetId = info['wolfTargetId'] as String?;
          final canSaveTarget = info['canSaveTarget'] as bool? ?? false;

          content = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                antidoteUsed
                    ? '解药已用完，无法得知今夜倒牌信息。'
                    : (wolfTargetId == null
                        ? '今夜没有人被狼人袭击。'
                        : '今夜被狼人袭击的是：${_seatLabel(players, wolfTargetId)}'),
                style: const TextStyle(
                  color: PartyColors.witchPurple,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              if (_witchPoisonMode) ...[
                const SizedBox(height: 6),
                Text(
                  _selectedTargetId == null
                      ? '请点击上方要毒杀的玩家座位'
                      : '将毒杀：${_seatLabel(players, _selectedTargetId!)}',
                  style: const TextStyle(color: PartyColors.wolfRed, fontSize: 13),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: PartyColors.guardGreen,
                        foregroundColor: const Color(0xFF042217),
                      ),
                      onPressed: canSaveTarget
                          ? () => ctrl.sendGameAction(
                                WerewolfActionType.witchAct,
                                {'action': 'save'},
                              )
                          : null,
                      child: Text(antidoteUsed ? '解药已用' : '使用解药'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: PartyColors.witchPurple,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: poisonUsed
                          ? null
                          : () {
                              if (!_witchPoisonMode) {
                                setState(() => _witchPoisonMode = true);
                              } else if (_selectedTargetId != null) {
                                ctrl.sendGameAction(
                                  WerewolfActionType.witchAct,
                                  {
                                    'action': 'poison',
                                    'targetId': _selectedTargetId,
                                  },
                                );
                              }
                            },
                      child: Text(
                        poisonUsed
                            ? '毒药已用'
                            : (_witchPoisonMode ? '确认毒杀' : '使用毒药'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => ctrl.sendGameAction(
                      WerewolfActionType.witchAct,
                      {'action': 'skip'},
                    ),
                    child: const Text('不用药'),
                  ),
                ],
              ),
            ],
          );
        } else {
          content = _sleepPrompt(isDecoy);
        }

      case WerewolfPhase.nightSeer:
        if (myAlive && myRole == WerewolfRole.seer) {
          final checked = gs['currentNightSeerChecked'] as bool? ?? false;
          final history = ((gs['seerHistory'] as List?) ?? const [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          final latest = history.isNotEmpty ? history.last : null;

          content = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (checked && latest != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (latest['isWolf'] as bool)
                        ? PartyColors.wolfRedSoft
                        : PartyColors.goldSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '查验结果：${latest['targetSeat']}号 ${latest['targetName']} 是【${(latest['isWolf'] as bool) ? "狼人" : "好人"}】',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: (latest['isWolf'] as bool)
                          ? PartyColors.wolfRed
                          : PartyColors.gold,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () =>
                        ctrl.sendGameAction(WerewolfActionType.seerDone),
                    child: const Text('已记住结果，闭眼进入天亮'),
                  ),
                ),
              ] else ...[
                Text(
                  _selectedTargetId == null
                      ? '请点击上方一名其他玩家进行查验'
                      : '准备查验：${_seatLabel(players, _selectedTargetId!)}',
                  style: const TextStyle(color: PartyColors.seerCyan, fontSize: 13),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: PartyColors.seerCyan,
                      foregroundColor: const Color(0xFF041A24),
                    ),
                    onPressed: _selectedTargetId == null
                        ? null
                        : () => ctrl.sendGameAction(
                              WerewolfActionType.seerCheck,
                              {'targetId': _selectedTargetId},
                            ),
                    child: const Text('立即查验'),
                  ),
                ),
              ],
            ],
          );
        } else {
          content = _sleepPrompt(isDecoy);
        }

      case WerewolfPhase.sheriffSignup:
        final decided = sheriffSignupDecidedIds.contains(myId);
        final isCandidate = sheriffCandidates.contains(myId);
        content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '12人警长竞选 · 已表态 ${sheriffSignupDecidedIds.length}/${players.length} 人（当前 ${sheriffCandidates.length} 人上警）',
              style: const TextStyle(color: PartyColors.gold, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: decided && !isCandidate
                        ? null
                        : () => ctrl.sendGameAction(
                              WerewolfActionType.sheriffSignup,
                              {'join': false},
                            ),
                    child: Text(decided && !isCandidate ? '已选不上警' : '不上警（警下）'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isCandidate
                        ? () => ctrl.sendGameAction(
                              WerewolfActionType.sheriffWithdraw,
                            )
                        : () => ctrl.sendGameAction(
                              WerewolfActionType.sheriffSignup,
                              {'join': true},
                            ),
                    icon: Icon(isCandidate ? Icons.undo : Icons.military_tech),
                    label: Text(isCandidate ? '退水（退出上警）' : '我要上警！'),
                  ),
                ),
              ],
            ),
          ],
        );

      case WerewolfPhase.sheriffVote:
        final isCandidate = sheriffCandidates.contains(myId);
        final hasVoted = sheriffVotedIds.contains(myId);
        content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isCandidate
                  ? '你是警上候选人，请线下竞选发言（也可随时退水）'
                  : (hasVoted
                      ? '你已完成警长投票，等待其他警下玩家…'
                      : '点击上方标有「警上」的候选人投票选出警长'),
              style: const TextStyle(color: PartyColors.gold, fontSize: 13),
            ),
            const SizedBox(height: 10),
            if (isCandidate)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () =>
                      ctrl.sendGameAction(WerewolfActionType.sheriffWithdraw),
                  child: const Text('退水'),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: hasVoted
                          ? null
                          : () => ctrl.sendGameAction(
                                WerewolfActionType.sheriffVote,
                                {'targetId': null},
                              ),
                      child: const Text('弃票'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: (hasVoted || _selectedTargetId == null)
                          ? null
                          : () => ctrl.sendGameAction(
                                WerewolfActionType.sheriffVote,
                                {'targetId': _selectedTargetId},
                              ),
                      child: Text(
                        _selectedTargetId == null
                            ? '请选择候选人'
                            : '投给 ${_seatLabel(players, _selectedTargetId!)}',
                      ),
                    ),
                  ),
                ],
              ),
          ],
        );

      case WerewolfPhase.dayAnnounce:
        final text = gs['lastAnnouncementText'] as String? ?? '天亮了';
        content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: PartyColors.gold,
              ),
            ),
            const SizedBox(height: 12),
            if (isHost)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () =>
                      ctrl.sendGameAction(WerewolfActionType.hostAdvance),
                  child: const Text('确认公告，继续流程'),
                ),
              )
            else
              const Text(
                '等待房主继续流程…',
                style: TextStyle(color: PartyColors.textSecondary, fontSize: 13),
              ),
          ],
        );

      case WerewolfPhase.sheriffBadgeTransfer:
        final isMeDyingSheriff = gs['pendingBadgeTransferFromId'] == myId;
        content = isMeDyingSheriff
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '你作为警长即将出局，请选择存活玩家移交警徽，或直接撕毁警徽',
                    style: TextStyle(color: PartyColors.gold, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => ctrl.sendGameAction(
                            WerewolfActionType.sheriffTransfer,
                            {'targetId': null},
                          ),
                          child: const Text('撕毁警徽'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _selectedTargetId == null
                              ? null
                              : () => ctrl.sendGameAction(
                                    WerewolfActionType.sheriffTransfer,
                                    {'targetId': _selectedTargetId},
                                  ),
                          child: const Text('移交警徽'),
                        ),
                      ),
                    ],
                  ),
                ],
              )
            : const Text(
                '正在等待出局警长决定警徽去向…',
                style: TextStyle(color: PartyColors.gold, fontSize: 14),
              );

      case WerewolfPhase.hunterShoot:
        final isMeHunter = gs['pendingHunterId'] == myId;
        content = isMeHunter
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '猎人翻牌发动技能！请选择开枪带走一名存活玩家，或选择压枪',
                    style: TextStyle(color: Color(0xFFFB923C), fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => ctrl.sendGameAction(
                            WerewolfActionType.hunterShoot,
                            {'targetId': null},
                          ),
                          child: const Text('压枪不开枪'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFB923C),
                            foregroundColor: Colors.black,
                          ),
                          onPressed: _selectedTargetId == null
                              ? null
                              : () => ctrl.sendGameAction(
                                    WerewolfActionType.hunterShoot,
                                    {'targetId': _selectedTargetId},
                                  ),
                          child: const Text('开枪带走'),
                        ),
                      ),
                    ],
                  ),
                ],
              )
            : const Text(
                '猎人正在选择开枪目标…',
                style: TextStyle(color: Color(0xFFFB923C), fontSize: 14),
              );

      case WerewolfPhase.dayDiscuss:
        content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.timer_outlined, color: PartyColors.gold),
                const SizedBox(width: 8),
                Text(
                  '发言计时：$_discussSecondsLeft 秒',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _toggleDiscussTimer,
                  child: Text(_discussTimerRunning ? '暂停' : '开始计时'),
                ),
                TextButton(
                  onPressed: _resetDiscussTimer,
                  child: const Text('重置'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (isHost)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () =>
                      ctrl.sendGameAction(WerewolfActionType.hostAdvance),
                  icon: const Icon(Icons.how_to_vote),
                  label: const Text('发言结束，开启放逐投票'),
                ),
              )
            else
              const Text(
                '线下自由发言中，结束后由房主开启手机投票。',
                style: TextStyle(color: PartyColors.textSecondary, fontSize: 13),
              ),
          ],
        );

      case WerewolfPhase.dayVote:
        final eligibleCount = players
            .where((p) => (p['isAlive'] as bool? ?? false) && (p['canVote'] as bool? ?? true))
            .length;
        final hasVoted = dayVotedIds.contains(myId);
        final pkRound = (gs['votePkRound'] as num?)?.toInt() ?? 0;

        content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${pkRound > 0 ? "平票 PK 复投" : "放逐投票"} · 已投票 ${dayVotedIds.length} / $eligibleCount 人',
              style: const TextStyle(color: PartyColors.gold, fontSize: 13),
            ),
            const SizedBox(height: 10),
            if (!myAlive || !myCanVote)
              Text(
                !myAlive ? '你已出局，无法参与投票。' : '你已翻牌白痴，失去投票权。',
                style: const TextStyle(color: PartyColors.textSecondary),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: hasVoted
                          ? null
                          : () => ctrl.sendGameAction(
                                WerewolfActionType.dayVote,
                                {'targetId': null},
                              ),
                      child: const Text('弃票'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: (hasVoted || _selectedTargetId == null)
                          ? null
                          : () => ctrl.sendGameAction(
                                WerewolfActionType.dayVote,
                                {'targetId': _selectedTargetId},
                              ),
                      child: Text(
                        hasVoted
                            ? '已投票，等待结算…'
                            : (_selectedTargetId == null
                                ? '点击上方座位选人'
                                : '投票放逐 ${_seatLabel(players, _selectedTargetId!)}'),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        );

      case WerewolfPhase.voteResult:
        final summary = gs['lastVoteSummary'] as String? ?? '';
        final tally = gs['lastVoteTally'] is Map
            ? Map<String, dynamic>.from(gs['lastVoteTally'] as Map)
            : const <String, dynamic>{};
        content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              summary,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: PartyColors.gold,
              ),
            ),
            if (tally.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                alignment: WrapAlignment.center,
                children: tally.entries.map((e) {
                  final v = (e.value as num).toDouble();
                  final vStr = v == v.roundToDouble()
                      ? '${v.toInt()}票'
                      : '${v.toStringAsFixed(1)}票';
                  return Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('${_seatLabel(players, e.key)}：$vStr'),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 10),
            if (isHost)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () =>
                      ctrl.sendGameAction(WerewolfActionType.hostAdvance),
                  child: const Text('继续（结算技能 / 进入下一夜）'),
                ),
              )
            else
              const Text(
                '等待房主进入下一阶段…',
                style: TextStyle(color: PartyColors.textSecondary, fontSize: 13),
              ),
          ],
        );

      case WerewolfPhase.gameOver:
        content = const SizedBox.shrink();
    }

    final showHostOverride = isHost &&
        phase != WerewolfPhase.dayAnnounce &&
        phase != WerewolfPhase.dayDiscuss &&
        phase != WerewolfPhase.voteResult &&
        phase != WerewolfPhase.gameOver;

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
                      ctrl.sendGameAction(WerewolfActionType.hostAdvance),
                  icon: const Icon(Icons.skip_next, size: 16),
                  label: Text(
                    isDecoy ? '跳过空过伪装等待' : '房主手动推进',
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

  Widget _sleepPrompt(bool isDecoy) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.bedtime_outlined, color: PartyColors.textSecondary),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              isDecoy
                  ? '天黑请闭眼，请保持安静等待下一阶段…'
                  : '天黑请闭眼，当前为其他角色行动时间，请勿触碰屏幕。',
              style: const TextStyle(
                color: PartyColors.textSecondary,
                fontSize: 13.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameOverView(
    Map<String, dynamic> gs,
    List<Map<String, dynamic>> players,
    bool isHost,
  ) {
    final winnerCamp = gs['winnerCamp'] as String? ?? 'good';
    final winReason = gs['winReason'] as String? ?? '';
    final logs = ((gs['logs'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final isGoodWin = winnerCamp == 'good';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: isGoodWin
                  ? [PartyColors.goldSoft, PartyColors.bgCard]
                  : [PartyColors.wolfRedSoft, PartyColors.bgCard],
            ),
            border: Border.all(
              color: isGoodWin ? PartyColors.gold : PartyColors.wolfRed,
              width: 1.6,
            ),
          ),
          child: Column(
            children: [
              Icon(
                isGoodWin ? Icons.emoji_events : Icons.pets,
                size: 44,
                color: isGoodWin ? PartyColors.gold : PartyColors.wolfRed,
              ),
              const SizedBox(height: 8),
              Text(
                isGoodWin ? '好人阵营获胜！' : '狼人阵营获胜！',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: isGoodWin ? PartyColors.gold : PartyColors.wolfRed,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                winReason,
                textAlign: TextAlign.center,
                style: const TextStyle(color: PartyColors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '全员身份揭晓',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ...players.map((p) {
          final role = WerewolfRole.fromName(p['role'] as String? ?? 'villager');
          final alive = p['isAlive'] as bool? ?? false;
          return Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              leading: CircleAvatar(
                backgroundColor: roleAccentColor(role).withValues(alpha: 0.2),
                child: Text(
                  '${p['seatNumber']}',
                  style: TextStyle(
                    color: roleAccentColor(role),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              title: Text(
                '${p['name']} · ${role.displayName}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                alive
                    ? '存活至终局'
                    : '第 ${p['deathDay'] ?? "?"} 天 ${p['deathReason'] ?? "出局"}',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: (p['isSheriff'] as bool? ?? false)
                  ? const Icon(Icons.military_tech, color: PartyColors.gold)
                  : null,
            ),
          );
        }),
        const SizedBox(height: 16),
        const Text(
          '完整行动复盘时间线',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: logs
                  .map(
                    (l) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '[${l['phase']}] ${l['summary']}',
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

class _TableSeatTile extends StatelessWidget {
  const _TableSeatTile({
    required this.player,
    required this.isMe,
    required this.isSelected,
    required this.isSelectable,
    required this.isWolfTeammate,
    required this.isSheriffCandidate,
    required this.hasConfirmed,
    required this.hasVoted,
    required this.wolfTargetCount,
    this.onTap,
  });

  final Map<String, dynamic> player;
  final bool isMe;
  final bool isSelected;
  final bool isSelectable;
  final bool isWolfTeammate;
  final bool isSheriffCandidate;
  final bool hasConfirmed;
  final bool hasVoted;
  final int wolfTargetCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final alive = player['isAlive'] as bool? ?? true;
    final isSheriff = player['isSheriff'] as bool? ?? false;
    final idiotRevealed = player['idiotRevealed'] as bool? ?? false;
    final seatNum = (player['seatNumber'] as num).toInt();
    final name = player['name'] as String;

    Color borderColor = PartyColors.border;
    if (isSelected) {
      borderColor = PartyColors.gold;
    } else if (isSelectable) {
      borderColor = PartyColors.seerCyan.withValues(alpha: 0.65);
    } else if (isMe) {
      borderColor = PartyColors.gold.withValues(alpha: 0.5);
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected
              ? PartyColors.goldSoft
              : alive
                  ? PartyColors.bgCard
                  : PartyColors.bgDeep.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: borderColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  '$seatNum号',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: alive ? PartyColors.gold : PartyColors.textMuted,
                  ),
                ),
                const Spacer(),
                if (isSheriff)
                  const Icon(
                    Icons.military_tech,
                    size: 16,
                    color: PartyColors.gold,
                  )
                else if (isSheriffCandidate)
                  const Text(
                    '警上',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: PartyColors.gold,
                    ),
                  )
                else if (hasConfirmed || hasVoted)
                  const Icon(
                    Icons.check_circle,
                    size: 14,
                    color: PartyColors.guardGreen,
                  ),
              ],
            ),
            CircleAvatar(
              radius: 17,
              backgroundColor: !alive
                  ? PartyColors.bgSurface
                  : isWolfTeammate
                      ? PartyColors.wolfRedSoft
                      : PartyColors.bgElevated,
              child: Text(
                alive ? name.characters.first : '✕',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: !alive
                      ? PartyColors.textMuted
                      : isWolfTeammate
                          ? PartyColors.wolfRed
                          : PartyColors.textPrimary,
                ),
              ),
            ),
            Column(
              children: [
                Text(
                  isMe ? '$name(我)' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: alive ? PartyColors.textPrimary : PartyColors.textMuted,
                    decoration: alive ? null : TextDecoration.lineThrough,
                  ),
                ),
                if (wolfTargetCount > 0)
                  Text(
                    '刀口 ×$wolfTargetCount',
                    style: const TextStyle(
                      fontSize: 10,
                      color: PartyColors.wolfRed,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else if (idiotRevealed)
                  const Text(
                    '白痴(无票)',
                    style: TextStyle(fontSize: 10, color: Color(0xFFFACC15)),
                  )
                else if (isWolfTeammate && !isMe)
                  const Text(
                    '狼队友',
                    style: TextStyle(fontSize: 10, color: PartyColors.wolfRed),
                  )
                else if (!alive)
                  const Text(
                    '已出局',
                    style: TextStyle(fontSize: 10, color: PartyColors.textMuted),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
