import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_strings.dart';
import '../models/settings_models.dart';
import '../services/api/deepseek_client.dart';

class SettingsProvider extends ChangeNotifier {
  static const _kApiKey = 'chat-demo:api-key';
  static const _kApiOrigin = 'chat-demo:api-origin';
  static const _kModel = 'chat-demo:model';
  static const _kLocale = 'chat-demo:locale';
  static const _kTheme = 'chat-demo:theme-preference';
  static const _kLocation = 'chat-demo:location';
  static const _kTtsVoice = 'chat-demo:tts-voice';
  static const _kThinking = 'chat-demo:thinking';
  static const _kSearch = 'chat-demo:search';

  AppSettings _settings = const AppSettings();
  bool _loaded = false;

  AppSettings get settings => _settings;
  bool get loaded => _loaded;
  bool get hasApiKey =>
      _settings.apiKey != null && _settings.apiKey!.trim().isNotEmpty;
  AppStrings get strings => AppStrings.of(_settings.locale);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final systemLang = ui.PlatformDispatcher.instance.locale.languageCode;
    final defaultLocale = systemLang.startsWith('zh') ? 'zh-CN' : 'en-US';

    UserLocation? location;
    final rawLoc = prefs.getString(_kLocation);
    if (rawLoc != null && rawLoc.isNotEmpty) {
      try {
        location = UserLocation.fromJson(
          jsonDecode(rawLoc) as Map<String, dynamic>,
        );
      } catch (_) {}
    }

    _settings = AppSettings(
      apiKey: prefs.getString(_kApiKey),
      apiOrigin: prefs.getString(_kApiOrigin) ?? AppSettings.defaultApiOrigin,
      model: prefs.getString(_kModel) ?? AppSettings.defaultModel,
      locale: prefs.getString(_kLocale) ?? defaultLocale,
      themePreference: ThemePreference.fromStorage(prefs.getString(_kTheme)),
      location: location,
      ttsVoice: TtsVoice.fromStorage(prefs.getString(_kTtsVoice)),
      thinking: prefs.getBool(_kThinking) ?? false,
      search: prefs.getBool(_kSearch) ?? false,
    );
    _loaded = true;
    notifyListeners();
  }

  DeepSeekClient createClient([String? overrideApiKey]) {
    return DeepSeekClient(
      apiKey: overrideApiKey ?? _settings.apiKey ?? '',
      apiOrigin: _settings.apiOrigin,
    );
  }

  /// Verifies [apiKey] against `GET /models` before persisting.
  Future<void> verifyAndSaveApiKey(String apiKey) async {
    final trimmed = apiKey.trim();
    final client = createClient(trimmed);
    await client.verifyApiKey();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kApiKey, trimmed);
    _settings = _settings.copyWith(apiKey: trimmed);
    notifyListeners();
  }

  Future<void> setApiOrigin(String origin) async {
    final cleaned = origin.trim().replaceAll(RegExp(r'/+$'), '');
    final value = cleaned.isEmpty ? AppSettings.defaultApiOrigin : cleaned;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kApiOrigin, value);
    _settings = _settings.copyWith(apiOrigin: value);
    notifyListeners();
  }

  Future<void> setModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kModel, model);
    _settings = _settings.copyWith(model: model);
    notifyListeners();
  }

  Future<void> setThemePreference(ThemePreference pref) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTheme, pref.storageKey);
    _settings = _settings.copyWith(themePreference: pref);
    notifyListeners();
  }

  Future<void> setLocale(String locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocale, locale);
    _settings = _settings.copyWith(locale: locale);
    notifyListeners();
  }

  Future<void> setTtsVoice(TtsVoice voice) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTtsVoice, voice.apiValue);
    _settings = _settings.copyWith(ttsVoice: voice);
    notifyListeners();
  }

  Future<void> setLocation(UserLocation? location) async {
    final prefs = await SharedPreferences.getInstance();
    if (location == null) {
      await prefs.remove(_kLocation);
      _settings = _settings.copyWith(clearLocation: true);
    } else {
      await prefs.setString(_kLocation, jsonEncode(location.toJson()));
      _settings = _settings.copyWith(location: location);
    }
    notifyListeners();
  }

  Future<void> setThinking(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kThinking, enabled);
    _settings = _settings.copyWith(thinking: enabled);
    notifyListeners();
  }

  Future<void> setSearch(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSearch, enabled);
    _settings = _settings.copyWith(search: enabled);
    notifyListeners();
  }
}
