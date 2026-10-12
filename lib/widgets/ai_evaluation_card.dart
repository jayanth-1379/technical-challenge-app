import 'package:flutter/material.dart';
import '../models/ai_evaluation_result.dart';

class AiEvaluationCard extends StatelessWidget {
  final AiEvaluationResult evaluation;
  final VoidCallback onDismiss;

  const AiEvaluationCard({
    super.key,
    required this.evaluation,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isPass = evaluation.verdict.toLowerCase().contains('pass');
    final verdictColor = isPass ? const Color(0xFFA6E3A1) : const Color(0xFFFAB387);
    final verdictBg = isPass ? const Color(0xFF1E3A2B) : const Color(0xFF3B2E1E);

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF181825),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: verdictColor.withValues(alpha: 0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: verdictColor.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text('🧠', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Text(
                    evaluation.modelSource,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: Color(0xFF89B4FA),
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                onPressed: onDismiss,
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Score & Verdict Row
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF45475A)),
                ),
                child: Row(
                  children: [
                    const Text('🎯 Score: ',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(
                      '${evaluation.score}/10',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: verdictBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: verdictColor),
                ),
                child: Text(
                  evaluation.verdict,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: verdictColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Summary
          if (evaluation.summary.isNotEmpty) ...[
            Text(
              evaluation.summary,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFFCDD6F4),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Strengths Section
          if (evaluation.strengths.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF11111B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFFA6E3A1).withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '✅ WHAT WENT WELL',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: Color(0xFFA6E3A1),
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...evaluation.strengths.map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• ',
                              style: TextStyle(color: Color(0xFFA6E3A1))),
                          Expanded(
                            child: Text(
                              s,
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFFCDD6F4)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Improvements Section
          if (evaluation.improvements.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF11111B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFFFAB387).withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '💡 SUGGESTED IMPROVEMENTS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: Color(0xFFFAB387),
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...evaluation.improvements.map(
                    (imp) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• ',
                              style: TextStyle(color: Color(0xFFFAB387))),
                          Expanded(
                            child: Text(
                              imp,
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFFCDD6F4)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
