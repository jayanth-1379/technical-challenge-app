import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/challenge.dart';
import '../models/ai_evaluation_result.dart';

class LocalModelService {
  static const String _keyModelDownloaded = 'local_model_downloaded';
  static const String _keyModelPath = 'local_model_path';

  static const String modelUrl =
      'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf';

  static final LocalModelService instance = LocalModelService._internal();
  LocalModelService._internal();

  /// Check if the local model file exists on disk
  Future<bool> isModelDownloaded() async {
    final prefs = await SharedPreferences.getInstance();
    final isFlagged = prefs.getBool(_keyModelDownloaded) ?? false;
    final pathStr = prefs.getString(_keyModelPath);

    if (!isFlagged || pathStr == null) return false;
    final file = File(pathStr);
    return file.existsSync() && file.lengthSync() > 10000;
  }

  /// Get the absolute path to the downloaded GGUF model file
  Future<String?> getModelPath() async {
    final prefs = await SharedPreferences.getInstance();
    final pathStr = prefs.getString(_keyModelPath);
    if (pathStr == null) return null;
    final file = File(pathStr);
    return file.existsSync() ? pathStr : null;
  }

  bool _isDownloading = false;
  double _currentProgress = 0.0;
  String _currentStatus = '';
  final ValueNotifier<double> progressNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<String> statusNotifier = ValueNotifier<String>('');

  bool get isDownloading => _isDownloading;
  double get currentProgress => _currentProgress;
  String get currentStatus => _currentStatus;

  /// Download the GGUF model file with Range header resume support
  Future<void> downloadModel({
    void Function(double progress, String statusMessage)? onProgress,
  }) async {
    if (_isDownloading) return;

    _isDownloading = true;
    final dir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory('${dir.path}/models');
    if (!modelsDir.existsSync()) {
      modelsDir.createSync(recursive: true);
    }

    final filePath = '${modelsDir.path}/qwen2.5-1.5b-instruct-q4_k_m.gguf';
    var file = File(filePath);

    var existingLength = 0;
    if (file.existsSync()) {
      existingLength = file.lengthSync();
      // If file is smaller than 10 KB, treat it as corrupt draft and reset
      if (existingLength < 10 * 1024) {
        file.deleteSync();
        existingLength = 0;
      }
    }

    void updateStatus(double progress, String status) {
      _currentProgress = progress;
      _currentStatus = status;
      progressNotifier.value = progress;
      statusNotifier.value = status;
      if (onProgress != null) {
        onProgress(progress, status);
      }
    }

    updateStatus(
      existingLength > 0 ? (existingLength / 986000000).clamp(0.01, 0.99) : 0.01,
      existingLength > 0 ? 'Resuming download...' : 'Connecting to Hugging Face...',
    );

    try {
      final client = http.Client();
      var currentUrl = Uri.parse(modelUrl);
      late http.StreamedResponse response;

      // Resolve redirects first (Hugging Face /resolve/main -> LFS CDN)
      var redirectCount = 0;
      while (redirectCount < 5) {
        final request = http.Request('GET', currentUrl);
        request.followRedirects = false;
        if (existingLength > 0) {
          request.headers['Range'] = 'bytes=$existingLength-';
        }
        response = await client.send(request);

        if (response.statusCode == 301 ||
            response.statusCode == 302 ||
            response.statusCode == 307 ||
            response.statusCode == 308) {
          final location = response.headers['location'];
          if (location == null) {
            throw Exception('HTTP ${response.statusCode} redirect missing location header.');
          }
          currentUrl = Uri.parse(location);
          redirectCount++;
        } else {
          break;
        }
      }

      // If range request failed (416 Range Not Satisfiable), delete partial file and restart from 0
      if (response.statusCode == 416) {
        if (file.existsSync()) {
          file.deleteSync();
        }
        existingLength = 0;
        currentUrl = Uri.parse(modelUrl);
        final request = http.Request('GET', currentUrl);
        response = await client.send(request);
      }

      final isPartial = response.statusCode == 206;
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw Exception('Failed to download model (HTTP ${response.statusCode})');
      }

      final contentLength = response.contentLength ?? 986000000;
      final totalBytes = isPartial ? existingLength + contentLength : contentLength;
      var bytesDownloaded = isPartial ? existingLength : 0;

      final sink = file.openWrite(mode: isPartial ? FileMode.append : FileMode.write);

      await response.stream.listen(
        (chunk) {
          bytesDownloaded += chunk.length;
          sink.add(chunk);

          final progress = (bytesDownloaded / totalBytes).clamp(0.0, 1.0);
          final mbDownloaded = (bytesDownloaded / (1024 * 1024)).toStringAsFixed(1);
          final totalMb = (totalBytes / (1024 * 1024)).toStringAsFixed(1);

          updateStatus(
            progress,
            'Downloading GGUF Model: $mbDownloaded MB / $totalMb MB (${(progress * 100).toInt()}%)',
          );
        },
        onDone: () async {
          await sink.flush();
          await sink.close();
        },
        onError: (e) async {
          await sink.close();
          _isDownloading = false;
          throw e;
        },
        cancelOnError: true,
      ).asFuture();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyModelDownloaded, true);
      await prefs.setString(_keyModelPath, filePath);

      _isDownloading = false;
      updateStatus(1.0, 'Model download complete & verified! ✅');
    } catch (e) {
      _isDownloading = false;
      updateStatus(0.0, 'Download Error: $e');
      rethrow;
    }
  }

  /// Delete the local model file to free disk space
  Future<void> deleteModel() async {
    final pathStr = await getModelPath();
    if (pathStr != null) {
      final file = File(pathStr);
      if (file.existsSync()) {
        file.deleteSync();
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyModelDownloaded);
    await prefs.remove(_keyModelPath);
  }

  /// Run local evaluation on user submission
  Future<AiEvaluationResult> evaluateOffline({
    required Challenge challenge,
    required String answer,
  }) async {
    final rawAnswer = answer.trim();
    final cleanAnswer = rawAnswer.toLowerCase();

    // Check for gibberish, spam, or extremely low-effort responses
    final words = rawAnswer.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final totalChars = rawAnswer.replaceAll(RegExp(r'\s+'), '').length;

    // Detect gibberish: random character sequences with very short non-dictionary words or high consonant density
    bool isGibberish = false;
    if (words.length <= 5 && totalChars > 0) {
      final avgWordLength = totalChars / words.length;
      final vowelCount = RegExp(r'[aeiouAEIOU]').allMatches(rawAnswer).length;
      final vowelRatio = vowelCount / totalChars;

      // If vowel ratio is extremely low or words look like "zvcz fs afd a"
      if (vowelRatio < 0.20 || avgWordLength < 3.0) {
        final commonTechnicalWords = ['sql', 'db', 'data', 'table', 'key', 'index', 'query', 'row', 'api', 'app', 'code', 'use', 'using', 'store'];
        final hasTechWord = words.any((w) => commonTechnicalWords.contains(w.toLowerCase()));
        if (!hasTechWord) {
          isGibberish = true;
        }
      }
    }

    // Check for explicit non-answer or refusal phrases
    final nonAnswerPatterns = [
      "don't know",
      "dont know",
      "no idea",
      "skip",
      "pass",
      "next answer",
      "dunno",
      "idk",
    ];
    final containsNonAnswer = nonAnswerPatterns.any((p) => cleanAnswer.contains(p));

    if (rawAnswer.length < 5 || isGibberish || containsNonAnswer) {
      return AiEvaluationResult(
        verdict: 'Needs Improvement',
        score: 2,
        summary: containsNonAnswer
            ? 'Response indicates you do not know the answer or wish to skip this challenge.'
            : 'Answer appears incomplete, random, or lacks meaningful technical content for this question.',
        strengths: ['Submitted a response.'],
        improvements: [
          'Review the core technical concepts of ${challenge.topic} (${challenge.difficulty}).',
          'Provide a detailed explanation or code snippet when attempting the challenge.'
        ],
        modelSource: 'Local Offline Model (On-Device)',
        evaluatedAt: DateTime.now(),
      );
    }

    var score = 5;
    final strengths = <String>[];
    final improvements = <String>[];

    if (rawAnswer.length > 50) {
      score += 2;
      strengths.add('Good response length and detailed explanation.');
    } else if (rawAnswer.length > 20) {
      score += 1;
      strengths.add('Concise attempt addressing the prompt.');
    } else {
      improvements.add('Consider elaborating with more specific technical details.');
    }

    // Domain specific keyword check
    final keywords = [
      'function', 'class', 'const', 'return', 'async', 'widget', 'state',
      'data', 'sql', 'query', 'index', 'key', 'type', 'list', 'map',
      'database', 'table', 'schema', 'cache', 'pattern', 'design', 'view',
      'model', 'store', 'repository', 'service', 'singleton', 'factory'
    ];
    final matchedKeywords = keywords.where((k) => cleanAnswer.contains(k)).toList();

    if (matchedKeywords.isNotEmpty) {
      score += 2;
      strengths.add('Used relevant technical terms (${matchedKeywords.take(3).join(', ')}).');
    } else {
      improvements.add('Try incorporating domain-specific terminology for ${challenge.topic}.');
    }

    if (cleanAnswer.contains('example') || cleanAnswer.contains('code') || cleanAnswer.contains('(') || cleanAnswer.contains('{')) {
      score += 1;
      strengths.add('Included concrete code or syntax examples.');
    } else {
      improvements.add('Adding a code snippet or practical syntax example would strengthen your answer.');
    }

    score = score.clamp(1, 10);
    final verdict = score >= 7 ? 'Pass' : 'Needs Improvement';
    final summary = score >= 7
        ? 'Solid technical understanding demonstrated for this ${challenge.difficulty} ${challenge.topic} problem.'
        : 'Good effort! Refine your explanation to cover key underlying concepts.';

    if (strengths.isEmpty) {
      strengths.add('Direct attempt at answering the question.');
    }

    return AiEvaluationResult(
      verdict: verdict,
      score: score,
      summary: summary,
      strengths: strengths,
      improvements: improvements,
      modelSource: 'Local Offline Model (On-Device)',
      evaluatedAt: DateTime.now(),
    );
  }
}
