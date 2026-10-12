import 'package:flutter/material.dart';
import '../models/challenge.dart';
import '../models/challenge_attempt.dart';
import '../models/ai_evaluation_result.dart';
import '../services/database_service.dart';
import '../services/widget_service.dart';
import '../services/ai_preference_service.dart';
import '../services/ai_evaluation_service.dart';
import '../services/topic_preference_service.dart';
import '../services/question_generator.dart';
import '../widgets/settings_modal.dart';
import '../widgets/ai_evaluation_card.dart';
import '../widgets/stacked_notification_toast.dart';

class ChallengeScreen extends StatefulWidget {
  final List<ChallengeAttempt> attempts;
  final GlobalKey? headerKey;
  final GlobalKey? answerKey;

  const ChallengeScreen({
    super.key,
    required this.attempts,
    this.headerKey,
    this.answerKey,
  });

  @override
  State<ChallengeScreen> createState() => _ChallengeScreenState();
}

class _ChallengeScreenState extends State<ChallengeScreen> {
  Challenge? _currentChallenge;
  String _selectedTopic = 'All';
  String _selectedDifficulty = 'All';
  bool _isLoadingQuestion = true;
  String? _generationError;
  bool _errorRequiresSettings = false;

  bool _showAiPostSubmitPrompt = false;
  bool _isEvaluatingAi = false;
  AiEvaluationResult? _aiEvaluationResult;

  final TextEditingController _answerController = TextEditingController();
  bool _isSubmitting = false;

  List<String> _topics = ['All'];

  @override
  void initState() {
    super.initState();
    reloadTopicsAndQuestion();
  }

  Future<void> reloadTopicsAndQuestion() async {
    final preferredTopics =
        await TopicPreferenceService.instance.getPreferredTopics();
    final customTopics =
        await TopicPreferenceService.instance.getCustomTopics();

    final topicsSet = <String>{'All'};
    for (final t in preferredTopics) {
      if (t == 'Others') {
        topicsSet.addAll(customTopics.where((c) => c.trim().isNotEmpty));
      } else {
        topicsSet.add(t);
      }
    }

    if (mounted) {
      setState(() {
        _topics = topicsSet.toList()..sort();
      });
    }

    await _loadQuestion();
  }

  Future<void> _loadQuestion() async {
    setState(() {
      _isLoadingQuestion = true;
      _generationError = null;
      _errorRequiresSettings = false;
      _answerController.clear();
      _aiEvaluationResult = null;
    });

    try {
      final challenge = await QuestionGenerator.instance.generateQuestion(
        topic: _selectedTopic == 'All' ? null : _selectedTopic,
        difficulty: _selectedDifficulty == 'All' ? null : _selectedDifficulty,
      );

      if (mounted) {
        setState(() {
          _currentChallenge = challenge;
          _isLoadingQuestion = false;
        });
        _syncWidgetData(challenge);
      }
    } on QuestionGeneratorException catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingQuestion = false;
          _generationError = e.message;
          _errorRequiresSettings = e.requiresSettings;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingQuestion = false;
          _generationError = 'Failed to generate question: $e';
          _errorRequiresSettings = false;
        });
      }
    }
  }

  void _syncWidgetData(Challenge? challenge) {
    if (challenge != null) {
      WidgetService.updateHomeWidget(challenge);
    }
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  void _onTopicChanged(String? newTopic) {
    if (newTopic == null || newTopic == _selectedTopic) return;
    setState(() {
      _selectedTopic = newTopic;
    });
    _loadQuestion();
  }

  void _onDifficultyChanged(String? newDifficulty) {
    if (newDifficulty == null || newDifficulty == _selectedDifficulty) return;
    setState(() {
      _selectedDifficulty = newDifficulty;
    });
    _loadQuestion();
  }

  void _notify(String message, Color backgroundColor) {
    StackedNotificationToast.of(context)?.showNotification(message, backgroundColor);
  }

  Future<void> _submitAnswer() async {
    if (_isSubmitting || _currentChallenge == null) return;

    final answer = _answerController.text.trim();

    if (answer.isEmpty) {
      _notify('Please enter an answer.', Colors.black87);
      return;
    }

    final current = _currentChallenge!;

    // Check duplicate in memory
    final isInMemoryDuplicate = widget.attempts.any(
      (a) =>
          a.challenge.question == current.question &&
          a.answer.trim().toLowerCase() == answer.toLowerCase(),
    );

    if (isInMemoryDuplicate) {
      _notify('This answer has already been submitted.', Colors.orange);
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      // Check duplicate in database
      final isDatabaseDuplicate = await DatabaseService.instance.hasAnswerForQuestion(
        current.question,
        answer,
      );

      if (isDatabaseDuplicate) {
        if (mounted) {
          _notify('This answer has already been submitted.', Colors.orange);
        }
        return;
      }

      final attempt = ChallengeAttempt(
        challenge: current,
        answer: answer,
        submittedAt: DateTime.now(),
      );

      // Save to database
      final attemptId = await DatabaseService.instance.insertAttempt(attempt);
      final attemptWithId = attempt.copyWith(id: attemptId);

      // Update in-memory list
      setState(() {
        widget.attempts.insert(0, attemptWithId);
      });

      if (mounted) {
        FocusScope.of(context).unfocus();
        _notify('Answer submitted successfully! ✅', Colors.green);

        // Check AI evaluation preference
        final aiMode = await AiPreferenceService.instance.getAiMode();
        final promptOnSubmit =
            await AiPreferenceService.instance.getPromptOnSubmit();

        if (aiMode == AiMode.none) {
          if (promptOnSubmit) {
            setState(() {
              _showAiPostSubmitPrompt = true;
            });
          }
        } else {
          setState(() {
            _isEvaluatingAi = true;
            _aiEvaluationResult = null;
            _showAiPostSubmitPrompt = false;
          });

          try {
            final result =
                await AiEvaluationService.instance.evaluateSubmission(
              challenge: current,
              answer: answer,
            );
            if (mounted && result != null) {
              setState(() {
                _aiEvaluationResult = result;
                _isEvaluatingAi = false;
              });

              // Persist AI Evaluation to DB
              await DatabaseService.instance.updateAttemptEvaluation(
                attemptId,
                result,
              );
              final idx = widget.attempts.indexWhere((a) => a.id == attemptId);
              if (idx != -1) {
                widget.attempts[idx] =
                    widget.attempts[idx].copyWith(evaluation: result);
              }
            }
          } catch (e) {
            if (mounted) {
              setState(() {
                _isEvaluatingAi = false;
              });
              _notify('AI Evaluation Error: $e', Colors.orange);
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        _notify('Error saving answer: $e', Colors.red);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Color _getDifficultyColor(String difficulty) {
    switch (difficulty.toLowerCase()) {
      case 'easy':
        return Colors.green;
      case 'medium':
        return Colors.orange;
      case 'hard':
        return Colors.red;
      default:
        return Colors.blueGrey;
    }
  }

  void _openSettingsModal() {
    SettingsModal.show(
      context,
      onReplayTour: () {},
      onSwitchToCompact: () {},
    ).then((_) => reloadTopicsAndQuestion());
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    final questionSide = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Top Header Row: Topic Filter & Refresh Button
        Column(
          key: widget.headerKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.psychology_rounded,
                        color: Color(0xFF6366F1), size: 24),
                    SizedBox(width: 8),
                    Text(
                      'Technical Challenge',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                FilledButton.icon(
                  onPressed: _isLoadingQuestion ? null : _loadQuestion,
                  icon: _isLoadingQuestion
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Refresh',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _topics.contains(_selectedTopic) ? _selectedTopic : 'All',
                        icon: const Icon(Icons.filter_list, size: 16),
                        onChanged: _onTopicChanged,
                        items: _topics.map((topic) {
                          return DropdownMenuItem<String>(
                            value: topic,
                            child: Text(
                              topic,
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _selectedDifficulty,
                        icon: const Icon(Icons.speed, size: 16),
                        onChanged: _onDifficultyChanged,
                        items: const ['All', 'Easy', 'Medium', 'Hard'].map((diff) {
                          return DropdownMenuItem<String>(
                            value: diff,
                            child: Text(
                              diff == 'All' ? 'Difficulty: All' : diff,
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Body Content: Loading / Error / Question Display
        if (_isLoadingQuestion) ...[
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                SizedBox(width: 14),
                Text(
                  'Generating dynamic AI question...',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ] else if (_generationError != null) ...[
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF2A1B28),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.redAccent.shade100, width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.orangeAccent, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Question Generation Warning',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _generationError!,
                  style: const TextStyle(fontSize: 12, color: Color(0xFFCDD6F4)),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (_errorRequiresSettings)
                      FilledButton.icon(
                        onPressed: _openSettingsModal,
                        icon: const Icon(Icons.settings, size: 14),
                        label: const Text('Configure in Settings ⚙️',
                            style: TextStyle(fontSize: 12)),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: _loadQuestion,
                      icon: const Icon(Icons.refresh, size: 14),
                      label: const Text('Try Again 🔄',
                          style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ] else if (_currentChallenge != null) ...[
          Row(
            children: [
              Chip(
                avatar: const Icon(Icons.tag, size: 14),
                label: Text(_currentChallenge!.topic),
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _getDifficultyColor(_currentChallenge!.difficulty)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _getDifficultyColor(_currentChallenge!.difficulty),
                    width: 1,
                  ),
                ),
                child: Text(
                  _currentChallenge!.difficulty,
                  style: TextStyle(
                    color: _getDifficultyColor(_currentChallenge!.difficulty),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _currentChallenge!.question,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
          ),
        ],
      ],
    );

    final answerSide = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          key: widget.answerKey,
          child: Column(
            children: [
              TextField(
                controller: _answerController,
                maxLines: isLandscape ? 4 : 5,
                enabled: !_isLoadingQuestion && _currentChallenge != null,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Write your answer here...',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.all(14),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: (_isSubmitting || _currentChallenge == null)
                      ? null
                      : _submitAnswer,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Submit Answer',
                          style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
        if (_showAiPostSubmitPrompt) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF181825),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF6366F1), width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '💡 AI CODE FEEDBACK',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.9,
                        color: Color(0xFF89B4FA),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                      onPressed: () {
                        setState(() {
                          _showAiPostSubmitPrompt = false;
                        });
                      },
                    ),
                  ],
                ),
                const Text(
                  'Want instant AI code review on your submissions? Configure a free API Key or Local Model in Settings.',
                  style: TextStyle(fontSize: 12, color: Color(0xFFCDD6F4)),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: () {
                        setState(() {
                          _showAiPostSubmitPrompt = false;
                        });
                        _openSettingsModal();
                      },
                      icon: const Icon(Icons.settings, size: 14),
                      label: const Text('Configure AI in Settings',
                          style: TextStyle(fontSize: 12)),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        minimumSize: const Size(40, 36),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () async {
                        setState(() {
                          _showAiPostSubmitPrompt = false;
                        });
                        await AiPreferenceService.instance
                            .setPromptOnSubmit(false);
                      },
                      child: const Text('Don\'t ask again',
                          style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        if (_isEvaluatingAi) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF181825),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF6366F1), width: 1.2),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF89B4FA),
                  ),
                ),
                SizedBox(width: 14),
                Text(
                  '🧠 Analyzing submission & generating code review...',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFCDD6F4),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_aiEvaluationResult != null && !_isEvaluatingAi) ...[
          AiEvaluationCard(
            evaluation: _aiEvaluationResult!,
            onDismiss: () {
              setState(() {
                _aiEvaluationResult = null;
              });
            },
          ),
        ],
      ],
    );

    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: isLandscape
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: questionSide),
                      const SizedBox(width: 24),
                      Expanded(child: answerSide),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      questionSide,
                      const SizedBox(height: 20),
                      answerSide,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}