import 'dart:async';
import 'dart:math';

import 'package:party_core/party_core.dart';

import 'game_transport.dart';

/// Single-device demo transport with smart AI bots for BOTH Werewolf (6/9/12p)
/// and Guandan (4p Red vs Blue), so one player can test any game solo immediately.
class LocalDemoTransport implements GameTransport {
  LocalDemoTransport({
    required String playerName,
    int playerAvatarIndex = 0,
    GameType gameType = GameType.werewolf,
    WerewolfConfig? werewolfConfig,
    GuandanConfig? guandanConfig,
    OneNightConfig? oneNightConfig,
    Random? random,
  }) : _random = random ?? Random() {
    _controller = RoomController(
      roomId: 'demo_room',
      roomCode: 'DEMO',
      gameType: gameType,
      registry: GamePluginRegistry([
        WerewolfPlugin(random: _random),
        GuandanPlugin(random: _random),
        OneNightPlugin(random: _random),
      ]),
      random: _random,
    );
    final me = _controller.joinPlayer(
      name: playerName,
      avatarIndex: playerAvatarIndex,
    );
    _humanId = me.playerId;

    if (gameType == GameType.werewolf) {
      final cfg = werewolfConfig ?? WerewolfConfig.preset6();
      _controller.updateConfig(_humanId, cfg.toJson());
      _syncBotsToCount(cfg.totalPlayers);
    } else if (gameType == GameType.guandan) {
      final cfg = guandanConfig ?? const GuandanConfig();
      _controller.updateConfig(_humanId, cfg.toJson());
      _syncBotsToCount(4);
    } else if (gameType == GameType.oneNight) {
      final cfg = oneNightConfig ?? OneNightConfig.preset5();
      _controller.updateConfig(_humanId, cfg.toJson());
      _syncBotsToCount(cfg.requiredPlayers);
    }

    scheduleMicrotask(() {
      _emitSnapshot(includeToken: true);
    });
  }

  final Random _random;
  late final RoomController _controller;
  late final String _humanId;

  final _snapshotsController = StreamController<RoomSnapshot>.broadcast();
  final _eventsController = StreamController<GameEvent>.broadcast();
  final _errorsController = StreamController<String>.broadcast();
  final _statusController = StreamController<TransportStatus>.broadcast();

  Timer? _botTimer;
  bool _closed = false;

  @override
  Stream<RoomSnapshot> get snapshots => _snapshotsController.stream;

  @override
  Stream<GameEvent> get events => _eventsController.stream;

  @override
  Stream<String> get errors => _errorsController.stream;

  @override
  Stream<TransportStatus> get statusStream => _statusController.stream;

  @override
  TransportStatus get status =>
      _closed ? TransportStatus.disconnected : TransportStatus.connected;

  @override
  TransportEndpointInfo get endpointInfo => const TransportEndpointInfo(
        mode: ConnectionMode.localDemo,
        label: '单人 AI 演示模式',
      );

  void _syncBotsToCount(int desired) {
    while (_controller.players.length > desired) {
      final hasBot = _controller.players.any((p) => p.isBot);
      if (!hasBot) break;
      _controller.removeBot(_humanId);
    }
    const botNames = [
      '阿杰',
      '小雨',
      '老陈',
      '思思',
      '大鹏',
      '林林',
      '可乐',
      '子墨',
      '米粒',
      '阿澈',
      '柚子',
      '南风',
      '北辰',
      '小橘',
      '老王',
    ];
    while (_controller.players.length < desired) {
      final idx = _controller.players.length - 1;
      final label =
          idx < botNames.length ? '${botNames[idx]}(AI)' : 'AI玩家${idx + 2}';
      final usedAvatars = _controller.players.map((p) => p.avatarIndex).toSet();
      var avatarIdx = (idx + 1) % 16;
      while (usedAvatars.contains(avatarIdx) && usedAvatars.length < 16) {
        avatarIdx = (avatarIdx + 1) % 16;
      }
      _controller.joinPlayer(
        name: label,
        avatarIndex: avatarIdx,
        isBot: true,
      );
    }
  }

  @override
  void send(ClientMessage message) {
    if (_closed) return;
    try {
      List<GameEvent> emitted = const [];
      switch (message.type) {
        case ClientMessageType.updateProfile:
          _controller.updateProfile(
            _humanId,
            name: message.payload['name'] as String?,
            avatarIndex: (message.payload['avatarIndex'] as num?)?.toInt(),
          );
        case ClientMessageType.updateConfig:
          final cfgMap = Map<String, dynamic>.from(
            message.payload['config'] as Map? ?? {},
          );
          _controller.updateConfig(_humanId, cfgMap);
          if (_controller.gameType == GameType.werewolf) {
            _syncBotsToCount(WerewolfConfig.fromJson(cfgMap).totalPlayers);
          } else if (_controller.gameType == GameType.guandan) {
            _syncBotsToCount(4);
          } else if (_controller.gameType == GameType.oneNight) {
            _syncBotsToCount(OneNightConfig.fromJson(cfgMap).requiredPlayers);
          }
        case ClientMessageType.toggleReady:
          _controller.toggleReady(_humanId);
        case ClientMessageType.startGame:
          emitted = _controller.startGame(_humanId);
        case ClientMessageType.returnToLobby:
          _botTimer?.cancel();
          _controller.returnToLobby(_humanId);
        case ClientMessageType.gameAction:
          final actionType = message.payload['actionType'] as String? ?? '';
          final data = Map<String, dynamic>.from(
            message.payload['data'] as Map? ?? {},
          );
          emitted = _controller.handleGameAction(_humanId, actionType, data);
        default:
          return;
      }
      _emitSnapshot();
      _emitEvents(emitted);
      _scheduleBotStep();
    } on GameRuleException catch (e) {
      if (!_errorsController.isClosed) {
        _errorsController.add(e.message);
      }
    } catch (e) {
      if (!_errorsController.isClosed) {
        _errorsController.add('演示模式执行异常：$e');
      }
    }
  }

  void _scheduleBotStep() {
    _botTimer?.cancel();
    if (_closed || _controller.status != RoomStatus.playing) return;
    final delay = _controller.gameType == GameType.guandan
        ? const Duration(milliseconds: 700)
        : const Duration(milliseconds: 850);
    _botTimer = Timer(delay, _runBotDecisions);
  }

  void _runBotDecisions() {
    if (_closed || _controller.status != RoomStatus.playing) return;
    final raw = _controller.rawGameState;
    if (raw is WerewolfState) {
      _runWerewolfBots(raw);
    } else if (raw is GuandanState) {
      _runGuandanBots(raw);
    } else if (raw is OneNightState) {
      _runOneNightBots(raw);
    }
  }

  void _runOneNightBots(OneNightState state) {
    final events = <GameEvent>[];
    var progressed = false;

    try {
      switch (state.phase) {
        case OneNightPhase.roleReveal:
          for (final p in _controller.players) {
            if ((_controller.rawGameState as OneNightState).phase !=
                OneNightPhase.roleReveal) {
              break;
            }
            if (p.isBot && !state.confirmedRoleIds.contains(p.id)) {
              events.addAll(_controller.handleGameAction(
                p.id,
                OneNightActionType.confirmRole,
                const {},
              ));
              progressed = true;
            }
          }

        case OneNightPhase.nightStep:
          if (state.isDecoyStep) {
            events.addAll(_controller.handleGameAction(
              _humanId,
              OneNightActionType.hostAdvance,
              const {},
            ));
            progressed = true;
          } else {
            final activeRole = state.activeWakeRole!;
            final holders = state.initialRoleHolders(activeRole);
            for (final h in holders) {
              if ((_controller.rawGameState as OneNightState).phase !=
                      OneNightPhase.nightStep ||
                  (_controller.rawGameState as OneNightState).activeWakeRole !=
                      activeRole) {
                break;
              }
              if (_isBot(h.playerId) &&
                  !state.actedInCurrentStepIds.contains(h.playerId)) {
                final payload = _buildOneNightBotAction(state, h, activeRole);
                events.addAll(_controller.handleGameAction(
                  h.playerId,
                  OneNightActionType.nightAct,
                  payload,
                ));
                progressed = true;
              }
            }
          }

        case OneNightPhase.dayVote:
          for (final p in state.players) {
            if ((_controller.rawGameState as OneNightState).phase !=
                OneNightPhase.dayVote) {
              break;
            }
            if (_isBot(p.playerId) && !state.votes.containsKey(p.playerId)) {
              final targets = state.players
                  .where((t) => t.playerId != p.playerId)
                  .toList();
              final pick = targets[_random.nextInt(targets.length)].playerId;
              events.addAll(_controller.handleGameAction(
                p.playerId,
                OneNightActionType.castVote,
                {'targetId': pick},
              ));
              progressed = true;
            }
          }

        case OneNightPhase.dayDiscuss:
        case OneNightPhase.gameOver:
          break;
      }
    } catch (_) {}

    if (progressed) {
      _emitSnapshot();
      _emitEvents(events);
      _scheduleBotStep();
    }
  }

  Map<String, dynamic> _buildOneNightBotAction(
    OneNightState state,
    OneNightPlayerState bot,
    OneNightRole role,
  ) {
    final others = state.players
        .where((p) => p.playerId != bot.playerId)
        .toList();
    return switch (role) {
      OneNightRole.werewolf =>
        state.initialRoleHolders(OneNightRole.werewolf).length == 1
            ? {'centerIndex': _random.nextInt(3)}
            : const {},
      OneNightRole.seer => _random.nextBool()
          ? {'mode': 'player', 'targetId': others[_random.nextInt(others.length)].playerId}
          : const {'mode': 'center', 'centerIndices': [0, 1]},
      OneNightRole.robber => {
          'targetId': others[_random.nextInt(others.length)].playerId,
        },
      OneNightRole.troublemaker => others.length >= 2
          ? {
              'targetIds': [others[0].playerId, others[1].playerId],
            }
          : const {},
      OneNightRole.drunk => {'centerIndex': _random.nextInt(3)},
      _ => const {},
    };
  }

  void _runGuandanBots(GuandanState state) {
    final events = <GameEvent>[];
    var progressed = false;

    try {
      switch (state.phase) {
        case GuandanPhase.tributePay:
          for (final t in state.tributes) {
            if (t.tributedCard == null && _isBot(t.fromPlayerId)) {
              final payer = state.playerById(t.fromPlayerId)!;
              final eligible = payer.hand
                  .where((c) => !c.isWildcard(state.currentLevel))
                  .toList()
                ..sort((a, b) => b
                    .strength(state.currentLevel)
                    .compareTo(a.strength(state.currentLevel)));
              if (eligible.isNotEmpty) {
                events.addAll(_controller.handleGameAction(
                  t.fromPlayerId,
                  GuandanActionType.payTribute,
                  {'cardId': eligible.first.id},
                ));
                progressed = true;
                break;
              }
            }
          }

        case GuandanPhase.tributeReturn:
          for (final t in state.tributes) {
            if (t.returnedCard == null && _isBot(t.toPlayerId)) {
              final returner = state.playerById(t.toPlayerId)!;
              final under10 = returner.hand
                  .where((c) =>
                      !c.isJoker &&
                      !c.isLevelCard(state.currentLevel) &&
                      c.rank <= 10)
                  .toList()
                ..sort((a, b) => a.rank.compareTo(b.rank));
              final pick = under10.isNotEmpty ? under10.first : returner.hand.last;
              events.addAll(_controller.handleGameAction(
                t.toPlayerId,
                GuandanActionType.returnTribute,
                {'cardId': pick.id},
              ));
              progressed = true;
              break;
            }
          }

        case GuandanPhase.playing:
          final current = state.currentTurnPlayer;
          if (!_isBot(current.playerId)) return;

          final isLeading = state.lastPlay == null ||
              state.lastPlayPlayerId == current.playerId;

          if (isLeading) {
            final hints = GuandanEvaluator.findHintPlays(
              current.hand,
              state.currentLevel,
            );
            // Prefer non-bomb multi-card hands first to shed cleanly
            final nonBombs = hints.where((h) => !h.isBomb).toList();
            GuandanPlay chosen;
            if (nonBombs.isNotEmpty) {
              final multi = nonBombs.where((h) => h.length >= 2).toList();
              chosen = multi.isNotEmpty ? multi.first : nonBombs.first;
            } else {
              chosen = hints.first;
            }
            events.addAll(_controller.handleGameAction(
              current.playerId,
              GuandanActionType.playCards,
              {'cardIds': chosen.cards.map((c) => c.id).toList()},
            ));
            progressed = true;
          } else {
            final lastPlayer = state.playerById(state.lastPlayPlayerId!)!;
            final isTeammateLeading = lastPlayer.teamIndex == current.teamIndex;
            final lastPlay = state.lastPlay!;

            // Smart teammate awareness: let partner hold strong tricks
            if (isTeammateLeading &&
                (lastPlay.isBomb ||
                    lastPlay.primaryValue >= 13 ||
                    lastPlayer.hand.length <= 6)) {
              events.addAll(_controller.handleGameAction(
                current.playerId,
                GuandanActionType.passTurn,
                const {},
              ));
              progressed = true;
            } else {
              final hints = GuandanEvaluator.findHintPlays(
                current.hand,
                state.currentLevel,
                beatTarget: lastPlay,
              );
              final nonBombs = hints.where((h) => !h.isBomb).toList();
              GuandanPlay? chosen;
              if (nonBombs.isNotEmpty) {
                chosen = nonBombs.first;
              } else if (hints.isNotEmpty &&
                  !isTeammateLeading &&
                  (lastPlayer.hand.length <= 8 ||
                      current.hand.length <= 7 ||
                      lastPlay.length >= 5)) {
                chosen = hints.first;
              }

              if (chosen != null) {
                events.addAll(_controller.handleGameAction(
                  current.playerId,
                  GuandanActionType.playCards,
                  {'cardIds': chosen.cards.map((c) => c.id).toList()},
                ));
              } else {
                events.addAll(_controller.handleGameAction(
                  current.playerId,
                  GuandanActionType.passTurn,
                  const {},
                ));
              }
              progressed = true;
            }
          }

        case GuandanPhase.roundOver:
        case GuandanPhase.matchOver:
          break;
      }
    } catch (_) {}

    if (progressed) {
      _emitSnapshot();
      _emitEvents(events);
      _scheduleBotStep();
    }
  }

  void _runWerewolfBots(WerewolfState raw) {
    final allEvents = <GameEvent>[];
    var progressed = false;

    try {
      switch (raw.phase) {
        case WerewolfPhase.roleReveal:
          for (final p in _controller.players) {
            if (p.isBot && !raw.confirmedRolePlayerIds.contains(p.id)) {
              allEvents.addAll(_controller.handleGameAction(
                p.id,
                WerewolfActionType.confirmRole,
                const {},
              ));
              progressed = true;
            }
          }

        case WerewolfPhase.nightGuard:
          if (raw.isDecoyNightStep) {
            allEvents.addAll(_controller.handleGameAction(
              _humanId,
              WerewolfActionType.hostAdvance,
              const {},
            ));
            progressed = true;
          } else {
            final guard = raw.aliveWithRole(WerewolfRole.guard).firstOrNull;
            if (guard != null && _isBot(guard.playerId)) {
              final candidates = raw.alivePlayers
                  .where((p) => p.playerId != raw.lastNightGuardTargetId)
                  .toList();
              final pick = candidates.isEmpty
                  ? null
                  : candidates[_random.nextInt(candidates.length)].playerId;
              allEvents.addAll(_controller.handleGameAction(
                guard.playerId,
                WerewolfActionType.guardProtect,
                {'targetId': pick},
              ));
              progressed = true;
            }
          }

        case WerewolfPhase.nightWolf:
          final aliveWolves = raw.aliveWithRole(WerewolfRole.werewolf);
          final botWolves = aliveWolves
              .where((w) =>
                  _isBot(w.playerId) &&
                  !raw.wolfConfirmedIds.contains(w.playerId))
              .toList();
          if (botWolves.isNotEmpty) {
            final nonWolves =
                raw.alivePlayers.where((p) => !p.role.isWolf).toList();
            final target = nonWolves.isEmpty
                ? null
                : nonWolves[_random.nextInt(nonWolves.length)].playerId;
            for (final bw in botWolves) {
              if ((_controller.rawGameState as WerewolfState).phase !=
                  WerewolfPhase.nightWolf) {
                break;
              }
              allEvents.addAll(_controller.handleGameAction(
                bw.playerId,
                WerewolfActionType.wolfConfirm,
                {'targetId': target},
              ));
              progressed = true;
            }
          }

        case WerewolfPhase.nightWitch:
          if (raw.isDecoyNightStep) {
            allEvents.addAll(_controller.handleGameAction(
              _humanId,
              WerewolfActionType.hostAdvance,
              const {},
            ));
            progressed = true;
          } else {
            final witch = raw.aliveWithRole(WerewolfRole.witch).firstOrNull;
            if (witch != null && _isBot(witch.playerId)) {
              final canSave = !raw.witchAntidoteUsed &&
                  raw.currentNightWolfTargetId != null &&
                  (raw.currentNightWolfTargetId != witch.playerId ||
                      (raw.dayNumber == 1 &&
                          raw.config.witchSelfSaveFirstNight));
              if (canSave && raw.dayNumber == 1) {
                allEvents.addAll(_controller.handleGameAction(
                  witch.playerId,
                  WerewolfActionType.witchAct,
                  const {'action': 'save'},
                ));
              } else {
                allEvents.addAll(_controller.handleGameAction(
                  witch.playerId,
                  WerewolfActionType.witchAct,
                  const {'action': 'skip'},
                ));
              }
              progressed = true;
            }
          }

        case WerewolfPhase.nightSeer:
          if (raw.isDecoyNightStep) {
            allEvents.addAll(_controller.handleGameAction(
              _humanId,
              WerewolfActionType.hostAdvance,
              const {},
            ));
            progressed = true;
          } else {
            final seer = raw.aliveWithRole(WerewolfRole.seer).firstOrNull;
            if (seer != null && _isBot(seer.playerId)) {
              if (!raw.currentNightSeerChecked) {
                final targets = raw.alivePlayers
                    .where((p) => p.playerId != seer.playerId)
                    .toList();
                if (targets.isNotEmpty) {
                  allEvents.addAll(_controller.handleGameAction(
                    seer.playerId,
                    WerewolfActionType.seerCheck,
                    {
                      'targetId':
                          targets[_random.nextInt(targets.length)].playerId
                    },
                  ));
                }
              }
              allEvents.addAll(_controller.handleGameAction(
                seer.playerId,
                WerewolfActionType.seerDone,
                const {},
              ));
              progressed = true;
            }
          }

        case WerewolfPhase.sheriffSignup:
          for (final p in _controller.players) {
            if ((_controller.rawGameState as WerewolfState).phase !=
                WerewolfPhase.sheriffSignup) {
              break;
            }
            if (p.isBot && !raw.sheriffSignupDecidedIds.contains(p.id)) {
              final join = _random.nextInt(4) == 0;
              allEvents.addAll(_controller.handleGameAction(
                p.id,
                WerewolfActionType.sheriffSignup,
                {'join': join},
              ));
              progressed = true;
            }
          }

        case WerewolfPhase.sheriffVote:
          final candidates = raw.sheriffCandidates.toList();
          for (final p in _controller.players) {
            if ((_controller.rawGameState as WerewolfState).phase !=
                WerewolfPhase.sheriffVote) {
              break;
            }
            if (p.isBot &&
                !raw.sheriffCandidates.contains(p.id) &&
                !raw.sheriffVotes.containsKey(p.id)) {
              final pick = candidates.isEmpty
                  ? null
                  : candidates[_random.nextInt(candidates.length)];
              allEvents.addAll(_controller.handleGameAction(
                p.id,
                WerewolfActionType.sheriffVote,
                {'targetId': pick},
              ));
              progressed = true;
            }
          }

        case WerewolfPhase.sheriffBadgeTransfer:
          final fromId = raw.pendingBadgeTransferFromId;
          if (fromId != null && _isBot(fromId)) {
            final alive = raw.alivePlayers;
            final pick = alive.isEmpty
                ? null
                : alive[_random.nextInt(alive.length)].playerId;
            allEvents.addAll(_controller.handleGameAction(
              fromId,
              WerewolfActionType.sheriffTransfer,
              {'targetId': pick},
            ));
            progressed = true;
          }

        case WerewolfPhase.hunterShoot:
          final hunterId = raw.pendingHunterId;
          if (hunterId != null && _isBot(hunterId)) {
            final alive = raw.alivePlayers;
            final pick = alive.isEmpty
                ? null
                : alive[_random.nextInt(alive.length)].playerId;
            allEvents.addAll(_controller.handleGameAction(
              hunterId,
              WerewolfActionType.hunterShoot,
              {'targetId': pick},
            ));
            progressed = true;
          }

        case WerewolfPhase.dayVote:
          final candidates = raw.votePkRound > 0
              ? raw.alivePlayers
                  .where((p) => raw.votePkCandidates.contains(p.playerId))
                  .toList()
              : raw.alivePlayers;
          for (final p in raw.alivePlayers) {
            if ((_controller.rawGameState as WerewolfState).phase !=
                WerewolfPhase.dayVote) {
              break;
            }
            if (_isBot(p.playerId) &&
                p.canVote &&
                !raw.dayVotes.containsKey(p.playerId)) {
              final choices =
                  candidates.where((c) => c.playerId != p.playerId).toList();
              final pick = choices.isEmpty
                  ? null
                  : choices[_random.nextInt(choices.length)].playerId;
              allEvents.addAll(_controller.handleGameAction(
                p.playerId,
                WerewolfActionType.dayVote,
                {'targetId': pick},
              ));
              progressed = true;
            }
          }

        case WerewolfPhase.dayAnnounce:
        case WerewolfPhase.dayDiscuss:
        case WerewolfPhase.voteResult:
        case WerewolfPhase.gameOver:
          break;
      }
    } catch (_) {}

    if (progressed) {
      _emitSnapshot();
      _emitEvents(allEvents);
      _scheduleBotStep();
    }
  }

  bool _isBot(String playerId) {
    for (final p in _controller.players) {
      if (p.id == playerId) return p.isBot;
    }
    return false;
  }

  void _emitSnapshot({bool includeToken = false}) {
    if (!_snapshotsController.isClosed) {
      _snapshotsController.add(
        _controller.snapshotForPlayer(_humanId, includeToken: includeToken),
      );
    }
  }

  void _emitEvents(List<GameEvent> events) {
    for (final ev in events) {
      final targets = ev.targetPlayerIds;
      if (targets == null || targets.contains(_humanId)) {
        if (!_eventsController.isClosed) {
          _eventsController.add(ev);
        }
      }
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    _botTimer?.cancel();
    await _snapshotsController.close();
    await _eventsController.close();
    await _errorsController.close();
    await _statusController.close();
  }
}
