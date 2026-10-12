import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ai_preference_service.dart';
import '../services/local_model_service.dart';
import '../services/topic_preference_service.dart';

class SettingsModal extends StatefulWidget {
  final VoidCallback onReplayTour;
  final VoidCallback onSwitchToCompact;
  final VoidCallback? onSettingsSaved;

  const SettingsModal({
    super.key,
    required this.onReplayTour,
    required this.onSwitchToCompact,
    this.onSettingsSaved,
  });

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onReplayTour,
    required VoidCallback onSwitchToCompact,
    VoidCallback? onSettingsSaved,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SettingsModal(
        onReplayTour: onReplayTour,
        onSwitchToCompact: onSwitchToCompact,
        onSettingsSaved: onSettingsSaved,
      ),
    );
  }

  @override
  State<SettingsModal> createState() => _SettingsModalState();
}

class _SettingsModalState extends State<SettingsModal> {
  AiMode _selectedMode = AiMode.none;
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _customTopicController = TextEditingController();
  bool _obscureApiKey = true;
  bool _promptOnSubmit = true;
  bool _isLoading = true;
  bool _isSavingKey = false;
  String _savedKeyMessage = '';

  // Preferred Topics State
  List<String> _preferredTopics = [];
  List<String> _customTopics = [];
  bool _showAllTopics = false;

  // Local Offline Model State
  bool _isModelDownloaded = false;
  bool _isDownloadingModel = false;
  double _downloadProgress = 0.0;
  String _downloadStatus = '';

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    LocalModelService.instance.progressNotifier.addListener(_onDownloadProgressChanged);
    LocalModelService.instance.statusNotifier.addListener(_onDownloadStatusChanged);
  }

  void _onDownloadProgressChanged() {
    if (mounted) {
      setState(() {
        _downloadProgress = LocalModelService.instance.progressNotifier.value;
        _isDownloadingModel = LocalModelService.instance.isDownloading;
      });
    }
  }

  void _onDownloadStatusChanged() {
    if (mounted) {
      setState(() {
        _downloadStatus = LocalModelService.instance.statusNotifier.value;
      });
    }
  }

  @override
  void dispose() {
    LocalModelService.instance.progressNotifier.removeListener(_onDownloadProgressChanged);
    LocalModelService.instance.statusNotifier.removeListener(_onDownloadStatusChanged);
    _apiKeyController.dispose();
    _customTopicController.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final mode = await AiPreferenceService.instance.getAiMode();
    final key = await AiPreferenceService.instance.getApiKey();
    final prompt = await AiPreferenceService.instance.getPromptOnSubmit();
    final isDownloaded = await LocalModelService.instance.isModelDownloaded();
    final topics = await TopicPreferenceService.instance.getPreferredTopics();
    final customTopics = await TopicPreferenceService.instance.getCustomTopics();

    if (mounted) {
      setState(() {
        _selectedMode = mode;
        _apiKeyController.text = key;
        _promptOnSubmit = prompt;
        _isModelDownloaded = isDownloaded;
        _isDownloadingModel = LocalModelService.instance.isDownloading;
        _downloadProgress = LocalModelService.instance.currentProgress;
        _downloadStatus = LocalModelService.instance.currentStatus;
        _preferredTopics = topics;
        _customTopics = customTopics;
        _isLoading = false;
        if (key.isNotEmpty) {
          _savedKeyMessage = 'Key Saved ✅';
        }
      });
    }
  }

  void _toggleTopic(String topic) {
    setState(() {
      if (_preferredTopics.contains(topic)) {
        _preferredTopics.remove(topic);
      } else {
        _preferredTopics.add(topic);
      }
    });
  }

  void _addCustomTopic() {
    final text = _customTopicController.text.trim();
    if (text.isEmpty) return;

    if (!_customTopics.contains(text)) {
      setState(() {
        _customTopics.add(text);
        if (!_preferredTopics.contains('Others')) {
          _preferredTopics.add('Others');
        }
      });
    }
    _customTopicController.clear();
  }

  void _removeCustomTopic(String topic) {
    setState(() {
      _customTopics.remove(topic);
    });
  }

  Future<void> _saveSettings() async {
    await TopicPreferenceService.instance.setPreferredTopics(_preferredTopics);
    
    // Save all custom topics
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('user_custom_topics_list', _customTopics);

    if (_apiKeyController.text.trim().isNotEmpty) {
      await _saveApiKey();
    }
    await AiPreferenceService.instance.setAiMode(_selectedMode);
    await AiPreferenceService.instance.setPromptOnSubmit(_promptOnSubmit);

    if (widget.onSettingsSaved != null) {
      widget.onSettingsSaved!();
    }
  }

  Future<void> _downloadLocalModel() async {
    setState(() {
      _isDownloadingModel = true;
      _downloadProgress = 0.01;
      _downloadStatus = 'Starting GGUF download...';
    });

    try {
      await LocalModelService.instance.downloadModel(
        onProgress: (progress, status) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress;
              _downloadStatus = status;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isDownloadingModel = false;
          _isModelDownloaded = true;
          _selectedMode = AiMode.offline;
        });
        await AiPreferenceService.instance.setAiMode(AiMode.offline);
      }
    } catch (e) {
      final path = await LocalModelService.instance.getModelPath();
      if (!mounted) return;
      final fileExists = path != null && File(path).existsSync() && File(path).lengthSync() > 10 * 1024;
      setState(() {
        _isDownloadingModel = false;
        if (!fileExists) {
          _downloadProgress = 0.0;
        }
        _downloadStatus = 'Download Error: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download Error: $e'),
          backgroundColor: Colors.red[800],
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _deleteLocalModel() async {
    await LocalModelService.instance.deleteModel();
    if (mounted) {
      setState(() {
        _isModelDownloaded = false;
        if (_selectedMode == AiMode.offline) {
          _selectedMode = AiMode.none;
        }
      });
      await AiPreferenceService.instance.setAiMode(_selectedMode);
    }
  }

  Future<void> _changeMode(AiMode mode) async {
    setState(() {
      _selectedMode = mode;
    });
    await AiPreferenceService.instance.setAiMode(mode);
  }

  Future<void> _saveApiKey() async {
    final key = _apiKeyController.text.trim();
    setState(() {
      _isSavingKey = true;
    });

    await AiPreferenceService.instance.setApiKey(key);
    if (key.isNotEmpty) {
      await AiPreferenceService.instance.setAiMode(AiMode.apiKey);
    }

    if (mounted) {
      setState(() {
        _isSavingKey = false;
        _selectedMode = key.isNotEmpty ? AiMode.apiKey : _selectedMode;
        _savedKeyMessage = key.isNotEmpty ? 'Key Saved ✅' : 'Key Cleared';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(key.isNotEmpty ? 'API Key saved successfully!' : 'API Key cleared.'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _togglePrompt(bool val) async {
    setState(() {
      _promptOnSubmit = val;
    });
    await AiPreferenceService.instance.setPromptOnSubmit(val);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Container(
      constraints: BoxConstraints(
        maxHeight: screenSize.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle Bar
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.settings_rounded, color: Color(0xFF89B4FA), size: 24),
                      SizedBox(width: 10),
                      Text(
                        'Application Settings',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF313244), height: 1),

            // Body Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Preferred Topics Selection
                          const Text(
                            '🎯 PREFERRED TOPICS FOR DAILY CHALLENGES',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                              color: Color(0xFFA6ADC8),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Select topics to practice. Daily challenges will dynamically adapt to your preferences.',
                            style: TextStyle(fontSize: 11, color: Color(0xFFCDD6F4)),
                          ),
                          const SizedBox(height: 12),
                          Builder(
                            builder: (context) {
                              final allDefault = TopicPreferenceService.defaultTopics;
                              const initialCount = 5;
                              final displayedDefaultTopics = _showAllTopics
                                  ? allDefault
                                  : allDefault.take(initialCount).toList();

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Animated Container wrapping single unified Wrap & Typing Bar
                                  AnimatedSize(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Single unified Wrap for all default & custom topic chips
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            ...displayedDefaultTopics.map((topic) {
                                              final isSelected = _preferredTopics.contains(topic);
                                              return FilterChip(
                                                label: Text(topic),
                                                selected: isSelected,
                                                onSelected: (_) => _toggleTopic(topic),
                                                selectedColor: const Color(0xFF6366F1),
                                                checkmarkColor: Colors.white,
                                                labelStyle: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: isSelected
                                                      ? Colors.white
                                                      : const Color(0xFFCDD6F4),
                                                ),
                                                backgroundColor: const Color(0xFF11111B),
                                                side: BorderSide(
                                                  color: isSelected
                                                      ? const Color(0xFF6366F1)
                                                      : const Color(0xFF313244),
                                                ),
                                              );
                                            }),
                                            if (_showAllTopics &&
                                                _preferredTopics.contains('Others') &&
                                                _customTopics.isNotEmpty)
                                              ..._customTopics.map((ct) {
                                                return InputChip(
                                                  label: Text('# $ct',
                                                      style: const TextStyle(
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.bold,
                                                          color: Colors.white)),
                                                  onDeleted: () => _removeCustomTopic(ct),
                                                  deleteIcon: const Icon(Icons.close,
                                                      size: 14, color: Colors.white70),
                                                  backgroundColor: const Color(0xFF2A2B3D),
                                                  side: const BorderSide(
                                                      color: Color(0xFF6366F1)),
                                                );
                                              }),
                                          ],
                                        ),

                                        // Custom Topic Typing Bar
                                        if (_showAllTopics && _preferredTopics.contains('Others')) ...[
                                          const SizedBox(height: 12),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: TextField(
                                                  controller: _customTopicController,
                                                  onSubmitted: (_) => _addCustomTopic(),
                                                  style: const TextStyle(
                                                      color: Colors.white, fontSize: 13),
                                                  decoration: InputDecoration(
                                                    hintText:
                                                        'Type custom topic (e.g. Rust, Go, ML)...',
                                                    hintStyle:
                                                        TextStyle(color: Colors.grey[600]),
                                                    filled: true,
                                                    fillColor: const Color(0xFF11111B),
                                                    contentPadding: const EdgeInsets.symmetric(
                                                        horizontal: 14, vertical: 12),
                                                    border: OutlineInputBorder(
                                                      borderRadius: BorderRadius.circular(12),
                                                      borderSide: const BorderSide(
                                                          color: Color(0xFF6366F1)),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              FilledButton.icon(
                                                onPressed: _addCustomTopic,
                                                icon: const Icon(Icons.add, size: 18),
                                                label: const Text('Add',
                                                    style: TextStyle(
                                                        fontSize: 13,
                                                        fontWeight: FontWeight.bold)),
                                                style: FilledButton.styleFrom(
                                                  backgroundColor: const Color(0xFF6366F1),
                                                  shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(12)),
                                                  padding: const EdgeInsets.symmetric(
                                                      horizontal: 16, vertical: 14),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),

                                  // Show More / Show Less Toggle Button
                                  const SizedBox(height: 8),
                                  TextButton.icon(
                                    onPressed: () {
                                      setState(() {
                                        _showAllTopics = !_showAllTopics;
                                      });
                                    },
                                    icon: Icon(
                                      _showAllTopics
                                          ? Icons.keyboard_arrow_up_rounded
                                          : Icons.keyboard_arrow_down_rounded,
                                      size: 18,
                                      color: const Color(0xFF89B4FA),
                                    ),
                                    label: Text(
                                      _showAllTopics
                                          ? 'Show Less'
                                          : 'Show More (+${allDefault.length - initialCount} topics)',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF89B4FA),
                                      ),
                                    ),
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 24),

                          // 2. AI Evaluation Engine Selection
                          const Text(
                            '🧠 AI EVALUATION ENGINE',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                              color: Color(0xFFA6ADC8),
                            ),
                          ),
                          const SizedBox(height: 12),

                          _buildModeCard(
                            mode: AiMode.offline,
                            icon: '🤖',
                            title: 'Local Offline Model',
                            subtitle:
                                'Private, on-device evaluation. No internet or API key required.',
                            badge: 'RECOMMENDED FOR PRIVACY',
                            badgeColor: const Color(0xFFA6E3A1),
                          ),
                          const SizedBox(height: 10),

                          _buildModeCard(
                            mode: AiMode.apiKey,
                            icon: '🔑',
                            title: 'Cloud API Key',
                            subtitle:
                                'Fast, comprehensive AI feedback using your Gemini or OpenAI API key.',
                            badge: 'FAST & DETAILED',
                            badgeColor: const Color(0xFF89B4FA),
                          ),
                          const SizedBox(height: 10),

                          _buildModeCard(
                            mode: AiMode.none,
                            icon: '⏩',
                            title: 'Disabled / Skip AI',
                            subtitle:
                                'Standard answer saving without AI code review or feedback.',
                            badge: 'STANDARD MODE',
                            badgeColor: Colors.grey,
                          ),
                          const SizedBox(height: 20),

                          // Local Model Downloader Section
                          if (_selectedMode == AiMode.offline) ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF11111B),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: const Color(0xFFA6E3A1), width: 1.2),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Offline GGUF Model (Qwen2.5 1.5B / 1.7B)',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      Text(
                                        _isModelDownloaded
                                            ? 'Ready ✅'
                                            : 'Not Downloaded',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: _isModelDownloaded
                                              ? const Color(0xFFA6E3A1)
                                              : Colors.amber,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Downloads the compact 986 MB Qwen 1.5B/1.7B Instruct GGUF model directly from Hugging Face for 100% offline evaluation.',
                                    style: TextStyle(
                                        fontSize: 11, color: Color(0xFFA6ADC8)),
                                  ),
                                  const SizedBox(height: 12),
                                  if (_isDownloadingModel) ...[
                                    LinearProgressIndicator(
                                      value: _downloadProgress,
                                      backgroundColor: const Color(0xFF313244),
                                      color: const Color(0xFFA6E3A1),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _downloadStatus,
                                      style: const TextStyle(
                                          fontSize: 11, color: Color(0xFF89B4FA)),
                                    ),
                                  ] else if (!_isModelDownloaded) ...[
                                    SizedBox(
                                      width: double.infinity,
                                      height: 42,
                                      child: FilledButton.icon(
                                        onPressed: _downloadLocalModel,
                                        icon: const Icon(Icons.download_rounded,
                                            size: 18),
                                        label: Text(
                                            _downloadProgress > 0
                                                ? 'Resume Offline Model Download'
                                                : 'Download Offline Model (986 MB)',
                                            style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold)),
                                        style: FilledButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFF2E3D32),
                                          foregroundColor:
                                              const Color(0xFFA6E3A1),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ] else ...[
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: _deleteLocalModel,
                                            icon: const Icon(
                                                Icons.delete_outline,
                                                size: 16),
                                            label: const Text(
                                                'Delete Local Model File'),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: Colors.red[300],
                                              side: BorderSide(
                                                  color: Colors.red
                                                      .withValues(alpha: 0.3)),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],

                          // 2. API Key Configuration Box
                          if (_selectedMode == AiMode.apiKey ||
                              _apiKeyController.text.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF11111B),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: const Color(0xFF6366F1), width: 1.2),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Configure Cloud API Key',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      if (_savedKeyMessage.isNotEmpty)
                                        Text(
                                          _savedKeyMessage,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFFA6E3A1),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: _apiKeyController,
                                    obscureText: _obscureApiKey,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13),
                                    decoration: InputDecoration(
                                      hintText: 'Enter API Key (e.g. AIzaSy...)',
                                      hintStyle:
                                          TextStyle(color: Colors.grey[600]),
                                      filled: true,
                                      fillColor: const Color(0xFF1E1E2E),
                                      contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 12),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                            color: Color(0xFF45475A)),
                                      ),
                                      suffixIcon: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: Icon(
                                              _obscureApiKey
                                                  ? Icons.visibility
                                                  : Icons.visibility_off,
                                              color: Colors.grey,
                                              size: 20,
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                _obscureApiKey =
                                                    !_obscureApiKey;
                                              });
                                            },
                                          ),
                                          if (_apiKeyController.text.isNotEmpty)
                                            IconButton(
                                              icon: const Icon(Icons.clear,
                                                  color: Colors.grey, size: 18),
                                              onPressed: () {
                                                _apiKeyController.clear();
                                                _saveApiKey();
                                              },
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 42,
                                    child: FilledButton.icon(
                                      onPressed:
                                          _isSavingKey ? null : _saveApiKey,
                                      icon: _isSavingKey
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white),
                                            )
                                          : const Icon(Icons.save_rounded,
                                              size: 18),
                                      label: const Text('Save API Key',
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold)),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(0xFF6366F1),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],

                          // 3. Post-Submit Prompt Preference Switch
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF11111B),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFF313244)),
                            ),
                            child: SwitchListTile(
                              value: _promptOnSubmit,
                              onChanged: _togglePrompt,
                              activeTrackColor: const Color(0xFF6366F1),
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'Post-Submit AI Prompt',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              subtitle: const Text(
                                'Prompt to set up AI evaluation after submitting an answer if disabled.',
                                style: TextStyle(
                                    fontSize: 11, color: Color(0xFFA6ADC8)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),

            // Sticky Bottom Tab Bar (Always Visible at bottom of modal)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF11111B),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
                border: const Border(
                  top: BorderSide(color: Color(0xFF313244), width: 1),
                ),
              ),
              child: Row(
                children: [
                  // a) Clear / Reset Changes Button
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loadPreferences,
                      icon: const Icon(Icons.undo_rounded, size: 16),
                      label: const Text(
                        'Clear Changes',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFF38BA8),
                        side: const BorderSide(color: Color(0xFFF38BA8), width: 1),
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // b) Save & Apply Settings Button
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        final navigator = Navigator.of(context);
                        final messenger = ScaffoldMessenger.of(context);
                        await _saveSettings();
                        navigator.pop();
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Settings saved & applied across the application! ✅'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.check_circle_rounded, size: 16),
                      label: const Text(
                        'Save & Apply',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeCard({
    required AiMode mode,
    required String icon,
    required String title,
    required String subtitle,
    required String badge,
    required Color badgeColor,
  }) {
    final isSelected = _selectedMode == mode;

    return GestureDetector(
      onTap: () => _changeMode(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2A2B3D) : const Color(0xFF11111B),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF313244),
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(icon, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : const Color(0xFFCDD6F4),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: badgeColor, width: 0.8),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: badgeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFA6ADC8),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isSelected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: isSelected ? const Color(0xFF6366F1) : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}
