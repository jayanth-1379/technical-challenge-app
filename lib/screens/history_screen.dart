import 'package:flutter/material.dart';
import '../models/challenge_attempt.dart';
import '../services/database_service.dart';
import '../widgets/ai_evaluation_card.dart';

class HistoryScreen extends StatefulWidget {
  final List<ChallengeAttempt> attempts;
  final VoidCallback? onClearHistory;
  final GlobalKey? listKey;

  const HistoryScreen({
    super.key,
    required this.attempts,
    this.onClearHistory,
    this.listKey,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _selectedTopic = 'All';

  Future<void> _confirmClearHistory(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All History?'),
        content: const Text(
          'Are you sure you want to delete all past challenge attempts? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DatabaseService.instance.clearAllAttempts();
      if (widget.onClearHistory != null) {
        widget.onClearHistory!();
      }
    }
  }

  List<String> get _topics {
    final topicsSet = widget.attempts.map((a) => a.challenge.topic).toSet().toList();
    topicsSet.sort();
    return ['All', ...topicsSet];
  }

  List<ChallengeAttempt> get _filteredAttempts {
    if (_selectedTopic == 'All') {
      return widget.attempts;
    }
    return widget.attempts.where((a) => a.challenge.topic == _selectedTopic).toList();
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

  String _formatDateTime(DateTime dt) {
    final year = dt.year;
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  void _showAttemptDetails(BuildContext context, ChallengeAttempt attempt) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final diffColor = _getDifficultyColor(attempt.challenge.difficulty);

        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: ListView(
                controller: scrollController,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Topic, Difficulty and Date
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Chip(
                        avatar: const Icon(Icons.tag, size: 14),
                        label: Text(attempt.challenge.topic),
                        visualDensity: VisualDensity.compact,
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: diffColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: diffColor),
                        ),
                        child: Text(
                          attempt.challenge.difficulty,
                          style: TextStyle(
                            color: diffColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Submitted: ${_formatDateTime(attempt.submittedAt)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                  const Divider(height: 24),

                  // Question Title
                  Text(
                    'Question',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    attempt.challenge.question,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 20),

                  // Full Answer
                  Text(
                    'Your Answer',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: SelectableText(
                      attempt.answer,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
                    ),
                  ),
                  if (attempt.evaluation != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      'AI Model Review & Feedback',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    AiEvaluationCard(
                      evaluation: attempt.evaluation!,
                      onDismiss: () {},
                    ),
                  ],
                  const SizedBox(height: 20),

                  // Close button
                  FilledButton.tonal(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredAttempts;
    final availableTopics = _topics;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Filter Bar placed cleanly at the top if topics exist
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 20, top: 12, bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Past Submissions',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                  Row(
                    children: [
                      if (availableTopics.length > 1)
                        DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: availableTopics.contains(_selectedTopic) ? _selectedTopic : 'All',
                            icon: const Icon(Icons.filter_list, size: 20),
                            onChanged: (newTopic) {
                              if (newTopic != null) {
                                setState(() {
                                  _selectedTopic = newTopic;
                                });
                              }
                            },
                            items: availableTopics.map((topic) {
                              return DropdownMenuItem<String>(
                                value: topic,
                                child: Text(topic, style: const TextStyle(fontSize: 13)),
                              );
                            }).toList(),
                          ),
                        ),
                      if (widget.attempts.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () => _confirmClearHistory(context),
                          icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 22),
                          tooltip: 'Clear All History',
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              key: widget.listKey,
              child: widget.attempts.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history_toggle_off, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'No challenges answered yet.',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : filtered.isEmpty
                      ? Center(
                          child: Text('No attempts found for topic: $_selectedTopic'),
                        )
                      : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            itemCount: filtered.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final attempt = filtered[index];
                              final diffColor = _getDifficultyColor(attempt.challenge.difficulty);

                              return Card(
                                elevation: 1,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
                                  ),
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => _showAttemptDetails(context, attempt),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Header: Topic chip, Difficulty Badge, and Date
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                attempt.challenge.topic,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: diffColor.withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: diffColor, width: 0.8),
                                              ),
                                              child: Text(
                                                attempt.challenge.difficulty,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: diffColor,
                                                ),
                                              ),
                                            ),
                                            const Spacer(),
                                            Text(
                                              _formatDateTime(attempt.submittedAt),
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),

                                        // Question Text
                                        Text(
                                          attempt.challenge.question,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 8),

                                        // Answer Preview
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Icon(Icons.subdirectory_arrow_right, size: 16, color: Colors.grey),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                attempt.answer,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey[800],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
            ),
          ],
        ),
      ),
    );
  }
}
