import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'models/challenge_attempt.dart';
import 'screens/challenge_screen.dart';
import 'screens/compact_widget_view.dart';
import 'screens/history_screen.dart';
import 'services/database_service.dart';
import 'services/notification_service.dart';
import 'services/onboarding_service.dart';
import 'services/question_generator.dart';
import 'services/widget_service.dart';
import 'services/window_service.dart';
import 'widgets/spotlight_tour.dart';
import 'widgets/settings_modal.dart';
import 'widgets/stacked_notification_toast.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Initialize Desktop Window Manager
  await WindowService.initialize();

  // Initial Sync of today's dynamic challenge to Home Screen AppWidget
  try {
    final initialChallenge = await QuestionGenerator.instance.generateQuestion();
    await WidgetService.updateHomeWidget(initialChallenge);
  } catch (_) {}

  runApp(const TechnicalChallengeApp());
}

class TechnicalChallengeApp extends StatelessWidget {
  const TechnicalChallengeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Technical Challenge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      builder: (context, child) {
        return StackedNotificationToast(
          maxStacked: 3,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const AppRoot(),
    );
  }
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  bool _isCompactMode = false;

  void _switchToCompactMode() {
    WindowService.setCompactMode();
    setState(() {
      _isCompactMode = true;
    });
  }

  void _switchToFullMode() {
    WindowService.setFullMode();
    setState(() {
      _isCompactMode = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isCompactMode && WindowService.isDesktop) {
      return CompactWidgetView(
        onExpandToFullApp: _switchToFullMode,
      );
    }

    return MainShell(
      onSwitchToCompact: _switchToCompactMode,
    );
  }
}

class MainShell extends StatefulWidget {
  final VoidCallback onSwitchToCompact;

  const MainShell({
    super.key,
    required this.onSwitchToCompact,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late final PageController _pageController;
  int _currentIndex = 0;
  final List<ChallengeAttempt> _attempts = [];
  bool _isLoading = true;

  // Onboarding Tour State & Keys
  bool _isTourActive = false;
  int _tourStepIndex = 0;

  final GlobalKey _keyTopNav = GlobalKey();
  final GlobalKey _keyWelcomeCard = GlobalKey();
  final GlobalKey _keyChallengeHeader = GlobalKey();
  final GlobalKey _keyChallengeAnswer = GlobalKey();
  final GlobalKey _keyHistoryList = GlobalKey();

  final GlobalKey<State<ChallengeScreen>> _challengeScreenKey = GlobalKey<State<ChallengeScreen>>();
  late final List<SpotlightStep> _tourSteps;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _initTourSteps();
    _initNotifications();
    _initWidgetNavigation();
    _loadAttemptsAndCheckTour();
  }

  void _initTourSteps() {
    _tourSteps = [
      const SpotlightStep(
        title: 'Welcome Aboard! 👋',
        description:
            'Sharpen your software engineering & coding skills every day with bite-sized technical challenges.',
        targetKey: null, // Pure centered modal without cutout
        tabIndex: 0,
      ),
      SpotlightStep(
        title: 'Curved Navigation & Swipe 👆',
        description:
            'Tap these curved header buttons or swipe left/right across the screen to switch tabs smoothly.',
        targetKey: _keyTopNav,
        tabIndex: 0,
      ),
      SpotlightStep(
        title: 'Android Home-Screen Widget 📱',
        description:
            'Add the Technical Challenge widget to your phone\'s home screen to view daily questions, topic tags, and difficulty badges.',
        targetKey: null, // Pure info modal without highlight cutout
        tabIndex: 0,
        contentWidget: _buildWidgetPreviewSample(),
      ),
      SpotlightStep(
        title: 'Choose AI Learning Engine 🧠',
        description:
            'Choose how your answers are reviewed: Private Local Offline Model, Cloud API Key, or Skip for standard mode. Configure anytime in Settings ⚙️.',
        targetKey: null,
        tabIndex: 0,
        contentWidget: _buildAiOnboardingSample(),
      ),
      SpotlightStep(
        title: 'Write & Submit Answers 🎯',
        description:
            'Type your code or explanation here. Submissions are checked for duplicates and stored in your local database.',
        targetKey: _keyChallengeAnswer,
        tabIndex: 1,
      ),
      SpotlightStep(
        title: 'History & Past Attempts 📜',
        description:
            'Review all your saved past attempts, timestamps, and submitted code anytime.',
        targetKey: _keyHistoryList,
        tabIndex: 2,
      ),
    ];
  }

  Future<void> _loadAttemptsAndCheckTour() async {
    try {
      final savedAttempts = await DatabaseService.instance.getAttempts();
      setState(() {
        _attempts.clear();
        _attempts.addAll(savedAttempts);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }

    // Check if first launch for Guided Onboarding Tour
    final isFirst = await OnboardingService.isFirstLaunch();
    if (isFirst && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startTour();
      });
    }
  }

  void _startTour() {
    setState(() {
      _tourStepIndex = 0;
      _isTourActive = true;
    });
    _syncTourTab(0);
  }

  Future<void> _syncTourTab(int stepIndex) async {
    final step = _tourSteps[stepIndex];
    if (_currentIndex != step.tabIndex) {
      setState(() {
        _currentIndex = step.tabIndex;
      });
      _pageController.animateToPage(
        step.tabIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubic,
      );
      // Wait for page transition & frame render to finish before updating target bounds
      await Future.delayed(const Duration(milliseconds: 340));
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _nextTourStep() async {
    if (_tourStepIndex < _tourSteps.length - 1) {
      final nextIndex = _tourStepIndex + 1;
      await _syncTourTab(nextIndex);
      if (mounted) {
        setState(() {
          _tourStepIndex = nextIndex;
        });
      }
    } else {
      _finishTour();
    }
  }

  Future<void> _prevTourStep() async {
    if (_tourStepIndex > 0) {
      final prevIndex = _tourStepIndex - 1;
      await _syncTourTab(prevIndex);
      if (mounted) {
        setState(() {
          _tourStepIndex = prevIndex;
        });
      }
    }
  }

  void _finishTour() {
    setState(() {
      _isTourActive = false;
      _currentIndex = 0;
    });
    _pageController.animateToPage(
      0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOutCubic,
    );
    OnboardingService.markTourCompleted();
  }

  void _skipTour() {
    setState(() {
      _isTourActive = false;
      _currentIndex = 0;
    });
    _pageController.animateToPage(
      0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOutCubic,
    );
    OnboardingService.markTourCompleted();
  }

  Future<void> _initWidgetNavigation() async {
    WidgetService.setNavigationHandler((target) {
      if (target == 'challenge' && mounted) {
        _navigateToChallengeTab();
      }
    });

    final String? initialTarget = await WidgetService.getInitialTarget();
    if (initialTarget == 'challenge' && mounted) {
      _navigateToChallengeTab();
    }
  }

  Future<void> _initNotifications() async {
    await NotificationService.instance.initialize(
      onNotificationTap: (payload) {
        if (mounted) {
          _navigateToChallengeTab();
        }
      },
    );
  }

  void _navigateToChallengeTab() {
    if (_currentIndex != 1) {
      setState(() {
        _currentIndex = 1;
      });
      _pageController.animateToPage(
        1,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onNavDestinationSelected(int index) {
    setState(() {
      _currentIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOutCubic,
    );
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  Widget _buildTopHeaderNav(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final navItems = [
      {'label': 'Home', 'icon': Icons.home_outlined, 'selectedIcon': Icons.home},
      {'label': 'Challenge', 'icon': Icons.bolt_outlined, 'selectedIcon': Icons.bolt},
      {'label': 'History', 'icon': Icons.history_outlined, 'selectedIcon': Icons.history},
    ];

    return Container(
      key: _keyTopNav,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompactWidth = constraints.maxWidth < 420;
            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isCompactWidth ? 8 : 16,
                vertical: 8,
              ),
              child: Row(
                children: [
                  // Title / Logo
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.code, color: colorScheme.primary),
                        if (!isCompactWidth) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Tech Challenge',
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Spacer(),

                  // Animated Scaled Top Navigation Bar Items
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(navItems.length, (index) {
                  final item = navItems[index];
                  final isSelected = _currentIndex == index;

                  return GestureDetector(
                    onTap: () => _onNavDestinationSelected(index),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                        padding: EdgeInsets.symmetric(
                          horizontal: isSelected ? 14 : 10,
                          vertical: isSelected ? 8 : 6,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colorScheme.primaryContainer
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            AnimatedScale(
                              duration: const Duration(milliseconds: 250),
                              scale: isSelected ? 1.25 : 0.9,
                              child: Icon(
                                isSelected
                                    ? (item['selectedIcon'] as IconData)
                                    : (item['icon'] as IconData),
                                size: 20,
                                color: isSelected
                                    ? colorScheme.onPrimaryContainer
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                            if (isSelected) ...[
                              const SizedBox(width: 6),
                              AnimatedOpacity(
                                duration: const Duration(milliseconds: 200),
                                opacity: isSelected ? 1.0 : 0.0,
                                child: Text(
                                  item['label'] as String,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                      color: colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Application Settings',
                icon: const Icon(Icons.settings_rounded, size: 20),
                onPressed: () {
                  SettingsModal.show(
                    context,
                    onReplayTour: _startTour,
                    onSwitchToCompact: widget.onSwitchToCompact,
                    onSettingsSaved: () {
                      final state = _challengeScreenKey.currentState;
                      if (state != null) {
                        (state as dynamic).reloadTopicsAndQuestion();
                      }
                    },
                  );
                },
              ),
              if (WindowService.isDesktop) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Switch to Compact Widget Mode',
                  icon: const Icon(Icons.picture_in_picture_alt, size: 20),
                  onPressed: widget.onSwitchToCompact,
                ),
              ],
            ],
          ),
        );
      },
    ),
  ),
);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              // 1. Curved Top Navigation Header
              _buildTopHeaderNav(context),

              // 2. Swipeable PageView Body (Touch Tap + Swipe supported)
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: _onPageChanged,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    HomeScreen(
                      welcomeCardKey: _keyWelcomeCard,
                      attempts: _attempts,
                      onSwitchToCompact: widget.onSwitchToCompact,
                      onNavigateToChallenge: _navigateToChallengeTab,
                      onReplayTour: _startTour,
                    ),
                    ChallengeScreen(
                      key: _challengeScreenKey,
                      attempts: _attempts,
                      headerKey: _keyChallengeHeader,
                      answerKey: _keyChallengeAnswer,
                    ),
                    HistoryScreen(
                      attempts: _attempts,
                      onClearHistory: () {
                        setState(() {
                          _attempts.clear();
                        });
                      },
                      listKey: _keyHistoryList,
                    ),
                  ],
                ),
              ),
            ],
          ),

          // 3. Guided Onboarding Spotlight Tour Overlay
          if (_isTourActive)
            SpotlightOverlay(
              steps: _tourSteps,
              currentStepIndex: _tourStepIndex,
              onNext: _nextTourStep,
              onBack: _prevTourStep,
              onSkip: _skipTour,
              onFinish: _finishTour,
            ),
        ],
      ),
    );
  }
}

Widget _buildAiOnboardingSample() {
  return Container(
    margin: const EdgeInsets.only(top: 10, bottom: 4),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF11111B),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFF313244)),
    ),
    child: const Column(
      children: [
        Row(
          children: [
            Text('🤖', style: TextStyle(fontSize: 16)),
            SizedBox(width: 8),
            Text('Local Offline Model',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            Spacer(),
            Text('Private',
                style: TextStyle(
                    fontSize: 10,
                    color: Color(0xFFA6E3A1),
                    fontWeight: FontWeight.bold)),
          ],
        ),
        SizedBox(height: 6),
        Row(
          children: [
            Text('🔑', style: TextStyle(fontSize: 16)),
            SizedBox(width: 8),
            Text('Cloud API Key',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            Spacer(),
            Text('Cloud AI',
                style: TextStyle(
                    fontSize: 10,
                    color: Color(0xFF89B4FA),
                    fontWeight: FontWeight.bold)),
          ],
        ),
        SizedBox(height: 6),
        Row(
          children: [
            Text('⏩', style: TextStyle(fontSize: 16)),
            SizedBox(width: 8),
            Text('Skip for Now',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey)),
            Spacer(),
            Text('Standard',
                style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    ),
  );
}

Widget _buildWidgetPreviewSample() {
  return Container(
    margin: const EdgeInsets.only(top: 12, bottom: 4),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFF11111B),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFF313244), width: 1.2),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Text(
              '⚡ DAILY CHALLENGE WIDGET',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: Color(0xFFA6ADC8),
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2B3D),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF45475A)),
              ),
              child: const Text(
                'Medium',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFAB387),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          '🏷️ Flutter & Dart',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Color(0xFF89B4FA),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Explain the difference between StatelessWidget and StatefulWidget in Flutter.',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFFCDD6F4),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Home Screen AppWidget',
              style: TextStyle(fontSize: 10, color: Color(0xFFA6ADC8)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Answer Now ➔',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

int _calculateStreak(List<ChallengeAttempt> attempts) {
  if (attempts.isEmpty) return 0;

  // Extract unique sorted submitted dates (newest to oldest)
  final Set<String> uniqueDateStrs = {};
  final List<DateTime> dates = [];

  for (final a in attempts) {
    final d = DateTime(a.submittedAt.year, a.submittedAt.month, a.submittedAt.day);
    final dateStr = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    if (uniqueDateStrs.add(dateStr)) {
      dates.add(d);
    }
  }

  if (dates.isEmpty) return 0;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));

  // Check if user solved today or yesterday to maintain active streak
  final firstDate = dates.first;
  if (firstDate != today && firstDate != yesterday) {
    return 0;
  }

  int streak = 1;
  for (int i = 0; i < dates.length - 1; i++) {
    final current = dates[i];
    final next = dates[i + 1];
    final difference = current.difference(next).inDays;

    if (difference == 1) {
      streak++;
    } else if (difference > 1) {
      break; // Streak broken, stop early
    }
  }

  return streak;
}

bool _isTodayCompleted(List<ChallengeAttempt> attempts) {
  final now = DateTime.now();
  return attempts.any((a) =>
      a.submittedAt.year == now.year &&
      a.submittedAt.month == now.month &&
      a.submittedAt.day == now.day);
}

class HomeScreen extends StatelessWidget {
  final GlobalKey welcomeCardKey;
  final List<ChallengeAttempt> attempts;
  final VoidCallback onSwitchToCompact;
  final VoidCallback onNavigateToChallenge;
  final VoidCallback onReplayTour;

  const HomeScreen({
    super.key,
    required this.welcomeCardKey,
    required this.attempts,
    required this.onSwitchToCompact,
    required this.onNavigateToChallenge,
    required this.onReplayTour,
  });

  @override
  Widget build(BuildContext context) {
    final streak = _calculateStreak(attempts);
    final totalSolved = attempts.length;
    final isDoneToday = _isTodayCompleted(attempts);

    final statsRow = Row(
      children: [
        // Streak Card
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2E),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: const Color(0xFFFAB387).withValues(alpha: 0.4),
                  width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('🔥', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 6),
                    Text(
                      'STREAK',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: Colors.amber[200],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '$streak ${streak == 1 ? "Day" : "Days"}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 14),

        // Total Solved Card
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2E),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: const Color(0xFF89B4FA).withValues(alpha: 0.4),
                  width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('🎯', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 6),
                    Text(
                      'ANSWERED',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: Colors.blue[200],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '$totalSolved ${totalSolved == 1 ? "Question" : "Questions"}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    final todayCard = Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF181825),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color:
              isDoneToday ? const Color(0xFFA6E3A1) : const Color(0xFF6366F1),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isDoneToday ? Colors.green : Colors.indigo)
                .withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '⚡ TODAY\'S CHALLENGE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.9,
                  color: Color(0xFFA6ADC8),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isDoneToday
                      ? const Color(0xFF1E3A2B)
                      : const Color(0xFF3B2E1E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDoneToday
                        ? const Color(0xFFA6E3A1)
                        : const Color(0xFFFAB387),
                  ),
                ),
                child: Text(
                  isDoneToday ? '✅ Completed' : '⏳ Pending',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isDoneToday
                        ? const Color(0xFFA6E3A1)
                        : const Color(0xFFFAB387),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            isDoneToday
                ? 'Great job! You completed today\'s technical challenge.'
                : 'Keep your streak alive! Solve today\'s challenge to test your engineering knowledge.',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFFCDD6F4),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: onNavigateToChallenge,
              icon: Icon(
                isDoneToday ? Icons.replay_rounded : Icons.play_arrow_rounded,
                size: 20,
              ),
              label: Text(
                isDoneToday
                    ? 'Continue Practice ➔'
                    : 'Start Today\'s Challenge ➔',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: isDoneToday
                    ? const Color(0xFF2D3142)
                    : const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                statsRow,
                const SizedBox(height: 18),
                todayCard,
              ],
            ),
          ),
        ),
      ),
    );
  }
}