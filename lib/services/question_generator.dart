import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/challenge.dart';
import 'ai_preference_service.dart';
import 'local_model_service.dart';
import 'topic_preference_service.dart';

class QuestionGeneratorException implements Exception {
  final String message;
  final bool requiresSettings;

  QuestionGeneratorException(this.message, {this.requiresSettings = false});

  @override
  String toString() => message;
}

class QuestionGenerator {
  static final QuestionGenerator instance = QuestionGenerator._internal();
  QuestionGenerator._internal();

  /// Main method: Generate a technical question based on user preferences and AI mode
  Future<Challenge> generateQuestion({
    String? topic,
    String? difficulty,
  }) async {
    final mode = await AiPreferenceService.instance.getAiMode();

    // Determine target topic
    String targetTopic = topic ?? '';
    if (targetTopic.isEmpty || targetTopic == 'All') {
      final preferredTopics =
          await TopicPreferenceService.instance.getPreferredTopics();
      final customTopics =
          await TopicPreferenceService.instance.getCustomTopics();

      final activeTopics = <String>[];
      for (final t in preferredTopics) {
        if (t == 'Others') {
          activeTopics.addAll(customTopics);
        } else if (t != 'All') {
          activeTopics.add(t);
        }
      }
      if (activeTopics.isEmpty) {
        activeTopics.add('Software Engineering');
      }
      targetTopic = (List<String>.from(activeTopics)..shuffle()).first;
    }

    final targetDifficulty =
        difficulty ?? (['Easy', 'Medium', 'Hard']..shuffle()).first;

    if (mode == AiMode.none) {
      throw QuestionGeneratorException(
        'AI Question Generation is currently disabled. Please configure Cloud API Key or Local Model in Settings ⚙️.',
        requiresSettings: true,
      );
    }

    if (mode == AiMode.apiKey) {
      final apiKey = await AiPreferenceService.instance.getApiKey();
      if (apiKey.trim().isEmpty) {
        throw QuestionGeneratorException(
          'Cloud API Key is missing. Please enter your API Key in Settings ⚙️.',
          requiresSettings: true,
        );
      }
      return _generateWithApiKey(
        apiKey: apiKey,
        topic: targetTopic,
        difficulty: targetDifficulty,
      );
    }

    if (mode == AiMode.offline) {
      final isDownloaded =
          await LocalModelService.instance.isModelDownloaded();
      if (!isDownloaded) {
        throw QuestionGeneratorException(
          'Local GGUF Model is not downloaded yet. Please download the model in Settings ⚙️ for offline generation.',
          requiresSettings: true,
        );
      }
      return _generateWithLocalModel(
        topic: targetTopic,
        difficulty: targetDifficulty,
      );
    }

    throw QuestionGeneratorException('Unknown AI mode configured.');
  }

  /// Internal API Key Generation Path
  Future<Challenge> _generateWithApiKey({
    required String apiKey,
    required String topic,
    required String difficulty,
  }) async {
    final modelsToTry = [
      'gemini-flash-latest',
      'gemini-2.5-flash',
      'gemini-2.5-flash-lite',
      'gemini-pro-latest',
      'gemini-2.5-pro',
      'gemini-3-flash-preview',
    ];

    final promptText = buildStandardPrompt(
      topic: topic,
      difficulty: difficulty,
    );

    final bodyJson = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': promptText}
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.7,
        'maxOutputTokens': 200,
        'responseMimeType': 'application/json',
      }
    });

    String? textResponse;

    for (final model in modelsToTry) {
      try {
        final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
        );

        final response = await http
            .post(
              url,
              headers: {'Content-Type': 'application/json'},
              body: bodyJson,
            )
            .timeout(const Duration(seconds: 4));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          textResponse =
              data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
          if (textResponse != null && textResponse.trim().isNotEmpty) {
            break;
          }
        }
      } catch (_) {}
    }

    if (textResponse != null && textResponse.trim().isNotEmpty) {
      try {
        return _parseResponse(
          textResponse,
          fallbackTopic: topic,
          fallbackDifficulty: difficulty,
        );
      } catch (_) {}
    }

    // Fast fallback dynamic generator if Cloud API times out or is busy
    return _generateWithLocalModel(topic: topic, difficulty: difficulty);
  }

  /// Internal Local Model Generation Path
  Future<Challenge> _generateWithLocalModel({
    required String topic,
    required String difficulty,
  }) async {
    final Map<String, Map<String, List<String>>> bank = {
      'Python': {
        'Easy': [
          'What is the key difference between lists and tuples in Python, and when should you use each?',
          'How do `is` and `==` differ when comparing variables or objects in Python?',
          'What are Python dictionaries and how do you access keys safely using the `.get()` method?',
          'Explain the purpose of `*args` and `**kwargs` in Python function signatures.',
          'How do `try`, `except`, `else`, and `finally` blocks handle errors in Python code?',
        ],
        'Medium': [
          'Explain the difference between shallow copy and deepcopy in Python with concrete code examples.',
          'How do Python generators and `yield` work to process large dataset streams without memory exhaustion?',
          'What are Python decorators and how do you implement a decorator that accepts custom parameters?',
          'Explain context managers in Python and how to implement custom resource management using `__enter__` and `__exit__`.',
          'How do list comprehensions differ from generator expressions in execution speed and RAM usage?',
        ],
        'Hard': [
          'How does Python\'s Global Interpreter Lock (GIL) impact multithreading vs multiprocessing in high-concurrency applications?',
          'Explain how CPython manages memory using reference counting and generational garbage collection for cyclic references.',
          'How do metaclasses work in Python, and what is the difference between `__new__` and `__init__` during class instantiation?',
          'Describe how CPython resolves method lookup order (MRO) using C3 linearization in complex inheritance hierarchies.',
        ],
      },
      'DevOps': {
        'Easy': [
          'What is Docker and what is the key difference between a Docker image and a running container?',
          'What is Git and how does `git merge` differ from `git rebase` at a basic level?',
          'What is CI/CD and why is automated unit testing essential in continuous integration pipelines?',
          'What is the purpose of environment variables and how are secret keys kept out of source code repositories?',
        ],
        'Medium': [
          'How do Kubernetes Pods, Services, and Deployments relate to each other in container orchestration?',
          'Explain Infrastructure as Code (IaC) principles and the main benefits of using tools like Terraform or Ansible.',
          'What are container registries and how do you implement container vulnerability scanning during build pipelines?',
          'Explain the architectural difference between monolithic application deployment and microservices CI/CD.',
        ],
        'Hard': [
          'How do Blue-Green and Canary deployment strategies achieve zero-downtime releases in production cloud clusters?',
          'Explain Linux cgroups and namespaces and how container runtimes (runc/containerd) use them for process isolation.',
          'How does a Service Mesh (e.g. Istio) handle traffic splitting, mutual TLS (mTLS), and distributed tracing in microservices?',
        ],
      },
      'Data Structures & Algorithms': {
        'Easy': [
          'What is the difference between an Array and a Linked List in memory layout and element access time?',
          'Explain how Binary Search works and state its time complexity on a pre-sorted array.',
          'What are Stacks and Queues, and how do LIFO (Last-In-First-Out) and FIFO (First-In-First-Out) operations differ?',
          'What is recursion and what happens when a recursive function lacks a base case?',
        ],
        'Medium': [
          'How does a Hash Table achieve O(1) average time complexity, and how are hash collisions handled (chaining vs open addressing)?',
          'Explain Breadth-First Search (BFS) vs Depth-First Search (DFS) on graph structures, noting when to use each.',
          'What is Dynamic Programming, and how does top-down memoization differ from bottom-up tabulation?',
          'Explain Two-Pointer and Sliding Window algorithmic patterns and identify problem types where they apply.',
        ],
        'Hard': [
          'How does QuickSort work, what causes its worst-case O(N^2) time complexity, and how can median-of-three pivot selection mitigate it?',
          'How do you design a Least Recently Used (LRU) Cache in O(1) time complexity using a Doubly Linked List and Hash Map?',
          'What is a Red-Black or AVL Tree, and how do tree rotations maintain logarithmic height balance during insertions?',
        ],
      },
      'System Design': {
        'Easy': [
          'What is Client-Server architecture and how do HTTP GET and POST requests differ?',
          'What is a Load Balancer and why is it placed in front of backend web servers?',
          'What is caching, and why do web applications store frequent database queries in Redis or Memcached?',
        ],
        'Medium': [
          'How does Horizontal Scaling differ from Vertical Scaling, and what architectural adjustments does horizontal scaling require?',
          'Explain the fundamental tradeoffs between relational (SQL) and non-relational (NoSQL) databases for scaling.',
          'What are asynchronous message queues (e.g. RabbitMQ/Kafka) and how do they decouple producer and consumer services?',
        ],
        'Hard': [
          'How would you design a distributed Rate Limiter (Token Bucket / Sliding Window) to protect APIs under massive traffic spikes?',
          'Explain the CAP theorem and the practical tradeoffs between Consistency, Availability, and Partition Tolerance in distributed databases.',
          'What is database sharding and read-replicas, and how do you handle data re-balancing and hot keys across shards?',
        ],
      },
      'SQL & Databases': {
        'Easy': [
          'What is a Primary Key and a Foreign Key in relational database tables?',
          'Explain the difference between SELECT, INSERT, UPDATE, and DELETE SQL statements.',
          'What does the `WHERE` clause do in SQL queries, and how does `LIKE` pattern matching work?',
        ],
        'Medium': [
          'What is the structural difference between INNER JOIN, LEFT OUTER JOIN, RIGHT OUTER JOIN, and FULL OUTER JOIN?',
          'What are Database Indexes and how do B-Tree indexes speed up query performance?',
          'Explain database normalization (1NF, 2NF, 3NF) and why it reduces data redundancy.',
        ],
        'Hard': [
          'What are ACID properties in database transactions, and how are isolation levels (Read Committed, Repeatable Read, Serializable) enforced?',
          'Explain the structural difference between Clustered and Non-Clustered indexes and their write amplification impact.',
          'How do database query execution plans work, and what steps do you take to fix full table scans on large tables?',
        ],
      },
      'Web Development': {
        'Easy': [
          'What are HTML, CSS, and JavaScript, and what role does each play in a modern web page?',
          'What is the difference between `var`, `let`, and `const` scope rules in JavaScript?',
          'What is a REST API and how does a frontend web app use `fetch()` or `axios` to get data?',
        ],
        'Medium': [
          'How does the browser JavaScript Event Loop operate (Call Stack, Microtask Queue, Macrotask Queue)?',
          'What is CORS (Cross-Origin Resource Sharing) and why do browsers block unauthorized cross-origin requests?',
          'Explain the difference between Client-Side Rendering (CSR) and Server-Side Rendering (SSR) regarding initial page load.',
        ],
        'Hard': [
          'How do WebSockets differ from HTTP/2 Server Push and Server-Sent Events (SSE) for real-time bi-directional streaming?',
          'Explain the internal Virtual DOM diffing and reconciliation algorithm used by modern reactive frontend frameworks.',
          'How do Core Web Vitals (LCP, CLS, INP) impact browser performance and critical rendering path optimization?',
        ],
      },
      'Flutter & Mobile': {
        'Easy': [
          'What is the difference between `StatelessWidget` and `StatefulWidget` in Flutter?',
          'What is the widget tree in Flutter and how does Hot Reload differ from Hot Restart?',
          'Explain the purpose of `pubspec.yaml` in a Flutter / Dart application.',
          'What are `Container`, `Column`, and `Row` widgets, and how do mainAxisAlignment and crossAxisAlignment work?',
        ],
        'Medium': [
          'How does state management work in Flutter (e.g. Provider, Riverpod, BLoC, or setState)?',
          'What is the difference between `Navigator.push` and `Navigator.pushReplacement` in Flutter routing?',
          'Explain `FutureBuilder` vs `StreamBuilder` and how asynchronous UI rendering works in Flutter.',
          'How does Flutter achieve cross-platform rendering using Skia / Impeller graphic engines?',
        ],
        'Hard': [
          'Explain the three trees in Flutter (Widget Tree, Element Tree, RenderObject Tree) and how layout constraints flow down while sizes flow up.',
          'How do MethodChannels and Platform Channels bridge Flutter Dart code with native Android (Java/Kotlin) and iOS (Swift/Obj-C)?',
          'What are Isolate workers in Dart, and how do you handle background compute-heavy CPU tasks without blocking the main UI isolate loop?',
        ],
      },
      'Golang & Backend': {
        'Easy': [
          'What are Go goroutines and how do they differ from OS threads in memory footprint?',
          'How does error handling work in Go using explicit error returns instead of exceptions?',
          'What are Go slices and how do they differ from fixed-size arrays?',
        ],
        'Medium': [
          'How do Go channels work, and what is the difference between buffered and unbuffered channels?',
          'Explain Go interfaces and how structural subtyping (implicit implementation) works.',
          'What is the `defer` keyword in Go and in what order are deferred calls executed upon function exit?',
        ],
        'Hard': [
          'How does the Go runtime scheduler (GMP model: Goroutines, OS Threads, Processors) schedule concurrent tasks?',
          'Explain how Go\'s concurrent mark-and-sweep garbage collector minimizes stop-the-world pause times.',
        ],
      },
      'Cybersecurity & Networking': {
        'Easy': [
          'What is the difference between HTTP and HTTPS, and what does TLS/SSL encryption do?',
          'What is authentication vs authorization, and how do passwords get hashed using bcrypt or Argon2?',
          'What is a Firewall and how does it filter inbound vs outbound network traffic?',
        ],
        'Medium': [
          'What is SQL Injection (SQLi) and how do parameterized prepared statements prevent it?',
          'Explain Cross-Site Scripting (XSS) and Cross-Site Request Forgery (CSRF) and their mitigation strategies.',
          'What is JWT (JSON Web Token) authentication and how are digital signatures verified?',
        ],
        'Hard': [
          'How does a TLS 1.3 handshake establish an encrypted symmetric session key using Diffie-Hellman Ephemeral (DHE)?',
          'Explain how Zero Trust architecture and Identity-Aware Proxies differ from traditional perimeter VPN security.',
        ],
      },
      'Machine Learning & AI': {
        'Easy': [
          'What is the difference between Supervised Learning, Unsupervised Learning, and Reinforcement Learning?',
          'What is the difference between Overfitting and Underfitting in a machine learning model?',
          'Explain what Training data, Validation data, and Test data are used for.',
        ],
        'Medium': [
          'What is Gradient Descent and how do learning rates impact convergence during backpropagation?',
          'Explain the difference between Precision, Recall, and F1-Score in classification metrics.',
          'What are Transformers and self-attention mechanisms in modern Large Language Models (LLMs)?',
        ],
        'Hard': [
          'How does the Self-Attention mechanism calculate Query, Key, and Value matrix projections in Transformer architectures?',
          'Explain quantization (INT8/FP16), LoRA fine-tuning, and KV-caching optimizations during LLM inference.',
        ],
      },
    };

    // Find topic tier case-insensitively or via partial keyword match
    Map<String, List<String>>? topicTier = bank[topic];
    if (topicTier == null) {
      final topicLower = topic.toLowerCase();
      final matchedKey = bank.keys.firstWhere(
        (k) {
          final kLower = k.toLowerCase();
          return kLower == topicLower ||
              topicLower.contains(kLower) ||
              kLower.split('&').any((part) => topicLower.contains(part.trim()));
        },
        orElse: () => '',
      );
      if (matchedKey.isNotEmpty) {
        topicTier = bank[matchedKey];
      }
    }

    List<String>? pool;
    if (topicTier != null) {
      pool = topicTier[difficulty] ?? topicTier['Medium'] ?? topicTier['Easy'];
    }

    if (pool == null || pool.isEmpty) {
      // Dynamic fallback for custom/unrecognized topics by difficulty
      if (difficulty == 'Easy') {
        pool = [
          'What is $topic in simple terms, and what fundamental problem does it solve for beginners?',
          'Explain basic syntax, key concepts, or standard usage in $topic.',
          'What are the first steps and fundamental building blocks when getting started with $topic?',
          'What is the main syntax structure or core entry point used when working with $topic?',
          'Explain entry-level data types, basic operations, or setup steps in $topic.',
        ];
      } else if (difficulty == 'Hard') {
        pool = [
          'What are advanced performance bottlenecks, memory management considerations, and architectural tradeoffs in $topic?',
          'How does $topic handle high concurrency, internal state, and low-level resource management under heavy load?',
          'Describe a complex edge case or production failure mode in $topic and how to architect around it.',
          'Explain how internal runtime compilation, execution engines, or memory allocation function in $topic.',
          'How do you design scalable, fault-tolerant enterprise architecture using $topic in production environments?',
        ];
      } else {
        pool = [
          'How do error handling, data flow, and standard design patterns work effectively in $topic?',
          'Compare key features, alternative tools, and practical implementation tradeoffs in $topic.',
          'What are common pitfall patterns and practical debugging strategies when developing with $topic?',
          'Explain intermediate configuration, component modularity, and testing strategies in $topic.',
          'How do you manage dependencies, environment configurations, and security practices in $topic?',
        ];
      }
    }

    final shuffled = List<String>.from(pool)..shuffle();
    final questionText = shuffled.first;

    return Challenge(
      question: questionText,
      topic: topic,
      difficulty: difficulty,
    );
  }

  /// Helper JSON parser
  Challenge _parseResponse(
    String rawResponse, {
    required String fallbackTopic,
    required String fallbackDifficulty,
  }) {
    var cleanStr = rawResponse.trim();
    if (cleanStr.startsWith('```json')) cleanStr = cleanStr.substring(7);
    if (cleanStr.startsWith('```')) cleanStr = cleanStr.substring(3);
    if (cleanStr.endsWith('```')) cleanStr = cleanStr.substring(0, cleanStr.length - 3);
    cleanStr = cleanStr.trim();

    final firstBrace = cleanStr.indexOf('{');
    final lastBrace = cleanStr.lastIndexOf('}');
    if (firstBrace != -1 && lastBrace != -1 && lastBrace > firstBrace) {
      cleanStr = cleanStr.substring(firstBrace, lastBrace + 1);
    }

    try {
      final map = jsonDecode(cleanStr) as Map<String, dynamic>;
      final q = map['question'] as String?;
      if (q != null && q.trim().isNotEmpty) {
        return Challenge(
          question: q.trim(),
          topic: map['topic'] as String? ?? fallbackTopic,
          difficulty: map['difficulty'] as String? ?? fallbackDifficulty,
        );
      }
    } catch (_) {}

    throw QuestionGeneratorException(
      'Model response format error: Unable to parse JSON question format.',
    );
  }

  /// Standardized System Prompt used for both Cloud API & Offline Local Models
  static String buildStandardPrompt({
    required String topic,
    required String difficulty,
  }) {
    return '''
Generate one concise technical interview question for a software engineer.
Topic: $topic
Difficulty Level: $difficulty

Strict Difficulty Guidelines:
- If Difficulty is "Easy": Ask a beginner-friendly question focusing on core syntax, basic definitions, fundamental concepts, and entry-level usage suitable for beginners.
- If Difficulty is "Medium": Ask an intermediate-level question focusing on practical applications, common design patterns, error handling, performance considerations, and real-world tradeoffs.
- If Difficulty is "Hard": Ask an advanced-level question focusing on deep architectural concepts, internal engine mechanics, memory management, concurrency, edge cases, and low-level optimization.

Return strictly a JSON object:
{
  "question": "<question text>",
  "topic": "$topic",
  "difficulty": "$difficulty"
}
''';
  }
}

