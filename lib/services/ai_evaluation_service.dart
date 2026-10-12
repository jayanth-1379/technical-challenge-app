import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/challenge.dart';
import '../models/ai_evaluation_result.dart';
import 'ai_preference_service.dart';
import 'local_model_service.dart';
import 'question_generator.dart';

class AiEvaluationService {
  static final AiEvaluationService instance = AiEvaluationService._internal();
  AiEvaluationService._internal();

  /// Evaluate user submission based on active AI preference mode
  Future<AiEvaluationResult?> evaluateSubmission({
    required Challenge challenge,
    required String answer,
  }) async {
    final mode = await AiPreferenceService.instance.getAiMode();
    final apiKey = await AiPreferenceService.instance.getApiKey();

    if (mode == AiMode.none) {
      return null;
    }

    if (mode == AiMode.apiKey) {
      if (apiKey.isEmpty) {
        throw Exception('Cloud API Key is missing. Please configure key in Settings ⚙️.');
      }
      return evaluateCloudApi(
        apiKey: apiKey,
        challenge: challenge,
        answer: answer,
      );
    }

    if (mode == AiMode.offline) {
      return LocalModelService.instance.evaluateOffline(
        challenge: challenge,
        answer: answer,
      );
    }

    return null;
  }

  /// Cloud API Evaluation via Gemini API endpoints (with model fallback)
  Future<AiEvaluationResult> evaluateCloudApi({
    required String apiKey,
    required Challenge challenge,
    required String answer,
  }) async {
    final modelsToTry = [
      'gemini-flash-latest',
      'gemini-2.5-flash',
      'gemini-2.5-flash-lite',
      'gemini-pro-latest',
      'gemini-2.5-pro',
      'gemini-3-flash-preview',
    ];

    final promptText = '''
You are an expert, rigorous technical interviewer evaluating a candidate's answer for a software engineering challenge.

Question Context:
- Topic: ${challenge.topic}
- Difficulty: ${challenge.difficulty}
- Question: "${challenge.question}"

Candidate's Submitted Answer:
"$answer"

EVALUATION RUBRIC & SCORING RULES:
1. Score from 1 to 10:
   - 9–10 (Excellent): Comprehensive, highly accurate, correct technical terminology, covers edge cases/tradeoffs.
   - 7–8 (Good): Mostly accurate and complete, but misses slight nuances, edge cases, or extra depth.
   - 5–6 (Fair / Partial): Contains partial technical truth but has significant gaps, ambiguities, or missing core principles.
   - 3–4 (Weak): Superficial attempt, barely addresses the question, or contains major technical inaccuracies.
   - 1–2 (Fail / Unacceptable): Off-topic, gibberish, empty, refusal ("idk", "pass", "don't know"), or completely wrong.

2. Strict Rules:
   - If candidate answer is under 5 words, says "don't know", "skip", "idk", or is non-technical gibberish -> Score MUST be 1 or 2, Verdict MUST be "Needs Improvement".
   - Evaluate whether the candidate actually answered the SPECIFIC question asked, not just generic statements about ${challenge.topic}.

Return strictly a JSON object formatted as follows (no markdown wrappers):
{
  "score": <integer 1 to 10>,
  "verdict": "<'Pass' for score >= 7 else 'Needs Improvement'>",
  "summary": "<2-3 sentence precise technical breakdown of the answer>",
  "strengths": ["<specific accurate point stated by candidate>", "<another strength if any>"],
  "improvements": ["<specific missing detail or correction needed>", "<another actionable improvement>"]
}
''';

    final bodyJson = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': promptText}
          ]
        }
      ]
    });

    String? textResponse;
    String usedModel = 'Gemini Cloud API';

    for (final model in modelsToTry) {
      try {
        final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
        );

        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: bodyJson,
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          textResponse = data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
          if (textResponse != null && textResponse.trim().isNotEmpty) {
            usedModel = model;
            break;
          }
        }
      } catch (_) {}
    }

    if (textResponse == null || textResponse.trim().isEmpty) {
      // Automatic seamless fallback to offline evaluation if Cloud API is rate-limited or high demand
      return LocalModelService.instance.evaluateOffline(
        challenge: challenge,
        answer: answer,
      );
    }

    // Clean JSON response string from code fencing and surrounding prose if present
    var cleanJsonStr = textResponse.trim();
    if (cleanJsonStr.startsWith('```json')) {
      cleanJsonStr = cleanJsonStr.substring(7);
    }
    if (cleanJsonStr.startsWith('```')) {
      cleanJsonStr = cleanJsonStr.substring(3);
    }
    if (cleanJsonStr.endsWith('```')) {
      cleanJsonStr = cleanJsonStr.substring(0, cleanJsonStr.length - 3);
    }
    cleanJsonStr = cleanJsonStr.trim();

    final firstBrace = cleanJsonStr.indexOf('{');
    final lastBrace = cleanJsonStr.lastIndexOf('}');
    if (firstBrace != -1 && lastBrace != -1 && lastBrace > firstBrace) {
      cleanJsonStr = cleanJsonStr.substring(firstBrace, lastBrace + 1);
    }

    final jsonMap = jsonDecode(cleanJsonStr) as Map<String, dynamic>;

    return AiEvaluationResult(
      verdict: jsonMap['verdict'] as String? ?? 'Pass',
      score: (jsonMap['score'] as num?)?.toInt() ?? 8,
      summary: jsonMap['summary'] as String? ?? 'Good technical response.',
      strengths: (jsonMap['strengths'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      improvements: (jsonMap['improvements'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      modelSource: '$usedModel (Cloud API)',
      evaluatedAt: DateTime.now(),
    );
  }

  /// Dynamically generate a new, unique technical question using the AI Model
  Future<Challenge> generateAiQuestion({
    required List<String> topics,
    required List<String> customTopics,
  }) async {
    final mode = await AiPreferenceService.instance.getAiMode();
    final apiKey = await AiPreferenceService.instance.getApiKey();

    final activeTopics = <String>[];
    for (final t in topics) {
      if (t == 'Others') {
        activeTopics.addAll(customTopics);
      } else if (t != 'All') {
        activeTopics.add(t);
      }
    }
    if (activeTopics.isEmpty) {
      activeTopics.add('Software Engineering & Computer Science');
    }

    final targetTopic = (List<String>.from(activeTopics)..shuffle()).first;

    if (mode == AiMode.apiKey && apiKey.isNotEmpty) {
      final modelsToTry = [
        'gemini-flash-latest',
        'gemini-2.5-flash',
        'gemini-2.5-flash-lite',
        'gemini-pro-latest',
        'gemini-2.5-pro',
        'gemini-3-flash-preview',
      ];

      for (final model in modelsToTry) {
        try {
          final url = Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
          );

          final promptText = '''
You are an expert technical interviewer. Generate 1 new, unique, bite-sized technical interview question for a software engineer.
Target Topic: $targetTopic

Return strictly a JSON object with fields:
{
  "question": "<The question string>",
  "topic": "$targetTopic",
  "difficulty": "<'Easy', 'Medium', or 'Hard'>"
}
Do not include markdown or code block backticks.
''';

          final response = await http.post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': promptText}
                  ]
                }
              ]
            }),
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final rawText = data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
            if (rawText != null && rawText.trim().isNotEmpty) {
              var cleanJsonStr = rawText.trim();
              if (cleanJsonStr.startsWith('```json')) cleanJsonStr = cleanJsonStr.substring(7);
              if (cleanJsonStr.startsWith('```')) cleanJsonStr = cleanJsonStr.substring(3);
              if (cleanJsonStr.endsWith('```')) cleanJsonStr = cleanJsonStr.substring(0, cleanJsonStr.length - 3);

              final map = jsonDecode(cleanJsonStr.trim()) as Map<String, dynamic>;
              final q = map['question'] as String?;
              if (q != null && q.isNotEmpty) {
                return Challenge(
                  question: q,
                  topic: map['topic'] as String? ?? targetTopic,
                  difficulty: map['difficulty'] as String? ?? 'Medium',
                );
              }
            }
          }
        } catch (_) {}
      }
    }

    // Fallback topic-specific question generator
    return QuestionGenerator.instance.generateQuestion(
      topic: targetTopic,
    );
  }
}
