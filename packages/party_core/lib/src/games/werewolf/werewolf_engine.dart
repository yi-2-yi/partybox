import 'dart:math';

import '../../models/room_models.dart';
import '../../engine/game_plugin.dart';
import 'werewolf_models.dart';

/// Pure, deterministic-friendly Werewolf game engine for in-person party play.
class WerewolfEngine {
  WerewolfEngine({Random? random}) : _random = random ?? Random();

  final Random _random;

  String? validateStart(List<PlayerInfo> players, WerewolfConfig config) {
    final totalRoles = config.totalPlayers;
    if (totalRoles < 6) {
      return '狼人杀至少需要 6 名玩家。';
    }
    if ((config.roleCounts[WerewolfRole.werewolf] ?? 0) < 1) {
      return '板子中至少需要 1 名狼人。';
    }
    final goodCount = totalRoles - (config.roleCounts[WerewolfRole.werewolf] ?? 0);
    if (goodCount <= (config.roleCounts[WerewolfRole.werewolf] ?? 0)) {
      return '好人数量必须多于狼人数量。';
    }
    if (players.length != totalRoles) {
      return '当前房间有 ${players.length} 人，但板子需要 $totalRoles 人，请调整人数或板子。';
    }
    return null;
  }

  GameTransition<WerewolfState> initGame(
    List<PlayerInfo> players,
    WerewolfConfig config,
  ) {
    final error = validateStart(players, config);
    if (error != null) {
      throw GameRuleException(error);
    }

    final roleDeck = <WerewolfRole>[];
    for (final entry in config.roleCounts.entries) {
      for (var i = 0; i < entry.value; i++) {
        roleDeck.add(entry.key);
      }
    }
    roleDeck.shuffle(_random);

    final sortedPlayers = [...players]
      ..sort((a, b) => a.seatNumber.compareTo(b.seatNumber));

    final wwPlayers = <WerewolfPlayerState>[];
    for (var i = 0; i < sortedPlayers.length; i++) {
      final p = sortedPlayers[i];
      wwPlayers.add(
        WerewolfPlayerState(
          playerId: p.id,
          name: p.name,
          seatNumber: p.seatNumber,
          role: roleDeck[i],
          avatarIndex: p.avatarIndex,
        ),
      );
    }

    var state = WerewolfState(
      config: config,
      players: wwPlayers,
      phase: WerewolfPhase.roleReveal,
      dayNumber: 0,
      logs: [
        GameLogEntry(
          day: 0,
          phase: '发牌',
          summary:
              '游戏开始（${config.totalPlayers}人局${config.enableSheriff ? " · 含警长竞选" : ""}），身份牌已随机发放。',
          isPublic: true,
        ),
      ],
    );

    final events = <GameEvent>[];
    state = _emitEvent(
      state,
      events,
      type: 'phase_change',
      message: '身份牌已发放，请长按查看自己的身份并点击确认。',
      narrationText: '游戏开始，请各位玩家秘密查看自己的身份牌，确认完毕后准备天黑。',
    );

    return GameTransition(state: state, events: events);
  }

  GameTransition<WerewolfState> handleAction(
    WerewolfState state,
    String playerId,
    String actionType,
    Map<String, dynamic> payload, {
    required String hostId,
  }) {
    if (state.phase == WerewolfPhase.gameOver) {
      throw const GameRuleException('本局游戏已经结束。');
    }

    final events = <GameEvent>[];

    if (actionType == WerewolfActionType.hostAdvance) {
      if (playerId != hostId) {
        throw const GameRuleException('只有房主可以手动推进阶段。');
      }
      final next = _hostAdvance(state, events);
      return GameTransition(
        state: next,
        events: events,
        isFinished: next.phase == WerewolfPhase.gameOver,
      );
    }

    final next = switch (actionType) {
      WerewolfActionType.confirmRole => _handleConfirmRole(state, playerId, events),
      WerewolfActionType.guardProtect =>
        _handleGuardProtect(state, playerId, payload['targetId'] as String?, events),
      WerewolfActionType.wolfSelect =>
        _handleWolfSelect(state, playerId, payload['targetId'] as String?, events),
      WerewolfActionType.wolfConfirm =>
        _handleWolfConfirm(state, playerId, payload['targetId'] as String?, events),
      WerewolfActionType.witchAct => _handleWitchAct(
          state,
          playerId,
          payload['action'] as String? ?? 'skip',
          payload['targetId'] as String?,
          events,
        ),
      WerewolfActionType.seerCheck =>
        _handleSeerCheck(state, playerId, payload['targetId'] as String?, events),
      WerewolfActionType.seerDone => _handleSeerDone(state, playerId, events),
      WerewolfActionType.sheriffSignup =>
        _handleSheriffSignup(state, playerId, payload['join'] as bool? ?? false, events),
      WerewolfActionType.sheriffWithdraw =>
        _handleSheriffWithdraw(state, playerId, events),
      WerewolfActionType.sheriffVote =>
        _handleSheriffVote(state, playerId, payload['targetId'] as String?, events),
      WerewolfActionType.sheriffTransfer =>
        _handleSheriffTransfer(state, playerId, payload['targetId'] as String?, events),
      WerewolfActionType.hunterShoot =>
        _handleHunterShoot(state, playerId, payload['targetId'] as String?, events),
      WerewolfActionType.dayVote =>
        _handleDayVote(state, playerId, payload['targetId'] as String?, events),
      _ => throw GameRuleException('未知的游戏操作：$actionType'),
    };

    return GameTransition(
      state: next,
      events: events,
      isFinished: next.phase == WerewolfPhase.gameOver,
    );
  }

  WerewolfState _handleConfirmRole(
    WerewolfState state,
    String playerId,
    List<GameEvent> events,
  ) {
    _requirePhase(state, WerewolfPhase.roleReveal);
    _requirePlayer(state, playerId);

    final updated = {...state.confirmedRolePlayerIds, playerId};
    var next = state.copyWith(confirmedRolePlayerIds: updated);
    if (updated.length >= state.players.length) {
      next = _enterNight(next, events);
    }
    return next;
  }

  WerewolfState _handleGuardProtect(
    WerewolfState state,
    String playerId,
    String? targetId,
    List<GameEvent> events,
  ) {
    _requirePhase(state, WerewolfPhase.nightGuard);
    final player = _requireAlivePlayer(state, playerId);
    if (player.role != WerewolfRole.guard) {
      throw const GameRuleException('当前不是你的行动阶段。');
    }

    if (targetId != null) {
      final target = _requireAlivePlayer(state, targetId);
      if (state.lastNightGuardTargetId == target.playerId) {
        throw const GameRuleException('守卫不能连续两晚守护同一名玩家。');
      }
      state = state.copyWith(
        currentNightGuardTargetId: target.playerId,
        logs: [
          ...state.logs,
          GameLogEntry(
            day: state.dayNumber,
            phase: '夜晚·守卫',
            summary: '守卫（${player.seatNumber}号）守护了 ${target.seatNumber}号 ${target.name}。',
          ),
        ],
      );
    } else {
      state = state.copyWith(
        clearCurrentNightGuardTarget: true,
        logs: [
          ...state.logs,
          GameLogEntry(
            day: state.dayNumber,
            phase: '夜晚·守卫',
            summary: '守卫（${player.seatNumber}号）选择空守。',
          ),
        ],
      );
    }

    return _advanceNightAfterGuard(state, events);
  }

  WerewolfState _handleWolfSelect(
    WerewolfState state,
    String playerId,
    String? targetId,
    List<GameEvent> events,
  ) {
    _requirePhase(state, WerewolfPhase.nightWolf);
    final player = _requireAlivePlayer(state, playerId);
    if (player.role != WerewolfRole.werewolf) {
      throw const GameRuleException('只有存活狼人可以在此阶段操作。');
    }
    if (targetId != null) {
      _requireAlivePlayer(state, targetId);
    }

    final selections = Map<String, String?>.from(state.wolfSelections);
    selections[playerId] = targetId;
    final confirmed = Set<String>.from(state.wolfConfirmedIds)..remove(playerId);

    return state.copyWith(
      wolfSelections: selections,
      wolfConfirmedIds: confirmed,
    );
  }

  WerewolfState _handleWolfConfirm(
    WerewolfState state,
    String playerId,
    String? targetId,
    List<GameEvent> events,
  ) {
    _requirePhase(state, WerewolfPhase.nightWolf);
    final player = _requireAlivePlayer(state, playerId);
    if (player.role != WerewolfRole.werewolf) {
      throw const GameRuleException('只有存活狼人可以确认袭击目标。');
    }
    if (targetId != null) {
      _requireAlivePlayer(state, targetId);
    }

    final selections = Map<String, String?>.from(state.wolfSelections);
    if (targetId != null || !selections.containsKey(playerId)) {
      selections[playerId] = targetId;
    }
    final confirmed = {...state.wolfConfirmedIds, playerId};
    var next = state.copyWith(
      wolfSelections: selections,
      wolfConfirmedIds: confirmed,
    );

    final aliveWolves = next.aliveWithRole(WerewolfRole.werewolf);
    if (aliveWolves.every((w) => confirmed.contains(w.playerId))) {
      next = _finalizeWolfKill(next, events);
    }
    return next;
  }

  WerewolfState _finalizeWolfKill(WerewolfState state, List<GameEvent> events) {
    final counts = <String, int>{};
    for (final wolf in state.aliveWithRole(WerewolfRole.werewolf)) {
      final pick = state.wolfSelections[wolf.playerId];
      if (pick != null) {
        counts[pick] = (counts[pick] ?? 0) + 1;
      }
    }

    String? chosenTargetId;
    var bestCount = 0;
    for (final entry in counts.entries) {
      if (entry.value > bestCount) {
        bestCount = entry.value;
        chosenTargetId = entry.key;
      } else if (entry.value == bestCount && chosenTargetId != null) {
        final existingSeat = state.playerById(chosenTargetId)?.seatNumber ?? 99;
        final candidateSeat = state.playerById(entry.key)?.seatNumber ?? 99;
        if (candidateSeat < existingSeat) {
          chosenTargetId = entry.key;
        }
      }
    }

    final targetPlayer =
        chosenTargetId == null ? null : state.playerById(chosenTargetId);
    final next = state.copyWith(
      currentNightWolfTargetId: chosenTargetId,
      clearCurrentNightWolfTarget: chosenTargetId == null,
      logs: [
        ...state.logs,
        GameLogEntry(
          day: state.dayNumber,
          phase: '夜晚·狼人',
          summary: targetPlayer == null
              ? '狼人团队选择空刀。'
              : '狼人团队袭击了 ${targetPlayer.seatNumber}号 ${targetPlayer.name}。',
        ),
      ],
    );

    return _advanceNightAfterWolf(next, events);
  }

  WerewolfState _handleWitchAct(
    WerewolfState state,
    String playerId,
    String action,
    String? targetId,
    List<GameEvent> events,
  ) {
    _requirePhase(state, WerewolfPhase.nightWitch);
    final witch = _requireAlivePlayer(state, playerId);
    if (witch.role != WerewolfRole.witch) {
      throw const GameRuleException('当前不是你的行动阶段。');
    }

    var next = state;
    switch (action) {
      case 'save':
        if (state.witchAntidoteUsed) {
          throw const GameRuleException('解药已经用过了。');
        }
        final wolfTargetId = state.currentNightWolfTargetId;
        if (wolfTargetId == null) {
          throw const GameRuleException('今夜无人被狼人袭击，无法使用解药。');
        }
        if (wolfTargetId == witch.playerId &&
            !(state.dayNumber == 1 && state.config.witchSelfSaveFirstNight)) {
          throw const GameRuleException('当前规则下女巫今晚不能自救。');
        }
        final target = state.playerById(wolfTargetId)!;
        next = state.copyWith(
          witchAntidoteUsed: true,
          currentNightWitchSaved: true,
          logs: [
            ...state.logs,
            GameLogEntry(
              day: state.dayNumber,
              phase: '夜晚·女巫',
              summary: '女巫（${witch.seatNumber}号）使用解药救了 ${target.seatNumber}号 ${target.name}。',
            ),
          ],
        );
      case 'poison':
        if (state.witchPoisonUsed) {
          throw const GameRuleException('毒药已经用过了。');
        }
        if (targetId == null) {
          throw const GameRuleException('请选择要使用毒药的目标。');
        }
        final target = _requireAlivePlayer(state, targetId);
        next = state.copyWith(
          witchPoisonUsed: true,
          currentNightWitchPoisonTargetId: target.playerId,
          logs: [
            ...state.logs,
            GameLogEntry(
              day: state.dayNumber,
              phase: '夜晚·女巫',
              summary: '女巫（${witch.seatNumber}号）使用毒药毒杀了 ${target.seatNumber}号 ${target.name}。',
            ),
          ],
        );
      case 'skip':
        next = state.copyWith(
          logs: [
            ...state.logs,
            GameLogEntry(
              day: state.dayNumber,
              phase: '夜晚·女巫',
              summary: '女巫（${witch.seatNumber}号）本夜未用药。',
            ),
          ],
        );
      default:
        throw GameRuleException('无效的女巫操作：$action');
    }

    return _advanceNightAfterWitch(next, events);
  }

  WerewolfState _handleSeerCheck(
    WerewolfState state,
    String playerId,
    String? targetId,
    List<GameEvent> events,
  ) {
    _requirePhase(state, WerewolfPhase.nightSeer);
    final seer = _requireAlivePlayer(state, playerId);
    if (seer.role != WerewolfRole.seer) {
      throw const GameRuleException('当前不是你的行动阶段。');
    }
    if (state.currentNightSeerChecked) {
      throw const GameRuleException('今晚已经查验过了，请点击完成。');
    }
    if (targetId == null) {
      throw const GameRuleException('请选择要查验的玩家。');
    }
    if (targetId == seer.playerId) {
      throw const GameRuleException('不能查验自己。');
    }
    final target = _requireAlivePlayer(state, targetId);
    final record = SeerCheckRecord(
      night: state.dayNumber,
      targetId: target.playerId,
      targetSeat: target.seatNumber,
      targetName: target.name,
      isWolf: target.role.isWolf,
    );

    return state.copyWith(
      currentNightSeerChecked: true,
      seerHistory: [...state.seerHistory, record],
      logs: [
        ...state.logs,
        GameLogEntry(
          day: state.dayNumber,
          phase: '夜晚·预言家',
          summary:
              '预言家（${seer.seatNumber}号）查验了 ${target.seatNumber}号 ${target.name}，结果为「${record.isWolf ? "狼人" : "好人"}」。',
        ),
      ],
    );
  }

  WerewolfState _handleSeerDone(
    WerewolfState state,
    String playerId,
    List<GameEvent> events,
  ) {
    _requirePhase(state, WerewolfPhase.nightSeer);
    final seer = _requireAlivePlayer(state, playerId);
    if (seer.role != WerewolfRole.seer) {
      throw const GameRuleException('只有预言家可以结束查验阶段。');
    }
    return _finishNight(state, events);
  }

  WerewolfState _handleSheriffSignup(
    WerewolfState state,
    String playerId,
    bool join,
    List<GameEvent> events,
  ) {
    _requirePhase(state, WerewolfPhase.sheriffSignup);
    _requirePlayer(state, playerId);

    final decided = {...state.sheriffSignupDecidedIds, playerId};
    final candidates = Set<String>.from(state.sheriffCandidates);
    if (join) {
      candidates.add(playerId);
    } else {
      candidates.remove(playerId);
    }

    var next = state.copyWith(
      sheriffSignupDecidedIds: decided,
      sheriffCandidates: candidates,
    );

    if (decided.length >= state.players.length) {
      next = _resolveSheriffSignup(next, events);
    }
    return next;
  }

  WerewolfState _handleSheriffWithdraw(
    WerewolfState state,
    String playerId,
    List<GameEvent> events,
  ) {
    if (state.phase != WerewolfPhase.sheriffSignup &&
        state.phase != WerewolfPhase.sheriffVote) {
      throw const GameRuleException('当前不在警长竞选阶段。');
    }
    if (!state.sheriffCandidates.contains(playerId)) {
      throw const GameRuleException('你目前不在上警名单中。');
    }

    final player = _requirePlayer(state, playerId);
    final candidates = Set<String>.from(state.sheriffCandidates)..remove(playerId);
    var next = state.copyWith(
      sheriffCandidates: candidates,
      logs: [
        ...state.logs,
        GameLogEntry(
          day: state.dayNumber,
          phase: '警长竞选',
          summary: '${player.seatNumber}号 ${player.name} 退水。',
          isPublic: true,
        ),
      ],
    );

    if (state.phase == WerewolfPhase.sheriffVote) {
      if (candidates.isEmpty) {
        next = _emitEvent(
          next.copyWith(sheriffBadgeDestroyed: true),
          events,
          type: 'sheriff_result',
          message: '所有上警玩家均已退水，警徽流失！',
          narrationText: '所有上警玩家退水，本局警徽流失。',
        );
        return _announceDawn(next, next.pendingNightDeaths, events);
      }
      if (candidates.length == 1) {
        final winnerId = candidates.first;
        final winner = next.playerById(winnerId)!;
        next = next.copyWith(
          sheriffId: winnerId,
          logs: [
            ...next.logs,
            GameLogEntry(
              day: next.dayNumber,
              phase: '警长竞选',
              summary: '其余候选人退水，${winner.seatNumber}号 ${winner.name} 自动当选警长！',
              isPublic: true,
            ),
          ],
        );
        next = _emitEvent(
          next,
          events,
          type: 'sheriff_result',
          message: '${winner.seatNumber}号 ${winner.name} 当选警长！',
          narrationText: '恭喜${winner.seatNumber}号玩家当选警长。',
        );
        return _announceDawn(next, next.pendingNightDeaths, events);
      }
    }

    return next;
  }

  WerewolfState _resolveSheriffSignup(
    WerewolfState state,
    List<GameEvent> events,
  ) {
    final candidates = state.sheriffCandidates;
    if (candidates.isEmpty) {
      var next = state.copyWith(
        sheriffBadgeDestroyed: true,
        logs: [
          ...state.logs,
          GameLogEntry(
            day: state.dayNumber,
            phase: '警长竞选',
            summary: '无人上警，本局无警长。',
            isPublic: true,
          ),
        ],
      );
      next = _emitEvent(
        next,
        events,
        type: 'sheriff_result',
        message: '无人上警，本局没有警长。',
        narrationText: '无人上警，本局没有警长，下面公布昨夜信息。',
      );
      return _announceDawn(next, next.pendingNightDeaths, events);
    }

    if (candidates.length >= state.players.length) {
      var next = state.copyWith(
        sheriffBadgeDestroyed: true,
        logs: [
          ...state.logs,
          GameLogEntry(
            day: state.dayNumber,
            phase: '警长竞选',
            summary: '全员上警，无人投票，警徽流失。',
            isPublic: true,
          ),
        ],
      );
      next = _emitEvent(
        next,
        events,
        type: 'sheriff_result',
        message: '全员上警，本局警徽流失！',
        narrationText: '全员上警，警徽流失，下面公布昨夜信息。',
      );
      return _announceDawn(next, next.pendingNightDeaths, events);
    }

    if (candidates.length == 1) {
      final winnerId = candidates.first;
      final winner = state.playerById(winnerId)!;
      var next = state.copyWith(
        sheriffId: winnerId,
        logs: [
          ...state.logs,
          GameLogEntry(
            day: state.dayNumber,
            phase: '警长竞选',
            summary: '仅 ${winner.seatNumber}号 ${winner.name} 上警，自动当选警长！',
            isPublic: true,
          ),
        ],
      );
      next = _emitEvent(
        next,
        events,
        type: 'sheriff_result',
        message: '${winner.seatNumber}号 ${winner.name} 自动当选警长！',
        narrationText: '只有${winner.seatNumber}号玩家上警，自动当选警长。',
      );
      return _announceDawn(next, next.pendingNightDeaths, events);
    }

    final seatLabels = candidates
        .map((id) => '${state.playerById(id)!.seatNumber}号')
        .toList()
      ..sort();

    return _emitEvent(
      state.copyWith(
        phase: WerewolfPhase.sheriffVote,
        sheriffVotes: {},
        sheriffPkRound: 0,
      ),
      events,
      type: 'phase_change',
      message: '上警玩家：${seatLabels.join("、")}。警上发言结束后，请警下玩家投票。',
      narrationText: '上警结束，请上警玩家依次发言，发言完毕后由警下玩家投票选出警长。',
    );
  }

  WerewolfState _handleSheriffVote(
    WerewolfState state,
    String playerId,
    String? targetId,
    List<GameEvent> events,
  ) {
    _requirePhase(state, WerewolfPhase.sheriffVote);
    _requirePlayer(state, playerId);

    if (state.sheriffCandidates.contains(playerId)) {
      throw const GameRuleException('上警候选人不能在警长投票中投票。');
    }
    if (targetId != null && !state.sheriffCandidates.contains(targetId)) {
      throw const GameRuleException('只能投票给当前上警候选人。');
    }

    final votes = Map<String, String?>.from(state.sheriffVotes);
    votes[playerId] = targetId;
    var next = state.copyWith(sheriffVotes: votes);

    final eligibleVoters = state.players
        .where((p) => !state.sheriffCandidates.contains(p.playerId))
        .toList();
    if (eligibleVoters.every((p) => votes.containsKey(p.playerId))) {
      next = _resolveSheriffVote(next, events);
    }
    return next;
  }

  WerewolfState _resolveSheriffVote(
    WerewolfState state,
    List<GameEvent> events,
  ) {
    final counts = <String, int>{};
    for (final pick in state.sheriffVotes.values) {
      if (pick != null && state.sheriffCandidates.contains(pick)) {
        counts[pick] = (counts[pick] ?? 0) + 1;
      }
    }

    final roundLabel = state.sheriffPkRound > 0
        ? '第${state.dayNumber}天 · 警长竞选PK'
        : '第${state.dayNumber}天 · 警长竞选';

    if (counts.isEmpty) {
      const summary = '警下全部弃票，警徽流失。';
      var next = _appendVoteHistory(
        state.copyWith(
          sheriffBadgeDestroyed: true,
          logs: [
            ...state.logs,
            GameLogEntry(
              day: state.dayNumber,
              phase: '警长竞选',
              summary: summary,
              isPublic: true,
            ),
          ],
        ),
        roundLabel: roundLabel,
        ballots: state.sheriffVotes,
        summary: summary,
        isSheriffVote: true,
      );
      next = _emitEvent(
        next,
        events,
        type: 'sheriff_result',
        message: '全部弃票，警徽流失。',
        narrationText: '无人投票，警徽流失，下面公布昨夜信息。',
      );
      return _announceDawn(next, next.pendingNightDeaths, events);
    }

    final maxVotes = counts.values.reduce(max);
    final topIds = counts.entries
        .where((e) => e.value == maxVotes)
        .map((e) => e.key)
        .toSet();

    if (topIds.length == 1) {
      final winnerId = topIds.first;
      final winner = state.playerById(winnerId)!;
      final summary = '${winner.seatNumber}号 ${winner.name} 以 $maxVotes 票当选警长！';
      var next = _appendVoteHistory(
        state.copyWith(
          sheriffId: winnerId,
          logs: [
            ...state.logs,
            GameLogEntry(
              day: state.dayNumber,
              phase: '警长竞选',
              summary: summary,
              isPublic: true,
            ),
          ],
        ),
        roundLabel: roundLabel,
        ballots: state.sheriffVotes,
        summary: summary,
        isSheriffVote: true,
      );
      next = _emitEvent(
        next,
        events,
        type: 'sheriff_result',
        message: summary,
        narrationText: '恭喜${winner.seatNumber}号玩家当选警长。下面公布昨夜信息。',
      );
      return _announceDawn(next, next.pendingNightDeaths, events);
    }

    if (state.sheriffPkRound == 0) {
      final pkLabels = topIds
          .map((id) => '${state.playerById(id)!.seatNumber}号')
          .toList()
        ..sort();
      final pkSummary = '警长竞选平票（${pkLabels.join("、")} 进入 PK）';
      final recorded = _appendVoteHistory(
        state,
        roundLabel: roundLabel,
        ballots: state.sheriffVotes,
        summary: pkSummary,
        isSheriffVote: true,
      );
      return _emitEvent(
        recorded.copyWith(
          sheriffCandidates: topIds,
          sheriffVotes: {},
          sheriffPkRound: 1,
        ),
        events,
        type: 'sheriff_pk',
        message: '警长竞选平票！${pkLabels.join("、")} 进入 PK 发言并重新投票。',
        narrationText: '警长投票平票，请平票玩家进行 PK 发言并重新投票。',
      );
    }

    const tieSummary = '警长 PK 再次平票，警徽流失。';
    var next = _appendVoteHistory(
      state.copyWith(
        sheriffBadgeDestroyed: true,
        logs: [
          ...state.logs,
          GameLogEntry(
            day: state.dayNumber,
            phase: '警长竞选',
            summary: tieSummary,
            isPublic: true,
          ),
        ],
      ),
      roundLabel: roundLabel,
      ballots: state.sheriffVotes,
      summary: tieSummary,
      isSheriffVote: true,
    );
    next = _emitEvent(
      next,
      events,
      type: 'sheriff_result',
      message: '警长 PK 再次平票，本局警徽流失！',
      narrationText: '再次平票，警徽流失，下面公布昨夜信息。',
    );
    return _announceDawn(next, next.pendingNightDeaths, events);
  }

  WerewolfState _handleSheriffTransfer(
    WerewolfState state,
    String playerId,
    String? targetId,
    List<GameEvent> events,
  ) {
    _requirePhase(state, WerewolfPhase.sheriffBadgeTransfer);
    if (playerId != state.pendingBadgeTransferFromId) {
      throw const GameRuleException('只有出局的警长可以移交或撕毁警徽。');
    }

    var next = state.copyWith(clearPendingBadgeTransfer: true);
    if (targetId == null) {
      next = next.copyWith(
        clearSheriffId: true,
        sheriffBadgeDestroyed: true,
        logs: [
          ...next.logs,
          GameLogEntry(
            day: next.dayNumber,
            phase: '警徽处理',
            summary: '原警长选择撕毁警徽，本局不再有警长。',
            isPublic: true,
          ),
        ],
      );
      next = _emitEvent(
        next,
        events,
        type: 'sheriff_transfer',
        message: '警长撕毁了警徽！',
        narrationText: '警长选择撕毁警徽。',
      );
    } else {
      final target = _requireAlivePlayer(state, targetId);
      next = next.copyWith(
        sheriffId: target.playerId,
        logs: [
          ...next.logs,
          GameLogEntry(
            day: next.dayNumber,
            phase: '警徽处理',
            summary: '警徽移交给了 ${target.seatNumber}号 ${target.name}。',
            isPublic: true,
          ),
        ],
      );
      next = _emitEvent(
        next,
        events,
        type: 'sheriff_transfer',
        message: '警徽已移交给 ${target.seatNumber}号 ${target.name}！',
        narrationText: '${target.seatNumber}号玩家接过警徽，成为新任警长。',
      );
    }

    return _continueAfterSpecialPhases(next, events);
  }

  WerewolfState _handleHunterShoot(
    WerewolfState state,
    String playerId,
    String? targetId,
    List<GameEvent> events,
  ) {
    _requirePhase(state, WerewolfPhase.hunterShoot);
    if (playerId != state.pendingHunterId) {
      throw const GameRuleException('只有出局的猎人可以开枪。');
    }

    final hunter = state.playerById(playerId)!;
    var next = state.copyWith(clearPendingHunter: true);

    if (targetId == null) {
      next = next.copyWith(
        logs: [
          ...next.logs,
          GameLogEntry(
            day: next.dayNumber,
            phase: '猎人开枪',
            summary: '猎人（${hunter.seatNumber}号）选择压枪不开枪。',
            isPublic: true,
          ),
        ],
      );
      next = _emitEvent(
        next,
        events,
        type: 'hunter_shoot',
        message: '猎人（${hunter.seatNumber}号）选择不开枪。',
        narrationText: '猎人选择不开枪。',
      );
      return _continueAfterSpecialPhases(next, events);
    }

    final target = _requireAlivePlayer(state, targetId);
    final updatedPlayers = next.players.map((p) {
      if (p.playerId == target.playerId) {
        return p.copyWith(
          isAlive: false,
          deathReason: DeathReason.hunterShot,
          deathDay: next.dayNumber,
        );
      }
      return p;
    }).toList();

    next = next.copyWith(
      players: updatedPlayers,
      pendingBadgeTransferFromId:
          next.sheriffId == target.playerId ? target.playerId : next.pendingBadgeTransferFromId,
      logs: [
        ...next.logs,
        GameLogEntry(
          day: next.dayNumber,
          phase: '猎人开枪',
          summary: '猎人（${hunter.seatNumber}号）开枪带走了 ${target.seatNumber}号 ${target.name}！',
          isPublic: true,
        ),
      ],
    );
    next = _emitEvent(
      next,
      events,
      type: 'hunter_shoot',
      message: '猎人（${hunter.seatNumber}号）开枪带走了 ${target.seatNumber}号 ${target.name}！',
      narrationText: '猎人发动技能，带走了${target.seatNumber}号玩家。',
    );

    return _continueAfterSpecialPhases(next, events);
  }

  WerewolfState _handleDayVote(
    WerewolfState state,
    String playerId,
    String? targetId,
    List<GameEvent> events,
  ) {
    _requirePhase(state, WerewolfPhase.dayVote);
    final voter = _requireAlivePlayer(state, playerId);
    if (!voter.canVote) {
      throw const GameRuleException('你已翻牌白痴，失去投票权。');
    }
    if (targetId != null) {
      final target = _requireAlivePlayer(state, targetId);
      if (state.votePkRound > 0 && !state.votePkCandidates.contains(target.playerId)) {
        throw const GameRuleException('PK 阶段只能投票给平票候选人。');
      }
    }

    final votes = Map<String, String?>.from(state.dayVotes);
    votes[playerId] = targetId;
    var next = state.copyWith(dayVotes: votes);

    final eligibleVoters = state.alivePlayers.where((p) => p.canVote).toList();
    if (eligibleVoters.every((p) => votes.containsKey(p.playerId))) {
      next = _resolveDayVote(next, events);
    }
    return next;
  }

  WerewolfState _resolveDayVote(WerewolfState state, List<GameEvent> events) {
    // Use integer half-votes so Sheriff's 1.5 vote is exact (3 vs 2).
    final halfVoteCounts = <String, int>{};
    for (final entry in state.dayVotes.entries) {
      final voterId = entry.key;
      final targetId = entry.value;
      if (targetId == null) continue;
      final voter = state.playerById(voterId);
      if (voter == null || !voter.isAlive || !voter.canVote) continue;
      final weight = (state.sheriffId == voterId) ? 3 : 2;
      halfVoteCounts[targetId] = (halfVoteCounts[targetId] ?? 0) + weight;
    }

    final tallyDouble = {
      for (final e in halfVoteCounts.entries) e.key: e.value / 2.0,
    };

    final roundLabel = state.votePkRound > 0
        ? '第${state.dayNumber}天 · 放逐投票PK'
        : '第${state.dayNumber}天 · 放逐投票';

    if (halfVoteCounts.isEmpty) {
      final summary = '全员弃票，今天没有人被放逐。';
      var next = _appendVoteHistory(
        state.copyWith(
          phase: WerewolfPhase.voteResult,
          lastVoteTally: {},
          lastVoteSummary: summary,
          clearAfterSpecialPhase: true,
          logs: [
            ...state.logs,
            GameLogEntry(day: state.dayNumber, phase: '白天·投票', summary: summary, isPublic: true),
          ],
        ),
        roundLabel: roundLabel,
        ballots: state.dayVotes,
        summary: summary,
      );
      return _emitEvent(
        next,
        events,
        type: 'vote_result',
        message: summary,
        narrationText: '全员弃票，今天无人出局，即将进入黑夜。',
      );
    }

    final maxHalf = halfVoteCounts.values.reduce(max);
    final topIds = halfVoteCounts.entries
        .where((e) => e.value == maxHalf)
        .map((e) => e.key)
        .toSet();

    if (topIds.length > 1) {
      if (state.votePkRound == 0) {
        final pkLabels = topIds
            .map((id) => '${state.playerById(id)!.seatNumber}号')
            .toList()
          ..sort();
        final recorded = _appendVoteHistory(
          state,
          roundLabel: roundLabel,
          ballots: state.dayVotes,
          summary: '放逐投票平票（${pkLabels.join("、")} 进入 PK）',
        );
        return _emitEvent(
          recorded.copyWith(
            votePkCandidates: topIds,
            votePkRound: 1,
            dayVotes: {},
            lastVoteTally: tallyDouble,
          ),
          events,
          type: 'vote_pk',
          message: '投票平票！${pkLabels.join("、")} 进入 PK 发言并重新投票。',
          narrationText: '放逐投票平票，请平票玩家进行 PK 发言，发言后重新投票。',
        );
      }

      final summary = 'PK 投票再次平票，今天无人出局。';
      var next = _appendVoteHistory(
        state.copyWith(
          phase: WerewolfPhase.voteResult,
          lastVoteTally: tallyDouble,
          lastVoteSummary: summary,
          clearAfterSpecialPhase: true,
          logs: [
            ...state.logs,
            GameLogEntry(day: state.dayNumber, phase: '白天·投票', summary: summary, isPublic: true),
          ],
        ),
        roundLabel: roundLabel,
        ballots: state.dayVotes,
        summary: summary,
      );
      return _emitEvent(
        next,
        events,
        type: 'vote_result',
        message: summary,
        narrationText: '再次平票，今天平安日无人出局。',
      );
    }

    final exiledId = topIds.first;
    final exiled = state.playerById(exiledId)!;
    final voteLabel = _formatVotes(maxHalf);

    // Idiot reveal exemption
    if (exiled.role == WerewolfRole.idiot && !exiled.idiotRevealed) {
      final updatedPlayers = state.players.map((p) {
        if (p.playerId == exiledId) {
          return p.copyWith(idiotRevealed: true, canVote: false);
        }
        return p;
      }).toList();
      final summary =
          '${exiled.seatNumber}号 ${exiled.name} 得票最高（$voteLabel票），但翻牌亮出【白痴】免死，失去后续投票权！';
      var next = _appendVoteHistory(
        state.copyWith(
          players: updatedPlayers,
          phase: WerewolfPhase.voteResult,
          lastVoteTally: tallyDouble,
          lastVoteSummary: summary,
          clearAfterSpecialPhase: true,
          logs: [
            ...state.logs,
            GameLogEntry(day: state.dayNumber, phase: '白天·投票', summary: summary, isPublic: true),
          ],
        ),
        roundLabel: roundLabel,
        ballots: state.dayVotes,
        summary: summary,
      );
      return _emitEvent(
        next,
        events,
        type: 'vote_result',
        message: summary,
        narrationText: '${exiled.seatNumber}号玩家翻牌白痴，免于放逐，但失去后续投票权。',
      );
    }

    final updatedPlayers = state.players.map((p) {
      if (p.playerId == exiledId) {
        return p.copyWith(
          isAlive: false,
          deathReason: DeathReason.dayExile,
          deathDay: state.dayNumber,
        );
      }
      return p;
    }).toList();

    final summary = '${exiled.seatNumber}号 ${exiled.name} 以 $voteLabel 票被放逐出局！';
    var next = _appendVoteHistory(
      state.copyWith(
        players: updatedPlayers,
        phase: WerewolfPhase.voteResult,
        lastVoteTally: tallyDouble,
        lastVoteSummary: summary,
        pendingBadgeTransferFromId:
            state.sheriffId == exiledId ? exiledId : state.pendingBadgeTransferFromId,
        pendingHunterId: exiled.role == WerewolfRole.hunter ? exiledId : null,
        clearAfterSpecialPhase: true,
        logs: [
          ...state.logs,
          GameLogEntry(day: state.dayNumber, phase: '白天·投票', summary: summary, isPublic: true),
        ],
      ),
      roundLabel: roundLabel,
      ballots: state.dayVotes,
      summary: summary,
    );

    return _emitEvent(
      next,
      events,
      type: 'vote_result',
      message: summary,
      narrationText: '${exiled.seatNumber}号玩家被投票放逐，请发表遗言。',
    );
  }

  WerewolfState _hostAdvance(WerewolfState state, List<GameEvent> events) {
    return switch (state.phase) {
      WerewolfPhase.roleReveal => _enterNight(state, events),
      WerewolfPhase.nightGuard => _advanceNightAfterGuard(state, events),
      WerewolfPhase.nightWolf => _finalizeWolfKill(state, events),
      WerewolfPhase.nightWitch => _advanceNightAfterWitch(state, events),
      WerewolfPhase.nightSeer => _finishNight(state, events),
      WerewolfPhase.sheriffSignup => _resolveSheriffSignup(state, events),
      WerewolfPhase.sheriffVote => _resolveSheriffVote(state, events),
      WerewolfPhase.dayAnnounce => _continueAfterSpecialPhases(state, events),
      WerewolfPhase.sheriffBadgeTransfer => _handleSheriffTransfer(
          state,
          state.pendingBadgeTransferFromId!,
          null,
          events,
        ),
      WerewolfPhase.hunterShoot => _handleHunterShoot(
          state,
          state.pendingHunterId!,
          null,
          events,
        ),
      WerewolfPhase.dayDiscuss => _enterDayVote(state, events),
      WerewolfPhase.dayVote => _resolveDayVote(state, events),
      WerewolfPhase.voteResult => _continueAfterSpecialPhases(state, events),
      WerewolfPhase.gameOver => state,
    };
  }

  WerewolfState _enterNight(WerewolfState state, List<GameEvent> events) {
    final nextDay = state.dayNumber + 1;
    var next = state.copyWith(
      dayNumber: nextDay,
      clearCurrentNightGuardTarget: true,
      wolfSelections: {},
      wolfConfirmedIds: {},
      clearCurrentNightWolfTarget: true,
      currentNightWitchSaved: false,
      clearCurrentNightWitchPoisonTarget: true,
      currentNightSeerChecked: false,
      isDecoyNightStep: false,
      pendingNightDeaths: {},
      dayVotes: {},
      votePkCandidates: {},
      votePkRound: 0,
      clearPendingBadgeTransfer: true,
      clearPendingHunter: true,
      clearAfterSpecialPhase: true,
    );

    if (next.config.hasRole(WerewolfRole.guard)) {
      final hasAliveGuard = next.aliveWithRole(WerewolfRole.guard).isNotEmpty;
      next = next.copyWith(
        phase: WerewolfPhase.nightGuard,
        isDecoyNightStep: !hasAliveGuard,
      );
      return _emitEvent(
        next,
        events,
        type: 'phase_change',
        message: '第 $nextDay 夜 · 天黑请闭眼，守卫请睁眼。',
        narrationText: '天黑请闭眼。守卫请睁眼，请选择今晚要守护的玩家。',
        payload: const {'scriptKey': 'night_guard'},
      );
    }

    return _enterNightWolf(next, events, includeNightOpening: true);
  }

  WerewolfState _advanceNightAfterGuard(
    WerewolfState state,
    List<GameEvent> events,
  ) {
    return _enterNightWolf(state, events, includeNightOpening: false);
  }

  WerewolfState _enterNightWolf(
    WerewolfState state,
    List<GameEvent> events, {
    required bool includeNightOpening,
  }) {
    final next = state.copyWith(
      phase: WerewolfPhase.nightWolf,
      isDecoyNightStep: false,
    );
    return _emitEvent(
      next,
      events,
      type: 'phase_change',
      message: '第 ${next.dayNumber} 夜 · 狼人请睁眼并商议击杀目标。',
      narrationText: includeNightOpening
          ? '天黑请闭眼。狼人请睁眼，确认队友并选择今晚要袭击的玩家。'
          : '守卫请闭眼。狼人请睁眼，确认队友并选择今晚要袭击的玩家。',
      payload: const {'scriptKey': 'night_wolf'},
    );
  }

  WerewolfState _advanceNightAfterWolf(
    WerewolfState state,
    List<GameEvent> events,
  ) {
    if (state.config.hasRole(WerewolfRole.witch)) {
      final hasAliveWitch = state.aliveWithRole(WerewolfRole.witch).isNotEmpty;
      final next = state.copyWith(
        phase: WerewolfPhase.nightWitch,
        isDecoyNightStep: !hasAliveWitch,
      );
      return _emitEvent(
        next,
        events,
        type: 'phase_change',
        message: '狼人请闭眼，女巫请睁眼。',
        narrationText: '狼人请闭眼。女巫请睁眼，请决定是否使用解药或毒药。',
        payload: const {'scriptKey': 'night_witch'},
      );
    }
    return _advanceNightAfterWitch(state, events);
  }

  WerewolfState _advanceNightAfterWitch(
    WerewolfState state,
    List<GameEvent> events,
  ) {
    if (state.config.hasRole(WerewolfRole.seer)) {
      final hasAliveSeer = state.aliveWithRole(WerewolfRole.seer).isNotEmpty;
      final next = state.copyWith(
        phase: WerewolfPhase.nightSeer,
        isDecoyNightStep: !hasAliveSeer,
      );
      return _emitEvent(
        next,
        events,
        type: 'phase_change',
        message: '预言家请睁眼查验身份。',
        narrationText: '女巫请闭眼。预言家请睁眼，请选择今晚要查验的玩家。',
        payload: const {'scriptKey': 'night_seer'},
      );
    }
    return _finishNight(state, events);
  }

  WerewolfState _finishNight(WerewolfState state, List<GameEvent> events) {
    final deaths = <String, DeathReason>{};

    final wolfTargetId = state.currentNightWolfTargetId;
    if (wolfTargetId != null) {
      final guarded = state.currentNightGuardTargetId == wolfTargetId;
      final saved = state.currentNightWitchSaved;
      if (guarded && saved) {
        if (state.config.guardAndWitchBothKill) {
          deaths[wolfTargetId] = DeathReason.wolfKill;
        }
      } else if (!guarded && !saved) {
        deaths[wolfTargetId] = DeathReason.wolfKill;
      }
    }

    final poisonTargetId = state.currentNightWitchPoisonTargetId;
    if (poisonTargetId != null) {
      deaths[poisonTargetId] = DeathReason.witchPoison;
    }

    var next = state.copyWith(
      lastNightGuardTargetId: state.currentNightGuardTargetId,
      clearLastNightGuardTarget: state.currentNightGuardTargetId == null,
      isDecoyNightStep: false,
      pendingNightDeaths: deaths,
    );

    if (next.dayNumber == 1 && next.config.enableSheriff) {
      next = next.copyWith(
        phase: WerewolfPhase.sheriffSignup,
        sheriffSignupDecidedIds: {},
        sheriffCandidates: {},
        sheriffVotes: {},
        sheriffPkRound: 0,
      );
      return _emitEvent(
        next,
        events,
        type: 'phase_change',
        message: '天亮了！请先进行警长竞选，想要竞选警长的玩家请点击「上警」。',
        narrationText: '天亮请睁眼！本局为警长局，先进行警长竞选，想上警的玩家请操作。',
      );
    }

    return _announceDawn(next, deaths, events);
  }

  WerewolfState _announceDawn(
    WerewolfState state,
    Map<String, DeathReason> deaths,
    List<GameEvent> events,
  ) {
    String? pendingBadgeFrom;
    String? pendingHunter;

    final updatedPlayers = state.players.map((p) {
      final reason = deaths[p.playerId];
      if (reason == null) return p;
      if (state.sheriffId == p.playerId) {
        pendingBadgeFrom = p.playerId;
      }
      if (p.role == WerewolfRole.hunter && reason != DeathReason.witchPoison) {
        pendingHunter = p.playerId;
      }
      return p.copyWith(
        isAlive: false,
        deathReason: reason,
        deathDay: state.dayNumber,
      );
    }).toList();

    final deadIds = deaths.keys.toList()
      ..sort((a, b) =>
          (state.playerById(a)?.seatNumber ?? 0)
              .compareTo(state.playerById(b)?.seatNumber ?? 0));

    final announcement = deadIds.isEmpty
        ? '昨夜是平安夜，没有人出局！'
        : '昨夜出局的玩家是：${deadIds.map((id) {
            final p = state.playerById(id)!;
            return '${p.seatNumber}号 ${p.name}';
          }).join("、")}。';

    var next = state.copyWith(
      players: updatedPlayers,
      phase: WerewolfPhase.dayAnnounce,
      pendingNightDeaths: {},
      lastAnnouncedDeathIds: deadIds,
      lastAnnouncementText: announcement,
      pendingBadgeTransferFromId: pendingBadgeFrom,
      clearPendingBadgeTransfer: pendingBadgeFrom == null,
      pendingHunterId: pendingHunter,
      clearPendingHunter: pendingHunter == null,
      afterSpecialPhase: WerewolfPhase.dayDiscuss,
      logs: [
        ...state.logs,
        GameLogEntry(
          day: state.dayNumber,
          phase: '第${state.dayNumber}天·天亮',
          summary: announcement,
          isPublic: true,
        ),
      ],
    );

    return _emitEvent(
      next,
      events,
      type: 'dawn_announce',
      message: announcement,
      narrationText: deadIds.isEmpty
          ? '天亮请睁眼，昨夜是平安夜。'
          : '天亮请睁眼，昨夜${deadIds.map((id) => '${state.playerById(id)!.seatNumber}号').join('、')}玩家出局。',
    );
  }

  WerewolfState _continueAfterSpecialPhases(
    WerewolfState state,
    List<GameEvent> events,
  ) {
    // 1. Dying Sheriff transfers or destroys badge (if anyone is still alive)
    if (state.pendingBadgeTransferFromId != null && state.alivePlayers.isNotEmpty) {
      final from = state.playerById(state.pendingBadgeTransferFromId!)!;
      return _emitEvent(
        state.copyWith(phase: WerewolfPhase.sheriffBadgeTransfer),
        events,
        type: 'phase_change',
        message: '警长（${from.seatNumber}号）出局，请选择移交警徽或撕毁警徽。',
        narrationText: '警长出局，请选择移交警徽或撕毁警徽。',
      );
    }

    // 2. Dying Hunter shoots (if not poisoned & alive targets exist)
    if (state.pendingHunterId != null && state.alivePlayers.isNotEmpty) {
      final hunter = state.playerById(state.pendingHunterId!)!;
      return _emitEvent(
        state.copyWith(phase: WerewolfPhase.hunterShoot),
        events,
        type: 'phase_change',
        message: '猎人（${hunter.seatNumber}号）翻牌发动技能，请选择开枪带走一名玩家或不开枪。',
        narrationText: '猎人发动技能，请选择开枪目标。',
      );
    }

    // 3. Check win condition
    final winResult = checkWinCondition(state);
    if (winResult != null) {
      final (camp, reason) = winResult;
      final campLabel = camp == 'good' ? '好人阵营获胜！' : '狼人阵营获胜！';
      var next = state.copyWith(
        phase: WerewolfPhase.gameOver,
        winnerCamp: camp,
        winReason: reason,
        logs: [
          ...state.logs,
          GameLogEntry(
            day: state.dayNumber,
            phase: '终局',
            summary: '$campLabel $reason',
            isPublic: true,
          ),
        ],
      );
      return _emitEvent(
        next,
        events,
        type: 'game_over',
        message: '$campLabel $reason',
        narrationText: '游戏结束，$campLabel',
      );
    }

    // 4. Advance to Day Discussion or Next Night
    if (state.afterSpecialPhase == WerewolfPhase.dayDiscuss) {
      return _emitEvent(
        state.copyWith(
          phase: WerewolfPhase.dayDiscuss,
          clearAfterSpecialPhase: true,
        ),
        events,
        type: 'phase_change',
        message: '进入白天自由发言阶段，请大家线下依次发言，结束后由房主开启投票。',
        narrationText: '请存活玩家开始自由发言。',
      );
    }

    return _enterNight(state, events);
  }

  WerewolfState _enterDayVote(WerewolfState state, List<GameEvent> events) {
    return _emitEvent(
      state.copyWith(
        phase: WerewolfPhase.dayVote,
        dayVotes: {},
        votePkCandidates: {},
        votePkRound: 0,
      ),
      events,
      type: 'phase_change',
      message: '发言结束，请所有存活玩家在手机上进行放逐投票！',
      narrationText: '发言结束，请各位玩家进行放逐投票。',
      payload: const {'scriptKey': 'day_vote'},
    );
  }

  /// Returns (winnerCamp, winReason) or null if game continues.
  (String, String)? checkWinCondition(WerewolfState state) {
    final aliveWolves = state.alivePlayers.where((p) => p.role.isWolf).length;
    final aliveVillagers =
        state.alivePlayers.where((p) => p.role.isVillager).length;
    final aliveGods = state.alivePlayers.where((p) => p.role.isGod).length;

    if (aliveWolves == 0) {
      return ('good', '所有狼人已被放逐或淘汰！');
    }

    if (state.config.winMode == WerewolfWinMode.slaughterAll) {
      if (aliveVillagers == 0 && aliveGods == 0) {
        return ('wolf', '所有好人阵营玩家已全部出局！');
      }
      return null;
    }

    // Slaughter side (屠边): all gods dead OR all villagers dead.
    final boardHasGods = state.players.any((p) => p.role.isGod);
    final boardHasVillagers = state.players.any((p) => p.role.isVillager);

    if (boardHasGods && aliveGods == 0) {
      return ('wolf', '所有神职已全部出局（屠神达成）！');
    }
    if (boardHasVillagers && aliveVillagers == 0) {
      return ('wolf', '所有平民已全部出局（屠民达成）！');
    }
    return null;
  }

  /// Privacy-filtered state projection for a specific player.
  Map<String, dynamic> projectStateForPlayer(
    WerewolfState state,
    String playerId,
  ) {
    final viewer = state.playerById(playerId);
    final isGameOver = state.phase == WerewolfPhase.gameOver;
    final viewerIsWolf = viewer?.role.isWolf ?? false;
    final viewerIsSeer = viewer?.role == WerewolfRole.seer;
    final viewerIsWitch = viewer?.role == WerewolfRole.witch;
    final viewerIsGuard = viewer?.role == WerewolfRole.guard;

    final teammateWolfIds = (viewerIsWolf || isGameOver)
        ? state.players
            .where((p) => p.role.isWolf)
            .map((p) => p.playerId)
            .toList()
        : <String>[];

    Map<String, dynamic>? witchInfo;
    if (viewerIsWitch &&
        (viewer?.isAlive ?? false) &&
        state.phase == WerewolfPhase.nightWitch) {
      final wolfTargetId = state.witchAntidoteUsed ? null : state.currentNightWolfTargetId;
      final canSaveSelf =
          state.dayNumber == 1 && state.config.witchSelfSaveFirstNight;
      final canSaveTarget = wolfTargetId != null &&
          !state.witchAntidoteUsed &&
          (wolfTargetId != playerId || canSaveSelf);
      witchInfo = {
        'antidoteUsed': state.witchAntidoteUsed,
        'poisonUsed': state.witchPoisonUsed,
        'wolfTargetId': wolfTargetId,
        'canSaveTarget': canSaveTarget,
      };
    }

    final projectedPlayers = state.players.map((p) {
      final revealRole =
          isGameOver || p.playerId == playerId || p.idiotRevealed;
      return {
        'playerId': p.playerId,
        'name': p.name,
        'seatNumber': p.seatNumber,
        'avatarIndex': p.avatarIndex,
        'isAlive': p.isAlive,
        'idiotRevealed': p.idiotRevealed,
        'canVote': p.canVote,
        'isSheriff': state.sheriffId == p.playerId,
        'confirmedRole': state.confirmedRolePlayerIds.contains(p.playerId),
        if (p.deathReason != null)
          'deathReason': isGameOver
              ? p.deathReason!.detailedName
              : p.deathReason!.displayName,
        if (p.deathDay != null) 'deathDay': p.deathDay,
        if (revealRole) 'role': p.role.name,
        if (revealRole) 'roleName': p.role.displayName,
      };
    }).toList();

    final visibleLogs = isGameOver
        ? state.logs.map((l) => l.toJson()).toList()
        : state.logs.where((l) => l.isPublic).map((l) => l.toJson()).toList();

    return {
      'phase': state.phase.name,
      'phaseName': state.phase.displayName,
      'dayNumber': state.dayNumber,
      'isNight': state.phase.isNight,
      'isDecoyNightStep': state.isDecoyNightStep,
      'config': state.config.toJson(),
      if (viewer != null)
        'me': {
          'playerId': viewer.playerId,
          'seatNumber': viewer.seatNumber,
          'avatarIndex': viewer.avatarIndex,
          'role': viewer.role.name,
          'roleName': viewer.role.displayName,
          'campName': viewer.role.campName,
          'roleDescription': viewer.role.description,
          'isAlive': viewer.isAlive,
          'canVote': viewer.canVote,
          'confirmedRole': state.confirmedRolePlayerIds.contains(viewer.playerId),
        },
      'players': projectedPlayers,
      'teammateWolfIds': teammateWolfIds,
      if (viewerIsWolf && state.phase == WerewolfPhase.nightWolf)
        'wolfSelections': state.wolfSelections,
      if (viewerIsWolf && state.phase == WerewolfPhase.nightWolf)
        'wolfConfirmedIds': state.wolfConfirmedIds.toList(),
      if (witchInfo != null) 'witchInfo': witchInfo,
      if (viewerIsGuard && state.phase == WerewolfPhase.nightGuard)
        'guardLastTargetId': state.lastNightGuardTargetId,
      if (viewerIsSeer || isGameOver)
        'seerHistory': state.seerHistory.map((r) => r.toJson()).toList(),
      if (viewerIsSeer && state.phase == WerewolfPhase.nightSeer)
        'currentNightSeerChecked': state.currentNightSeerChecked,
      'sheriffId': state.sheriffId,
      'sheriffBadgeDestroyed': state.sheriffBadgeDestroyed,
      'sheriffCandidates': state.sheriffCandidates.toList(),
      'sheriffSignupDecidedIds': state.sheriffSignupDecidedIds.toList(),
      'sheriffVotedIds': state.sheriffVotes.keys.toList(),
      'sheriffPkRound': state.sheriffPkRound,
      'pendingBadgeTransferFromId': state.pendingBadgeTransferFromId,
      'pendingHunterId': state.pendingHunterId,
      'lastAnnouncedDeathIds': state.lastAnnouncedDeathIds,
      'lastAnnouncementText': state.lastAnnouncementText,
      'dayVotedIds': state.dayVotes.keys.toList(),
      'votePkCandidates': state.votePkCandidates.toList(),
      'votePkRound': state.votePkRound,
      'lastVoteTally': state.lastVoteTally,
      'lastVoteSummary': state.lastVoteSummary,
      'recordVoteHistory': state.config.recordVoteHistory,
      'voteHistory': state.config.recordVoteHistory
          ? state.voteHistory.map((r) => r.toJson()).toList()
          : const [],
      'winnerCamp': state.winnerCamp,
      'winReason': state.winReason,
      'logs': visibleLogs,
    };
  }

  WerewolfState _appendVoteHistory(
    WerewolfState state, {
    required String roundLabel,
    required Map<String, String?> ballots,
    required String summary,
    bool isSheriffVote = false,
  }) {
    if (!state.config.recordVoteHistory) return state;
    final record = VoteRoundRecord(
      dayNumber: state.dayNumber,
      roundLabel: roundLabel,
      ballots: Map<String, String?>.from(ballots),
      summary: summary,
      isSheriffVote: isSheriffVote,
      sheriffId: isSheriffVote ? null : state.sheriffId,
    );
    return state.copyWith(voteHistory: [...state.voteHistory, record]);
  }

  WerewolfState _emitEvent(
    WerewolfState state,
    List<GameEvent> events, {
    required String type,
    required String message,
    String? narrationText,
    List<String>? targetPlayerIds,
    Map<String, dynamic> payload = const {},
  }) {
    final nextSeq = state.eventSeq + 1;
    events.add(
      GameEvent(
        id: 'ww-$nextSeq',
        type: type,
        message: message,
        narrationText: narrationText,
        targetPlayerIds: targetPlayerIds,
        payload: payload,
      ),
    );
    return state.copyWith(eventSeq: nextSeq);
  }

  void _requirePhase(WerewolfState state, WerewolfPhase expected) {
    if (state.phase != expected) {
      throw GameRuleException(
        '当前处于「${state.phase.displayName}」，无法执行此操作。',
      );
    }
  }

  WerewolfPlayerState _requirePlayer(WerewolfState state, String playerId) {
    final player = state.playerById(playerId);
    if (player == null) {
      throw const GameRuleException('未找到该玩家信息。');
    }
    return player;
  }

  WerewolfPlayerState _requireAlivePlayer(WerewolfState state, String playerId) {
    final player = _requirePlayer(state, playerId);
    if (!player.isAlive) {
      throw const GameRuleException('已出局玩家无法执行此操作。');
    }
    return player;
  }

  String _formatVotes(int halfVotes) {
    if (halfVotes.isEven) return '${halfVotes ~/ 2}';
    return '${halfVotes / 2}';
  }
}
