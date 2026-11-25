/// Represents a PartyBox room discovered over the local Wi-Fi or mobile hotspot.
class DiscoveredLanRoom {
  const DiscoveredLanRoom({
    required this.roomCode,
    required this.hostName,
    required this.ip,
    required this.port,
    required this.gameName,
    required this.playerCount,
    required this.maxPlayers,
    required this.lastSeen,
  });

  final String roomCode;
  final String hostName;
  final String ip;
  final int port;
  final String gameName;
  final int playerCount;
  final int maxPlayers;
  final DateTime lastSeen;

  String get wsUrl => 'ws://$ip:$port/ws';

  String get key => '$ip:$port';
}
