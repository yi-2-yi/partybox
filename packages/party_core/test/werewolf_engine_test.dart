import 'dart:math';

import 'package:party_core/party_core.dart';
import 'package:test/test.dart';

List<PlayerInfo> _makePlayers(int count) {
  return List.generate(
    count,
    (i) => PlayerInfo(
      id: 'p${i + 1}',
      name: '玩家${i + 1}',
      seatNumber: i + 1,
      isHost: i == 0,
      isReady: true,
    ),
  );
}

WerewolfPlayerState _findRole(WerewolfState state, WerewolfRole role) =>
    state.players.firstWhere((p) => p.role == role);

List<WerewolfPlayerState> _findAllRole(WerewolfState state, WerewolfRole role) =>
    state.players.where((p) => p.role == role).toList();

WerewolfState _confirmAllRoles(WerewolfEngine engine, WerewolfState state) {
  var s = state;
  for (final p in s.players) {
    s = engine
        .handleAction(
          s,
          p.playerId,
          WerewolfActionType.confirmRole,
          const {},
          hostId: 'p1',
        )
        .state;
  }
  return s;
}

void main() {
  group('WerewolfConfig presets', () {
    test('6-player and 9-player presets disable sheriff; 12-player presets enable sheriff', () {
      expect(WerewolfConfig.preset6().totalPlayers, 6);
      expect(WerewolfConfig.preset6().enableSheriff, isFalse);

      expect(WerewolfConfig.preset9().totalPlayers, 9);
      expect(WerewolfConfig.preset9().enableSheriff, isFalse);

      expect(WerewolfConfig.preset12Idiot().totalPlayers, 12);
      expect(WerewolfConfig.preset12Idiot().enableSheriff, isTrue);

      expect(WerewolfConfig.preset12Guard().totalPlayers, 12);
      expect(WerewolfConfig.preset12Guard().enableSheriff, isTrue);
    });
  });

  group('WerewolfEngine 6-player full flow & privacy', () {
    test('strictly isolates secret roles per player and resolves peaceful night via witch save', () {
      final engine = WerewolfEngine(random: Random(42));
      final players = _makePlayers(6);
      var state = engine.initGame(players, WerewolfConfig.preset6()).state;

      expect(state.phase, WerewolfPhase.roleReveal);
      expect(state.players.length, 6);

      // Privacy check: villager only sees own role
      final villager = _findRole(state, WerewolfRole.villager);
      final villagerView = engine.projectStateForPlayer(state, villager.playerId);
      final projectedPlayers =
          (villagerView['players'] as List).cast<Map<String, dynamic>>();
      for (final p in projectedPlayers) {
        if (p['playerId'] == villager.playerId) {
          expect(p['role'], 'villager');
        } else {
          expect(p.containsKey('role'), isFalse);
        }
      }
      expect(villagerView['teammateWolfIds'], isEmpty);

      // Wolves see their teammates
      final wolves = _findAllRole(state, WerewolfRole.werewolf);
      final wolfView = engine.projectStateForPlayer(state, wolves.first.playerId);
      expect(
        (wolfView['teammateWolfIds'] as List).toSet(),
        wolves.map((w) => w.playerId).toSet(),
      );

      // Confirm all roles -> night 1 starts at nightWolf (no guard in 6p)
      state = _confirmAllRoles(engine, state);
      expect(state.phase, WerewolfPhase.nightWolf);
      expect(state.dayNumber, 1);

      // Wolves kill villager
      for (final w in wolves) {
        state = engine
            .handleAction(
              state,
              w.playerId,
              WerewolfActionType.wolfConfirm,
              {'targetId': villager.playerId},
              hostId: 'p1',
            )
            .state;
      }
      expect(state.phase, WerewolfPhase.nightWitch);

      // Witch sees wolf target and saves them
      final witch = _findRole(state, WerewolfRole.witch);
      final witchView = engine.projectStateForPlayer(state, witch.playerId);
      final witchInfo = witchView['witchInfo'] as Map<String, dynamic>;
      expect(witchInfo['wolfTargetId'], villager.playerId);
      expect(witchInfo['canSaveTarget'], isTrue);

      state = engine
          .handleAction(
            state,
            witch.playerId,
            WerewolfActionType.witchAct,
            {'action': 'save'},
            hostId: 'p1',
          )
          .state;
      expect(state.phase, WerewolfPhase.nightSeer);

      // Seer checks a wolf
      final seer = _findRole(state, WerewolfRole.seer);
      state = engine
          .handleAction(
            state,
            seer.playerId,
            WerewolfActionType.seerCheck,
            {'targetId': wolves.first.playerId},
            hostId: 'p1',
          )
          .state;
      final seerView = engine.projectStateForPlayer(state, seer.playerId);
      final history = (seerView['seerHistory'] as List).cast<Map<String, dynamic>>();
      expect(history.length, 1);
      expect(history.first['isWolf'], isTrue);

      state = engine
          .handleAction(
            state,
            seer.playerId,
            WerewolfActionType.seerDone,
            const {},
            hostId: 'p1',
          )
          .state;

      // Peaceful night!
      expect(state.phase, WerewolfPhase.dayAnnounce);
      expect(state.lastAnnouncedDeathIds, isEmpty);
      expect(state.lastAnnouncementText, contains('平安夜'));
    });

    test('good camp wins when all wolves are exiled', () {
      final engine = WerewolfEngine(random: Random(7));
      var state = engine.initGame(_makePlayers(6), WerewolfConfig.preset6()).state;
      final wolves = _findAllRole(state, WerewolfRole.werewolf);
      final witch = _findRole(state, WerewolfRole.witch);
      final seer = _findRole(state, WerewolfRole.seer);
      final villager = _findRole(state, WerewolfRole.villager);

      state = _confirmAllRoles(engine, state);

      // Night 1: wolves kill villager, witch poisons wolf[0], seer checks
      for (final w in wolves) {
        state = engine
            .handleAction(
              state,
              w.playerId,
              WerewolfActionType.wolfConfirm,
              {'targetId': villager.playerId},
              hostId: 'p1',
            )
            .state;
      }
      state = engine
          .handleAction(
            state,
            witch.playerId,
            WerewolfActionType.witchAct,
            {'action': 'poison', 'targetId': wolves[0].playerId},
            hostId: 'p1',
          )
          .state;
      state = engine
          .handleAction(
            state,
            seer.playerId,
            WerewolfActionType.seerCheck,
            {'targetId': wolves[1].playerId},
            hostId: 'p1',
          )
          .state;
      state = engine
          .handleAction(
            state,
            seer.playerId,
            WerewolfActionType.seerDone,
            const {},
            hostId: 'p1',
          )
          .state;

      expect(state.phase, WerewolfPhase.dayAnnounce);
      expect(state.lastAnnouncedDeathIds.length, 2);

      // Advance to discuss -> vote
      state = engine
          .handleAction(state, 'p1', WerewolfActionType.hostAdvance, const {}, hostId: 'p1')
          .state;
      expect(state.phase, WerewolfPhase.dayDiscuss);

      state = engine
          .handleAction(state, 'p1', WerewolfActionType.hostAdvance, const {}, hostId: 'p1')
          .state;
      expect(state.phase, WerewolfPhase.dayVote);

      // All alive players vote out wolves[1]
      for (final p in state.alivePlayers) {
        state = engine
            .handleAction(
              state,
              p.playerId,
              WerewolfActionType.dayVote,
              {'targetId': wolves[1].playerId},
              hostId: 'p1',
            )
            .state;
      }
      expect(state.phase, WerewolfPhase.voteResult);

      // Advance from voteResult -> GameOver (Good wins)
      final endTransition = engine.handleAction(
        state,
        'p1',
        WerewolfActionType.hostAdvance,
        const {},
        hostId: 'p1',
      );
      expect(endTransition.isFinished, isTrue);
      expect(endTransition.state.phase, WerewolfPhase.gameOver);
      expect(endTransition.state.winnerCamp, 'good');
    });
  });

  group('WerewolfEngine 12-player Sheriff Election & Special Roles', () {
    test('runs Day 1 sheriff election before dawn, applies 1.5 vote weight, and transfers badge on death', () {
      final engine = WerewolfEngine(random: Random(99));
      final config = WerewolfConfig.preset12Idiot();
      var state = engine.initGame(_makePlayers(12), config).state;
      state = _confirmAllRoles(engine, state);

      final wolves = _findAllRole(state, WerewolfRole.werewolf);
      final witch = _findRole(state, WerewolfRole.witch);
      final seer = _findRole(state, WerewolfRole.seer);
      final villagers = _findAllRole(state, WerewolfRole.villager);
      final idiot = _findRole(state, WerewolfRole.idiot);

      // Night 1: wolves kill villagers[0], witch skips, seer checks
      for (final w in wolves) {
        state = engine
            .handleAction(
              state,
              w.playerId,
              WerewolfActionType.wolfConfirm,
              {'targetId': villagers[0].playerId},
              hostId: 'p1',
            )
            .state;
      }
      state = engine
          .handleAction(
            state,
            witch.playerId,
            WerewolfActionType.witchAct,
            {'action': 'skip'},
            hostId: 'p1',
          )
          .state;
      state = engine
          .handleAction(
            state,
            seer.playerId,
            WerewolfActionType.seerCheck,
            {'targetId': wolves[0].playerId},
            hostId: 'p1',
          )
          .state;
      state = engine
          .handleAction(
            state,
            seer.playerId,
            WerewolfActionType.seerDone,
            const {},
            hostId: 'p1',
          )
          .state;

      // Day 1 MUST enter sheriffSignup BEFORE dawn deaths are revealed!
      expect(state.phase, WerewolfPhase.sheriffSignup);
      expect(state.playerById(villagers[0].playerId)!.isAlive, isTrue);

      // Seer and wolves[0] run for sheriff; others pass
      for (final p in state.players) {
        final join = p.playerId == seer.playerId || p.playerId == wolves[0].playerId;
        state = engine
            .handleAction(
              state,
              p.playerId,
              WerewolfActionType.sheriffSignup,
              {'join': join},
              hostId: 'p1',
            )
            .state;
      }
      expect(state.phase, WerewolfPhase.sheriffVote);

      // Non-candidates vote for Seer
      for (final p in state.players) {
        if (!state.sheriffCandidates.contains(p.playerId)) {
          state = engine
              .handleAction(
                state,
                p.playerId,
                WerewolfActionType.sheriffVote,
                {'targetId': seer.playerId},
                hostId: 'p1',
              )
              .state;
        }
      }

      // Seer elected sheriff, and NOW dawn announcement reveals villagers[0] died
      expect(state.sheriffId, seer.playerId);
      expect(state.phase, WerewolfPhase.dayAnnounce);
      expect(state.lastAnnouncedDeathIds, [villagers[0].playerId]);
      expect(state.playerById(villagers[0].playerId)!.isAlive, isFalse);

      // Advance to dayDiscuss -> dayVote
      state = engine
          .handleAction(state, 'p1', WerewolfActionType.hostAdvance, const {}, hostId: 'p1')
          .state;
      state = engine
          .handleAction(state, 'p1', WerewolfActionType.hostAdvance, const {}, hostId: 'p1')
          .state;
      expect(state.phase, WerewolfPhase.dayVote);

      // Test Sheriff 1.5 vote weight:
      // Sheriff (seer) votes for idiot (1.5 votes), wolves[0] votes for wolves[1] (1.0 vote),
      // everyone else abstains -> idiot gets 1.5 vs 1.0 -> Idiot flips card & survives!
      for (final p in state.alivePlayers) {
        String? target;
        if (p.playerId == seer.playerId) {
          target = idiot.playerId;
        } else if (p.playerId == wolves[0].playerId) {
          target = wolves[1].playerId;
        }
        state = engine
            .handleAction(
              state,
              p.playerId,
              WerewolfActionType.dayVote,
              {'targetId': target},
              hostId: 'p1',
            )
            .state;
      }
      expect(state.phase, WerewolfPhase.voteResult);
      final updatedIdiot = state.playerById(idiot.playerId)!;
      expect(updatedIdiot.isAlive, isTrue);
      expect(updatedIdiot.idiotRevealed, isTrue);
      expect(updatedIdiot.canVote, isFalse);

      // Advance to Night 2: wolves kill Sheriff (seer) -> badge transfer triggered!
      state = engine
          .handleAction(state, 'p1', WerewolfActionType.hostAdvance, const {}, hostId: 'p1')
          .state;
      expect(state.phase, WerewolfPhase.nightWolf);
      expect(state.dayNumber, 2);

      for (final w in wolves) {
        state = engine
            .handleAction(
              state,
              w.playerId,
              WerewolfActionType.wolfConfirm,
              {'targetId': seer.playerId},
              hostId: 'p1',
            )
            .state;
      }
      state = engine
          .handleAction(
            state,
            witch.playerId,
            WerewolfActionType.witchAct,
            {'action': 'skip'},
            hostId: 'p1',
          )
          .state;
      state = engine
          .handleAction(
            state,
            seer.playerId,
            WerewolfActionType.seerCheck,
            {'targetId': wolves[1].playerId},
            hostId: 'p1',
          )
          .state;
      state = engine
          .handleAction(
            state,
            seer.playerId,
            WerewolfActionType.seerDone,
            const {},
            hostId: 'p1',
          )
          .state;

      expect(state.phase, WerewolfPhase.dayAnnounce);
      state = engine
          .handleAction(state, 'p1', WerewolfActionType.hostAdvance, const {}, hostId: 'p1')
          .state;
      expect(state.phase, WerewolfPhase.sheriffBadgeTransfer);

      // Transfer badge to witch
      state = engine
          .handleAction(
            state,
            seer.playerId,
            WerewolfActionType.sheriffTransfer,
            {'targetId': witch.playerId},
            hostId: 'p1',
          )
          .state;
      expect(state.sheriffId, witch.playerId);
      expect(state.phase, WerewolfPhase.dayDiscuss);
    });

    test('guard+witch double-protection kills under default rule, and poisoned hunter cannot shoot', () {
      final engine = WerewolfEngine(random: Random(123));
      final config = WerewolfConfig.preset12Guard().copyWith(enableSheriff: false);
      var state = engine.initGame(_makePlayers(12), config).state;
      state = _confirmAllRoles(engine, state);

      final guard = _findRole(state, WerewolfRole.guard);
      final wolves = _findAllRole(state, WerewolfRole.werewolf);
      final witch = _findRole(state, WerewolfRole.witch);
      final hunter = _findRole(state, WerewolfRole.hunter);
      final seer = _findRole(state, WerewolfRole.seer);
      final villager = _findRole(state, WerewolfRole.villager);

      // Night 1: Guard protects villager, Wolves also kill villager, Witch ALSO saves villager -> 奶穿!
      expect(state.phase, WerewolfPhase.nightGuard);
      state = engine
          .handleAction(
            state,
            guard.playerId,
            WerewolfActionType.guardProtect,
            {'targetId': villager.playerId},
            hostId: 'p1',
          )
          .state;
      for (final w in wolves) {
        state = engine
            .handleAction(
              state,
              w.playerId,
              WerewolfActionType.wolfConfirm,
              {'targetId': villager.playerId},
              hostId: 'p1',
            )
            .state;
      }
      state = engine
          .handleAction(
            state,
            witch.playerId,
            WerewolfActionType.witchAct,
            {'action': 'save'},
            hostId: 'p1',
          )
          .state;
      state = engine
          .handleAction(
            state,
            seer.playerId,
            WerewolfActionType.seerCheck,
            {'targetId': wolves[0].playerId},
            hostId: 'p1',
          )
          .state;
      state = engine
          .handleAction(
            state,
            seer.playerId,
            WerewolfActionType.seerDone,
            const {},
            hostId: 'p1',
          )
          .state;

      expect(state.phase, WerewolfPhase.dayAnnounce);
      expect(state.lastAnnouncedDeathIds, [villager.playerId]);

      // Skip day -> Night 2
      state = engine
          .handleAction(state, 'p1', WerewolfActionType.hostAdvance, const {}, hostId: 'p1')
          .state;
      state = engine
          .handleAction(state, 'p1', WerewolfActionType.hostAdvance, const {}, hostId: 'p1')
          .state;
      state = engine
          .handleAction(state, 'p1', WerewolfActionType.hostAdvance, const {}, hostId: 'p1')
          .state;
      state = engine
          .handleAction(state, 'p1', WerewolfActionType.hostAdvance, const {}, hostId: 'p1')
          .state;
      expect(state.phase, WerewolfPhase.nightGuard);

      // Guard tries empty guard, Wolves kill seer, Witch poisons Hunter -> Hunter CANNOT shoot!
      state = engine
          .handleAction(
            state,
            guard.playerId,
            WerewolfActionType.guardProtect,
            {'targetId': null},
            hostId: 'p1',
          )
          .state;
      for (final w in wolves) {
        state = engine
            .handleAction(
              state,
              w.playerId,
              WerewolfActionType.wolfConfirm,
              {'targetId': seer.playerId},
              hostId: 'p1',
            )
            .state;
      }
      state = engine
          .handleAction(
            state,
            witch.playerId,
            WerewolfActionType.witchAct,
            {'action': 'poison', 'targetId': hunter.playerId},
            hostId: 'p1',
          )
          .state;
      state = engine
          .handleAction(
            state,
            seer.playerId,
            WerewolfActionType.seerCheck,
            {'targetId': wolves[1].playerId},
            hostId: 'p1',
          )
          .state;
      state = engine
          .handleAction(
            state,
            seer.playerId,
            WerewolfActionType.seerDone,
            const {},
            hostId: 'p1',
          )
          .state;

      expect(state.phase, WerewolfPhase.dayAnnounce);
      expect(state.pendingHunterId, isNull);
      state = engine
          .handleAction(state, 'p1', WerewolfActionType.hostAdvance, const {}, hostId: 'p1')
          .state;
      // Directly enters dayDiscuss without hunterShoot!
      expect(state.phase, WerewolfPhase.dayDiscuss);
    });
  });

  group('RoomController lifecycle & reconnection', () {
    test('handles join, start, disconnect, reconnect with session token, and return to lobby', () {
      final registry = GamePluginRegistry([WerewolfPlugin(random: Random(1))]);
      final room = RoomController(
        roomId: 'r1',
        roomCode: '1234',
        gameType: GameType.werewolf,
        registry: registry,
        random: Random(1),
      );

      final joins = <JoinResult>[];
      for (var i = 0; i < 6; i++) {
        final res = room.joinPlayer(name: '朋友${i + 1}');
        joins.add(res);
        if (i > 0) {
          room.toggleReady(res.playerId);
        }
      }

      final startEvents = room.startGame(joins.first.playerId);
      expect(startEvents, isNotEmpty);
      expect(room.status, RoomStatus.playing);

      // Player 2 disconnects and reconnects with sessionToken
      room.markDisconnected(joins[1].playerId);
      expect(
        room.players.firstWhere((p) => p.id == joins[1].playerId).isConnected,
        isFalse,
      );

      final rec = room.reconnectPlayer(
        playerId: joins[1].playerId,
        sessionToken: joins[1].sessionToken,
      );
      expect(rec.reconnected, isTrue);
      expect(
        room.players.firstWhere((p) => p.id == joins[1].playerId).isConnected,
        isTrue,
      );

      final snap = room.snapshotForPlayer(joins[1].playerId);
      expect(snap.gameState, isNotNull);
      expect(snap.gameState!['phase'], 'roleReveal');

      // Return to lobby resets status
      room.returnToLobby(joins.first.playerId);
      expect(room.status, RoomStatus.lobby);
    });
  });
}
