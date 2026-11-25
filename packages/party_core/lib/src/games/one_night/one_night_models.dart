/// Official roles for PartyBox One Night Ultimate Werewolf (一夜终极狼人).
enum OneNightRole {
  werewolf,
  minion,
  mason,
  seer,
  robber,
  troublemaker,
  drunk,
  insomniac,
  tanner,
  hunter,
  villager;

  String get displayName => switch (this) {
        OneNightRole.werewolf => '狼人',
        OneNightRole.minion => '爪牙',
        OneNightRole.mason => '守夜人',
        OneNightRole.seer => '预言家',
        OneNightRole.robber => '强盗',
        OneNightRole.troublemaker => '捣蛋鬼',
        OneNightRole.drunk => '酒鬼',
        OneNightRole.insomniac => '失眠者',
        OneNightRole.tanner => '皮匠',
        OneNightRole.hunter => '猎人',
        OneNightRole.villager => '村民',
      };

  String get campName => switch (this) {
        OneNightRole.werewolf || OneNightRole.minion => '狼人阵营',
        OneNightRole.tanner => '第三方（皮匠）',
        _ => '好人阵营',
      };

  bool get isWolfTeam =>
      this == OneNightRole.werewolf || this == OneNightRole.minion;

  bool get isGoodTeam => !isWolfTeam && this != OneNightRole.tanner;

  /// Official wake-up sequence order (lower wakes earlier; null means sleeps all night).
  int? get wakeOrder => switch (this) {
        OneNightRole.werewolf => 1,
        OneNightRole.minion => 2,
        OneNightRole.mason => 3,
        OneNightRole.seer => 4,
        OneNightRole.robber => 5,
        OneNightRole.troublemaker => 6,
        OneNightRole.drunk => 7,
        OneNightRole.insomniac => 8,
        OneNightRole.tanner => null,
        OneNightRole.hunter => null,
        OneNightRole.villager => null,
      };

  String get description => switch (this) {
        OneNightRole.werewolf => '夜晚与狼队友互认；若是独狼（其他狼牌在底牌），可偷看 1 张底牌。',
        OneNightRole.minion => '夜晚睁眼得知所有狼人是谁（狼人不知爪牙），帮狼人隐藏即获胜。',
        OneNightRole.mason => '夜晚睁眼确认另一名守夜人是谁，互相验证好人身份。',
        OneNightRole.seer => '夜晚可查看 1 名其他玩家的身份牌，或同时查看 2 张中间底牌。',
        OneNightRole.robber => '夜晚可将自己与 1 名其他玩家的身份牌互换，并查看换来的新身份。',
        OneNightRole.troublemaker => '夜晚可将任意 2 名其他玩家的身份牌盲换（不查看）。',
        OneNightRole.drunk => '夜晚必须将自己的身份牌与 1 张中间底牌互换（不查看新牌）。',
        OneNightRole.insomniac => '夜晚最后醒来，查看自己当前的身份牌确认是否被换过。',
        OneNightRole.tanner => '厌世皮匠：只有自己被投票出局时才获胜！',
        OneNightRole.hunter => '被动技能：若白天被投票出局，你所投票的玩家也会一同出局。',
        OneNightRole.villager => '安稳睡觉，白天依靠大家发言找出真正的狼人！',
      };

  String get wakeNarration => switch (this) {
        OneNightRole.werewolf => '狼人请睁眼，互相确认队友；如果是独狼，可以查看一张底牌。',
        OneNightRole.minion => '狼人请闭眼。爪牙请睁眼，查看场上的狼人。',
        OneNightRole.mason => '守夜人请睁眼，互相确认同伴。',
        OneNightRole.seer => '预言家请睁眼，选择查看一名玩家的牌，或查看两张底牌。',
        OneNightRole.robber => '强盗请睁眼，选择一名玩家交换身份牌并查看你的新身份。',
        OneNightRole.troublemaker => '捣蛋鬼请睁眼，选择两名其他玩家交换他们的身份牌。',
        OneNightRole.drunk => '酒鬼请睁眼，请将你的身份牌与一张中间底牌交换。',
        OneNightRole.insomniac => '失眠者请睁眼，查看你当前的身份牌。',
        _ => '',
      };

  static OneNightRole fromName(String name) => OneNightRole.values.firstWhere(
        (r) => r.name == name,
        orElse: () => OneNightRole.villager,
      );
}

enum OneNightPhase {
  roleReveal,
  nightStep,
  dayDiscuss,
  dayVote,
  gameOver;

  String get displayName => switch (this) {
        OneNightPhase.roleReveal => '查看初始身份',
        OneNightPhase.nightStep => '天黑 · 秘密行动',
        OneNightPhase.dayDiscuss => '天亮 · 限时推理讨论',
        OneNightPhase.dayVote => '全员同步投票',
        OneNightPhase.gameOver => '终局揭晓与复盘',
      };

  static OneNightPhase fromName(String name) => OneNightPhase.values.firstWhere(
        (p) => p.name == name,
        orElse: () => OneNightPhase.roleReveal,
      );
}

/// Configuration for One Night Ultimate Werewolf.
/// Deck size MUST equal `playerCount + 3` (3 center cards).
class OneNightConfig {
  const OneNightConfig({
    required this.presetId,
    required this.roles,
    this.discussSeconds = 300,
  });

  final String presetId;
  final List<OneNightRole> roles;
  final int discussSeconds;

  int get requiredPlayers => roles.length - 3;

  static OneNightConfig preset3() => const OneNightConfig(
        presetId: 'on_3',
        roles: [
          OneNightRole.werewolf,
          OneNightRole.werewolf,
          OneNightRole.seer,
          OneNightRole.robber,
          OneNightRole.troublemaker,
          OneNightRole.villager,
        ],
        discussSeconds: 240,
      );

  static OneNightConfig preset5() => const OneNightConfig(
        presetId: 'on_5',
        roles: [
          OneNightRole.werewolf,
          OneNightRole.werewolf,
          OneNightRole.seer,
          OneNightRole.robber,
          OneNightRole.troublemaker,
          OneNightRole.drunk,
          OneNightRole.insomniac,
          OneNightRole.villager,
        ],
        discussSeconds: 300,
      );

  static OneNightConfig preset7() => const OneNightConfig(
        presetId: 'on_7',
        roles: [
          OneNightRole.werewolf,
          OneNightRole.werewolf,
          OneNightRole.minion,
          OneNightRole.mason,
          OneNightRole.mason,
          OneNightRole.seer,
          OneNightRole.robber,
          OneNightRole.troublemaker,
          OneNightRole.insomniac,
          OneNightRole.tanner,
        ],
        discussSeconds: 360,
      );

  OneNightConfig copyWith({
    String? presetId,
    List<OneNightRole>? roles,
    int? discussSeconds,
  }) {
    return OneNightConfig(
      presetId: presetId ?? this.presetId,
      roles: roles ?? this.roles,
      discussSeconds: discussSeconds ?? this.discussSeconds,
    );
  }

  Map<String, dynamic> toJson() => {
        'presetId': presetId,
        'roles': roles.map((r) => r.name).toList(),
        'discussSeconds': discussSeconds,
      };

  factory OneNightConfig.fromJson(Map<String, dynamic> json) {
    if (json.isEmpty || json['roles'] == null) {
      return OneNightConfig.preset5();
    }
    final rawRoles = (json['roles'] as List).cast<String>();
    return OneNightConfig(
      presetId: json['presetId'] as String? ?? 'custom',
      roles: rawRoles.map(OneNightRole.fromName).toList(),
      discussSeconds: (json['discussSeconds'] as num?)?.toInt() ?? 300,
    );
  }
}

class OneNightPlayerState {
  const OneNightPlayerState({
    required this.playerId,
    required this.name,
    required this.seatNumber,
    required this.initialRole,
    required this.currentRole,
    this.nightNotes = const [],
  });

  final String playerId;
  final String name;
  final int seatNumber;
  final OneNightRole initialRole;
  final OneNightRole currentRole;

  /// Private observations collected by THIS player during their night wake-up.
  final List<String> nightNotes;

  OneNightPlayerState copyWith({
    OneNightRole? currentRole,
    List<String>? nightNotes,
  }) {
    return OneNightPlayerState(
      playerId: playerId,
      name: name,
      seatNumber: seatNumber,
      initialRole: initialRole,
      currentRole: currentRole ?? this.currentRole,
      nightNotes: nightNotes ?? this.nightNotes,
    );
  }
}

class OneNightState {
  const OneNightState({
    required this.config,
    required this.players,
    required this.centerCards,
    required this.phase,
    required this.wakeQueue,
    this.wakeIndex = 0,
    this.confirmedRoleIds = const {},
    this.actedInCurrentStepIds = const {},
    this.isDecoyStep = false,
    this.votes = const {},
    this.eliminatedPlayerIds = const [],
    this.winnerTeam,
    this.winnerSummary = '',
    this.tannerWon = false,
    this.nightReplayLogs = const [],
    this.eventSeq = 0,
  });

  final OneNightConfig config;
  final List<OneNightPlayerState> players;

  /// Always length 3: Center A (0), Center B (1), Center C (2).
  final List<OneNightRole> centerCards;

  final OneNightPhase phase;

  /// Distinct wake-up roles in this game's deck sorted by official wakeOrder.
  final List<OneNightRole> wakeQueue;
  final int wakeIndex;

  final Set<String> confirmedRoleIds;
  final Set<String> actedInCurrentStepIds;
  final bool isDecoyStep;

  /// `voterId -> targetPlayerId`.
  final Map<String, String> votes;

  final List<String> eliminatedPlayerIds;

  /// `'good'`, `'wolf'`, `'tanner'`, or `'good_and_tanner'`.
  final String? winnerTeam;
  final String winnerSummary;
  final bool tannerWon;

  /// Secret night swap & peek log revealed ONLY at gameOver!
  final List<String> nightReplayLogs;
  final int eventSeq;

  OneNightRole? get activeWakeRole =>
      (phase == OneNightPhase.nightStep && wakeIndex < wakeQueue.length)
          ? wakeQueue[wakeIndex]
          : null;

  OneNightPlayerState? playerById(String id) {
    for (final p in players) {
      if (p.playerId == id) return p;
    }
    return null;
  }

  /// Players who started the night with [role] (in ONUW, wake-up is ALWAYS by initialRole!).
  List<OneNightPlayerState> initialRoleHolders(OneNightRole role) =>
      players.where((p) => p.initialRole == role).toList();

  OneNightState copyWith({
    List<OneNightPlayerState>? players,
    List<OneNightRole>? centerCards,
    OneNightPhase? phase,
    List<OneNightRole>? wakeQueue,
    int? wakeIndex,
    Set<String>? confirmedRoleIds,
    Set<String>? actedInCurrentStepIds,
    bool? isDecoyStep,
    Map<String, String>? votes,
    List<String>? eliminatedPlayerIds,
    String? winnerTeam,
    String? winnerSummary,
    bool? tannerWon,
    List<String>? nightReplayLogs,
    int? eventSeq,
  }) {
    return OneNightState(
      config: config,
      players: players ?? this.players,
      centerCards: centerCards ?? this.centerCards,
      phase: phase ?? this.phase,
      wakeQueue: wakeQueue ?? this.wakeQueue,
      wakeIndex: wakeIndex ?? this.wakeIndex,
      confirmedRoleIds: confirmedRoleIds ?? this.confirmedRoleIds,
      actedInCurrentStepIds:
          actedInCurrentStepIds ?? this.actedInCurrentStepIds,
      isDecoyStep: isDecoyStep ?? this.isDecoyStep,
      votes: votes ?? this.votes,
      eliminatedPlayerIds: eliminatedPlayerIds ?? this.eliminatedPlayerIds,
      winnerTeam: winnerTeam ?? this.winnerTeam,
      winnerSummary: winnerSummary ?? this.winnerSummary,
      tannerWon: tannerWon ?? this.tannerWon,
      nightReplayLogs: nightReplayLogs ?? this.nightReplayLogs,
      eventSeq: eventSeq ?? this.eventSeq,
    );
  }
}

class OneNightActionType {
  static const confirmRole = 'confirm_role';
  static const nightAct = 'night_act';
  static const startVote = 'start_vote';
  static const castVote = 'cast_vote';
  static const hostAdvance = 'host_advance';
}
