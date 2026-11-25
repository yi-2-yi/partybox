/// Card suits for Guandan (2 standard decks = 108 cards).
enum CardSuit {
  spades,
  hearts,
  clubs,
  diamonds,
  joker;

  String get symbol => switch (this) {
        CardSuit.spades => '♠',
        CardSuit.hearts => '♥',
        CardSuit.clubs => '♣',
        CardSuit.diamonds => '♦',
        CardSuit.joker => '★',
      };

  bool get isRed => this == CardSuit.hearts || this == CardSuit.diamonds;

  static CardSuit fromName(String name) => CardSuit.values.firstWhere(
        (s) => s.name == name,
        orElse: () => CardSuit.spades,
      );
}

/// A single playing card in Guandan.
///
/// [rank] uses:
/// - `2..10`: face number
/// - `11`: J, `12`: Q, `13`: K, `14`: A
/// - `15`: Small Joker (小王)
/// - `16`: Big Joker (大王)
class PlayingCard {
  const PlayingCard({
    required this.id,
    required this.suit,
    required this.rank,
  });

  final String id;
  final CardSuit suit;
  final int rank;

  bool get isJoker => suit == CardSuit.joker || rank >= 15;
  bool get isSmallJoker => rank == 15;
  bool get isBigJoker => rank == 16;

  bool isLevelCard(int currentLevel) => !isJoker && rank == currentLevel;

  /// Heart level card is the Guandan wildcard (逢人配).
  bool isWildcard(int currentLevel) =>
      suit == CardSuit.hearts && rank == currentLevel;

  /// Guandan relative strength for singles/pairs/triples/bombs:
  /// normal 2..14 (excluding level) < level card (150) < Small Joker (160) < Big Joker (170).
  int strength(int currentLevel) {
    if (rank == 16) return 170;
    if (rank == 15) return 160;
    if (rank == currentLevel) return 150;
    return rank;
  }

  String get rankLabel => switch (rank) {
        11 => 'J',
        12 => 'Q',
        13 => 'K',
        14 => 'A',
        15 => '小王',
        16 => '大王',
        _ => '$rank',
      };

  String get shortLabel => isJoker ? rankLabel : '${suit.symbol}$rankLabel';

  Map<String, dynamic> toJson() => {
        'id': id,
        'suit': suit.name,
        'rank': rank,
      };

  factory PlayingCard.fromJson(Map<String, dynamic> json) => PlayingCard(
        id: json['id'] as String,
        suit: CardSuit.fromName(json['suit'] as String),
        rank: (json['rank'] as num).toInt(),
      );

  @override
  bool operator ==(Object other) => other is PlayingCard && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => shortLabel;
}

/// Official Guandan play types.
enum GuandanHandType {
  single,
  pair,
  triple,
  fullHouse,
  straight,
  tube, // 三连对 / 木板 (3 consecutive pairs)
  plate, // 钢板 / 二连三 (2 consecutive triples)
  bomb, // 4..10 of a kind
  straightFlush, // 同花顺 (5 cards same suit consecutive — beats 5-bomb, loses to 6-bomb)
  fourJokers; // 天王炸 (2 Big + 2 Small Jokers — supreme bomb)

  bool get isBomb =>
      this == GuandanHandType.bomb ||
      this == GuandanHandType.straightFlush ||
      this == GuandanHandType.fourJokers;

  String displayName(int cardCount) => switch (this) {
        GuandanHandType.single => '单张',
        GuandanHandType.pair => '对子',
        GuandanHandType.triple => '三张',
        GuandanHandType.fullHouse => '三带二',
        GuandanHandType.straight => '顺子',
        GuandanHandType.tube => '三连对（木板）',
        GuandanHandType.plate => '钢板（二连三）',
        GuandanHandType.bomb => '$cardCount张炸弹',
        GuandanHandType.straightFlush => '同花顺',
        GuandanHandType.fourJokers => '天王炸',
      };

  static GuandanHandType fromName(String name) =>
      GuandanHandType.values.firstWhere(
        (t) => t.name == name,
        orElse: () => GuandanHandType.single,
      );
}

/// Evaluated legal play with normalized comparison keys.
class GuandanPlay {
  const GuandanPlay({
    required this.type,
    required this.cards,
    required this.primaryValue,
    required this.bombTier,
  });

  final GuandanHandType type;
  final List<PlayingCard> cards;

  /// Primary comparison rank within the same type / bomb tier.
  final int primaryValue;

  /// Bomb hierarchy tier (0 = non-bomb):
  /// - 4-bomb: 40
  /// - 5-bomb: 50
  /// - straightFlush: 55 (beats 5-bomb, loses to 6-bomb!)
  /// - 6-bomb: 60, 7-bomb: 70, 8-bomb: 80, 9-bomb: 90, 10-bomb: 100
  /// - fourJokers: 999
  final int bombTier;

  int get length => cards.length;
  bool get isBomb => bombTier > 0;
  String get displayName => type.displayName(cards.length);

  bool beats(GuandanPlay other) {
    if (isBomb && !other.isBomb) return true;
    if (!isBomb && other.isBomb) return false;
    if (isBomb && other.isBomb) {
      if (bombTier != other.bombTier) return bombTier > other.bombTier;
      return primaryValue > other.primaryValue;
    }
    if (type != other.type || length != other.length) return false;
    return primaryValue > other.primaryValue;
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'displayName': displayName,
        'cards': cards.map((c) => c.toJson()).toList(),
        'primaryValue': primaryValue,
        'bombTier': bombTier,
      };

  factory GuandanPlay.fromJson(Map<String, dynamic> json) => GuandanPlay(
        type: GuandanHandType.fromName(json['type'] as String),
        cards: (json['cards'] as List)
            .map((e) => PlayingCard.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        primaryValue: (json['primaryValue'] as num).toInt(),
        bombTier: (json['bombTier'] as num).toInt(),
      );
}

enum GuandanPhase {
  tributePay,
  tributeReturn,
  playing,
  roundOver,
  matchOver;

  String get displayName => switch (this) {
        GuandanPhase.tributePay => '进贡阶段',
        GuandanPhase.tributeReturn => '还贡阶段',
        GuandanPhase.playing => '出牌中',
        GuandanPhase.roundOver => '本局结算',
        GuandanPhase.matchOver => '比赛结束',
      };

  static GuandanPhase fromName(String name) => GuandanPhase.values.firstWhere(
        (p) => p.name == name,
        orElse: () => GuandanPhase.playing,
      );
}

/// Configuration for a Guandan room.
class GuandanConfig {
  const GuandanConfig({
    this.startLevel = 2,
    this.targetLevel = 14, // 14 = A (过 A 夺冠)
    this.enableTribute = true,
  });

  final int startLevel;
  final int targetLevel;
  final bool enableTribute;

  GuandanConfig copyWith({
    int? startLevel,
    int? targetLevel,
    bool? enableTribute,
  }) {
    return GuandanConfig(
      startLevel: startLevel ?? this.startLevel,
      targetLevel: targetLevel ?? this.targetLevel,
      enableTribute: enableTribute ?? this.enableTribute,
    );
  }

  Map<String, dynamic> toJson() => {
        'startLevel': startLevel,
        'targetLevel': targetLevel,
        'enableTribute': enableTribute,
      };

  factory GuandanConfig.fromJson(Map<String, dynamic> json) => GuandanConfig(
        startLevel: (json['startLevel'] as num?)?.toInt() ?? 2,
        targetLevel: (json['targetLevel'] as num?)?.toInt() ?? 14,
        enableTribute: json['enableTribute'] as bool? ?? true,
      );
}

/// Per-player authoritative state in Guandan.
class GuandanPlayerState {
  const GuandanPlayerState({
    required this.playerId,
    required this.name,
    required this.seatNumber, // 1..4; 1&3 are team 0 (Red), 2&4 are team 1 (Blue)
    required this.hand,
    this.finishOrder,
  });

  final String playerId;
  final String name;
  final int seatNumber;
  final List<PlayingCard> hand;

  /// 1 = 头游, 2 = 二游, 3 = 三游, 4 = 末游, null = still playing.
  final int? finishOrder;

  int get teamIndex => (seatNumber - 1) % 2; // 0 = Red (1&3), 1 = Blue (2&4)
  String get teamName => teamIndex == 0 ? '红队' : '蓝队';
  bool get isFinished => finishOrder != null;

  GuandanPlayerState copyWith({
    List<PlayingCard>? hand,
    int? finishOrder,
    bool clearFinishOrder = false,
  }) {
    return GuandanPlayerState(
      playerId: playerId,
      name: name,
      seatNumber: seatNumber,
      hand: hand ?? this.hand,
      finishOrder: clearFinishOrder ? null : (finishOrder ?? this.finishOrder),
    );
  }
}

/// Pending tribute task between two players.
class TributeObligation {
  const TributeObligation({
    required this.fromPlayerId,
    required this.toPlayerId,
    this.tributedCard,
    this.returnedCard,
  });

  final String fromPlayerId;
  final String toPlayerId;
  final PlayingCard? tributedCard;
  final PlayingCard? returnedCard;

  TributeObligation copyWith({
    PlayingCard? tributedCard,
    PlayingCard? returnedCard,
  }) {
    return TributeObligation(
      fromPlayerId: fromPlayerId,
      toPlayerId: toPlayerId,
      tributedCard: tributedCard ?? this.tributedCard,
      returnedCard: returnedCard ?? this.returnedCard,
    );
  }

  Map<String, dynamic> toJson() => {
        'fromPlayerId': fromPlayerId,
        'toPlayerId': toPlayerId,
        if (tributedCard != null) 'tributedCard': tributedCard!.toJson(),
        if (returnedCard != null) 'returnedCard': returnedCard!.toJson(),
      };
}

class GuandanState {
  const GuandanState({
    required this.config,
    required this.players,
    required this.phase,
    required this.roundNumber,
    required this.teamLevels,
    required this.activeTeamIndex,
    required this.currentTurnIndex,
    this.lastPlay,
    this.lastPlayPlayerId,
    this.passedPlayerIds = const {},
    this.lastActionByPlayer = const {},
    this.finishOrderIds = const [],
    this.tributes = const [],
    this.tributeSummary = '',
    this.lastRoundSummary = '',
    this.lastWinningTeam,
    this.lastLevelGain = 0,
    this.matchWinnerTeam,
    this.eventSeq = 0,
  });

  final GuandanConfig config;
  final List<GuandanPlayerState> players; // Always length 4, sorted by seat 1..4
  final GuandanPhase phase;
  final int roundNumber;

  /// `[redLevel, blueLevel]`, values `2..14` (`14 == A`).
  final List<int> teamLevels;

  /// Which team's level is currently the active table level (`0` = Red, `1` = Blue).
  final int activeTeamIndex;

  /// Index in [players] (0..3) whose turn it is to play/pass.
  final int currentTurnIndex;

  final GuandanPlay? lastPlay;
  final String? lastPlayPlayerId;
  final Set<String> passedPlayerIds;

  /// Short visual status displayed beside each seat (e.g. '不要', '顺子', '同花顺').
  final Map<String, String> lastActionByPlayer;

  /// Ordered list of playerIds who have emptied their hands this round.
  final List<String> finishOrderIds;

  // Tribute phase between rounds
  final List<TributeObligation> tributes;
  final String tributeSummary;

  // Round / Match summaries
  final String lastRoundSummary;
  final int? lastWinningTeam;
  final int lastLevelGain;
  final int? matchWinnerTeam;
  final int eventSeq;

  int get currentLevel => teamLevels[activeTeamIndex];

  GuandanPlayerState get currentTurnPlayer => players[currentTurnIndex];

  GuandanPlayerState? playerById(String id) {
    for (final p in players) {
      if (p.playerId == id) return p;
    }
    return null;
  }

  int indexOfPlayer(String id) => players.indexWhere((p) => p.playerId == id);

  static String levelLabel(int level) => switch (level) {
        11 => 'J',
        12 => 'Q',
        13 => 'K',
        14 => 'A',
        _ => '$level',
      };

  GuandanState copyWith({
    GuandanConfig? config,
    List<GuandanPlayerState>? players,
    GuandanPhase? phase,
    int? roundNumber,
    List<int>? teamLevels,
    int? activeTeamIndex,
    int? currentTurnIndex,
    GuandanPlay? lastPlay,
    bool clearLastPlay = false,
    String? lastPlayPlayerId,
    bool clearLastPlayPlayerId = false,
    Set<String>? passedPlayerIds,
    Map<String, String>? lastActionByPlayer,
    List<String>? finishOrderIds,
    List<TributeObligation>? tributes,
    String? tributeSummary,
    String? lastRoundSummary,
    int? lastWinningTeam,
    int? lastLevelGain,
    int? matchWinnerTeam,
    int? eventSeq,
  }) {
    return GuandanState(
      config: config ?? this.config,
      players: players ?? this.players,
      phase: phase ?? this.phase,
      roundNumber: roundNumber ?? this.roundNumber,
      teamLevels: teamLevels ?? this.teamLevels,
      activeTeamIndex: activeTeamIndex ?? this.activeTeamIndex,
      currentTurnIndex: currentTurnIndex ?? this.currentTurnIndex,
      lastPlay: clearLastPlay ? null : (lastPlay ?? this.lastPlay),
      lastPlayPlayerId: clearLastPlayPlayerId
          ? null
          : (lastPlayPlayerId ?? this.lastPlayPlayerId),
      passedPlayerIds: passedPlayerIds ?? this.passedPlayerIds,
      lastActionByPlayer: lastActionByPlayer ?? this.lastActionByPlayer,
      finishOrderIds: finishOrderIds ?? this.finishOrderIds,
      tributes: tributes ?? this.tributes,
      tributeSummary: tributeSummary ?? this.tributeSummary,
      lastRoundSummary: lastRoundSummary ?? this.lastRoundSummary,
      lastWinningTeam: lastWinningTeam ?? this.lastWinningTeam,
      lastLevelGain: lastLevelGain ?? this.lastLevelGain,
      matchWinnerTeam: matchWinnerTeam ?? this.matchWinnerTeam,
      eventSeq: eventSeq ?? this.eventSeq,
    );
  }
}

class GuandanActionType {
  static const playCards = 'play_cards';
  static const passTurn = 'pass_turn';
  static const payTribute = 'pay_tribute';
  static const returnTribute = 'return_tribute';
  static const nextRound = 'next_round';
}
