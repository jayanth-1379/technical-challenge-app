import 'package:shared_preferences/shared_preferences.dart';

enum AiMode {
  none,
  offline,
  apiKey,
}

class AiPreferenceService {
  static const String _keyAiMode = 'ai_preference_mode';
  static const String _keyApiKey = 'ai_preference_api_key';
  static const String _keyPromptOnSubmit = 'ai_prompt_on_submit';

  static final AiPreferenceService instance = AiPreferenceService._internal();
  AiPreferenceService._internal();

  /// Retrieve the active AI mode from SharedPreferences
  Future<AiMode> getAiMode() async {
    final prefs = await SharedPreferences.getInstance();
    final modeStr = prefs.getString(_keyAiMode);

    switch (modeStr) {
      case 'offline':
        return AiMode.offline;
      case 'apiKey':
        return AiMode.apiKey;
      case 'none':
      default:
        return AiMode.none;
    }
  }

  /// Save the active AI mode
  Future<void> setAiMode(AiMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAiMode, mode.name);
  }

  /// Retrieve the user-configured API key
  Future<String> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyApiKey) ?? '';
  }

  /// Save the user-configured API key
  Future<void> setApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiKey, key.trim());
  }

  /// Retrieve whether to prompt user after submitting answer if AI mode is none
  Future<bool> getPromptOnSubmit() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyPromptOnSubmit) ?? true;
  }

  /// Save whether to prompt user after submit
  Future<void> setPromptOnSubmit(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyPromptOnSubmit, enabled);
  }
}
