import 'dart:convert';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:party_core/party_core.dart';

/// User-customizable TTS voice settings for the smart in-person moderator.
class VoiceSettings {
  const VoiceSettings({
    this.enabled = true,
    this.hostOnlyBroadcast = true,
    this.speechRate = 0.48,
    this.pitch = 1.0,
    this.volume = 1.0,
    this.voiceName,
    this.voiceLocale,
    this.stylePreset = 'party',
    this.customScripts = const {},
  });

  final bool enabled;

  /// When true, only Host (or Demo device) speaks aloud to prevent echo at the table.
  final bool hostOnlyBroadcast;

  final double speechRate; // 0.30 .. 0.80
  final double pitch; // 0.65 .. 1.45
  final double volume; // 0.20 .. 1.00
  final String? voiceName;
  final String? voiceLocale;
  final String stylePreset; // 'mystery' | 'party' | 'anime' | 'custom'
  final Map<String, String> customScripts;

  static const Map<String, String> defaultScriptLabels = {
    'night_guard': '守卫行动播报',
    'night_wolf': '天黑 · 狼人睁眼播报',
    'night_witch': '女巫睁眼播报',
    'night_seer': '预言家睁眼播报',
    'day_vote': '开启白天投票播报',
  };

  static const Map<String, String> defaultScripts = {
    'night_guard': '天黑请闭眼。守卫请睁眼，请选择今晚要守护的玩家。',
    'night_wolf': '天黑请闭眼。狼人请睁眼，确认队友并选择今晚要袭击的玩家。',
    'night_witch': '狼人请闭眼。女巫请睁眼，请决定是否使用解药或毒药。',
    'night_seer': '女巫请闭眼。预言家请睁眼，请选择今晚要查验的玩家。',
    'day_vote': '发言结束，请各位玩家进行放逐投票。',
  };

  VoiceSettings copyWith({
    bool? enabled,
    bool? hostOnlyBroadcast,
    double? speechRate,
    double? pitch,
    double? volume,
    String? voiceName,
    bool clearVoice = false,
    String? voiceLocale,
    String? stylePreset,
    Map<String, String>? customScripts,
  }) {
    return VoiceSettings(
      enabled: enabled ?? this.enabled,
      hostOnlyBroadcast: hostOnlyBroadcast ?? this.hostOnlyBroadcast,
      speechRate: speechRate ?? this.speechRate,
      pitch: pitch ?? this.pitch,
      volume: volume ?? this.volume,
      voiceName: clearVoice ? null : (voiceName ?? this.voiceName),
      voiceLocale: clearVoice ? null : (voiceLocale ?? this.voiceLocale),
      stylePreset: stylePreset ?? this.stylePreset,
      customScripts: customScripts ?? this.customScripts,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'hostOnlyBroadcast': hostOnlyBroadcast,
        'speechRate': speechRate,
        'pitch': pitch,
        'volume': volume,
        if (voiceName != null) 'voiceName': voiceName,
        if (voiceLocale != null) 'voiceLocale': voiceLocale,
        'stylePreset': stylePreset,
        'customScripts': customScripts,
      };

  String encode() => jsonEncode(toJson());

  factory VoiceSettings.fromJson(Map<String, dynamic> json) => VoiceSettings(
        enabled: json['enabled'] as bool? ?? true,
        hostOnlyBroadcast: json['hostOnlyBroadcast'] as bool? ?? true,
        speechRate: (json['speechRate'] as num?)?.toDouble() ?? 0.48,
        pitch: (json['pitch'] as num?)?.toDouble() ?? 1.0,
        volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
        voiceName: json['voiceName'] as String?,
        voiceLocale: json['voiceLocale'] as String?,
        stylePreset: json['stylePreset'] as String? ?? 'party',
        customScripts: Map<String, String>.from(
          json['customScripts'] as Map? ?? const {},
        ),
      );

  static VoiceSettings decodeOrDefault(String? raw) {
    if (raw == null || raw.isEmpty) return const VoiceSettings();
    try {
      return VoiceSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const VoiceSettings();
    }
  }
}

class DeviceVoiceOption {
  const DeviceVoiceOption({required this.name, required this.locale});
  final String name;
  final String locale;
}

/// Smart Chinese moderator voice narrator supporting custom voice selection,
/// speed/pitch/volume tuning, and custom phase scripts.
class NarratorService {
  NarratorService({bool enabled = true})
      : _settings = VoiceSettings(enabled: enabled);

  final FlutterTts _tts = FlutterTts();
  VoiceSettings _settings;
  bool _initialized = false;

  VoiceSettings get settings => _settings;
  bool get enabled => _settings.enabled;
  set enabled(bool value) {
    _settings = _settings.copyWith(enabled: value);
  }

  Future<void> applySettings(VoiceSettings next) async {
    _settings = next;
    if (!next.enabled) {
      await stop();
      return;
    }
    if (_initialized) {
      await _pushSettingsToEngine();
    }
  }

  Future<void> _ensureInit() async {
    if (_initialized) return;
    _initialized = true;
    await _pushSettingsToEngine();
  }

  Future<void> _pushSettingsToEngine() async {
    try {
      await _tts.setLanguage(_settings.voiceLocale ?? 'zh-CN');
      await _tts.setSpeechRate(_settings.speechRate);
      await _tts.setVolume(_settings.volume);
      await _tts.setPitch(_settings.pitch);
      if (_settings.voiceName != null && _settings.voiceLocale != null) {
        await _tts.setVoice({
          'name': _settings.voiceName!,
          'locale': _settings.voiceLocale!,
        });
      }
    } catch (_) {
      // Safe no-op in widget tests or unsupported platforms.
    }
  }

  Future<List<DeviceVoiceOption>> fetchChineseVoices() async {
    try {
      final raw = await _tts.getVoices;
      if (raw is! List) return const [];
      final options = <DeviceVoiceOption>[];
      final seen = <String>{};
      for (final item in raw) {
        if (item is! Map) continue;
        final name = item['name']?.toString() ?? '';
        final locale = item['locale']?.toString() ?? '';
        if (name.isEmpty || locale.isEmpty) continue;
        final lower = locale.toLowerCase();
        if (lower.startsWith('zh') || lower.contains('cmn') || lower.contains('yue')) {
          final key = '$name|$locale';
          if (seen.add(key)) {
            options.add(DeviceVoiceOption(name: name, locale: locale));
          }
        }
      }
      return options;
    } catch (_) {
      return const [];
    }
  }

  String resolveScriptForEvent(GameEvent event) {
    final key = event.payload['scriptKey'] as String?;
    if (key != null) {
      final custom = _settings.customScripts[key]?.trim();
      if (custom != null && custom.isNotEmpty) {
        return custom;
      }
    }
    return event.narrationText ?? '';
  }

  Future<void> speakEvent(GameEvent event) async {
    final text = resolveScriptForEvent(event);
    if (text.isEmpty) return;
    await speak(text);
  }

  Future<void> speak(String text) async {
    if (!_settings.enabled || text.trim().isEmpty) return;
    await _ensureInit();
    await _pushSettingsToEngine();
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> stop() async {
    if (!_initialized) return;
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
