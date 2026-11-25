import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:speech_to_text/speech_to_text.dart';
void main() {
  runApp(const SuhanaApp());
}

class SuhanaApp extends StatelessWidget {
  const SuhanaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Suhana',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0E17),
      ),
      home: const HomeScreen(),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final bool isInfo;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.isInfo = false,
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FlutterTts _tts = FlutterTts();

  final List<ChatMessage> _messages = [];
final SpeechToText _speech = SpeechToText();

bool _speechAvailable = false;
bool _isListening = false;
  String _apiKey = '';
  String _model = 'gemini-3.8-flash';
  String? _lastUsedModel;
  bool _isLoading = false;
  bool _isSpeaking = false;

  static const List<String> _models = [
  'gemini-3.8-flash',
  'gemini-3.5-flash-lite',
  'gemini-3.1-flash-lite',
];


  static const String _systemPrompt =
      'You are Suhana, a sweet, smart, friendly female AI assistant inside an app created by an independent app developer. '
      'You are powered by the Google Gemini API, but Google did not create this specific Suhana app. '
      'If asked who created you, explain that you are the Suhana assistant in this app and Gemini provides your AI responses. '
      'Never claim that Google created this Suhana app or that you have abilities not provided by the app. '
      'Reply in the same language as the user: Hindi, Hinglish or English. '
      'Keep answers short, natural and conversational. '
      'Do not use markdown symbols like * or #.';
  

  @override
  void initState() {
    super.initState();
    _setupTts();
    _initSpeech();
    _loadSettings();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _setupTts() async {
    await _tts.setSpeechRate(0.48);
    await _tts.setPitch(1.12);
    await _tts.setVolume(1.0);

    _tts.setStartHandler(() {
      if (mounted) {
        setState(() => _isSpeaking = true);
      }
    });

    _tts.setCompletionHandler(() {
      if (mounted) {
        setState(() => _isSpeaking = false);
      }
    });

    _tts.setCancelHandler(() {
      if (mounted) {
        setState(() => _isSpeaking = false);
      }
    });
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiKey = prefs.getString('gemini_api_key') ?? '';
      _model = prefs.getString('gemini_model') ?? 'gemini-3.8-flash';
    });

    if (_apiKey.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openSettings();
      });
    }
  }

  Future<void> _saveSettings(String key, String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', key);
    await prefs.setString('gemini_model', model);

    setState(() {
      _apiKey = key;
      _model = model;
    });
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _addInfoMessage(String text) {
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: false, isInfo: true));
    });
    _scrollToBottom();
  }
  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onStatus: (status) {
        if (mounted && (status == 'done' || status == 'notListening')) {
          setState(() => _isListening = false);
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() => _isListening = false);
        }
      },
    );

    if (mounted) {
      setState(() => _speechAvailable = available);
    }
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    if (!_speechAvailable) {
      await _initSpeech();
    }

    if (!_speechAvailable) {
      _addInfoMessage('Microphone permission ya speech recognition check karo.');
      return;
    }

    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        setState(() {
          _inputController.text = result.recognizedWords;
          _inputController.selection = TextSelection.fromPosition(
            TextPosition(offset: _inputController.text.length),
          );
        });
      },
      listenFor: const Duration(seconds: 45),
      pauseFor: const Duration(seconds: 4),
      partialResults: true,
    );

    if (mounted) setState(() => _isListening = true);
  }
  Future<void> _speak(String text) async {
    if (text.startsWith('⚠️')) return;

    String clean = text
        .replaceAll(RegExp(r'[*#`_>]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (clean.isEmpty) return;

    final hasHindi = RegExp(r'[\u0900-\u097F]').hasMatch(clean);

    try {
      await _tts.stop();
      await _tts.setLanguage(hasHindi ? 'hi-IN' : 'en-IN');
      await _tts.speak(clean);
    } catch (_) {}
  }

    List<Map<String, dynamic>> _buildHistory(String userText) {
    final previousMessages =
        _messages.where((m) => !m.isInfo).toList();

    if (previousMessages.isNotEmpty &&
        previousMessages.last.isUser &&
        previousMessages.last.text == userText) {
      previousMessages.removeLast();
    }

    final recentMessages = previousMessages.length > 12
        ? previousMessages.sublist(previousMessages.length - 12)
        : previousMessages;

    final contents = <Map<String, dynamic>>[];

    for (final msg in recentMessages) {
      final role = msg.isUser ? 'user' : 'model';

      if (contents.isNotEmpty && contents.last['role'] == role) {
        final parts = contents.last['parts'] as List;
        final lastPart = parts.last as Map<String, dynamic>;
        lastPart['text'] =
            '${lastPart['text']}\n${msg.text}';
      } else {
        contents.add({
          'role': role,
          'parts': [
            {'text': msg.text}
          ],
        });
      }
    }

    if (contents.isNotEmpty && contents.last['role'] == 'user') {
      final parts = contents.last['parts'] as List;
      final lastPart = parts.last as Map<String, dynamic>;
      lastPart['text'] =
          '${lastPart['text']}\n$userText';
    } else {
      contents.add({
        'role': 'user',
        'parts': [
          {'text': userText}
        ],
      });
    }

    return contents;
    }

    
  
Future<String> _callGemini(String userText) async {
  final contents = _buildHistory(userText);

  // Selected model first, then remaining models.
  final modelsToTry = [
    _model,
    ..._models.where((m) => m != _model),
  ];

  String lastError = 'Gemini abhi respond nahi kar pa raha.';

  for (final model in modelsToTry) {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
    );

    final body = {
      'system_instruction': {
        'parts': [
          {'text': _systemPrompt}
        ]
      },
      'contents': contents,
      'generationConfig': {
        'temperature': 0.7,
      },
    };

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await http
            .post(
              uri,
              headers: {
                'Content-Type': 'application/json',
                'x-goog-api-key': _apiKey,
              },
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 45));

        if (response.statusCode == 200) {
          final data = jsonDecode(utf8.decode(response.bodyBytes));
          final candidates = data['candidates'] as List?;

          if (candidates == null || candidates.isEmpty) {
            return '⚠️ Gemini ne empty response diya.';
          }

          final parts =
              (candidates[0]['content']?['parts'] as List?) ?? [];

          final answer = parts
              .where((part) => part is Map && part['text'] is String)
              .map((part) => part['text'] as String)
              .join()
              .trim();

          if (answer.isEmpty) {
            return '⚠️ Gemini ne empty text response diya.';
          }

          _lastUsedModel = model;
          return answer;
        }

        String errorMessage = 'Unknown API error';

        try {
          final decoded = jsonDecode(utf8.decode(response.bodyBytes));

          if (decoded is Map && decoded['error'] is Map) {
            errorMessage =
                decoded['error']['message']?.toString() ?? errorMessage;
          }
        } catch (_) {}

        if (response.statusCode == 401 ||
            response.statusCode == 403) {
          return '⚠️ API key ya permission issue: $errorMessage';
        }

        if (response.statusCode == 429) {
          return '⚠️ Gemini quota/rate limit issue: $errorMessage';
        }

        if (response.statusCode == 500 ||
            response.statusCode == 503) {
          lastError = 'Gemini server busy hai: $errorMessage';

          if (attempt == 0) {
            await Future.delayed(const Duration(seconds: 1));
            continue;
          }

          break;
        }

        if (response.statusCode == 404) {
          lastError = 'Model $model available nahi hai: $errorMessage';
          break;
        }

        return '⚠️ Gemini API error (${response.statusCode}): $errorMessage';

      } on TimeoutException {
        lastError = 'Model $model response mein bahut der laga raha hai.';

        if (attempt == 0) {
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }

        break;

      } on SocketException {
        lastError = 'Internet connection check karo.';

        if (attempt == 0) {
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }

        break;

      } on http.ClientException catch (e) {
        lastError = 'Network connection error: $e';

        if (attempt == 0) {
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }

        break;

      } catch (e) {
        return '⚠️ Request fail hui: $e';
      }
    }
  }

  return '⚠️ Sabhi available models fail ho gaye. $lastError';
}
  
  
  Future<void> _openUrl(String url, String successMessage) async {
    try {
      await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      setState(() {
        _messages.add(ChatMessage(text: successMessage, isUser: false));
      });
      _scrollToBottom();
    } catch (_) {
      _addInfoMessage('⚠️ Open nahi ho paya.');
    }
  }

  Future<bool> _handleCommand(String text) async {
    final lower = text.toLowerCase();

    if (lower.contains('youtube kholo') || lower.contains('open youtube')) {
      await _openUrl('https://www.youtube.com', 'YouTube khol diya! 🔴');
      return true;
    }

    if (lower.contains('whatsapp kholo') || lower.contains('open whatsapp')) {
      await _openUrl('https://www.whatsapp.com', 'WhatsApp khol diya! 💬');
      return true;
    }

    if (lower.contains('instagram kholo') ||
        lower.contains('open instagram')) {
      await _openUrl('https://www.instagram.com', 'Instagram khol diya! ✨');
      return true;
    }

    if (lower.contains('snapchat kholo') || lower.contains('open snapchat')) {
      await _openUrl('https://www.snapchat.com', 'Snapchat khol diya! 👻');
      return true;
    }

    if (lower.contains('google par') ||
        lower.contains('google pe') ||
        lower.contains('search karo')) {
      String query = text
          .replaceAll(RegExp(r'google par', caseSensitive: false), '')
          .replaceAll(RegExp(r'google pe', caseSensitive: false), '')
          .replaceAll(RegExp(r'search karo', caseSensitive: false), '')
          .trim();

      if (query.isEmpty) {
        query = 'Suhana AI';
      }

      await _openUrl(
        'https://www.google.com/search?q=${Uri.encodeComponent(query)}',
        'Google par "$query" search kar diya! 🔍',
      );
      return true;
    }

    return false;
  }

  Future<void> _sendMessage(String value) async {
    final text = value.trim();
    if (text.isEmpty || _isLoading) return;

    _inputController.clear();

    final commandHandled = await _handleCommand(text);
    if (commandHandled) return;

    if (_apiKey.isEmpty) {
      _openSettings();
      return;
    }

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _isLoading = true;
    });
    _scrollToBottom();

    final reply = await _callGemini(text);

    if (!mounted) return;

    setState(() {
      _messages.add(ChatMessage(text: reply, isUser: false));
      _isLoading = false;
    });

    _scrollToBottom();
    await _speak(reply);
  }

  void _openSettings() {
    final keyController = TextEditingController(text: _apiKey);
    String selectedModel = _model;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF161B26),
            title: const Text(
              'Suhana Settings',
              style: TextStyle(color: Colors.cyanAccent, fontSize: 20),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: keyController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Gemini API Key',
                    hintText: 'AIza...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedModel,
                  dropdownColor: const Color(0xFF161B26),
                  decoration: const InputDecoration(
                    labelText: 'Model',
                    border: OutlineInputBorder(),
                  ),
                  items: _models
                      .map(
                        (m) => DropdownMenuItem<String>(
                          value: m,
                          child: Text(m),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() {
                        selectedModel = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: 8),
                const Text(
                  'Recommended: gemini-3.8-flash',
                  style: TextStyle(fontSize: 11, color: Colors.white54),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  _saveSettings(keyController.text.trim(), selectedModel);
                  Navigator.pop(ctx);
                },
                child: const Text(
                  'Save',
                  style: TextStyle(color: Colors.cyanAccent),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAvatar() {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: _isSpeaking
              ? [Colors.pinkAccent, Colors.purple]
              : [Colors.cyanAccent, Colors.indigo.shade900],
        ),
        boxShadow: [
          BoxShadow(
            color: (_isSpeaking ? Colors.pinkAccent : Colors.cyanAccent)
                .withOpacity(0.4),
            blurRadius: 24,
            spreadRadius: 6,
          )
        ],
      ),
      child: const Icon(Icons.face_3, size: 54, color: Colors.white),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusText = _isSpeaking
        ? 'Suhana bol rahi hai...'
        : _isLoading
            ? 'Suhana soch rahi hai...'
            : 'Suhana • $_model';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        centerTitle: true,
        title: const Text(
          'SUHANA',
          style: TextStyle(
            letterSpacing: 6,
            color: Colors.cyanAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white38),
            onPressed: () => setState(() => _messages.clear()),
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.cyanAccent),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 10),
          _buildAvatar(),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              statusText,
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return Align(
                  alignment: msg.isUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.82,
                    ),
                    decoration: BoxDecoration(
                      color: msg.isInfo
                          ? Colors.orange.withOpacity(0.12)
                          : msg.isUser
                              ? Colors.cyan.shade800
                              : const Color(0xFF161B26),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      msg.text,
                      style: TextStyle(
                        color: msg.isInfo
                            ? Colors.orange.shade200
                            : Colors.white,
                        fontSize: 15,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(6),
              child: CircularProgressIndicator(color: Colors.cyanAccent),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 18),
              child: Row(
  children: [
    Expanded(
      child: TextField(
        controller: _inputController,
        textInputAction: TextInputAction.send,
        decoration: InputDecoration(
          hintText: 'Suhana se baat karo...',
          filled: true,
          fillColor: const Color(0xFF161B26),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none,
          ),
        ),
        onSubmitted: (_) => _sendMessage(),
      ),
    ),
    const SizedBox(width: 6),

    IconButton(
      onPressed: _toggleListening,
      icon: Icon(
        _isListening ? Icons.mic : Icons.mic_none,
        color: _isListening ? Colors.red : Colors.cyanAccent,
        size: 30,
      ),
    ),

    CircleAvatar(
      backgroundColor: Colors.cyanAccent,
      child: IconButton(
        icon: const Icon(Icons.send, color: Colors.black),
        onPressed: () => _sendMessage(_inputController.text),
      ),
    ),
  ],
)
              ],
            ),
          ),
        ],
      ),
    );
  }
}
