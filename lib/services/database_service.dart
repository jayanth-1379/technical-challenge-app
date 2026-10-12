import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/challenge.dart';
import '../models/challenge_attempt.dart';
import '../models/ai_evaluation_result.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseService {
  DatabaseService._internal();
  static final DatabaseService instance = DatabaseService._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'technical_challenge.db');

    return openDatabase(
      path,
      version: 2,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE attempts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            question TEXT NOT NULL,
            topic TEXT NOT NULL,
            difficulty TEXT NOT NULL,
            answer TEXT NOT NULL,
            submitted_at TEXT NOT NULL,
            ai_evaluation_json TEXT
          )
        ''');
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try {
            await database.execute(
              'ALTER TABLE attempts ADD COLUMN ai_evaluation_json TEXT',
            );
          } catch (_) {}
        }
      },
    );
  }

  /// Checks if an answer for the same question already exists in the database
  Future<bool> hasAnswerForQuestion(String question, String answer) async {
    final db = await database;
    final results = await db.query(
      'attempts',
      where: 'question = ? AND answer = ?',
      whereArgs: [question, answer],
      limit: 1,
    );
    return results.isNotEmpty;
  }

  /// Insert a new attempt and return its auto-increment ID
  Future<int> insertAttempt(ChallengeAttempt attempt) async {
    final db = await database;

    final id = await db.insert(
      'attempts',
      {
        'question': attempt.challenge.question,
        'topic': attempt.challenge.topic,
        'difficulty': attempt.challenge.difficulty,
        'answer': attempt.answer,
        'submitted_at': attempt.submittedAt.toIso8601String(),
        'ai_evaluation_json': attempt.evaluation != null
            ? jsonEncode(attempt.evaluation!.toJson())
            : null,
      },
    );
    return id;
  }

  /// Update an existing attempt record with its AI evaluation result
  Future<void> updateAttemptEvaluation(
    int id,
    AiEvaluationResult evaluation,
  ) async {
    final db = await database;
    await db.update(
      'attempts',
      {
        'ai_evaluation_json': jsonEncode(evaluation.toJson()),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Fetch attempts with optional limit and offset pagination
  Future<List<ChallengeAttempt>> getAttempts({
    int? limit,
    int? offset,
  }) async {
    final db = await database;

    final List<Map<String, dynamic>> maps = await db.query(
      'attempts',
      orderBy: 'submitted_at DESC',
      limit: limit,
      offset: offset,
    );

    return maps.map((map) {
      AiEvaluationResult? eval;
      final evalJsonStr = map['ai_evaluation_json'] as String?;
      if (evalJsonStr != null && evalJsonStr.trim().isNotEmpty) {
        try {
          final jsonMap = jsonDecode(evalJsonStr) as Map<String, dynamic>;
          eval = AiEvaluationResult.fromJson(jsonMap);
        } catch (_) {}
      }

      return ChallengeAttempt(
        id: map['id'] as int?,
        challenge: Challenge(
          question: map['question'] as String,
          topic: map['topic'] as String,
          difficulty: map['difficulty'] as String,
        ),
        answer: map['answer'] as String,
        submittedAt: DateTime.parse(map['submitted_at'] as String),
        evaluation: eval,
      );
    }).toList();
  }

  /// Get total count of attempts efficiently without decoding full rows
  Future<int> getAttemptsCount() async {
    final db = await database;
    final res = await db.rawQuery('SELECT COUNT(*) as count FROM attempts');
    if (res.isNotEmpty) {
      return (res.first['count'] as num?)?.toInt() ?? 0;
    }
    return 0;
  }

  /// Clear all past challenge attempts from SQLite database
  Future<void> clearAllAttempts() async {
    final db = await database;
    await db.delete('attempts');
  }
}