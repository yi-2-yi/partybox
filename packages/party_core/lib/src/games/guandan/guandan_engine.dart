import 'dart:math';

import '../../engine/game_plugin.dart';
import '../../models/room_models.dart';
import 'guandan_evaluator.dart';
import 'guandan_models.dart';

/// Authoritative 4-player Guandan (掼蛋) engine for PartyBox.
class GuandanEngine {
  GuandanEngine({Random? random}) : _random = random ?? Random();

  final Random _random;

  String? validateStart(List<PlayerInfo> players, GuandanConfig config) {
    if (players.length != 4) {
      return '掼蛋需要恰好 4 名玩家（1/3号红队 vs 2/4号蓝队），当前有 ${players.length} 人。';
    }
    return null;
  }

  GameTransition<GuandanState> initGame(
    List<PlayerInfo> players,
    GuandanConfig config,
  ) {
    final err = validateStart(players, config);
    if (err != null) throw GameRuleException(err);

    final sorted = [...players]
      ..sort((a, b) => a.seatNumber.compareTo(b.seatNumber));
    final level = config.startLevel.clamp(2, 14);
    final hands = _dealHands(level);

    final gdPlayers = <GuandanPlayerState>[];
    for (var i = 0; i < 4; i++) {
      gdPlayers.add(
        GuandanPlayerState(
          playerId: sorted[i].id,
          name: sorted[i].name,
          seatNumber: i + 1,
          hand: hands[i],
        ),
      );
    }

    final firstLead = _random.nextInt(4);
    var state = GuandanState(
      config: config,
      players: gdPlayers,
      phase: GuandanPhase.playing,
      roundNumber: 1,
      teamLevels: [level, level],
      activeTeamIndex: 0,
      currentTurnIndex: firstLead,
    );

    final events = <GameEvent>[];
    final leader = gdPlayers[firstLead];
    state = _emitEvent(
      state,
      events,
      type: 'round_start',
      message:
          '第 1 局开始！当前打 ${GuandanState.levelLabel(level)}（红桃${GuandanState.levelLabel(level)}为逢人配），由 ${leader.seatNumber}号 ${leader.name} 先出牌。',
      narrationText: '掼蛋开局，当前打${GuandanState.levelLabel(level)}，请${leader.seatNumber}号玩家先出牌。',
    );
    return GameTransition(state: state, events: events);
  }

  GameTransition<GuandanState> handleAction(
    GuandanState state,
    String playerId,
    String actionType,
    Map<String, dynamic> payload, {
    required String hostId,
  }) {
    if (state.phase == GuandanPhase.matchOver) {
      throw const GameRuleException('本场比赛已结束。');
    }

    final events = <GameEvent>[];
    final next = switch (actionType) {
      GuandanActionType.playCards => _handlePlayCards(
          state,
          playerId,
          ((payload['cardIds'] as List?) ?? const []).cast<String>(),
          events,
        ),
      GuandanActionType.passTurn => _handlePass(state, playerId, events),
      GuandanActionType.payTribute => _handlePayTribute(
          state,
          playerId,
          payload['cardId'] as String? ?? '',
          events,
        ),
      GuandanActionType.returnTribute => _handleReturnTribute(
          state,
          playerId,
          payload['cardId'] as String? ?? '',
          events,
        ),
      GuandanActionType.nextRound =>
        _handleNextRound(state, playerId, hostId, events),
      _ => throw GameRuleException('未知的掼蛋操作：$actionType'),
    };

    return GameTransition(
      state: next,
      events: events,
      isFinished: next.phase == GuandanPhase.matchOver,
    );
  }

  GuandanState _handlePlayCards(
    GuandanState state,
    String playerId,
    List<String> cardIds,
    List<GameEvent> events,
  ) {
    if (state.phase != GuandanPhase.playing) {
      throw const GameRuleException('当前不在出牌阶段。');
    }
    final turnPlayer = state.currentTurnPlayer;
    if (turnPlayer.playerId != playerId) {
      throw const GameRuleException('还没轮到你出牌。');
    }
    if (cardIds.isEmpty) {
      throw const GameRuleException('请选择要出的牌。');
    }

    final idSet = cardIds.toSet();
    if (idSet.length != cardIds.length) {
      throw const GameRuleException('存在重复选中的牌。');
    }

    final selected = <PlayingCard>[];
    for (final id in cardIds) {
      final card = turnPlayer.hand.where((c) => c.id == id).firstOrNull;
      if (card == null) {
        throw const GameRuleException('所选卡牌不在你的手牌中。');
      }
      selected.add(card);
    }

    final isLeading =
        state.lastPlay == null || state.lastPlayPlayerId == playerId;
    final evaluated = GuandanEvaluator.evaluateBest(
      selected,
      state.currentLevel,
      beatTarget: isLeading ? null : state.lastPlay,
    );
    if (evaluated == null) {
      throw GameRuleException(
        isLeading ? '所选卡牌不是合法的掼蛋牌型。' : '所选牌型无法压过桌上的牌。',
      );
    }

    final remainingHand =
        turnPlayer.hand.where((c) => !idSet.contains(c.id)).toList();
    final finishOrderIds = List<String>.from(state.finishOrderIds);
    int? newFinishOrder = turnPlayer.finishOrder;
    if (remainingHand.isEmpty) {
      finishOrderIds.add(playerId);
      newFinishOrder = finishOrderIds.length;
    }

    final updatedPlayers = state.players.map((p) {
      if (p.playerId != playerId) return p;
      return p.copyWith(hand: remainingHand, finishOrder: newFinishOrder);
    }).toList();

    final actions = isLeading
        ? <String, String>{playerId: evaluated.displayName}
        : <String, String>{
            ...state.lastActionByPlayer,
            playerId: evaluated.displayName,
          };

    var next = state.copyWith(
      players: updatedPlayers,
      lastPlay: evaluated,
      lastPlayPlayerId: playerId,
      passedPlayerIds: {},
      lastActionByPlayer: actions,
      finishOrderIds: finishOrderIds,
    );

    if (evaluated.isBomb) {
      next = _emitEvent(
        next,
        events,
        type: 'bomb',
        message:
            '${turnPlayer.seatNumber}号 ${turnPlayer.name} 打出【${evaluated.displayName}】！',
        narrationText: '${turnPlayer.seatNumber}号打出${evaluated.displayName}！',
      );
    }

    if (remainingHand.isEmpty) {
      final rankTitle = switch (newFinishOrder) {
        1 => '头游',
        2 => '二游',
        3 => '三游',
        _ => '末游',
      };
      next = _emitEvent(
        next,
        events,
        type: 'player_finished',
        message: '${turnPlayer.seatNumber}号 ${turnPlayer.name} 出完手牌，拿下$rankTitle！',
        narrationText: '${turnPlayer.seatNumber}号拿下$rankTitle！',
      );

      // Check if either team has both players finished
      final redFinished =
          next.players.where((p) => p.teamIndex == 0 && p.isFinished).length;
      final blueFinished =
          next.players.where((p) => p.teamIndex == 1 && p.isFinished).length;
      if (redFinished == 2 || blueFinished == 2 || finishOrderIds.length >= 3) {
        return _finishRound(next, events);
      }
    }

    final nextTurn = _nextActiveIndex(next.players, state.currentTurnIndex);
    return next.copyWith(currentTurnIndex: nextTurn);
  }

  GuandanState _handlePass(
    GuandanState state,
    String playerId,
    List<GameEvent> events,
  ) {
    if (state.phase != GuandanPhase.playing) {
      throw const GameRuleException('当前不在出牌阶段。');
    }
    final turnPlayer = state.currentTurnPlayer;
    if (turnPlayer.playerId != playerId) {
      throw const GameRuleException('还没轮到你操作。');
    }
    if (state.lastPlay == null || state.lastPlayPlayerId == playerId) {
      throw const GameRuleException('你是本轮先手，必须出牌，不能「不要」。');
    }

    final passed = {...state.passedPlayerIds, playerId};
    final actions = {...state.lastActionByPlayer, playerId: '不要'};
    var next = state.copyWith(
      passedPlayerIds: passed,
      lastActionByPlayer: actions,
    );

    final lastPlayer = next.playerById(state.lastPlayPlayerId!)!;
    final othersStillActive = next.players
        .where((p) => !p.isFinished && p.playerId != lastPlayer.playerId)
        .toList();

    if (othersStillActive.every((p) => passed.contains(p.playerId))) {
      // Trick won! If lastPlayer already emptied their hand, trigger Partner Wind (接风).
      int nextLeadIndex;
      if (!lastPlayer.isFinished) {
        nextLeadIndex = next.indexOfPlayer(lastPlayer.playerId);
      } else {
        nextLeadIndex = (next.indexOfPlayer(lastPlayer.playerId) + 2) % 4;
        if (next.players[nextLeadIndex].isFinished) {
          nextLeadIndex = _nextActiveIndex(next.players, nextLeadIndex);
        }
        final partner = next.players[nextLeadIndex];
        next = _emitEvent(
          next,
          events,
          type: 'partner_wind',
          message: '${partner.seatNumber}号 ${partner.name} 接风，获得新一轮出牌权！',
          narrationText: '${partner.seatNumber}号接风出牌。',
        );
      }
      return next.copyWith(
        currentTurnIndex: nextLeadIndex,
        clearLastPlay: true,
        clearLastPlayPlayerId: true,
        passedPlayerIds: {},
        lastActionByPlayer: {},
      );
    }

    final nextTurn = _nextActiveIndex(next.players, state.currentTurnIndex);
    return next.copyWith(currentTurnIndex: nextTurn);
  }

  GuandanState _finishRound(GuandanState state, List<GameEvent> events) {
    // Assign remaining players finish orders deterministically by seat order
    final orderIds = List<String>.from(state.finishOrderIds);
    for (final p in state.players) {
      if (!orderIds.contains(p.playerId)) {
        orderIds.add(p.playerId);
      }
    }

    final finalPlayers = state.players.map((p) {
      final order = orderIds.indexOf(p.playerId) + 1;
      return p.copyWith(finishOrder: order);
    }).toList();

    final firstPlayer = finalPlayers.firstWhere((p) => p.playerId == orderIds[0]);
    final winningTeam = firstPlayer.teamIndex;
    final teammate = finalPlayers.firstWhere(
      (p) => p.teamIndex == winningTeam && p.playerId != firstPlayer.playerId,
    );

    final teammateOrder = teammate.finishOrder!;
    final levelGain = switch (teammateOrder) {
      2 => 3, // 双下！
      3 => 2, // 单下
      _ => 1, // 头游+末游
    };

    final teamLabel = winningTeam == 0 ? '红队' : '蓝队';
    final resultTag = switch (teammateOrder) {
      2 => '双下（+$levelGain级）',
      3 => '头游+三游（+$levelGain级）',
      _ => '头游+末游（+$levelGain级）',
    };

    final oldLevel = state.teamLevels[winningTeam];
    final targetLevel = state.config.targetLevel;

    // Classic 过A victory: already at targetLevel (e.g. A) and teammate is not 4th!
    if (oldLevel >= targetLevel && teammateOrder <= 3) {
      final summary =
          '$teamLabel 在打 ${GuandanState.levelLabel(oldLevel)} 局拿下 $resultTag，成功过 ${GuandanState.levelLabel(targetLevel)} 夺得全场冠军！';
      var next = state.copyWith(
        players: finalPlayers,
        finishOrderIds: orderIds,
        phase: GuandanPhase.matchOver,
        lastWinningTeam: winningTeam,
        lastLevelGain: levelGain,
        matchWinnerTeam: winningTeam,
        lastRoundSummary: summary,
        clearLastPlay: true,
        clearLastPlayPlayerId: true,
        passedPlayerIds: {},
      );
      return _emitEvent(
        next,
        events,
        type: 'match_over',
        message: summary,
        narrationText: '恭喜$teamLabel成功过${GuandanState.levelLabel(targetLevel)}，赢得整场比赛！',
      );
    }

    final updatedLevels = List<int>.from(state.teamLevels);
    updatedLevels[winningTeam] = min(targetLevel, oldLevel + levelGain);
    final newLevelLabel = GuandanState.levelLabel(updatedLevels[winningTeam]);

    final summary = oldLevel >= targetLevel
        ? '$teamLabel 拿下头游但队友末游，未能过 ${GuandanState.levelLabel(targetLevel)}，下局继续打 $newLevelLabel！'
        : '第 ${state.roundNumber} 局结束！$teamLabel $resultTag，升级至打 $newLevelLabel！';

    var next = state.copyWith(
      players: finalPlayers,
      finishOrderIds: orderIds,
      phase: GuandanPhase.roundOver,
      teamLevels: updatedLevels,
      activeTeamIndex: winningTeam,
      lastWinningTeam: winningTeam,
      lastLevelGain: levelGain,
      lastRoundSummary: summary,
      clearLastPlay: true,
      clearLastPlayPlayerId: true,
      passedPlayerIds: {},
    );

    return _emitEvent(
      next,
      events,
      type: 'round_over',
      message: summary,
      narrationText: '本局结束，$teamLabel升级，下局打$newLevelLabel。',
    );
  }

  GuandanState _handleNextRound(
    GuandanState state,
    String playerId,
    String hostId,
    List<GameEvent> events,
  ) {
    if (state.phase != GuandanPhase.roundOver) {
      throw const GameRuleException('当前不在局间结算阶段。');
    }
    if (playerId != hostId) {
      throw const GameRuleException('只有房主可以开启下一局。');
    }

    final prevOrder = state.finishOrderIds;
    final nextRound = state.roundNumber + 1;
    final level = state.currentLevel;
    final hands = _dealHands(level);

    final newPlayers = <GuandanPlayerState>[];
    for (var i = 0; i < 4; i++) {
      newPlayers.add(
        state.players[i].copyWith(
          hand: hands[i],
          clearFinishOrder: true,
        ),
      );
    }

    final firstPlaceId = prevOrder.first;
    final firstPlaceIndex = newPlayers.indexWhere((p) => p.playerId == firstPlaceId);

    var next = state.copyWith(
      players: newPlayers,
      roundNumber: nextRound,
      finishOrderIds: const [],
      clearLastPlay: true,
      clearLastPlayPlayerId: true,
      passedPlayerIds: {},
      lastActionByPlayer: {},
      tributes: const [],
      tributeSummary: '',
    );

    // Check Tribute & Anti-Tribute (进贡/抗贡)
    if (state.config.enableTribute && prevOrder.length == 4) {
      final p1 = newPlayers.firstWhere((p) => p.playerId == prevOrder[0]);
      final p2 = newPlayers.firstWhere((p) => p.playerId == prevOrder[1]);
      final p3 = newPlayers.firstWhere((p) => p.playerId == prevOrder[2]);
      final p4 = newPlayers.firstWhere((p) => p.playerId == prevOrder[3]);

      final isDoubleDown = p1.teamIndex == p2.teamIndex;
      final isSingleDown = p1.teamIndex == p3.teamIndex;

      if (isDoubleDown) {
        final loserBigJokers =
            p3.hand.where((c) => c.isBigJoker).length +
            p4.hand.where((c) => c.isBigJoker).length;
        if (loserBigJokers >= 2) {
          next = next.copyWith(
            phase: GuandanPhase.playing,
            currentTurnIndex: firstPlaceIndex,
            tributeSummary: '败方手握双大王，抗贡成功！由上局头游 ${p1.seatNumber}号 先出牌。',
          );
          return _emitEvent(
            next,
            events,
            type: 'anti_tribute',
            message: next.tributeSummary,
            narrationText: '抗贡成功，免除进贡，请${p1.seatNumber}号头游先出牌。',
          );
        }

        next = next.copyWith(
          phase: GuandanPhase.tributePay,
          currentTurnIndex: firstPlaceIndex,
          tributes: [
            TributeObligation(fromPlayerId: p3.playerId, toPlayerId: p1.playerId),
            TributeObligation(fromPlayerId: p4.playerId, toPlayerId: p2.playerId),
          ],
          tributeSummary: '上局双下！请 ${p3.seatNumber}号、${p4.seatNumber}号 进贡手中最大非逢人配卡牌。',
        );
        return _emitEvent(
          next,
          events,
          type: 'tribute_start',
          message: next.tributeSummary,
          narrationText: '第$nextRound局打${GuandanState.levelLabel(level)}，请双下玩家进贡。',
        );
      } else if (isSingleDown) {
        final p4BigJokers = p4.hand.where((c) => c.isBigJoker).length;
        if (p4BigJokers >= 2) {
          next = next.copyWith(
            phase: GuandanPhase.playing,
            currentTurnIndex: firstPlaceIndex,
            tributeSummary: '${p4.seatNumber}号手握双大王，抗贡成功！由上局头游 ${p1.seatNumber}号 先出牌。',
          );
          return _emitEvent(
            next,
            events,
            type: 'anti_tribute',
            message: next.tributeSummary,
            narrationText: '${p4.seatNumber}号抗贡成功，请${p1.seatNumber}号先出牌。',
          );
        }

        next = next.copyWith(
          phase: GuandanPhase.tributePay,
          currentTurnIndex: firstPlaceIndex,
          tributes: [
            TributeObligation(fromPlayerId: p4.playerId, toPlayerId: p1.playerId),
          ],
          tributeSummary: '请末游 ${p4.seatNumber}号 向头游 ${p1.seatNumber}号 进贡最大非逢人配卡牌。',
        );
        return _emitEvent(
          next,
          events,
          type: 'tribute_start',
          message: next.tributeSummary,
          narrationText: '第$nextRound局打${GuandanState.levelLabel(level)}，请${p4.seatNumber}号进贡。',
        );
      }
    }

    next = next.copyWith(
      phase: GuandanPhase.playing,
      currentTurnIndex: firstPlaceIndex,
    );
    return _emitEvent(
      next,
      events,
      type: 'round_start',
      message:
          '第 $nextRound 局开始！当前打 ${GuandanState.levelLabel(level)}，由上局头游先出牌。',
      narrationText: '第$nextRound局开始，当前打${GuandanState.levelLabel(level)}。',
    );
  }

  GuandanState _handlePayTribute(
    GuandanState state,
    String playerId,
    String cardId,
    List<GameEvent> events,
  ) {
    if (state.phase != GuandanPhase.tributePay) {
      throw const GameRuleException('当前不在进贡阶段。');
    }
    final idx = state.tributes.indexWhere(
      (t) => t.fromPlayerId == playerId && t.tributedCard == null,
    );
    if (idx == -1) {
      throw const GameRuleException('你不需要进贡或已完成进贡。');
    }

    final payer = state.playerById(playerId)!;
    final card = payer.hand.where((c) => c.id == cardId).firstOrNull;
    if (card == null) {
      throw const GameRuleException('所选进贡牌不在手牌中。');
    }
    if (card.isWildcard(state.currentLevel)) {
      throw const GameRuleException('红桃逢人配不能作为进贡牌。');
    }

    final maxAllowedStrength = _highestTributableStrength(payer.hand, state.currentLevel);
    if (card.strength(state.currentLevel) < maxAllowedStrength) {
      throw const GameRuleException('必须进贡手牌中点数最大的非逢人配单牌。');
    }

    final updatedHand = payer.hand.where((c) => c.id != card.id).toList();
    var updatedPlayers = state.players
        .map((p) => p.playerId == playerId ? p.copyWith(hand: updatedHand) : p)
        .toList();

    final updatedTributes = List<TributeObligation>.from(state.tributes);
    updatedTributes[idx] = updatedTributes[idx].copyWith(tributedCard: card);

    if (updatedTributes.any((t) => t.tributedCard == null)) {
      return state.copyWith(
        players: updatedPlayers,
        tributes: updatedTributes,
      );
    }

    // All tributes paid! For double-down, higher tribute card goes to 1st place (tributes[0].toPlayerId).
    if (updatedTributes.length == 2) {
      final s0 = updatedTributes[0].tributedCard!.strength(state.currentLevel);
      final s1 = updatedTributes[1].tributedCard!.strength(state.currentLevel);
      if (s1 > s0) {
        final to0 = updatedTributes[0].toPlayerId;
        final to1 = updatedTributes[1].toPlayerId;
        updatedTributes[0] = TributeObligation(
          fromPlayerId: updatedTributes[0].fromPlayerId,
          toPlayerId: to1,
          tributedCard: updatedTributes[0].tributedCard,
        );
        updatedTributes[1] = TributeObligation(
          fromPlayerId: updatedTributes[1].fromPlayerId,
          toPlayerId: to0,
          tributedCard: updatedTributes[1].tributedCard,
        );
      }
    }

    // Deliver tributed cards to recipients' hands
    for (final t in updatedTributes) {
      updatedPlayers = updatedPlayers.map((p) {
        if (p.playerId != t.toPlayerId) return p;
        return p.copyWith(
          hand: GuandanEvaluator.sortHand(
            [...p.hand, t.tributedCard!],
            state.currentLevel,
          ),
        );
      }).toList();
    }

    var next = state.copyWith(
      players: updatedPlayers,
      tributes: updatedTributes,
      phase: GuandanPhase.tributeReturn,
      tributeSummary: '进贡完成！请收贡方各选择一张不大于 10 的牌还贡。',
    );
    return _emitEvent(
      next,
      events,
      type: 'tribute_return_start',
      message: next.tributeSummary,
      narrationText: '进贡完成，请赢家还贡。',
    );
  }

  GuandanState _handleReturnTribute(
    GuandanState state,
    String playerId,
    String cardId,
    List<GameEvent> events,
  ) {
    if (state.phase != GuandanPhase.tributeReturn) {
      throw const GameRuleException('当前不在还贡阶段。');
    }
    final idx = state.tributes.indexWhere(
      (t) => t.toPlayerId == playerId && t.returnedCard == null,
    );
    if (idx == -1) {
      throw const GameRuleException('你不需要还贡或已完成还贡。');
    }

    final returner = state.playerById(playerId)!;
    final card = returner.hand.where((c) => c.id == cardId).firstOrNull;
    if (card == null) {
      throw const GameRuleException('所选还贡牌不在手牌中。');
    }

    final hasUnder10 = returner.hand.any(
      (c) => !c.isJoker && !c.isLevelCard(state.currentLevel) && c.rank <= 10,
    );
    if (hasUnder10 &&
        (card.isJoker || card.isLevelCard(state.currentLevel) || card.rank > 10)) {
      throw const GameRuleException('还贡牌点数不能大于 10（且不能是级牌或大小王）。');
    }

    final obligation = state.tributes[idx];
    final updatedPlayers = state.players.map((p) {
      if (p.playerId == playerId) {
        return p.copyWith(
          hand: p.hand.where((c) => c.id != card.id).toList(),
        );
      }
      if (p.playerId == obligation.fromPlayerId) {
        return p.copyWith(
          hand: GuandanEvaluator.sortHand([...p.hand, card], state.currentLevel),
        );
      }
      return p;
    }).toList();

    final updatedTributes = List<TributeObligation>.from(state.tributes);
    updatedTributes[idx] = obligation.copyWith(returnedCard: card);

    if (updatedTributes.any((t) => t.returnedCard == null)) {
      return state.copyWith(
        players: updatedPlayers,
        tributes: updatedTributes,
      );
    }

    // All returned! The tribute payer who paid the highest card leads the round.
    var leaderObligation = updatedTributes.first;
    for (final t in updatedTributes.skip(1)) {
      if (t.tributedCard!.strength(state.currentLevel) >
          leaderObligation.tributedCard!.strength(state.currentLevel)) {
        leaderObligation = t;
      }
    }
    final leadIdx =
        updatedPlayers.indexWhere((p) => p.playerId == leaderObligation.fromPlayerId);
    final leadPlayer = updatedPlayers[leadIdx];

    var next = state.copyWith(
      players: updatedPlayers,
      tributes: updatedTributes,
      phase: GuandanPhase.playing,
      currentTurnIndex: leadIdx,
      tributeSummary: '进贡还贡完成！由进贡方 ${leadPlayer.seatNumber}号 ${leadPlayer.name} 率先出牌。',
    );
    return _emitEvent(
      next,
      events,
      type: 'tribute_done',
      message: next.tributeSummary,
      narrationText: '还贡完成，请${leadPlayer.seatNumber}号玩家先出牌。',
    );
  }

  /// Strict privacy-filtered projection: only sends [playerId]'s own hand!
  Map<String, dynamic> projectStateForPlayer(
    GuandanState state,
    String playerId,
  ) {
    final viewer = state.playerById(playerId);
    final currentLevel = state.currentLevel;

    final pendingPay = state.phase == GuandanPhase.tributePay &&
        state.tributes.any(
          (t) => t.fromPlayerId == playerId && t.tributedCard == null,
        );
    final pendingReturn = state.phase == GuandanPhase.tributeReturn &&
        state.tributes.any(
          (t) => t.toPlayerId == playerId && t.returnedCard == null,
        );

    final isMyTurn = state.phase == GuandanPhase.playing &&
        state.currentTurnPlayer.playerId == playerId;
    final canPass = isMyTurn &&
        state.lastPlay != null &&
        state.lastPlayPlayerId != playerId;

    return {
      'phase': state.phase.name,
      'phaseName': state.phase.displayName,
      'roundNumber': state.roundNumber,
      'currentLevel': currentLevel,
      'currentLevelLabel': GuandanState.levelLabel(currentLevel),
      'teamLevels': state.teamLevels,
      'teamLevelLabels': [
        GuandanState.levelLabel(state.teamLevels[0]),
        GuandanState.levelLabel(state.teamLevels[1]),
      ],
      'activeTeamIndex': state.activeTeamIndex,
      'currentTurnPlayerId': state.currentTurnPlayer.playerId,
      'currentTurnSeat': state.currentTurnPlayer.seatNumber,
      'isMyTurn': isMyTurn,
      'canPass': canPass,
      'pendingTributePay': pendingPay,
      'pendingTributeReturn': pendingReturn,
      'tributeSummary': state.tributeSummary,
      'config': state.config.toJson(),
      if (state.lastPlay != null) 'lastPlay': state.lastPlay!.toJson(),
      'lastPlayPlayerId': state.lastPlayPlayerId,
      'lastActionByPlayer': state.lastActionByPlayer,
      'finishOrderIds': state.finishOrderIds,
      'lastRoundSummary': state.lastRoundSummary,
      'lastWinningTeam': state.lastWinningTeam,
      'lastLevelGain': state.lastLevelGain,
      'matchWinnerTeam': state.matchWinnerTeam,
      if (viewer != null)
        'myHand': GuandanEvaluator.sortHand(viewer.hand, currentLevel)
            .map((c) => c.toJson())
            .toList(),
      'players': state.players
          .map((p) => {
                'playerId': p.playerId,
                'name': p.name,
                'seatNumber': p.seatNumber,
                'teamIndex': p.teamIndex,
                'teamName': p.teamName,
                'cardCount': p.hand.length,
                'finishOrder': p.finishOrder,
                'isFinished': p.isFinished,
                'isCurrentTurn': state.phase == GuandanPhase.playing &&
                    state.currentTurnPlayer.playerId == p.playerId,
                'lastAction': state.lastActionByPlayer[p.playerId],
              })
          .toList(),
    };
  }

  List<List<PlayingCard>> _dealHands(int currentLevel) {
    final deck = <PlayingCard>[];
    const suits = [
      CardSuit.spades,
      CardSuit.hearts,
      CardSuit.clubs,
      CardSuit.diamonds,
    ];
    for (var d = 0; d < 2; d++) {
      for (final suit in suits) {
        for (var rank = 2; rank <= 14; rank++) {
          deck.add(PlayingCard(
            id: 'd${d}_${suit.name}_$rank',
            suit: suit,
            rank: rank,
          ));
        }
      }
      deck.add(PlayingCard(id: 'd${d}_joker_15', suit: CardSuit.joker, rank: 15));
      deck.add(PlayingCard(id: 'd${d}_joker_16', suit: CardSuit.joker, rank: 16));
    }
    deck.shuffle(_random);

    return List.generate(
      4,
      (i) => GuandanEvaluator.sortHand(
        deck.sublist(i * 27, (i + 1) * 27),
        currentLevel,
      ),
    );
  }

  int _highestTributableStrength(List<PlayingCard> hand, int currentLevel) {
    var best = -1;
    for (final c in hand) {
      if (c.isWildcard(currentLevel)) continue;
      final s = c.strength(currentLevel);
      if (s > best) best = s;
    }
    return best;
  }

  int _nextActiveIndex(List<GuandanPlayerState> players, int fromIndex) {
    for (var step = 1; step <= 4; step++) {
      final idx = (fromIndex + step) % 4;
      if (!players[idx].isFinished) return idx;
    }
    return fromIndex;
  }

  GuandanState _emitEvent(
    GuandanState state,
    List<GameEvent> events, {
    required String type,
    required String message,
    String? narrationText,
  }) {
    final seq = state.eventSeq + 1;
    events.add(
      GameEvent(
        id: 'gd-$seq',
        type: type,
        message: message,
        narrationText: narrationText,
      ),
    );
    return state.copyWith(eventSeq: seq);
  }
}
