/// Roles available in PartyBox Werewolf v1.
enum WerewolfRole {
  werewolf,
  villager,
  seer,
  witch,
  hunter,
  guard,
  idiot;

  String get displayName => switch (this) {
        WerewolfRole.werewolf => '狼人',
        WerewolfRole.villager => '村民',
        WerewolfRole.seer => '预言家',
        WerewolfRole.witch => '女巫',
        WerewolfRole.hunter => '猎人',
        WerewolfRole.guard => '守卫',
        WerewolfRole.idiot => '白痴',
      };

  String get campName => isWolf ? '狼人阵营' : '好人阵营';

  bool get isWolf => this == WerewolfRole.werewolf;
  bool get isVillager => this == WerewolfRole.villager;
  bool get isGod => !isWolf && !isVillager;

  String get description => switch (this) {
        WerewolfRole.werewolf => '夜晚与狼队友互认并合力击杀一名玩家，白天隐藏身份误导好人。',
        WerewolfRole.villager => '没有特殊技能，依靠白天发言与逻辑推理找出所有狼人。',
        WerewolfRole.seer => '每晚可查验一名存活玩家的阵营（好人或狼人）。',
        WerewolfRole.witch => '拥有一瓶解药与一瓶毒药，每晚最多使用一瓶。',
        WerewolfRole.hunter => '被狼刀或被投票放逐时可开枪带走一名玩家；被女巫毒杀不可开枪。',
        WerewolfRole.guard => '每晚守护一名玩家免受狼人袭击，不可连续两晚守护同一人。',
        WerewolfRole.idiot => '白天被放逐时自动翻牌免死，但永久失去投票权。',
      };

  static WerewolfRole fromName(String name) => WerewolfRole.values.firstWhere(
        (r) => r.name == name,
        orElse: () => WerewolfRole.villager,
      );
}

enum WerewolfWinMode {
  slaughterSide, // 屠边：杀光神职或杀光平民
  slaughterAll; // 屠城：杀光所有好人

  String get displayName => switch (this) {
        WerewolfWinMode.slaughterSide => '屠边局（标准）',
        WerewolfWinMode.slaughterAll => '屠城局',
      };

  static WerewolfWinMode fromName(String name) =>
      WerewolfWinMode.values.firstWhere(
        (m) => m.name == name,
        orElse: () => WerewolfWinMode.slaughterSide,
      );
}

enum WerewolfPhase {
  roleReveal,
  nightGuard,
  nightWolf,
  nightWitch,
  nightSeer,
  sheriffSignup,
  sheriffVote,
  dayAnnounce,
  sheriffBadgeTransfer,
  hunterShoot,
  dayDiscuss,
  dayVote,
  voteResult,
  gameOver;

  String get displayName => switch (this) {
        WerewolfPhase.roleReveal => '查看身份牌',
        WerewolfPhase.nightGuard => '天黑 · 守卫行动',
        WerewolfPhase.nightWolf => '天黑 · 狼人行动',
        WerewolfPhase.nightWitch => '天黑 · 女巫行动',
        WerewolfPhase.nightSeer => '天黑 · 预言家行动',
        WerewolfPhase.sheriffSignup => '警长竞选 · 上警报名',
        WerewolfPhase.sheriffVote => '警长竞选 · 投票',
        WerewolfPhase.dayAnnounce => '天亮了 · 公布昨夜信息',
        WerewolfPhase.sheriffBadgeTransfer => '警长移交警徽',
        WerewolfPhase.hunterShoot => '猎人发动技能',
        WerewolfPhase.dayDiscuss => '白天 · 自由发言',
        WerewolfPhase.dayVote => '白天 · 放逐投票',
        WerewolfPhase.voteResult => '放逐结果',
        WerewolfPhase.gameOver => '游戏结束',
      };

  bool get isNight =>
      this == WerewolfPhase.nightGuard ||
      this == WerewolfPhase.nightWolf ||
      this == WerewolfPhase.nightWitch ||
      this == WerewolfPhase.nightSeer;

  static WerewolfPhase fromName(String name) => WerewolfPhase.values.firstWhere(
        (p) => p.name == name,
        orElse: () => WerewolfPhase.roleReveal,
      );
}

enum DeathReason {
  wolfKill,
  witchPoison,
  dayExile,
  hunterShot;

  String get displayName => switch (this) {
        DeathReason.wolfKill => '昨夜倒牌',
        DeathReason.witchPoison => '昨夜倒牌',
        DeathReason.dayExile => '被投票放逐',
        DeathReason.hunterShot => '被猎人带走',
      };

  String get detailedName => switch (this) {
        DeathReason.wolfKill => '被狼人袭击',
        DeathReason.witchPoison => '被女巫毒杀',
        DeathReason.dayExile => '被投票放逐',
        DeathReason.hunterShot => '被猎人开枪带走',
      };

  static DeathReason fromName(String name) => DeathReason.values.firstWhere(
        (r) => r.name == name,
        orElse: () => DeathReason.wolfKill,
      );
}

/// Board and rule configuration for Werewolf.
class WerewolfConfig {
  const WerewolfConfig({
    required this.presetId,
    required this.roleCounts,
    this.enableSheriff = false,
    this.witchSelfSaveFirstNight = true,
    this.guardAndWitchBothKill = true,
    this.winMode = WerewolfWinMode.slaughterSide,
  });

  final String presetId;
  final Map<WerewolfRole, int> roleCounts;
  final bool enableSheriff;
  final bool witchSelfSaveFirstNight;
  final bool guardAndWitchBothKill;
  final WerewolfWinMode winMode;

  int get totalPlayers =>
      roleCounts.values.fold<int>(0, (sum, count) => sum + count);

  bool hasRole(WerewolfRole role) => (roleCounts[role] ?? 0) > 0;

  static WerewolfConfig preset6() => const WerewolfConfig(
        presetId: 'preset_6',
        roleCounts: {
          WerewolfRole.werewolf: 2,
          WerewolfRole.villager: 2,
          WerewolfRole.seer: 1,
          WerewolfRole.witch: 1,
        },
        enableSheriff: false,
      );

  static WerewolfConfig preset9() => const WerewolfConfig(
        presetId: 'preset_9',
        roleCounts: {
          WerewolfRole.werewolf: 3,
          WerewolfRole.villager: 3,
          WerewolfRole.seer: 1,
          WerewolfRole.witch: 1,
          WerewolfRole.hunter: 1,
        },
        enableSheriff: false,
      );

  static WerewolfConfig preset12Idiot() => const WerewolfConfig(
        presetId: 'preset_12_idiot',
        roleCounts: {
          WerewolfRole.werewolf: 4,
          WerewolfRole.villager: 4,
          WerewolfRole.seer: 1,
          WerewolfRole.witch: 1,
          WerewolfRole.hunter: 1,
          WerewolfRole.idiot: 1,
        },
        enableSheriff: true,
      );

  static WerewolfConfig preset12Guard() => const WerewolfConfig(
        presetId: 'preset_12_guard',
        roleCounts: {
          WerewolfRole.werewolf: 4,
          WerewolfRole.villager: 4,
          WerewolfRole.seer: 1,
          WerewolfRole.witch: 1,
          WerewolfRole.hunter: 1,
          WerewolfRole.guard: 1,
        },
        enableSheriff: true,
      );

  WerewolfConfig copyWith({
    String? presetId,
    Map<WerewolfRole, int>? roleCounts,
    bool? enableSheriff,
    bool? witchSelfSaveFirstNight,
    bool? guardAndWitchBothKill,
    WerewolfWinMode? winMode,
  }) {
    return WerewolfConfig(
      presetId: presetId ?? this.presetId,
      roleCounts: roleCounts ?? this.roleCounts,
      enableSheriff: enableSheriff ?? this.enableSheriff,
      witchSelfSaveFirstNight:
          witchSelfSaveFirstNight ?? this.witchSelfSaveFirstNight,
      guardAndWitchBothKill:
          guardAndWitchBothKill ?? this.guardAndWitchBothKill,
      winMode: winMode ?? this.winMode,
    );
  }

  Map<String, dynamic> toJson() => {
        'presetId': presetId,
        'roleCounts': {
          for (final entry in roleCounts.entries) entry.key.name: entry.value,
        },
        'enableSheriff': enableSheriff,
        'witchSelfSaveFirstNight': witchSelfSaveFirstNight,
        'guardAndWitchBothKill': guardAndWitchBothKill,
        'winMode': winMode.name,
      };

  factory WerewolfConfig.fromJson(Map<String, dynamic> json) {
    if (json.isEmpty || json['roleCounts'] == null) {
      return WerewolfConfig.preset6();
    }
    final rawCounts = Map<String, dynamic>.from(json['roleCounts'] as Map);
    final counts = <WerewolfRole, int>{};
    for (final entry in rawCounts.entries) {
      final value = (entry.value as num).toInt();
      if (value > 0) {
        counts[WerewolfRole.fromName(entry.key)] = value;
      }
    }
    final total = counts.values.fold<int>(0, (s, c) => s + c);
    return WerewolfConfig(
      presetId: json['presetId'] as String? ?? 'custom',
      roleCounts: counts,
      enableSheriff: json['enableSheriff'] as bool? ?? (total >= 12),
      witchSelfSaveFirstNight:
          json['witchSelfSaveFirstNight'] as bool? ?? true,
      guardAndWitchBothKill: json['guardAndWitchBothKill'] as bool? ?? true,
      winMode: WerewolfWinMode.fromName(
        json['winMode'] as String? ?? WerewolfWinMode.slaughterSide.name,
      ),
    );
  }
}

/// Authoritative per-player state inside Werewolf.
class WerewolfPlayerState {
  const WerewolfPlayerState({
    required this.playerId,
    required this.name,
    required this.seatNumber,
    required this.role,
    this.isAlive = true,
    this.deathReason,
    this.deathDay,
    this.idiotRevealed = false,
    this.canVote = true,
  });

  final String playerId;
  final String name;
  final int seatNumber;
  final WerewolfRole role;
  final bool isAlive;
  final DeathReason? deathReason;
  final int? deathDay;
  final bool idiotRevealed;
  final bool canVote;

  WerewolfPlayerState copyWith({
    bool? isAlive,
    DeathReason? deathReason,
    int? deathDay,
    bool? idiotRevealed,
    bool? canVote,
  }) {
    return WerewolfPlayerState(
      playerId: playerId,
      name: name,
      seatNumber: seatNumber,
      role: role,
      isAlive: isAlive ?? this.isAlive,
      deathReason: deathReason ?? this.deathReason,
      deathDay: deathDay ?? this.deathDay,
      idiotRevealed: idiotRevealed ?? this.idiotRevealed,
      canVote: canVote ?? this.canVote,
    );
  }
}

class SeerCheckRecord {
  const SeerCheckRecord({
    required this.night,
    required this.targetId,
    required this.targetSeat,
    required this.targetName,
    required this.isWolf,
  });

  final int night;
  final String targetId;
  final int targetSeat;
  final String targetName;
  final bool isWolf;

  Map<String, dynamic> toJson() => {
        'night': night,
        'targetId': targetId,
        'targetSeat': targetSeat,
        'targetName': targetName,
        'isWolf': isWolf,
      };
}

class GameLogEntry {
  const GameLogEntry({
    required this.day,
    required this.phase,
    required this.summary,
    this.isPublic = false,
  });

  final int day;
  final String phase;
  final String summary;
  final bool isPublic;

  Map<String, dynamic> toJson() => {
        'day': day,
        'phase': phase,
        'summary': summary,
        'isPublic': isPublic,
      };
}

/// Authoritative game state held exclusively by the host or server.
class WerewolfState {
  const WerewolfState({
    required this.config,
    required this.players,
    required this.phase,
    required this.dayNumber,
    this.confirmedRolePlayerIds = const {},
    this.witchAntidoteUsed = false,
    this.witchPoisonUsed = false,
    this.lastNightGuardTargetId,
    this.currentNightGuardTargetId,
    this.wolfSelections = const {},
    this.wolfConfirmedIds = const {},
    this.currentNightWolfTargetId,
    this.currentNightWitchSaved = false,
    this.currentNightWitchPoisonTargetId,
    this.currentNightSeerChecked = false,
    this.seerHistory = const [],
    this.isDecoyNightStep = false,
    this.pendingNightDeaths = const {},
    this.lastAnnouncedDeathIds = const [],
    this.lastAnnouncementText = '',
    this.sheriffId,
    this.sheriffBadgeDestroyed = false,
    this.sheriffSignupDecidedIds = const {},
    this.sheriffCandidates = const {},
    this.sheriffVotes = const {},
    this.sheriffPkRound = 0,
    this.pendingBadgeTransferFromId,
    this.pendingHunterId,
    this.afterSpecialPhase,
    this.dayVotes = const {},
    this.votePkCandidates = const {},
    this.votePkRound = 0,
    this.lastVoteTally = const {},
    this.lastVoteSummary = '',
    this.winnerCamp,
    this.winReason,
    this.logs = const [],
    this.eventSeq = 0,
  });

  final WerewolfConfig config;
  final List<WerewolfPlayerState> players;
  final WerewolfPhase phase;
  final int dayNumber;

  final Set<String> confirmedRolePlayerIds;

  // Witch & Guard persistent state
  final bool witchAntidoteUsed;
  final bool witchPoisonUsed;
  final String? lastNightGuardTargetId;

  // Current night scratchpad
  final String? currentNightGuardTargetId;
  final Map<String, String?> wolfSelections;
  final Set<String> wolfConfirmedIds;
  final String? currentNightWolfTargetId;
  final bool currentNightWitchSaved;
  final String? currentNightWitchPoisonTargetId;
  final bool currentNightSeerChecked;
  final List<SeerCheckRecord> seerHistory;

  /// True when the active night role is already dead and we hold a fake pause
  /// so nearby players cannot deduce deaths by sound/timing.
  final bool isDecoyNightStep;

  /// Deaths computed at end of night, held back until dayAnnounce (after Day 1 sheriff election).
  final Map<String, DeathReason> pendingNightDeaths;
  final List<String> lastAnnouncedDeathIds;
  final String lastAnnouncementText;

  // Sheriff state (12-player default or custom enabled)
  final String? sheriffId;
  final bool sheriffBadgeDestroyed;
  final Set<String> sheriffSignupDecidedIds;
  final Set<String> sheriffCandidates;
  final Map<String, String?> sheriffVotes;
  final int sheriffPkRound;
  final String? pendingBadgeTransferFromId;

  // Hunter state
  final String? pendingHunterId;
  final WerewolfPhase? afterSpecialPhase;

  // Day vote state
  final Map<String, String?> dayVotes;
  final Set<String> votePkCandidates;
  final int votePkRound;
  final Map<String, double> lastVoteTally;
  final String lastVoteSummary;

  // End game
  final String? winnerCamp; // 'good' | 'wolf'
  final String? winReason;
  final List<GameLogEntry> logs;
  final int eventSeq;

  WerewolfPlayerState? playerById(String id) {
    for (final p in players) {
      if (p.playerId == id) return p;
    }
    return null;
  }

  List<WerewolfPlayerState> get alivePlayers =>
      players.where((p) => p.isAlive).toList();

  List<WerewolfPlayerState> aliveWithRole(WerewolfRole role) =>
      players.where((p) => p.isAlive && p.role == role).toList();

  WerewolfState copyWith({
    WerewolfConfig? config,
    List<WerewolfPlayerState>? players,
    WerewolfPhase? phase,
    int? dayNumber,
    Set<String>? confirmedRolePlayerIds,
    bool? witchAntidoteUsed,
    bool? witchPoisonUsed,
    String? lastNightGuardTargetId,
    bool clearLastNightGuardTarget = false,
    String? currentNightGuardTargetId,
    bool clearCurrentNightGuardTarget = false,
    Map<String, String?>? wolfSelections,
    Set<String>? wolfConfirmedIds,
    String? currentNightWolfTargetId,
    bool clearCurrentNightWolfTarget = false,
    bool? currentNightWitchSaved,
    String? currentNightWitchPoisonTargetId,
    bool clearCurrentNightWitchPoisonTarget = false,
    bool? currentNightSeerChecked,
    List<SeerCheckRecord>? seerHistory,
    bool? isDecoyNightStep,
    Map<String, DeathReason>? pendingNightDeaths,
    List<String>? lastAnnouncedDeathIds,
    String? lastAnnouncementText,
    String? sheriffId,
    bool clearSheriffId = false,
    bool? sheriffBadgeDestroyed,
    Set<String>? sheriffSignupDecidedIds,
    Set<String>? sheriffCandidates,
    Map<String, String?>? sheriffVotes,
    int? sheriffPkRound,
    String? pendingBadgeTransferFromId,
    bool clearPendingBadgeTransfer = false,
    String? pendingHunterId,
    bool clearPendingHunter = false,
    WerewolfPhase? afterSpecialPhase,
    bool clearAfterSpecialPhase = false,
    Map<String, String?>? dayVotes,
    Set<String>? votePkCandidates,
    int? votePkRound,
    Map<String, double>? lastVoteTally,
    String? lastVoteSummary,
    String? winnerCamp,
    String? winReason,
    List<GameLogEntry>? logs,
    int? eventSeq,
  }) {
    return WerewolfState(
      config: config ?? this.config,
      players: players ?? this.players,
      phase: phase ?? this.phase,
      dayNumber: dayNumber ?? this.dayNumber,
      confirmedRolePlayerIds:
          confirmedRolePlayerIds ?? this.confirmedRolePlayerIds,
      witchAntidoteUsed: witchAntidoteUsed ?? this.witchAntidoteUsed,
      witchPoisonUsed: witchPoisonUsed ?? this.witchPoisonUsed,
      lastNightGuardTargetId: clearLastNightGuardTarget
          ? null
          : (lastNightGuardTargetId ?? this.lastNightGuardTargetId),
      currentNightGuardTargetId: clearCurrentNightGuardTarget
          ? null
          : (currentNightGuardTargetId ?? this.currentNightGuardTargetId),
      wolfSelections: wolfSelections ?? this.wolfSelections,
      wolfConfirmedIds: wolfConfirmedIds ?? this.wolfConfirmedIds,
      currentNightWolfTargetId: clearCurrentNightWolfTarget
          ? null
          : (currentNightWolfTargetId ?? this.currentNightWolfTargetId),
      currentNightWitchSaved:
          currentNightWitchSaved ?? this.currentNightWitchSaved,
      currentNightWitchPoisonTargetId: clearCurrentNightWitchPoisonTarget
          ? null
          : (currentNightWitchPoisonTargetId ??
              this.currentNightWitchPoisonTargetId),
      currentNightSeerChecked:
          currentNightSeerChecked ?? this.currentNightSeerChecked,
      seerHistory: seerHistory ?? this.seerHistory,
      isDecoyNightStep: isDecoyNightStep ?? this.isDecoyNightStep,
      pendingNightDeaths: pendingNightDeaths ?? this.pendingNightDeaths,
      lastAnnouncedDeathIds:
          lastAnnouncedDeathIds ?? this.lastAnnouncedDeathIds,
      lastAnnouncementText: lastAnnouncementText ?? this.lastAnnouncementText,
      sheriffId: clearSheriffId ? null : (sheriffId ?? this.sheriffId),
      sheriffBadgeDestroyed:
          sheriffBadgeDestroyed ?? this.sheriffBadgeDestroyed,
      sheriffSignupDecidedIds:
          sheriffSignupDecidedIds ?? this.sheriffSignupDecidedIds,
      sheriffCandidates: sheriffCandidates ?? this.sheriffCandidates,
      sheriffVotes: sheriffVotes ?? this.sheriffVotes,
      sheriffPkRound: sheriffPkRound ?? this.sheriffPkRound,
      pendingBadgeTransferFromId: clearPendingBadgeTransfer
          ? null
          : (pendingBadgeTransferFromId ?? this.pendingBadgeTransferFromId),
      pendingHunterId: clearPendingHunter
          ? null
          : (pendingHunterId ?? this.pendingHunterId),
      afterSpecialPhase: clearAfterSpecialPhase
          ? null
          : (afterSpecialPhase ?? this.afterSpecialPhase),
      dayVotes: dayVotes ?? this.dayVotes,
      votePkCandidates: votePkCandidates ?? this.votePkCandidates,
      votePkRound: votePkRound ?? this.votePkRound,
      lastVoteTally: lastVoteTally ?? this.lastVoteTally,
      lastVoteSummary: lastVoteSummary ?? this.lastVoteSummary,
      winnerCamp: winnerCamp ?? this.winnerCamp,
      winReason: winReason ?? this.winReason,
      logs: logs ?? this.logs,
      eventSeq: eventSeq ?? this.eventSeq,
    );
  }
}

/// Action identifiers submitted by clients during Werewolf.
class WerewolfActionType {
  static const confirmRole = 'confirm_role';
  static const guardProtect = 'guard_protect';
  static const wolfSelect = 'wolf_select';
  static const wolfConfirm = 'wolf_confirm';
  static const witchAct = 'witch_act';
  static const seerCheck = 'seer_check';
  static const seerDone = 'seer_done';
  static const sheriffSignup = 'sheriff_signup';
  static const sheriffWithdraw = 'sheriff_withdraw';
  static const sheriffVote = 'sheriff_vote';
  static const sheriffTransfer = 'sheriff_transfer';
  static const hunterShoot = 'hunter_shoot';
  static const dayVote = 'day_vote';
  static const hostAdvance = 'host_advance';
}
