import 'dart:async';
import 'dart:math';

import 'package:party_core/party_core.dart';

import 'game_transport.dart';

/// Single-device demo transport with smart AI bots so one user can experience
/// a full 6, 9, or 12-player (with Sheriff election) Werewolf game immediately.
class LocalDemoTransport implements GameTransport {
  LocalDemoTransport({
    required String playerName,
    WerewolfConfig? initialConfig,
    Random? random,
  }) : _random = random ?? Random() {
    final config = initialConfig ?? WerewolfConfig.preset6();
    _controller = RoomController(
      roomId: 'demo_room',
      roomCode: 'DEMO',
      gameType: GameType.werewolf,
      registry: GamePluginRegistry([WerewolfPlugin(random: _random)]),
      random: _random,
    );
    final me = _controller.joinPlayer(name: playerName);
    _humanId = me.playerId;
    _controller.updateConfig(_humanId, config.toJson());
    _syncBotsToConfig(config);

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

  void _syncBotsToConfig(WerewolfConfig config) {
    final desired = config.totalPlayers;
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
      final label = idx < botNames.length ? '${botNames[idx]}(AI)' : 'AI玩家${idx + 2}';
      _controller.joinPlayer(name: label, isBot: true);
    }
  }

  @override
  void send(ClientMessage message) {
    if (_closed) return;
    try {
      List<GameEvent> emitted = const [];
      switch (message.type) {
        case ClientMessageType.updateConfig:
          final cfgMap = Map<String, dynamic>.from(
            message.payload['config'] as Map? ?? {},
          );
          _controller.updateConfig(_humanId, cfgMap);
          _syncBotsToConfig(WerewolfConfig.fromJson(cfgMap));
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
    _botTimer = Timer(const Duration(milliseconds: 850), _runBotDecisions);
  }

  void _runBotDecisions() {
    if (_closed || _controller.status != RoomStatus.playing) return;
    final raw = _controller.rawGameState;
    if (raw is! WerewolfState) return;

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
              .where((w) => _isBot(w.playerId) && !raw.wolfConfirmedIds.contains(w.playerId))
              .toList();
          if (botWolves.isNotEmpty) {
            final nonWolves = raw.alivePlayers.where((p) => !p.role.isWolf).toList();
            final target = nonWolves.isEmpty
                ? null
                : nonWolves[_random.nextInt(nonWolves.length)].playerId;
            for (final bw in botWolves) {
              // Re-check phase in case previous bot confirmation advanced the night
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
                      (raw.dayNumber == 1 && raw.config.witchSelfSaveFirstNight));
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
                    {'targetId': targets[_random.nextInt(targets.length)].playerId},
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
              // About 25% of bots run for sheriff
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
              final choices = candidates.where((c) => c.playerId != p.playerId).toList();
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
