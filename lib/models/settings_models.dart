import 'package:flutter/material.dart';

enum ThemePreference {
  light,
  dark,
  system;

  String get storageKey => name;

  static ThemePreference fromStorage(String? value) {
    switch (value) {
      case 'light':
        return ThemePreference.light;
      case 'dark':
        return ThemePreference.dark;
      default:
        return ThemePreference.system;
    }
  }

  ThemeMode get themeMode {
    switch (this) {
      case ThemePreference.light:
        return ThemeMode.light;
      case ThemePreference.dark:
        return ThemeMode.dark;
      case ThemePreference.system:
        return ThemeMode.system;
    }
  }
}

enum TtsVoice {
  stella,
  tide;

  String get apiValue => name;

  static TtsVoice fromStorage(String? value) {
    return value == 'tide' ? TtsVoice.tide : TtsVoice.stella;
  }
}

class UserLocation {
  final String region;
  final String? province;
  final String? city;

  const UserLocation({
    required this.region,
    this.province,
    this.city,
  });

  Map<String, dynamic> toJson() => {
        'region': region,
        if (province != null) 'province': province,
        if (city != null) 'city': city,
      };

  factory UserLocation.fromJson(Map<String, dynamic> json) {
    return UserLocation(
      region: json['region'] as String? ?? 'CN',
      province: json['province'] as String?,
      city: json['city'] as String?,
    );
  }
}

class AppSettings {
  static const String defaultApiOrigin = 'https://api.deepseek.com';
  static const String defaultModel = 'deepseek-flash';
  static const List<String> availableModels = [
    'deepseek-flash',
    'deepseek-v4-pro',
  ];

  final String? apiKey;
  final String apiOrigin;
  final String model;
  final String locale; // 'zh-CN' | 'en-US'
  final ThemePreference themePreference;
  final UserLocation? location;
  final TtsVoice ttsVoice;
  final bool thinking;
  final bool search;

  const AppSettings({
    this.apiKey,
    this.apiOrigin = defaultApiOrigin,
    this.model = defaultModel,
    this.locale = 'zh-CN',
    this.themePreference = ThemePreference.system,
    this.location,
    this.ttsVoice = TtsVoice.stella,
    this.thinking = false,
    this.search = false,
  });

  AppSettings copyWith({
    String? apiKey,
    bool clearApiKey = false,
    String? apiOrigin,
    String? model,
    String? locale,
    ThemePreference? themePreference,
    UserLocation? location,
    bool clearLocation = false,
    TtsVoice? ttsVoice,
    bool? thinking,
    bool? search,
  }) {
    return AppSettings(
      apiKey: clearApiKey ? null : (apiKey ?? this.apiKey),
      apiOrigin: apiOrigin ?? this.apiOrigin,
      model: model ?? this.model,
      locale: locale ?? this.locale,
      themePreference: themePreference ?? this.themePreference,
      location: clearLocation ? null : (location ?? this.location),
      ttsVoice: ttsVoice ?? this.ttsVoice,
      thinking: thinking ?? this.thinking,
      search: search ?? this.search,
    );
  }
}
