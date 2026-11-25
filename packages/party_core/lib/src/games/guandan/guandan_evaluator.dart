import 'guandan_models.dart';

/// Official Guandan hand evaluator and smart hint generator.
///
/// Supports:
/// - All normal hand types: Single, Pair, Triple, Full House, 5-card Straight,
///   3-Consecutive Pairs (Tube/木板), 2-Consecutive Triples (Plate/钢板)
/// - Full Bomb ladder: 4-Bomb < 5-Bomb < Straight Flush (同花顺) < 6-Bomb < ... < 10-Bomb < Four Jokers (天王炸)
/// - Up to 2 Heart Level Wildcards (红桃逢人配) automatically substituted to form
///   the strongest valid play (or strongest play that beats [beatTarget]).
class GuandanEvaluator {
  const GuandanEvaluator._();

  /// Sorts a player's hand for mobile display:
  /// Big Joker > Small Joker > Wildcards (♥Level) > Other Level Cards > A..2 (by suit).
  static List<PlayingCard> sortHand(List<PlayingCard> cards, int currentLevel) {
    final sorted = [...cards];
    sorted.sort((a, b) {
      final sa = a.isWildcard(currentLevel) ? 155 : a.strength(currentLevel);
      final sb = b.isWildcard(currentLevel) ? 155 : b.strength(currentLevel);
      if (sa != sb) return sb.compareTo(sa);
      return a.suit.index.compareTo(b.suit.index);
    });
    return sorted;
  }

  /// Evaluates [cards] and returns all legal [GuandanPlay] interpretations,
  /// sorted strongest-first.
  static List<GuandanPlay> evaluateAll(
    List<PlayingCard> cards,
    int currentLevel,
  ) {
    if (cards.isEmpty) return const [];

    final n = cards.length;
    final wilds = cards.where((c) => c.isWildcard(currentLevel)).toList();
    final normals = cards.where((c) => !c.isWildcard(currentLevel)).toList();
    final w = wilds.length;
    final hasJoker = normals.any((c) => c.isJoker);

    final results = <GuandanPlay>[];

    // 1. Single (1 card)
    if (n == 1) {
      final c = cards.first;
      results.add(GuandanPlay(
        type: GuandanHandType.single,
        cards: cards,
        primaryValue: c.strength(currentLevel),
        bombTier: 0,
      ));
      return results;
    }

    // 2. Four Jokers (天王炸: 2 Big + 2 Small Jokers)
    if (n == 4 &&
        normals.length == 4 &&
        normals.where((c) => c.isBigJoker).length == 2 &&
        normals.where((c) => c.isSmallJoker).length == 2) {
      results.add(GuandanPlay(
        type: GuandanHandType.fourJokers,
        cards: cards,
        primaryValue: 999,
        bombTier: 999,
      ));
      return results;
    }

    // 3. Pair (2 cards)
    if (n == 2) {
      if (w == 2) {
        // Two wildcards -> Pair of Level Cards
        results.add(GuandanPlay(
          type: GuandanHandType.pair,
          cards: cards,
          primaryValue: 150,
          bombTier: 0,
        ));
      } else if (w == 1) {
        // Wildcard cannot pair with a Joker
        if (!hasJoker) {
          results.add(GuandanPlay(
            type: GuandanHandType.pair,
            cards: cards,
            primaryValue: normals.first.strength(currentLevel),
            bombTier: 0,
          ));
        }
      } else {
        if (normals[0].rank == normals[1].rank) {
          results.add(GuandanPlay(
            type: GuandanHandType.pair,
            cards: cards,
            primaryValue: normals[0].strength(currentLevel),
            bombTier: 0,
          ));
        }
      }
      return results;
    }

    // 4. Triple (3 cards, no jokers)
    if (n == 3 && !hasJoker) {
      final ranks = normals.map((c) => c.rank).toSet();
      if (ranks.length <= 1) {
        final rank = ranks.isEmpty ? currentLevel : ranks.first;
        final strength = rank == currentLevel ? 150 : rank;
        results.add(GuandanPlay(
          type: GuandanHandType.triple,
          cards: cards,
          primaryValue: strength,
          bombTier: 0,
        ));
      }
      return results;
    }

    // 5. Same-rank Bomb (4..10 cards, no jokers)
    if (n >= 4 && n <= 10 && !hasJoker) {
      final ranks = normals.map((c) => c.rank).toSet();
      if (ranks.length <= 1) {
        final rank = ranks.isEmpty ? currentLevel : ranks.first;
        final strength = rank == currentLevel ? 150 : rank;
        results.add(GuandanPlay(
          type: GuandanHandType.bomb,
          cards: cards,
          primaryValue: strength,
          bombTier: n * 10,
        ));
      }
    }

    // 6. 5-card hands: Straight Flush, Full House, Straight (no jokers)
    if (n == 5 && !hasJoker) {
      // 6a. Straight Flush (同花顺) — bombTier 55 (beats 5-bomb, loses to 6-bomb)
      final normalSuits = normals.map((c) => c.suit).toSet();
      if (normalSuits.length <= 1) {
        final bestHigh = _bestStraightHigh(normals, w);
        if (bestHigh != null) {
          results.add(GuandanPlay(
            type: GuandanHandType.straightFlush,
            cards: cards,
            primaryValue: bestHigh,
            bombTier: 55,
          ));
        }
      }

      // 6b. Full House (三带二)
      final bestTripleStrength = _bestFullHouseTripleStrength(normals, w, currentLevel);
      if (bestTripleStrength != null) {
        results.add(GuandanPlay(
          type: GuandanHandType.fullHouse,
          cards: cards,
          primaryValue: bestTripleStrength,
          bombTier: 0,
        ));
      }

      // 6c. Straight (顺子)
      final straightHigh = _bestStraightHigh(normals, w);
      if (straightHigh != null) {
        results.add(GuandanPlay(
          type: GuandanHandType.straight,
          cards: cards,
          primaryValue: straightHigh,
          bombTier: 0,
        ));
      }
    }

    // 7. 6-card hands: Plate (钢板: 2 consecutive triples) & Tube (木板: 3 consecutive pairs)
    if (n == 6 && !hasJoker) {
      final plateHigh = _bestConsecutiveGroupsHigh(
        normals,
        w,
        groupCount: 2,
        groupSize: 3,
      );
      if (plateHigh != null) {
        results.add(GuandanPlay(
          type: GuandanHandType.plate,
          cards: cards,
          primaryValue: plateHigh,
          bombTier: 0,
        ));
      }

      final tubeHigh = _bestConsecutiveGroupsHigh(
        normals,
        w,
        groupCount: 3,
        groupSize: 2,
      );
      if (tubeHigh != null) {
        results.add(GuandanPlay(
          type: GuandanHandType.tube,
          cards: cards,
          primaryValue: tubeHigh,
          bombTier: 0,
        ));
      }
    }

    results.sort((a, b) {
      if (a.bombTier != b.bombTier) return b.bombTier.compareTo(a.bombTier);
      return b.primaryValue.compareTo(a.primaryValue);
    });
    return results;
  }

  /// Evaluates [cards] and picks the best legal play; if [beatTarget] is given,
  /// prefers the strongest interpretation that legally beats [beatTarget].
  static GuandanPlay? evaluateBest(
    List<PlayingCard> cards,
    int currentLevel, {
    GuandanPlay? beatTarget,
  }) {
    final all = evaluateAll(cards, currentLevel);
    if (all.isEmpty) return null;
    if (beatTarget == null) return all.first;
    for (final play in all) {
      if (play.beats(beatTarget)) return play;
    }
    return null;
  }

  /// Generates candidate plays from [hand] that legally beat [beatTarget]
  /// (or valid opening plays when [beatTarget] is null), ordered from cheapest
  /// (preserve bombs) to strongest!
  static List<GuandanPlay> findHintPlays(
    List<PlayingCard> hand,
    int currentLevel, {
    GuandanPlay? beatTarget,
  }) {
    if (hand.isEmpty) return const [];

    final sortedAsc = [...hand]..sort(
        (a, b) => a.strength(currentLevel).compareTo(b.strength(currentLevel)),
      );
    final wilds = sortedAsc.where((c) => c.isWildcard(currentLevel)).toList();
    final normals = sortedAsc.where((c) => !c.isWildcard(currentLevel)).toList();

    final byRank = <int, List<PlayingCard>>{};
    for (final c in normals) {
      byRank.putIfAbsent(c.rank, () => []).add(c);
    }

    final candidates = <GuandanPlay>[];

    void tryAdd(List<PlayingCard> combo) {
      final play = evaluateBest(combo, currentLevel, beatTarget: beatTarget);
      if (play != null) {
        candidates.add(play);
      }
    }

    // Opening lead (no beatTarget): offer sensible non-bomb plays from smallest up, then bombs.
    if (beatTarget == null) {
      // Try straights / tubes / plates / full houses first for clean shedding, plus singles/pairs/triples
      for (final p in _generateStraights(normals, wilds, currentLevel, flushOnly: false)) {
        candidates.add(p);
      }
      for (final p in _generateConsecutiveGroups(normals, wilds, currentLevel, groupCount: 2, groupSize: 3)) {
        candidates.add(p);
      }
      for (final p in _generateConsecutiveGroups(normals, wilds, currentLevel, groupCount: 3, groupSize: 2)) {
        candidates.add(p);
      }
      for (final p in _generateFullHouses(byRank, wilds, currentLevel)) {
        candidates.add(p);
      }
      for (final entry in byRank.entries) {
        final list = entry.value;
        if (list.length >= 3 && entry.key < 15) tryAdd(list.take(3).toList());
        if (list.length >= 2) tryAdd(list.take(2).toList());
        tryAdd([list.first]);
      }
      if (wilds.isNotEmpty) {
        tryAdd([wilds.first]);
      }
      for (final b in _generateBombs(normals, byRank, wilds, currentLevel)) {
        candidates.add(b);
      }
      return _dedupeAndSortHints(candidates);
    }

    // Responding to a non-bomb target: try matching same type first (cheapest first)
    if (!beatTarget.isBomb) {
      switch (beatTarget.type) {
        case GuandanHandType.single:
          final seenRank = <int>{};
          for (final c in sortedAsc) {
            if (seenRank.add(c.rank)) {
              tryAdd([c]);
            }
          }
        case GuandanHandType.pair:
          for (final entry in byRank.entries) {
            final list = entry.value;
            if (list.length >= 2) {
              tryAdd(list.take(2).toList());
            } else if (list.length == 1 && wilds.isNotEmpty && entry.key < 15) {
              tryAdd([list.first, wilds.first]);
            }
          }
          if (wilds.length == 2) {
            tryAdd(wilds);
          }
        case GuandanHandType.triple:
          for (final entry in byRank.entries) {
            if (entry.key >= 15) continue;
            final list = entry.value;
            if (list.length >= 3) {
              tryAdd(list.take(3).toList());
            } else if (list.length + wilds.length >= 3) {
              tryAdd([...list, ...wilds.take(3 - list.length)]);
            }
          }
        case GuandanHandType.fullHouse:
          for (final p in _generateFullHouses(byRank, wilds, currentLevel)) {
            if (p.beats(beatTarget)) candidates.add(p);
          }
        case GuandanHandType.straight:
          for (final p in _generateStraights(normals, wilds, currentLevel, flushOnly: false)) {
            if (p.beats(beatTarget)) candidates.add(p);
          }
        case GuandanHandType.tube:
          for (final p in _generateConsecutiveGroups(
            normals,
            wilds,
            currentLevel,
            groupCount: 3,
            groupSize: 2,
          )) {
            if (p.beats(beatTarget)) candidates.add(p);
          }
        case GuandanHandType.plate:
          for (final p in _generateConsecutiveGroups(
            normals,
            wilds,
            currentLevel,
            groupCount: 2,
            groupSize: 3,
          )) {
            if (p.beats(beatTarget)) candidates.add(p);
          }
        default:
          break;
      }
    }

    // Always also include bombs that can beat beatTarget
    for (final bomb in _generateBombs(normals, byRank, wilds, currentLevel)) {
      if (bomb.beats(beatTarget)) {
        candidates.add(bomb);
      }
    }

    return _dedupeAndSortHints(candidates);
  }

  /// Highest high-card value for a 5-card straight (A2345 => 5, ..., 10JQKA => 14).
  static int? _bestStraightHigh(List<PlayingCard> normals, int wildCount) {
    // Straight ranks cannot have duplicates among normals
    final normalRanks = normals.map((c) => c.rank).toList();
    if (normalRanks.toSet().length != normalRanks.length) return null;

    // Sequences from highest (10..14) down to lowest (A,2,3,4,5)
    for (var high = 14; high >= 5; high--) {
      final seq = high == 5
          ? const [14, 2, 3, 4, 5]
          : [high - 4, high - 3, high - 2, high - 1, high];
      final seqSet = seq.toSet();
      if (normalRanks.every(seqSet.contains)) {
        final missing = 5 - normalRanks.length;
        if (missing == wildCount) {
          return high;
        }
      }
    }
    return null;
  }

  static int? _bestFullHouseTripleStrength(
    List<PlayingCard> normals,
    int wildCount,
    int currentLevel,
  ) {
    final counts = <int, int>{};
    for (final c in normals) {
      counts[c.rank] = (counts[c.rank] ?? 0) + 1;
    }
    if (counts.length > 2) return null;
    if (counts.values.any((c) => c > 3)) return null;

    int? bestStrength;
    final candidateRanks = {...counts.keys, currentLevel};
    for (final tripleRank in candidateRanks) {
      final existingTriple = counts[tripleRank] ?? 0;
      final needTriple = 3 - existingTriple;
      if (needTriple < 0 || needTriple > wildCount) continue;

      final remainingWilds = wildCount - needTriple;
      final otherEntries = counts.entries.where((e) => e.key != tripleRank).toList();
      if (otherEntries.length > 1) continue;

      final existingPair = otherEntries.isEmpty ? 0 : otherEntries.first.value;
      if (existingPair + remainingWilds == 2) {
        final strength = tripleRank == currentLevel ? 150 : tripleRank;
        if (bestStrength == null || strength > bestStrength) {
          bestStrength = strength;
        }
      }
    }
    return bestStrength;
  }

  /// Evaluates 3 consecutive pairs (tube) or 2 consecutive triples (plate).
  /// Sequences use face ranks: A-2-3 (high=3) .. Q-K-A (high=14) for tube,
  /// and A-2 (high=2) .. K-A (high=14) for plate.
  static int? _bestConsecutiveGroupsHigh(
    List<PlayingCard> normals,
    int wildCount, {
    required int groupCount,
    required int groupSize,
  }) {
    final counts = <int, int>{};
    for (final c in normals) {
      counts[c.rank] = (counts[c.rank] ?? 0) + 1;
    }
    if (counts.values.any((c) => c > groupSize)) return null;

    final minHigh = groupCount; // 3 for A-2-3, 2 for A-2
    for (var high = 14; high >= minHigh; high--) {
      final seq = <int>[];
      for (var i = 0; i < groupCount; i++) {
        final r = high - (groupCount - 1) + i;
        seq.add(r == 1 ? 14 : r);
      }
      final seqSet = seq.toSet();
      if (!counts.keys.every(seqSet.contains)) continue;

      var needed = 0;
      for (final r in seq) {
        needed += groupSize - (counts[r] ?? 0);
      }
      if (needed == wildCount) {
        return high;
      }
    }
    return null;
  }

  static List<GuandanPlay> _generateFullHouses(
    Map<int, List<PlayingCard>> byRank,
    List<PlayingCard> wilds,
    int currentLevel,
  ) {
    final results = <GuandanPlay>[];
    final regularRanks = byRank.keys.where((r) => r < 15).toList()
      ..sort((a, b) => _rankStrength(a, currentLevel).compareTo(_rankStrength(b, currentLevel)));

    for (final tr in regularRanks) {
      final tCards = byRank[tr]!;
      final needT = (3 - tCards.length).clamp(0, 3);
      if (needT > wilds.length) continue;

      final tripleCombo = [...tCards.take(3), ...wilds.take(needT)];
      final remWilds = wilds.skip(needT).toList();

      for (final pr in regularRanks) {
        if (pr == tr) continue;
        final pCards = byRank[pr]!;
        final needP = (2 - pCards.length).clamp(0, 2);
        if (needP > remWilds.length) continue;

        final fullCombo = [
          ...tripleCombo,
          ...pCards.take(2),
          ...remWilds.take(needP),
        ];
        final play = evaluateBest(fullCombo, currentLevel);
        if (play != null && play.type == GuandanHandType.fullHouse) {
          results.add(play);
          break; // Cheapest pair for this triple is enough for hints
        }
      }
    }
    return results;
  }

  static List<GuandanPlay> _generateStraights(
    List<PlayingCard> normals,
    List<PlayingCard> wilds,
    int currentLevel, {
    required bool flushOnly,
  }) {
    final results = <GuandanPlay>[];
    final nonJokers = normals.where((c) => !c.isJoker).toList();

    final suitGroups = flushOnly
        ? [
            for (final s in [
              CardSuit.spades,
              CardSuit.hearts,
              CardSuit.clubs,
              CardSuit.diamonds,
            ])
              nonJokers.where((c) => c.suit == s).toList(),
          ]
        : [nonJokers];

    for (final pool in suitGroups) {
      final byRank = <int, PlayingCard>{};
      for (final c in pool) {
        byRank.putIfAbsent(c.rank, () => c);
      }

      for (var high = 5; high <= 14; high++) {
        final seq = high == 5
            ? const [14, 2, 3, 4, 5]
            : [high - 4, high - 3, high - 2, high - 1, high];
        final picked = <PlayingCard>[];
        var missing = 0;
        for (final r in seq) {
          final card = byRank[r];
          if (card != null) {
            picked.add(card);
          } else {
            missing++;
          }
        }
        if (missing <= wilds.length) {
          final combo = [...picked, ...wilds.take(missing)];
          final all = evaluateAll(combo, currentLevel);
          for (final p in all) {
            if (flushOnly && p.type == GuandanHandType.straightFlush) {
              results.add(p);
              break;
            } else if (!flushOnly && p.type == GuandanHandType.straight) {
              results.add(p);
              break;
            }
          }
        }
      }
    }
    return results;
  }

  static List<GuandanPlay> _generateConsecutiveGroups(
    List<PlayingCard> normals,
    List<PlayingCard> wilds,
    int currentLevel, {
    required int groupCount,
    required int groupSize,
  }) {
    final results = <GuandanPlay>[];
    final byRank = <int, List<PlayingCard>>{};
    for (final c in normals.where((c) => !c.isJoker)) {
      byRank.putIfAbsent(c.rank, () => []).add(c);
    }

    final targetType =
        groupSize == 3 ? GuandanHandType.plate : GuandanHandType.tube;

    for (var high = groupCount; high <= 14; high++) {
      final seq = <int>[];
      for (var i = 0; i < groupCount; i++) {
        final r = high - (groupCount - 1) + i;
        seq.add(r == 1 ? 14 : r);
      }
      final picked = <PlayingCard>[];
      var missing = 0;
      for (final r in seq) {
        final available = byRank[r] ?? const [];
        final take = available.length >= groupSize ? groupSize : available.length;
        picked.addAll(available.take(take));
        missing += groupSize - take;
      }
      if (missing <= wilds.length) {
        final combo = [...picked, ...wilds.take(missing)];
        final all = evaluateAll(combo, currentLevel);
        for (final p in all) {
          if (p.type == targetType) {
            results.add(p);
            break;
          }
        }
      }
    }
    return results;
  }

  static List<GuandanPlay> _generateBombs(
    List<PlayingCard> normals,
    Map<int, List<PlayingCard>> byRank,
    List<PlayingCard> wilds,
    int currentLevel,
  ) {
    final results = <GuandanPlay>[];

    // 4..10 of a kind bombs
    for (final entry in byRank.entries) {
      if (entry.key >= 15) continue;
      final list = entry.value;
      for (var useW = 0; useW <= wilds.length; useW++) {
        final total = list.length + useW;
        if (total >= 4) {
          final combo = [...list, ...wilds.take(useW)];
          final play = evaluateBest(combo, currentLevel);
          if (play != null && play.type == GuandanHandType.bomb) {
            results.add(play);
          }
        }
      }
    }

    // Straight Flushes (bombTier 55)
    results.addAll(_generateStraights(normals, wilds, currentLevel, flushOnly: true));

    // Four Jokers (天王炸)
    final smallJokers = byRank[15] ?? const [];
    final bigJokers = byRank[16] ?? const [];
    if (smallJokers.length == 2 && bigJokers.length == 2) {
      final play = evaluateBest([...bigJokers, ...smallJokers], currentLevel);
      if (play != null) results.add(play);
    }

    return results;
  }

  static List<GuandanPlay> _dedupeAndSortHints(List<GuandanPlay> raw) {
    final seen = <String>{};
    final unique = <GuandanPlay>[];
    for (final p in raw) {
      final key = '${p.type.name}_${p.bombTier}_${p.primaryValue}_${p.length}';
      if (seen.add(key)) {
        unique.add(p);
      }
    }
    // Sort cheapest-first: non-bombs first (by primaryValue asc), then bombs (by bombTier asc, primaryValue asc)
    unique.sort((a, b) {
      if (a.isBomb != b.isBomb) return a.isBomb ? 1 : -1;
      if (a.bombTier != b.bombTier) return a.bombTier.compareTo(b.bombTier);
      return a.primaryValue.compareTo(b.primaryValue);
    });
    return unique;
  }

  static int _rankStrength(int rank, int currentLevel) {
    if (rank == 16) return 170;
    if (rank == 15) return 160;
    if (rank == currentLevel) return 150;
    return rank;
  }
}
