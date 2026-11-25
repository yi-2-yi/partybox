import 'dart:math';

import 'package:party_core/party_core.dart';
import 'package:test/test.dart';

List<PlayerInfo> _makePlayers(int n) => List.generate(
      n,
      (i) => PlayerInfo(
        id: 'p${i + 1}',
        name: '玩家${i + 1}',
        seatNumber: i + 1,
        isHost: i == 0,
        isReady: true,
      ),
    );

void main() {
  group('OneNightEngine full night swaps, privacy & win evaluation', () {
    test('presets deal N + 3 cards and hide center/other roles until gameOver', () {
      final engine = OneNightEngine(random: Random(7));
      final cfg = OneNightConfig.preset5();
      expect(cfg.requiredPlayers, 5);
      expect(cfg.roles.length, 8);

      final state = engine.initGame(_makePlayers(5), cfg).state;
      expect(state.players.length, 5);
      expect(state.centerCards.length, 3);

      final view = engine.projectStateForPlayer(state, 'p1');
      expect(view.containsKey('centerCards'), isFalse);
      expect(view.containsKey('nightReplayLogs'), isFalse);
      for (final p in (view['players'] as List).cast<Map<String, dynamic>>()) {
        expect(p.containsKey('initialRole'), isFalse);
        expect(p.containsKey('finalRole'), isFalse);
      }
    });

    test('Robber + Troublemaker swap chain updates Insomniac final role and wins on FINAL role', () {
      final engine = OneNightEngine(random: Random(1));
      // Build deterministic 5-player night start:
      // p1=werewolf (lone wolf!), p2=robber, p3=troublemaker, p4=drunk, p5=insomniac
      // center=[werewolf, seer, villager]
      var state = OneNightState(
        config: OneNightConfig.preset5(),
        players: const [
          OneNightPlayerState(
            playerId: 'p1',
            name: '玩家1',
            seatNumber: 1,
            initialRole: OneNightRole.werewolf,
            currentRole: OneNightRole.werewolf,
          ),
          OneNightPlayerState(
            playerId: 'p2',
            name: '玩家2',
            seatNumber: 2,
            initialRole: OneNightRole.robber,
            currentRole: OneNightRole.robber,
          ),
          OneNightPlayerState(
            playerId: 'p3',
            name: '玩家3',
            seatNumber: 3,
            initialRole: OneNightRole.troublemaker,
            currentRole: OneNightRole.troublemaker,
          ),
          OneNightPlayerState(
            playerId: 'p4',
            name: '玩家4',
            seatNumber: 4,
            initialRole: OneNightRole.drunk,
            currentRole: OneNightRole.drunk,
          ),
          OneNightPlayerState(
            playerId: 'p5',
            name: '玩家5',
            seatNumber: 5,
            initialRole: OneNightRole.insomniac,
            currentRole: OneNightRole.insomniac,
          ),
        ],
        centerCards: const [
          OneNightRole.werewolf,
          OneNightRole.seer,
          OneNightRole.villager,
        ],
        phase: OneNightPhase.roleReveal,
        wakeQueue: const [
          OneNightRole.werewolf,
          OneNightRole.seer, // in center -> decoy step!
          OneNightRole.robber,
          OneNightRole.troublemaker,
          OneNightRole.drunk,
          OneNightRole.insomniac,
        ],
      );

      // Confirm all roles -> wakes Werewolf (p1, lone wolf!)
      for (var i = 1; i <= 5; i++) {
        state = engine
            .handleAction(
              state,
              'p$i',
              OneNightActionType.confirmRole,
              const {},
              hostId: 'p1',
            )
            .state;
      }
      expect(state.phase, OneNightPhase.nightStep);
      expect(state.activeWakeRole, OneNightRole.werewolf);

      // Lone wolf peeks Center B (seer)
      state = engine
          .handleAction(
            state,
            'p1',
            OneNightActionType.nightAct,
            {'centerIndex': 1},
            hostId: 'p1',
          )
          .state;
      expect(state.playerById('p1')!.nightNotes.last, contains('预言家'));

      // Seer is in center -> decoy step! Host advances
      expect(state.activeWakeRole, OneNightRole.seer);
      expect(state.isDecoyStep, isTrue);
      state = engine
          .handleAction(
            state,
            'p1',
            OneNightActionType.hostAdvance,
            const {},
            hostId: 'p1',
          )
          .state;

      // Robber (p2) swaps with Werewolf (p1) -> p2 becomes werewolf, p1 becomes robber!
      expect(state.activeWakeRole, OneNightRole.robber);
      state = engine
          .handleAction(
            state,
            'p2',
            OneNightActionType.nightAct,
            {'targetId': 'p1'},
            hostId: 'p1',
          )
          .state;
      expect(state.playerById('p2')!.currentRole, OneNightRole.werewolf);
      expect(state.playerById('p1')!.currentRole, OneNightRole.robber);
      expect(state.playerById('p2')!.nightNotes.last, contains('狼人'));

      // Troublemaker (p3) swaps p2 (now werewolf!) and p5 (insomniac)
      expect(state.activeWakeRole, OneNightRole.troublemaker);
      state = engine
          .handleAction(
            state,
            'p3',
            OneNightActionType.nightAct,
            {
              'targetIds': ['p2', 'p5']
            },
            hostId: 'p1',
          )
          .state;
      expect(state.playerById('p5')!.currentRole, OneNightRole.werewolf);
      expect(state.playerById('p2')!.currentRole, OneNightRole.insomniac);

      // Drunk (p4) swaps with Center C (villager)
      expect(state.activeWakeRole, OneNightRole.drunk);
      state = engine
          .handleAction(
            state,
            'p4',
            OneNightActionType.nightAct,
            {'centerIndex': 2},
            hostId: 'p1',
          )
          .state;
      expect(state.playerById('p4')!.currentRole, OneNightRole.villager);
      expect(state.centerCards[2], OneNightRole.drunk);

      // Insomniac (p5) wakes up LAST and sees their FINAL role is Werewolf!
      expect(state.activeWakeRole, OneNightRole.insomniac);
      expect(state.playerById('p5')!.nightNotes.last, contains('狼人'));
      state = engine
          .handleAction(
            state,
            'p5',
            OneNightActionType.nightAct,
            const {},
            hostId: 'p1',
          )
          .state;

      expect(state.phase, OneNightPhase.dayDiscuss);

      // Start vote -> everyone votes out p5 (the true FINAL werewolf!)
      state = engine
          .handleAction(state, 'p1', OneNightActionType.startVote, const {}, hostId: 'p1')
          .state;
      expect(state.phase, OneNightPhase.dayVote);

      for (var i = 1; i <= 4; i++) {
        state = engine
            .handleAction(
              state,
              'p$i',
              OneNightActionType.castVote,
              {'targetId': 'p5'},
              hostId: 'p1',
            )
            .state;
      }
      final res = engine.handleAction(
        state,
        'p5',
        OneNightActionType.castVote,
        {'targetId': 'p1'},
        hostId: 'p1',
      );
      expect(res.isFinished, isTrue);
      expect(res.state.phase, OneNightPhase.gameOver);
      expect(res.state.eliminatedPlayerIds, ['p5']);
      expect(res.state.winnerTeam, 'good');
    });

    test('Tanner wins alone when voted out, and Hunter takes down their vote target', () {
      final engine = OneNightEngine(random: Random(2));
      var state = OneNightState(
        config: OneNightConfig.preset3(),
        players: const [
          OneNightPlayerState(
            playerId: 'p1',
            name: '狼',
            seatNumber: 1,
            initialRole: OneNightRole.werewolf,
            currentRole: OneNightRole.werewolf,
          ),
          OneNightPlayerState(
            playerId: 'p2',
            name: '猎人',
            seatNumber: 2,
            initialRole: OneNightRole.hunter,
            currentRole: OneNightRole.hunter,
          ),
          OneNightPlayerState(
            playerId: 'p3',
            name: '皮匠',
            seatNumber: 3,
            initialRole: OneNightRole.tanner,
            currentRole: OneNightRole.tanner,
          ),
        ],
        centerCards: const [
          OneNightRole.villager,
          OneNightRole.seer,
          OneNightRole.robber,
        ],
        phase: OneNightPhase.dayVote,
        wakeQueue: const [],
      );

      // p1 and p3 vote p2 (Hunter); p2 (Hunter) votes p1 (Werewolf) -> both p2 and p1 die! Good wins!
      state = engine
          .handleAction(state, 'p1', OneNightActionType.castVote, {'targetId': 'p2'}, hostId: 'p1')
          .state;
      state = engine
          .handleAction(state, 'p3', OneNightActionType.castVote, {'targetId': 'p2'}, hostId: 'p1')
          .state;
      final res = engine.handleAction(
        state,
        'p2',
        OneNightActionType.castVote,
        {'targetId': 'p1'},
        hostId: 'p1',
      );
      expect(res.state.eliminatedPlayerIds, containsAll(['p1', 'p2']));
      expect(res.state.winnerTeam, 'good');
    });
  });
}
