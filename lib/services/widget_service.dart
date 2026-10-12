import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/challenge.dart';

class WidgetService {
  static const MethodChannel _channel =
      MethodChannel('com.example.technical_challenge_test/widget');

  static Future<void> updateHomeWidget(Challenge challenge) async {
    if (kIsWeb || !Platform.isAndroid) return;

    try {
      await _channel.invokeMethod('updateWidget', {
        'question': challenge.question,
        'topic': challenge.topic,
        'difficulty': challenge.difficulty,
      });
    } catch (e) {
      debugPrint('Error updating home widget via MethodChannel: $e');
    }
  }

  static Future<String?> getInitialTarget() async {
    if (kIsWeb || !Platform.isAndroid) return null;

    try {
      final String? target = await _channel.invokeMethod<String>('getInitialTarget');
      return target;
    } catch (e) {
      debugPrint('Error getting initial widget target: $e');
      return null;
    }
  }

  static void setNavigationHandler(void Function(String target) onNavigate) {
    if (kIsWeb || !Platform.isAndroid) return;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'navigateTo') {
        final String? target = call.arguments as String?;
        if (target != null) {
          onNavigate(target);
        }
      }
    });
  }
}
