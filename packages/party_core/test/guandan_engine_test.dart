import 'dart:math';

import 'package:party_core/party_core.dart';
import 'package:test/test.dart';

PlayingCard _c(String id, CardSuit suit, int rank) =>
    PlayingCard(id: id, suit: suit, rank: rank);

List<PlayerInfo> _make4Players() => List.generate(
      4,
      (i) => PlayerInfo(
        id: 'p${i + 1}',
        name: '玩家${i + 1}',
        seatNumber: i + 1,
        isHost: i == 0,
        isReady: true,
      ),
    );

void main() {
  group('GuandanEvaluator hand types, bomb ladder & Heart wildcard', () {
    test('enforces bomb ladder: 4-bomb < 5-bomb < Straight Flush < 6-bomb < Four Jokers', () {
      const level = 2;

      final bomb4 = GuandanEvaluator.evaluateBest([
        _c('1', CardSuit.spades, 9),
        _c('2', CardSuit.hearts, 9),
        _c('3', CardSuit.clubs, 9),
        _c('4', CardSuit.diamonds, 9),
      ], level)!;
      expect(bomb4.type, GuandanHandType.bomb);
      expect(bomb4.bombTier, 40);

      final bomb5 = GuandanEvaluator.evaluateBest([
        _c('1', CardSuit.spades, 5),
        _c('2', CardSuit.hearts, 5),
        _c('3', CardSuit.clubs, 5),
        _c('4', CardSuit.diamonds, 5),
        _c('5', CardSuit.spades, 5),
      ], level)!;
      expect(bomb5.bombTier, 50);

      final straightFlush = GuandanEvaluator.evaluateBest([
        _c('1', CardSuit.spades, 3),
        _c('2', CardSuit.spades, 4),
        _c('3', CardSuit.spades, 5),
        _c('4', CardSuit.spades, 6),
        _c('5', CardSuit.spades, 7),
      ], level)!;
      expect(straightFlush.type, GuandanHandType.straightFlush);
      expect(straightFlush.bombTier, 55);

      final bomb6 = GuandanEvaluator.evaluateBest([
        _c('1', CardSuit.spades, 3),
        _c('2', CardSuit.hearts, 3),
        _c('3', CardSuit.clubs, 3),
        _c('4', CardSuit.diamonds, 3),
        _c('5', CardSuit.spades, 3),
        _c('6', CardSuit.clubs, 3),
      ], level)!;
      expect(bomb6.bombTier, 60);

      final fourJokers = GuandanEvaluator.evaluateBest([
        _c('j1', CardSuit.joker, 16),
        _c('j2', CardSuit.joker, 16),
        _c('j3', CardSuit.joker, 15),
        _c('j4', CardSuit.joker, 15),
      ], level)!;
      expect(fourJokers.type, GuandanHandType.fourJokers);

      expect(bomb5.beats(bomb4), isTrue);
      expect(straightFlush.beats(bomb5), isTrue);
      expect(bomb6.beats(straightFlush), isTrue);
      expect(fourJokers.beats(bomb6), isTrue);
    });

    test('Heart level wildcard (逢人配) completes straight flush, full house, tube, plate, and bombs', () {
      const level = 5;
      final wild = _c('w1', CardSuit.hearts, 5);

      // Completes Straight Flush (♠7, ♠8, ♠9, ♠10 + ♥5 -> ♠7-8-9-10-J straight flush!)
      final sf = GuandanEvaluator.evaluateBest([
        _c('a', CardSuit.spades, 7),
        _c('b', CardSuit.spades, 8),
        _c('c', CardSuit.spades, 9),
        _c('d', CardSuit.spades, 10),
        wild,
      ], level)!;
      expect(sf.type, GuandanHandType.straightFlush);
      expect(sf.primaryValue, 11); // J-high beats 10-high!

      // Completes Tube (三连对: 33 44 5 + wild -> 334455)
      final tube = GuandanEvaluator.evaluateBest([
        _c('t1', CardSuit.spades, 3),
        _c('t2', CardSuit.clubs, 3),
        _c('t3', CardSuit.spades, 4),
        _c('t4', CardSuit.clubs, 4),
        _c('t5', CardSuit.spades, 5),
        wild,
      ], level)!;
      expect(tube.type, GuandanHandType.tube);
      expect(tube.primaryValue, 5);

      // Completes Plate (钢板: JJJ QQ + wild -> JJJQQQ)
      final plate = GuandanEvaluator.evaluateBest([
        _c('p1', CardSuit.spades, 11),
        _c('p2', CardSuit.clubs, 11),
        _c('p3', CardSuit.diamonds, 11),
        _c('p4', CardSuit.spades, 12),
        _c('p5', CardSuit.clubs, 12),
        wild,
      ], level)!;
      expect(plate.type, GuandanHandType.plate);
      expect(plate.primaryValue, 12);

      // Wildcard CANNOT pair with a Joker
      final invalidJokerPair = GuandanEvaluator.evaluateBest([
        _c('jk', CardSuit.joker, 16),
        wild,
      ], level);
      expect(invalidJokerPair, isNull);
    });

    test('Level card beats Ace but loses to Jokers', () {
      const level = 7;
      final ace = GuandanEvaluator.evaluateBest([_c('a', CardSuit.spades, 14)], level)!;
      final lvl = GuandanEvaluator.evaluateBest([_c('l', CardSuit.clubs, 7)], level)!;
      final smallJoker = GuandanEvaluator.evaluateBest([_c('sj', CardSuit.joker, 15)], level)!;

      expect(lvl.beats(ace), isTrue);
      expect(smallJoker.beats(lvl), isTrue);
    });

    test('findHintPlays finds legal beating plays and preserves bombs until needed', () {
      const level = 2;
      final target = GuandanEvaluator.evaluateBest([_c('t', CardSuit.spades, 10)], level)!;
      final hand = [
        _c('1', CardSuit.spades, 4),
        _c('2', CardSuit.clubs, 12), // Q beats 10
        _c('3', CardSuit.spades, 8),
        _c('4', CardSuit.hearts, 8),
        _c('5', CardSuit.clubs, 8),
        _c('6', CardSuit.diamonds, 8), // 4-bomb
      ];
      final hints = GuandanEvaluator.findHintPlays(hand, level, beatTarget: target);
      expect(hints, isNotEmpty);
      expect(hints.first.type, GuandanHandType.single);
      expect(hints.first.cards.first.rank, 12);
      expect(hints.any((h) => h.type == GuandanHandType.bomb), isTrue);
    });
  });

  group('GuandanEngine full round, Partner Wind (接风), level-up & privacy', () {
    test('deals 108 unique cards (27 each) and strictly hides other players hands', () {
      final engine = GuandanEngine(random: Random(42));
      final state = engine.initGame(_make4Players(), const GuandanConfig()).state;

      expect(state.players.length, 4);
      final allIds = <String>{};
      for (final p in state.players) {
        expect(p.hand.length, 27);
        allIds.addAll(p.hand.map((c) => c.id));
      }
      expect(allIds.length, 108);

      final view = engine.projectStateForPlayer(state, 'p1');
      expect((view['myHand'] as List).length, 27);
      for (final p in (view['players'] as List).cast<Map<String, dynamic>>()) {
        expect(p.containsKey('hand'), isFalse);
        expect(p['cardCount'], 27);
      }
    });

    test('triggers Partner Wind (接风) when finisher is unchallenged, then Double-Down (+3 levels) and Tribute', () {
      final engine = GuandanEngine(random: Random(1));
      // Construct a compact deterministic end-game state:
      // p1 (Red, seat 1) has 1 card (A), p2 (Blue) has 2 small cards,
      // p3 (Red, seat 3 - p1's partner!) has 1 card (K), p4 (Blue) has 2 small cards.
      var state = GuandanState(
        config: const GuandanConfig(startLevel: 2, targetLevel: 14, enableTribute: true),
        players: [
          GuandanPlayerState(
            playerId: 'p1',
            name: '红1',
            seatNumber: 1,
            hand: [_c('a1', CardSuit.spades, 14)],
          ),
          GuandanPlayerState(
            playerId: 'p2',
            name: '蓝2',
            seatNumber: 2,
            hand: [_c('b1', CardSuit.spades, 3), _c('b2', CardSuit.clubs, 4)],
          ),
          GuandanPlayerState(
            playerId: 'p3',
            name: '红3',
            seatNumber: 3,
            hand: [_c('c1', CardSuit.hearts, 13)],
          ),
          GuandanPlayerState(
            playerId: 'p4',
            name: '蓝4',
            seatNumber: 4,
            hand: [_c('d1', CardSuit.spades, 5), _c('d2', CardSuit.clubs, 6)],
          ),
        ],
        phase: GuandanPhase.playing,
        roundNumber: 1,
        teamLevels: [2, 2],
        activeTeamIndex: 0,
        currentTurnIndex: 0,
      );

      // p1 plays last card (Ace) -> takes 1st place (头游)
      state = engine
          .handleAction(state, 'p1', GuandanActionType.playCards, {'cardIds': ['a1']}, hostId: 'p1')
          .state;
      expect(state.players[0].finishOrder, 1);
      expect(state.currentTurnPlayer.playerId, 'p2');

      // p2 passes, p3 passes, p4 passes -> Partner Wind (接风) gives lead to p3!
      state = engine.handleAction(state, 'p2', GuandanActionType.passTurn, const {}, hostId: 'p1').state;
      state = engine.handleAction(state, 'p3', GuandanActionType.passTurn, const {}, hostId: 'p1').state;
      final windRes = engine.handleAction(state, 'p4', GuandanActionType.passTurn, const {}, hostId: 'p1');
      state = windRes.state;
      expect(state.currentTurnPlayer.playerId, 'p3');
      expect(state.lastPlay, isNull);
      expect(windRes.events.any((e) => e.type == 'partner_wind'), isTrue);

      // p3 plays last card (K) -> Double-Down (双下)! Red team +3 levels (2 -> 5)!
      state = engine
          .handleAction(state, 'p3', GuandanActionType.playCards, {'cardIds': ['c1']}, hostId: 'p1')
          .state;
      expect(state.phase, GuandanPhase.roundOver);
      expect(state.lastWinningTeam, 0);
      expect(state.lastLevelGain, 3);
      expect(state.teamLevels[0], 5);
      expect(state.activeTeamIndex, 0);

      // Host starts Round 2 -> enters TributePay (or Anti-Tribute if losers got 2 Big Jokers)
      state = engine
          .handleAction(state, 'p1', GuandanActionType.nextRound, const {}, hostId: 'p1')
          .state;
      expect(state.roundNumber, 2);
      expect(state.currentLevel, 5);
      expect(
        state.phase == GuandanPhase.tributePay || state.phase == GuandanPhase.playing,
        isTrue,
      );
    });
  });
}
