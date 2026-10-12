import 'package:shared_preferences/shared_preferences.dart';

class OnboardingService {
  static const String _keyCompletedTour = 'has_completed_onboarding_tour';

  static Future<bool> isFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getBool(_keyCompletedTour) ?? false;
    return !completed;
  }

  static Future<void> markTourCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCompletedTour, true);
  }

  static Future<void> resetTour() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCompletedTour, false);
  }
}
