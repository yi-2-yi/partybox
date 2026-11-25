import 'dart:math';

import '../../engine/game_plugin.dart';
import '../../models/room_models.dart';
import 'one_night_models.dart';

/// Official One Night Ultimate Werewolf engine (3-10 players + 3 center cards).
class OneNightEngine {
  OneNightEngine({Random? random}) : _random = random ?? Random();

  final Random _random;

  static const List<String> centerLabels = ['底牌 A', '底牌 B', '底牌 C'];

  String? validateStart(List<PlayerInfo> players, OneNightConfig config) {
    if (players.length < 3 || players.length > 10) {
      return '一夜终极狼人支持 3 至 10 名玩家，当前有 ${players.length} 人。';
    }
    if (config.roles.length != players.length + 3) {
      return '一夜狼需要 ${players.length + 3} 张角色牌（玩家数 + 3 张底牌），当前配置了 ${config.roles.length} 张。';
    }
    return null;
  }

  GameTransition<OneNightState> initGame(
    List<PlayerInfo> players,
    OneNightConfig config,
  ) {
    final err = validateStart(players, config);
    if (err != null) throw GameRuleException(err);

    final deck = [...config.roles]..shuffle(_random);
    final sortedPlayers = [...players]
      ..sort((a, b) => a.seatNumber.compareTo(b.seatNumber));

    final onPlayers = <OneNightPlayerState>[];
    for (var i = 0; i < sortedPlayers.length; i++) {
      final p = sortedPlayers[i];
      onPlayers.add(
        OneNightPlayerState(
          playerId: p.id,
          name: p.name,
          seatNumber: p.seatNumber,
          initialRole: deck[i],
          currentRole: deck[i],
        ),
      );
    }

    final centerCards = deck.sublist(sortedPlayers.length, sortedPlayers.length + 3);

    // Build wake-up queue from ALL roles present in the deck (including ones in center, for decoy protection!)
    final wakeSet = config.roles.where((r) => r.wakeOrder != null).toSet().toList()
      ..sort((a, b) => a.wakeOrder!.compareTo(b.wakeOrder!));

    var state = OneNightState(
      config: config,
      players: onPlayers,
      centerCards: centerCards,
      phase: OneNightPhase.roleReveal,
      wakeQueue: wakeSet,
    );

    final events = <GameEvent>[];
    state = _emitEvent(
      state,
      events,
      type: 'phase_change',
      message: '身份牌已发放（含 3 张中间底牌），请长按查看自己的初始身份并确认。',
      narrationText: '一夜终极狼人开始，请各位玩家秘密查看自己的初始身份牌。',
    );
    return GameTransition(state: state, events: events);
  }

  GameTransition<OneNightState> handleAction(
    OneNightState state,
    String playerId,
    String actionType,
    Map<String, dynamic> payload, {
    required String hostId,
  }) {
    if (state.phase == OneNightPhase.gameOver) {
      throw const GameRuleException('本局已经结束。');
    }

    final events = <GameEvent>[];
    if (actionType == OneNightActionType.hostAdvance) {
      if (playerId != hostId) {
        throw const GameRuleException('只有房主可以手动推进阶段。');
      }
      final next = _hostAdvance(state, events);
      return GameTransition(
        state: next,
        events: events,
        isFinished: next.phase == OneNightPhase.gameOver,
      );
    }

    final next = switch (actionType) {
      OneNightActionType.confirmRole => _handleConfirmRole(state, playerId, events),
      OneNightActionType.nightAct =>
        _handleNightAct(state, playerId, payload, events),
      OneNightActionType.startVote => _handleStartVote(state, playerId, hostId, events),
      OneNightActionType.castVote =>
        _handleCastVote(state, playerId, payload['targetId'] as String? ?? '', events),
      _ => throw GameRuleException('未知的一夜狼操作：$actionType'),
    };

    return GameTransition(
      state: next,
      events: events,
      isFinished: next.phase == OneNightPhase.gameOver,
    );
  }

  OneNightState _handleConfirmRole(
    OneNightState state,
    String playerId,
    List<GameEvent> events,
  ) {
    if (state.phase != OneNightPhase.roleReveal) {
      throw const GameRuleException('当前不在看牌阶段。');
    }
    _requirePlayer(state, playerId);

    final confirmed = {...state.confirmedRoleIds, playerId};
    var next = state.copyWith(confirmedRoleIds: confirmed);
    if (confirmed.length >= state.players.length) {
      next = _enterNightStep(next, 0, events);
    }
    return next;
  }

  OneNightState _enterNightStep(
    OneNightState state,
    int index,
    List<GameEvent> events,
  ) {
    if (index >= state.wakeQueue.length) {
      return _enterDayDiscuss(state, events);
    }

    final role = state.wakeQueue[index];
    final holders = state.initialRoleHolders(role);
    var next = state.copyWith(
      phase: OneNightPhase.nightStep,
      wakeIndex: index,
      actedInCurrentStepIds: {},
      isDecoyStep: holders.isEmpty,
    );

    // Pre-populate automatic sight info for Werewolf/Minion/Mason/Insomniac when they wake up
    if (holders.isNotEmpty) {
      next = _applyAutomaticWakeVision(next, role, holders);
    }

    return _emitEvent(
      next,
      events,
      type: 'night_step',
      message: '天黑请闭眼 · ${role.displayName}请睁眼行动。',
      narrationText: role.wakeNarration,
    );
  }

  OneNightState _applyAutomaticWakeVision(
    OneNightState state,
    OneNightRole role,
    List<OneNightPlayerState> holders,
  ) {
    var players = List<OneNightPlayerState>.from(state.players);
    final logs = List<String>.from(state.nightReplayLogs);

    if (role == OneNightRole.werewolf) {
      if (holders.length > 1) {
        final wolfNames =
            holders.map((w) => '${w.seatNumber}号 ${w.name}').join('、');
        for (final w in holders) {
          final others = holders
              .where((o) => o.playerId != w.playerId)
              .map((o) => '${o.seatNumber}号 ${o.name}')
              .join('、');
          players = _appendNote(players, w.playerId, '你的狼队友是：$others');
        }
        logs.add('【狼人】$wolfNames 互相确认了狼队友身份。');
      } else {
        final lone = holders.first;
        players = _appendNote(
          players,
          lone.playerId,
          '你是场上唯一狼人（独狼），你可以偷看 1 张中间底牌！',
        );
      }
    } else if (role == OneNightRole.minion) {
      final wolves = state.initialRoleHolders(OneNightRole.werewolf);
      final note = wolves.isEmpty
          ? '场上没有狼人（所有狼牌都在中间底牌中）！'
          : '场上的狼人是：${wolves.map((w) => '${w.seatNumber}号 ${w.name}').join('、')}';
      for (final m in holders) {
        players = _appendNote(players, m.playerId, note);
        logs.add('【爪牙】${m.seatNumber}号 睁眼得知：$note');
      }
    } else if (role == OneNightRole.mason) {
      for (final m in holders) {
        final others = holders
            .where((o) => o.playerId != m.playerId)
            .map((o) => '${o.seatNumber}号 ${o.name}')
            .toList();
        final note = others.isEmpty
            ? '另一张守夜人牌在中间底牌中。'
            : '你的守夜人同伴是：${others.join('、')}';
        players = _appendNote(players, m.playerId, note);
      }
      logs.add(
        '【守夜人】${holders.map((m) => '${m.seatNumber}号').join('、')} 醒来确认了同伴。',
      );
    } else if (role == OneNightRole.insomniac) {
      for (final ins in holders) {
        final fresh = players.firstWhere((p) => p.playerId == ins.playerId);
        final note = fresh.currentRole == OneNightRole.insomniac
            ? '醒来查看自己的牌：你依然是【失眠者】，没有被换牌！'
            : '醒来查看自己的牌：你的身份已经被换成了【${fresh.currentRole.displayName}】！';
        players = _appendNote(players, ins.playerId, note);
        logs.add('【失眠者】${ins.seatNumber}号 查看自己当前牌为【${fresh.currentRole.displayName}】。');
      }
    }

    return state.copyWith(players: players, nightReplayLogs: logs);
  }

  OneNightState _handleNightAct(
    OneNightState state,
    String playerId,
    Map<String, dynamic> payload,
    List<GameEvent> events,
  ) {
    if (state.phase != OneNightPhase.nightStep) {
      throw const GameRuleException('当前不在夜晚行动阶段。');
    }
    final activeRole = state.activeWakeRole!;
    final actor = _requirePlayer(state, playerId);
    if (actor.initialRole != activeRole) {
      throw const GameRuleException('当前不是你的唤醒阶段。');
    }
    if (state.actedInCurrentStepIds.contains(playerId)) {
      throw const GameRuleException('你已完成本阶段操作。');
    }

    var players = List<OneNightPlayerState>.from(state.players);
    var center = List<OneNightRole>.from(state.centerCards);
    final logs = List<String>.from(state.nightReplayLogs);

    switch (activeRole) {
      case OneNightRole.werewolf:
        final wolves = state.initialRoleHolders(OneNightRole.werewolf);
        if (wolves.length == 1 && payload['centerIndex'] != null) {
          final cIdx = (payload['centerIndex'] as num).toInt();
          _validateCenterIndex(cIdx);
          final seen = center[cIdx];
          players = _appendNote(
            players,
            playerId,
            '独狼查看 ${centerLabels[cIdx]}：是【${seen.displayName}】',
          );
          logs.add(
            '【独狼】${actor.seatNumber}号 偷看了 ${centerLabels[cIdx]}（${seen.displayName}）。',
          );
        }

      case OneNightRole.minion:
      case OneNightRole.mason:
      case OneNightRole.insomniac:
        // Vision was already granted on wake; submitting acknowledges done.
        break;

      case OneNightRole.seer:
        final mode = payload['mode'] as String? ?? 'skip';
        if (mode == 'player') {
          final targetId = payload['targetId'] as String?;
          if (targetId == null || targetId == playerId) {
            throw const GameRuleException('请选择 1 名其他玩家进行查验。');
          }
          final target = _requirePlayer(state, targetId);
          players = _appendNote(
            players,
            playerId,
            '查验 ${target.seatNumber}号 ${target.name}：身份是【${target.currentRole.displayName}】',
          );
          logs.add(
            '【预言家】${actor.seatNumber}号 查验了 ${target.seatNumber}号（当时为 ${target.currentRole.displayName}）。',
          );
        } else if (mode == 'center') {
          final indices = ((payload['centerIndices'] as List?) ?? const [])
              .map((e) => (e as num).toInt())
              .toSet()
              .toList()
            ..sort();
          if (indices.length != 2) {
            throw const GameRuleException('查看底牌必须选择 2 张不同的中间底牌。');
          }
          for (final idx in indices) {
            _validateCenterIndex(idx);
          }
          final summary = indices
              .map((i) => '${centerLabels[i]}【${center[i].displayName}】')
              .join('、');
          players = _appendNote(players, playerId, '查看两张底牌：$summary');
          logs.add('【预言家】${actor.seatNumber}号 查看了底牌：$summary。');
        }

      case OneNightRole.robber:
        final targetId = payload['targetId'] as String?;
        if (targetId != null) {
          if (targetId == playerId) {
            throw const GameRuleException('强盗不能和自己换牌。');
          }
          final target = _requirePlayer(state, targetId);
          final myRoleNow = actor.currentRole;
          final theirRoleNow = target.currentRole;

          players = players.map((p) {
            if (p.playerId == playerId) {
              return p.copyWith(currentRole: theirRoleNow);
            }
            if (p.playerId == targetId) {
              return p.copyWith(currentRole: myRoleNow);
            }
            return p;
          }).toList();

          players = _appendNote(
            players,
            playerId,
            '你与 ${target.seatNumber}号 ${target.name} 交换了身份牌，你的新身份是【${theirRoleNow.displayName}】（${theirRoleNow.campName}）！',
          );
          logs.add(
            '【强盗】${actor.seatNumber}号 与 ${target.seatNumber}号 换牌，拿到【${theirRoleNow.displayName}】，把【${myRoleNow.displayName}】给了 ${target.seatNumber}号。',
          );
        } else {
          players = _appendNote(players, playerId, '你选择不发动强盗换牌。');
          logs.add('【强盗】${actor.seatNumber}号 选择不换牌。');
        }

      case OneNightRole.troublemaker:
        final targetIds =
            ((payload['targetIds'] as List?) ?? const []).cast<String>();
        if (targetIds.isNotEmpty) {
          if (targetIds.length != 2 ||
              targetIds[0] == targetIds[1] ||
              targetIds.contains(playerId)) {
            throw const GameRuleException('捣蛋鬼必须选择 2 名不同的其他玩家交换身份牌。');
          }
          final pA = _requirePlayer(state, targetIds[0]);
          final pB = _requirePlayer(state, targetIds[1]);
          final roleA = pA.currentRole;
          final roleB = pB.currentRole;

          players = players.map((p) {
            if (p.playerId == pA.playerId) return p.copyWith(currentRole: roleB);
            if (p.playerId == pB.playerId) return p.copyWith(currentRole: roleA);
            return p;
          }).toList();

          players = _appendNote(
            players,
            playerId,
            '你悄悄交换了 ${pA.seatNumber}号 ${pA.name} 与 ${pB.seatNumber}号 ${pB.name} 的身份牌。',
          );
          logs.add(
            '【捣蛋鬼】${actor.seatNumber}号 盲换了 ${pA.seatNumber}号（原 ${roleA.displayName}）与 ${pB.seatNumber}号（原 ${roleB.displayName}）的牌。',
          );
        } else {
          players = _appendNote(players, playerId, '你选择不发动捣蛋鬼换牌。');
          logs.add('【捣蛋鬼】${actor.seatNumber}号 选择不换牌。');
        }

      case OneNightRole.drunk:
        final cIdx = (payload['centerIndex'] as num?)?.toInt();
        if (cIdx == null) {
          throw const GameRuleException('酒鬼必须选择 1 张中间底牌进行交换。');
        }
        _validateCenterIndex(cIdx);
        final myRoleNow = actor.currentRole;
        final drawn = center[cIdx];
        center[cIdx] = myRoleNow;
        players = players.map((p) {
          if (p.playerId == playerId) return p.copyWith(currentRole: drawn);
          return p;
        }).toList();
        players = _appendNote(
          players,
          playerId,
          '你已将自己的牌与 ${centerLabels[cIdx]} 盲换（不知道新身份是什么）。',
        );
        logs.add(
          '【酒鬼】${actor.seatNumber}号 与 ${centerLabels[cIdx]} 盲换，新身份为【${drawn.displayName}】。',
        );

      default:
        break;
    }

    final acted = {...state.actedInCurrentStepIds, playerId};
    var next = state.copyWith(
      players: players,
      centerCards: center,
      nightReplayLogs: logs,
      actedInCurrentStepIds: acted,
    );

    final holders = next.initialRoleHolders(activeRole);
    if (holders.every((h) => acted.contains(h.playerId))) {
      next = _enterNightStep(next, next.wakeIndex + 1, events);
    }
    return next;
  }

  OneNightState _enterDayDiscuss(OneNightState state, List<GameEvent> events) {
    final next = state.copyWith(
      phase: OneNightPhase.dayDiscuss,
      isDecoyStep: false,
      actedInCurrentStepIds: {},
    );
    return _emitEvent(
      next,
      events,
      type: 'dawn',
      message: '天亮了！所有人睁眼开始推理讨论（切记：你的牌可能已经被悄悄换过了！）。',
      narrationText: '天亮请睁眼！所有夜晚行动已结束，请大家开始自由推理讨论。',
    );
  }

  OneNightState _handleStartVote(
    OneNightState state,
    String playerId,
    String hostId,
    List<GameEvent> events,
  ) {
    if (state.phase != OneNightPhase.dayDiscuss) {
      throw const GameRuleException('当前不在讨论阶段。');
    }
    if (playerId != hostId) {
      throw const GameRuleException('只有房主可以开启投票。');
    }
    return _enterVote(state, events);
  }

  OneNightState _enterVote(OneNightState state, List<GameEvent> events) {
    return _emitEvent(
      state.copyWith(
        phase: OneNightPhase.dayVote,
        votes: {},
      ),
      events,
      type: 'vote_start',
      message: '讨论结束！请所有玩家在手机上同时投票选出你认为的狼人。',
      narrationText: '讨论结束，请所有玩家在倒数三二一后同步投票。',
    );
  }

  OneNightState _handleCastVote(
    OneNightState state,
    String playerId,
    String targetId,
    List<GameEvent> events,
  ) {
    if (state.phase != OneNightPhase.dayVote) {
      throw const GameRuleException('当前不在投票阶段。');
    }
    _requirePlayer(state, playerId);
    if (targetId == playerId) {
      throw const GameRuleException('不能投票给自己。');
    }
    _requirePlayer(state, targetId);

    final updatedVotes = Map<String, String>.from(state.votes)
      ..[playerId] = targetId;
    var next = state.copyWith(votes: updatedVotes);
    if (updatedVotes.length >= state.players.length) {
      next = _resolveGame(next, events);
    }
    return next;
  }

  OneNightState _resolveGame(OneNightState state, List<GameEvent> events) {
    final counts = <String, int>{};
    for (final targetId in state.votes.values) {
      counts[targetId] = (counts[targetId] ?? 0) + 1;
    }

    final eliminated = <String>{};
    if (counts.isNotEmpty) {
      final maxVotes = counts.values.reduce(max);
      // Official ONUW rule: if everyone received at most 1 vote (circle vote), NO ONE dies!
      if (maxVotes >= 2) {
        for (final entry in counts.entries) {
          if (entry.value == maxVotes) {
            eliminated.add(entry.key);
          }
        }
      }
    }

    // Hunter trigger: if any eliminated player has FINAL role Hunter, their vote target ALSO dies!
    final hunterKills = <String>{};
    for (final pid in eliminated) {
      final p = state.playerById(pid);
      if (p != null && p.currentRole == OneNightRole.hunter) {
        final shotTarget = state.votes[pid];
        if (shotTarget != null) {
          hunterKills.add(shotTarget);
        }
      }
    }
    eliminated.addAll(hunterKills);

    final eliminatedList = eliminated.toList()
      ..sort((a, b) => (state.playerById(a)?.seatNumber ?? 0)
          .compareTo(state.playerById(b)?.seatNumber ?? 0));

    // Evaluate winners on FINAL currentRole!
    final wolvesInPlay =
        state.players.where((p) => p.currentRole == OneNightRole.werewolf).toList();
    final minionsInPlay =
        state.players.where((p) => p.currentRole == OneNightRole.minion).toList();

    final deadPlayers =
        eliminatedList.map((id) => state.playerById(id)!).toList();
    final wolfDied = deadPlayers.any((p) => p.currentRole == OneNightRole.werewolf);
    final tannerDied = deadPlayers.any((p) => p.currentRole == OneNightRole.tanner);
    final minionDied = deadPlayers.any((p) => p.currentRole == OneNightRole.minion);

    String winnerTeam;
    String summary;

    if (wolvesInPlay.isNotEmpty) {
      if (wolfDied && tannerDied) {
        winnerTeam = 'good_and_tanner';
        summary = '平票同时淘汰了狼人与皮匠！好人阵营与皮匠共同获胜！';
      } else if (wolfDied) {
        winnerTeam = 'good';
        summary = '成功放逐了狼人！好人阵营获胜！';
      } else if (tannerDied) {
        winnerTeam = 'tanner';
        summary = '皮匠成功让自己被投票出局！皮匠独自获胜（狼人与好人均落败）！';
      } else {
        winnerTeam = 'wolf';
        summary = eliminatedList.isEmpty
            ? '全员平票无人出局，但场上藏有狼人！狼人阵营获胜！'
            : '未能投出真正的狼人！狼人阵营获胜！';
      }
    } else {
      // No Werewolves among players (all werewolf cards are in the 3 Center Cards!)
      if (tannerDied) {
        winnerTeam = 'tanner';
        summary = '场上无狼，但皮匠被投票出局！皮匠获胜！';
      } else if (eliminatedList.isEmpty) {
        winnerTeam = 'good';
        summary = '场上没有狼人（狼牌全在底牌），且全员平票无人出局！好人阵营获胜！';
      } else if (minionsInPlay.isNotEmpty && !minionDied) {
        winnerTeam = 'wolf';
        summary = '场上无狼但爪牙幸存且好人被误投出局！爪牙（狼人阵营）获胜！';
      } else {
        winnerTeam = 'good';
        summary = minionDied
            ? '场上无狼，成功投出爪牙！好人阵营获胜！'
            : '场上无狼但好人误投了自己人！本局无人获胜（建议重来）。';
        if (!minionDied) {
          winnerTeam = 'wolf';
          summary = '场上没有狼人（狼牌全在底牌），好人却误投了自己人！好人阵营落败！';
        }
      }
    }

    final next = state.copyWith(
      phase: OneNightPhase.gameOver,
      eliminatedPlayerIds: eliminatedList,
      winnerTeam: winnerTeam,
      winnerSummary: summary,
      tannerWon: tannerDied,
    );

    return _emitEvent(
      next,
      events,
      type: 'game_over',
      message: summary,
      narrationText: '投票结束，$summary',
    );
  }

  OneNightState _hostAdvance(OneNightState state, List<GameEvent> events) {
    return switch (state.phase) {
      OneNightPhase.roleReveal => _enterNightStep(state, 0, events),
      OneNightPhase.nightStep => _enterNightStep(state, state.wakeIndex + 1, events),
      OneNightPhase.dayDiscuss => _enterVote(state, events),
      OneNightPhase.dayVote => _resolveGame(state, events),
      OneNightPhase.gameOver => state,
    };
  }

  /// Strictly privacy-filtered player projection.
  /// During play, players ONLY see their own initialRole + their own nightNotes!
  Map<String, dynamic> projectStateForPlayer(
    OneNightState state,
    String playerId,
  ) {
    final viewer = state.playerById(playerId);
    final isOver = state.phase == OneNightPhase.gameOver;
    final activeRole = state.activeWakeRole;
    final isMyNightTurn = state.phase == OneNightPhase.nightStep &&
        viewer != null &&
        viewer.initialRole == activeRole &&
        !state.actedInCurrentStepIds.contains(playerId);

    final isLoneWolf = activeRole == OneNightRole.werewolf &&
        state.initialRoleHolders(OneNightRole.werewolf).length == 1;

    return {
      'phase': state.phase.name,
      'phaseName': state.phase.displayName,
      'config': state.config.toJson(),
      'activeWakeRole': activeRole?.name,
      'activeWakeRoleName': activeRole?.displayName,
      'wakeIndex': state.wakeIndex,
      'wakeTotal': state.wakeQueue.length,
      'isDecoyStep': state.isDecoyStep,
      'isMyNightTurn': isMyNightTurn,
      'isLoneWolf': isMyNightTurn && isLoneWolf,
      'votedIds': state.votes.keys.toList(),
      'eliminatedPlayerIds': state.eliminatedPlayerIds,
      'winnerTeam': state.winnerTeam,
      'winnerSummary': state.winnerSummary,
      if (viewer != null)
        'me': {
          'playerId': viewer.playerId,
          'seatNumber': viewer.seatNumber,
          'initialRole': viewer.initialRole.name,
          'initialRoleName': viewer.initialRole.displayName,
          'initialRoleCamp': viewer.initialRole.campName,
          'initialRoleDescription': viewer.initialRole.description,
          'confirmedRole': state.confirmedRoleIds.contains(viewer.playerId),
          'hasVoted': state.votes.containsKey(viewer.playerId),
          'nightNotes': viewer.nightNotes,
          if (isOver) 'finalRole': viewer.currentRole.name,
          if (isOver) 'finalRoleName': viewer.currentRole.displayName,
        },
      'players': state.players
          .map((p) => {
                'playerId': p.playerId,
                'name': p.name,
                'seatNumber': p.seatNumber,
                'confirmedRole': state.confirmedRoleIds.contains(p.playerId),
                'hasVoted': state.votes.containsKey(p.playerId),
                if (isOver) 'votedTargetId': state.votes[p.playerId],
                if (isOver) 'initialRole': p.initialRole.name,
                if (isOver) 'initialRoleName': p.initialRole.displayName,
                if (isOver) 'finalRole': p.currentRole.name,
                if (isOver) 'finalRoleName': p.currentRole.displayName,
                if (isOver) 'wasSwapped': p.initialRole != p.currentRole,
              })
          .toList(),
      if (isOver)
        'centerCards': [
          for (var i = 0; i < state.centerCards.length; i++)
            {
              'label': centerLabels[i],
              'role': state.centerCards[i].name,
              'roleName': state.centerCards[i].displayName,
            },
        ],
      if (isOver) 'nightReplayLogs': state.nightReplayLogs,
    };
  }

  List<OneNightPlayerState> _appendNote(
    List<OneNightPlayerState> players,
    String playerId,
    String note,
  ) {
    return players.map((p) {
      if (p.playerId != playerId) return p;
      return p.copyWith(nightNotes: [...p.nightNotes, note]);
    }).toList();
  }

  OneNightPlayerState _requirePlayer(OneNightState state, String playerId) {
    final p = state.playerById(playerId);
    if (p == null) throw const GameRuleException('未找到该玩家。');
    return p;
  }

  void _validateCenterIndex(int idx) {
    if (idx < 0 || idx >= 3) {
      throw const GameRuleException('底牌索引无效（只能选择底牌 A / B / C）。');
    }
  }

  OneNightState _emitEvent(
    OneNightState state,
    List<GameEvent> events, {
    required String type,
    required String message,
    String? narrationText,
  }) {
    final seq = state.eventSeq + 1;
    events.add(
      GameEvent(
        id: 'on-$seq',
        type: type,
        message: message,
        narrationText: narrationText,
      ),
    );
    return state.copyWith(eventSeq: seq);
  }
}
