import 'package:material_ui/material_ui.dart';
import 'package:party_core/party_core.dart';

import '../../../core/state/app_controller.dart';
import '../../../core/theme/party_theme.dart';
import 'playing_card_widget.dart';

class GuandanTablePage extends StatefulWidget {
  const GuandanTablePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<GuandanTablePage> createState() => _GuandanTablePageState();
}

class _GuandanTablePageState extends State<GuandanTablePage> {
  final Set<String> _selectedIds = {};
  int _hintCycleIndex = 0;
  int? _lastRevision;

  void _syncSelectionWithHand(List<PlayingCard> myHand, int revision) {
    if (_lastRevision != revision) {
      _lastRevision = revision;
      final handIds = myHand.map((c) => c.id).toSet();
      _selectedIds.removeWhere((id) => !handIds.contains(id));
      _hintCycleIndex = 0;
    }
  }

  void _toggleCard(String cardId, {bool singleOnly = false}) {
    setState(() {
      if (singleOnly) {
        if (_selectedIds.contains(cardId)) {
          _selectedIds.clear();
        } else {
          _selectedIds
            ..clear()
            ..add(cardId);
        }
      } else {
        if (_selectedIds.contains(cardId)) {
          _selectedIds.remove(cardId);
        } else {
          _selectedIds.add(cardId);
        }
      }
    });
  }

  void _applyHint(
    List<PlayingCard> myHand,
    int currentLevel,
    GuandanPlay? beatTarget,
  ) {
    final hints = GuandanEvaluator.findHintPlays(
      myHand,
      currentLevel,
      beatTarget: beatTarget,
    );
    if (hints.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('没有能压过桌面的牌型，可以点击「不要」。')),
        );
      return;
    }
    final chosen = hints[_hintCycleIndex % hints.length];
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(chosen.cards.map((c) => c.id));
      _hintCycleIndex++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final snap = ctrl.snapshot!;
    final gs = snap.gameState!;

    final phase = GuandanPhase.fromName(gs['phase'] as String);
    final roundNumber = (gs['roundNumber'] as num).toInt();
    final currentLevel = (gs['currentLevel'] as num).toInt();
    final currentLevelLabel = gs['currentLevelLabel'] as String;
    final teamLevelLabels =
        (gs['teamLevelLabels'] as List).cast<String>();
    final activeTeamIndex = (gs['activeTeamIndex'] as num).toInt();

    final isMyTurn = gs['isMyTurn'] as bool? ?? false;
    final canPass = gs['canPass'] as bool? ?? false;
    final pendingPay = gs['pendingTributePay'] as bool? ?? false;
    final pendingReturn = gs['pendingTributeReturn'] as bool? ?? false;
    final tributeSummary = gs['tributeSummary'] as String? ?? '';

    final myHand = ((gs['myHand'] as List?) ?? const [])
        .map((e) => PlayingCard.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    _syncSelectionWithHand(myHand, snap.revision);

    final players = (gs['players'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final myIndex =
        players.indexWhere((p) => p['playerId'] == snap.yourPlayerId);
    final safeMyIndex = myIndex == -1 ? 0 : myIndex;

    final mePlayer = players[safeMyIndex];
    final rightPlayer = players[(safeMyIndex + 1) % 4];
    final partnerPlayer = players[(safeMyIndex + 2) % 4];
    final leftPlayer = players[(safeMyIndex + 3) % 4];

    final lastPlay = gs['lastPlay'] == null
        ? null
        : GuandanPlay.fromJson(Map<String, dynamic>.from(gs['lastPlay'] as Map));
    final lastPlayPlayerId = gs['lastPlayPlayerId'] as String?;
    final lastPlayOwner = lastPlayPlayerId == null
        ? null
        : players
            .where((p) => p['playerId'] == lastPlayPlayerId)
            .firstOrNull;

    final beatTarget =
        (isMyTurn && lastPlay != null && lastPlayPlayerId != snap.yourPlayerId)
            ? lastPlay
            : null;

    final selectedCards =
        myHand.where((c) => _selectedIds.contains(c.id)).toList();
    final evaluatedSelection = selectedCards.isEmpty
        ? null
        : GuandanEvaluator.evaluateBest(
            selectedCards,
            currentLevel,
            beatTarget: beatTarget,
          );
    final rawSelectionEval = selectedCards.isEmpty
        ? null
        : GuandanEvaluator.evaluateBest(selectedCards, currentLevel);

    final singleSelectMode = pendingPay || pendingReturn;

    return Scaffold(
      backgroundColor: const Color(0xFF0A1619),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1619),
        leading: IconButton(
          icon: const Icon(Icons.exit_to_app),
          tooltip: '退出房间',
          onPressed: ctrl.leaveRoom,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '掼蛋 · 第 $roundNumber 局 · 打 $currentLevelLabel',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            Text(
              '红队:${teamLevelLabels[0]}  |  蓝队:${teamLevelLabels[1]}  ·  ♥$currentLevelLabel 逢人配',
              style: TextStyle(
                fontSize: 12,
                color: activeTeamIndex == 0
                    ? const Color(0xFFFCA5A5)
                    : PartyColors.seerCyan,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              ctrl.ttsEnabled ? Icons.volume_up : Icons.volume_off,
              color: ctrl.ttsEnabled ? PartyColors.gold : PartyColors.textMuted,
            ),
            onPressed: ctrl.toggleTts,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: Column(
              children: [
                // Top: Partner (对家)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                  child: _OpponentSeatBadge(
                    player: partnerPlayer,
                    relationLabel: '对家（队友）',
                  ),
                ),

                // Middle: Left (上家) + Center Table + Right (下家)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 96,
                          child: _OpponentSeatBadge(
                            player: leftPlayer,
                            relationLabel: '上家',
                            compact: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0xFF10332C), Color(0xFF0A221E)],
                              ),
                              border: Border.all(
                                color: PartyColors.guardGreen
                                    .withValues(alpha: 0.35),
                                width: 1.4,
                              ),
                            ),
                            child: _buildCenterContent(
                              phase: phase,
                              gs: gs,
                              players: players,
                              isHost: snap.isHost,
                              currentLevel: currentLevel,
                              lastPlay: lastPlay,
                              lastPlayOwner: lastPlayOwner,
                              tributeSummary: tributeSummary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 96,
                          child: _OpponentSeatBadge(
                            player: rightPlayer,
                            relationLabel: '下家',
                            compact: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Status & Action Bar
                if (phase == GuandanPhase.playing ||
                    phase == GuandanPhase.tributePay ||
                    phase == GuandanPhase.tributeReturn)
                  _buildActionBar(
                    phase: phase,
                    mePlayer: mePlayer,
                    isMyTurn: isMyTurn,
                    canPass: canPass,
                    pendingPay: pendingPay,
                    pendingReturn: pendingReturn,
                    myHand: myHand,
                    currentLevel: currentLevel,
                    beatTarget: beatTarget,
                    selectedCards: selectedCards,
                    evaluatedSelection: evaluatedSelection,
                    rawSelectionEval: rawSelectionEval,
                  ),

                // Bottom: My Hand (2 clean overlapping rows)
                if (myHand.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
                    decoration: const BoxDecoration(
                      color: Color(0xFF0E1B1F),
                      border: Border(top: BorderSide(color: PartyColors.border)),
                    ),
                    child: _buildHandRows(
                      myHand,
                      currentLevel,
                      singleOnly: singleSelectMode,
                    ),
                  )
                else if (phase == GuandanPhase.playing)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    color: const Color(0xFF0E1B1F),
                    child: const Text(
                      '🎉 你已出完所有手牌！正在观战等待本局结算…',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: PartyColors.gold,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCenterContent({
    required GuandanPhase phase,
    required Map<String, dynamic> gs,
    required List<Map<String, dynamic>> players,
    required bool isHost,
    required int currentLevel,
    required GuandanPlay? lastPlay,
    required Map<String, dynamic>? lastPlayOwner,
    required String tributeSummary,
  }) {
    if (phase == GuandanPhase.roundOver || phase == GuandanPhase.matchOver) {
      final summary = gs['lastRoundSummary'] as String? ?? '本局结束';
      final isMatchOver = phase == GuandanPhase.matchOver;
      final ordered = [...players]..sort(
          (a, b) => ((a['finishOrder'] as num?)?.toInt() ?? 9)
              .compareTo((b['finishOrder'] as num?)?.toInt() ?? 9),
        );
      return SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isMatchOver ? Icons.emoji_events : Icons.military_tech,
              color: PartyColors.gold,
              size: 34,
            ),
            const SizedBox(height: 6),
            Text(
              isMatchOver ? '比赛冠军诞生！' : '本局结算',
              style: const TextStyle(
                color: PartyColors.gold,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              summary,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: PartyColors.textPrimary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: ordered.map((p) {
                final rank = (p['finishOrder'] as num?)?.toInt() ?? 4;
                final label = switch (rank) {
                  1 => '头游',
                  2 => '二游',
                  3 => '三游',
                  _ => '末游',
                };
                return Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    '$label: ${p['seatNumber']}号 ${p['name']} (${p['teamName']})',
                    style: const TextStyle(fontSize: 11),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            if (isHost)
              ElevatedButton.icon(
                onPressed: () {
                  if (isMatchOver) {
                    widget.controller.returnToLobby();
                  } else {
                    widget.controller.sendGameAction(GuandanActionType.nextRound);
                  }
                },
                icon: Icon(isMatchOver ? Icons.replay : Icons.arrow_forward),
                label: Text(isMatchOver ? '返回大厅再来一场' : '开启下一局'),
              )
            else
              Text(
                isMatchOver ? '等待房主返回大厅…' : '等待房主开启下一局…',
                style: const TextStyle(
                  color: PartyColors.textSecondary,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      );
    }

    if (phase == GuandanPhase.tributePay ||
        phase == GuandanPhase.tributeReturn) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.card_giftcard, color: PartyColors.gold, size: 32),
          const SizedBox(height: 8),
          Text(
            phase.displayName,
            style: const TextStyle(
              color: PartyColors.gold,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            tributeSummary,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: PartyColors.textPrimary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      );
    }

    if (lastPlay == null) {
      final turnSeat = gs['currentTurnSeat'];
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.style_outlined, color: PartyColors.gold, size: 30),
          const SizedBox(height: 8),
          Text(
            '新一轮出牌 · 等待 $turnSeat号 先手出牌',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: PartyColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (tributeSummary.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              tributeSummary,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: PartyColors.textSecondary,
                fontSize: 11.5,
              ),
            ),
          ],
        ],
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: lastPlay.isBomb
                ? PartyColors.wolfRedSoft
                : PartyColors.goldSoft,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '${lastPlayOwner != null ? "${lastPlayOwner['seatNumber']}号 ${lastPlayOwner['name']}：" : ""}${lastPlay.displayName}${lastPlay.isBomb ? " 🔥" : ""}',
            style: TextStyle(
              color: lastPlay.isBomb ? PartyColors.wolfRed : PartyColors.gold,
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          alignment: WrapAlignment.center,
          children: lastPlay.cards
              .map(
                (c) => PlayingCardWidget(
                  card: c,
                  currentLevel: currentLevel,
                  mini: true,
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildActionBar({
    required GuandanPhase phase,
    required Map<String, dynamic> mePlayer,
    required bool isMyTurn,
    required bool canPass,
    required bool pendingPay,
    required bool pendingReturn,
    required List<PlayingCard> myHand,
    required int currentLevel,
    required GuandanPlay? beatTarget,
    required List<PlayingCard> selectedCards,
    required GuandanPlay? evaluatedSelection,
    required GuandanPlay? rawSelectionEval,
  }) {
    final ctrl = widget.controller;

    if (phase == GuandanPhase.tributePay) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: pendingPay
            ? Row(
                children: [
                  const Expanded(
                    child: Text(
                      '请选择手中最大非逢人配卡牌进贡',
                      style: TextStyle(color: PartyColors.gold, fontSize: 13),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: selectedCards.length == 1
                        ? () {
                            ctrl.sendGameAction(GuandanActionType.payTribute, {
                              'cardId': selectedCards.first.id,
                            });
                            setState(() => _selectedIds.clear());
                          }
                        : null,
                    child: const Text('确认进贡'),
                  ),
                ],
              )
            : const Text(
                '正在等待败方完成进贡…',
                style: TextStyle(color: PartyColors.textSecondary, fontSize: 13),
              ),
      );
    }

    if (phase == GuandanPhase.tributeReturn) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: pendingReturn
            ? Row(
                children: [
                  const Expanded(
                    child: Text(
                      '请选择一张不大于 10 的单牌还贡',
                      style: TextStyle(color: PartyColors.gold, fontSize: 13),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: selectedCards.length == 1
                        ? () {
                            ctrl.sendGameAction(
                              GuandanActionType.returnTribute,
                              {'cardId': selectedCards.first.id},
                            );
                            setState(() => _selectedIds.clear());
                          }
                        : null,
                    child: const Text('确认还贡'),
                  ),
                ],
              )
            : const Text(
                '正在等待赢家还贡…',
                style: TextStyle(color: PartyColors.textSecondary, fontSize: 13),
              ),
      );
    }

    String hintText;
    Color hintColor = PartyColors.textSecondary;
    if (!isMyTurn) {
      hintText =
          '${mePlayer['seatNumber']}号 ${mePlayer['name']}（${mePlayer['teamName']}）· 等待其他玩家出牌';
    } else if (selectedCards.isEmpty) {
      hintText = beatTarget == null
          ? '轮到你先手出牌，点选下方手牌或按「提示」'
          : '轮到你出牌，需压过【${beatTarget.displayName}】或点击「不要」';
      hintColor = PartyColors.gold;
    } else if (evaluatedSelection != null) {
      hintText =
          '已选 ${selectedCards.length} 张 · ${evaluatedSelection.displayName}${evaluatedSelection.isBomb ? " 🔥" : ""}（可出）';
      hintColor = PartyColors.guardGreen;
    } else if (rawSelectionEval != null) {
      hintText = '已选【${rawSelectionEval.displayName}】，但无法压过桌面牌型';
      hintColor = PartyColors.wolfRed;
    } else {
      hintText = '已选 ${selectedCards.length} 张 · 暂未组成合法牌型';
      hintColor = PartyColors.wolfRed;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            hintText,
            style: TextStyle(
              color: hintColor,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (isMyTurn) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (canPass) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() => _selectedIds.clear());
                        ctrl.sendGameAction(GuandanActionType.passTurn);
                      },
                      child: const Text('不要'),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _applyHint(myHand, currentLevel, beatTarget),
                    icon: const Icon(Icons.lightbulb_outline, size: 17),
                    label: const Text('提示'),
                  ),
                ),
                const SizedBox(width: 8),
                if (selectedCards.isNotEmpty) ...[
                  OutlinedButton(
                    onPressed: () => setState(() => _selectedIds.clear()),
                    child: const Text('重选'),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: evaluatedSelection == null
                        ? null
                        : () {
                            final ids =
                                selectedCards.map((c) => c.id).toList();
                            setState(() => _selectedIds.clear());
                            ctrl.sendGameAction(
                              GuandanActionType.playCards,
                              {'cardIds': ids},
                            );
                          },
                    icon: const Icon(Icons.send_rounded, size: 17),
                    label: const Text('出牌'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHandRows(
    List<PlayingCard> hand,
    int currentLevel, {
    required bool singleOnly,
  }) {
    final splitAt = hand.length > 14 ? (hand.length / 2).ceil() : hand.length;
    final row1 = hand.sublist(0, splitAt);
    final row2 = hand.length > splitAt ? hand.sublist(splitAt) : <PlayingCard>[];

    Widget buildRow(List<PlayingCard> cards) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 2),
          child: SizedBox(
            height: 80,
            width: cards.isEmpty ? 0 : (cards.length - 1) * 32.0 + 54.0,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < cards.length; i++)
                  Positioned(
                    left: i * 32.0,
                    child: PlayingCardWidget(
                      card: cards[i],
                      currentLevel: currentLevel,
                      selected: _selectedIds.contains(cards[i].id),
                      onTap: () =>
                          _toggleCard(cards[i].id, singleOnly: singleOnly),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        buildRow(row1),
        if (row2.isNotEmpty) buildRow(row2),
      ],
    );
  }
}

class _OpponentSeatBadge extends StatelessWidget {
  const _OpponentSeatBadge({
    required this.player,
    required this.relationLabel,
    this.compact = false,
  });

  final Map<String, dynamic> player;
  final String relationLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isTurn = player['isCurrentTurn'] as bool? ?? false;
    final teamIndex = (player['teamIndex'] as num).toInt();
    final cardCount = (player['cardCount'] as num).toInt();
    final finishOrder = (player['finishOrder'] as num?)?.toInt();
    final lastAction = player['lastAction'] as String?;
    final teamColor =
        teamIndex == 0 ? PartyColors.wolfRed : PartyColors.seerCyan;

    final finishLabel = switch (finishOrder) {
      1 => '头游',
      2 => '二游',
      3 => '三游',
      4 => '末游',
      _ => null,
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: EdgeInsets.all(compact ? 8 : 10),
      decoration: BoxDecoration(
        color: PartyColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isTurn ? PartyColors.gold : teamColor.withValues(alpha: 0.45),
          width: isTurn ? 2 : 1,
        ),
      ),
      child: compact
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${player['seatNumber']}号 · $relationLabel',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: teamColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  player['name'] as String,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: PartyColors.bgSurface,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    finishLabel ?? '剩 $cardCount 张',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: finishLabel != null
                          ? PartyColors.gold
                          : PartyColors.textPrimary,
                    ),
                  ),
                ),
                if (lastAction != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    lastAction,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: PartyColors.gold,
                    ),
                  ),
                ],
              ],
            )
          : Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: teamColor.withValues(alpha: 0.2),
                  child: Text(
                    '${player['seatNumber']}',
                    style: TextStyle(
                      color: teamColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${player['name']}（$relationLabel · ${player['teamName']}）',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        finishLabel != null
                            ? '已出完 · $finishLabel'
                            : '剩余 $cardCount 张${lastAction != null ? " · $lastAction" : ""}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: PartyColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isTurn)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: PartyColors.goldSoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      '思考中',
                      style: TextStyle(
                        color: PartyColors.gold,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
