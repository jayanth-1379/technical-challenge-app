import 'package:flutter/material.dart';
import '../models/challenge.dart';
import '../services/question_generator.dart';
import '../services/window_service.dart';

class CompactWidgetView extends StatefulWidget {
  final VoidCallback onExpandToFullApp;

  const CompactWidgetView({
    super.key,
    required this.onExpandToFullApp,
  });

  @override
  State<CompactWidgetView> createState() => _CompactWidgetViewState();
}

class _CompactWidgetViewState extends State<CompactWidgetView> {
  Challenge? _currentChallenge;
  bool _isLoading = true;
  bool _isAlwaysOnTop = false;

  @override
  void initState() {
    super.initState();
    _loadDynamicChallenge();
  }

  Future<void> _loadDynamicChallenge() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final challenge = await QuestionGenerator.instance.generateQuestion();
      if (mounted) {
        setState(() {
          _currentChallenge = challenge;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _currentChallenge = const Challenge(
            question: 'What is the difference between synchronous and asynchronous operations in Dart?',
            topic: 'Flutter & Dart',
            difficulty: 'Easy',
          );
          _isLoading = false;
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

  Future<void> _togglePin() async {
    await WindowService.toggleAlwaysOnTop();
    setState(() {
      _isAlwaysOnTop = WindowService.isAlwaysOnTop;
    });
  }

  @override
  Widget build(BuildContext context) {
    final challenge = _currentChallenge;
    final diffColor = challenge != null ? _getDifficultyColor(challenge.difficulty) : Colors.blueGrey;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Compact Challenge'),
        actions: [
          IconButton(
            tooltip: 'Refresh Question',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadDynamicChallenge,
          ),
          IconButton(
            tooltip: _isAlwaysOnTop ? 'Unpin' : 'Pin Always on Top',
            icon: Icon(
              _isAlwaysOnTop ? Icons.push_pin : Icons.push_pin_outlined,
              color: _isAlwaysOnTop ? Colors.indigo : null,
            ),
            onPressed: _togglePin,
          ),
          IconButton(
            tooltip: 'Open Full Workspace',
            icon: const Icon(Icons.open_in_full),
            onPressed: widget.onExpandToFullApp,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _isLoading || challenge == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Chip(
                        avatar: const Icon(Icons.tag, size: 14),
                        label: Text(challenge.topic),
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: diffColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: diffColor, width: 0.8),
                        ),
                        child: Text(
                          challenge.difficulty,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: diffColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Text(
                      challenge.question,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _loadDynamicChallenge,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Refresh'),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: widget.onExpandToFullApp,
                        icon: const Icon(Icons.edit_note, size: 18),
                        label: const Text('Solve'),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}
