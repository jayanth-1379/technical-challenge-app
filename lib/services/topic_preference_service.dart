import 'package:shared_preferences/shared_preferences.dart';

class TopicPreferenceService {
  static const String _keyPreferredTopics = 'user_preferred_topics';
  static const String _keyCustomTopicsList = 'user_custom_topics_list';

  static const List<String> defaultTopics = [
    'DevOps',
    'Python',
    'JavaScript',
    'Databases',
    'Flutter & Dart',
    'Algorithms',
    'System Design',
    'General CS',
    'Others',
  ];

  static final TopicPreferenceService instance =
      TopicPreferenceService._internal();
  TopicPreferenceService._internal();

  /// Retrieve the user's selected preferred topics
  Future<List<String>> getPreferredTopics() async {
    final prefs = await SharedPreferences.getInstance();
    final topics = prefs.getStringList(_keyPreferredTopics);
    if (topics == null || topics.isEmpty) {
      return List<String>.from(defaultTopics);
    }
    return topics;
  }

  /// Save the user's preferred topics
  Future<void> setPreferredTopics(List<String> topics) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyPreferredTopics, topics);
  }

  /// Retrieve the list of custom topics added by the user
  Future<List<String>> getCustomTopics() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyCustomTopicsList) ?? [];
  }

  /// Add a new custom topic
  Future<void> addCustomTopic(String topic) async {
    final clean = topic.trim();
    if (clean.isEmpty) return;
    final current = await getCustomTopics();
    if (!current.contains(clean)) {
      current.add(clean);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_keyCustomTopicsList, current);
    }
  }

  /// Remove a custom topic
  Future<void> removeCustomTopic(String topic) async {
    final current = await getCustomTopics();
    current.remove(topic);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyCustomTopicsList, current);
  }
}
