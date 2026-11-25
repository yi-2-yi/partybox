import 'dart:math';

import '../../engine/game_plugin.dart';
import '../../models/room_models.dart';
import 'werewolf_engine.dart';
import 'werewolf_models.dart';

/// Adapts [WerewolfEngine] to PartyBox's multi-game [GamePlugin] interface.
class WerewolfPlugin extends GamePlugin<WerewolfState> {
  WerewolfPlugin({Random? random}) : _engine = WerewolfEngine(random: random);

  final WerewolfEngine _engine;

  @override
  GameType get gameType => GameType.werewolf;

  @override
  int get minPlayers => 6;

  @override
  int get maxPlayers => 16;

  @override
  Map<String, dynamic> defaultConfig() => WerewolfConfig.preset6().toJson();

  @override
  String? validateStart(List<PlayerInfo> players, Map<String, dynamic> config) {
    return _engine.validateStart(players, WerewolfConfig.fromJson(config));
  }

  @override
  GameTransition<WerewolfState> initGame(
    List<PlayerInfo> players,
    Map<String, dynamic> config,
  ) {
    return _engine.initGame(players, WerewolfConfig.fromJson(config));
  }

  @override
  GameTransition<WerewolfState> handleAction(
    WerewolfState state,
    String playerId,
    String actionType,
    Map<String, dynamic> payload, {
    required String hostId,
  }) {
    return _engine.handleAction(
      state,
      playerId,
      actionType,
      payload,
      hostId: hostId,
    );
  }

  @override
  Map<String, dynamic> projectStateForPlayer(
    WerewolfState state,
    String playerId,
  ) {
    return _engine.projectStateForPlayer(state, playerId);
  }
}
