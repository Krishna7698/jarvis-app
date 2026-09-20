import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

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

  String _apiKey = '';
  String _model = 'gemini-2.5-flash';

  bool _isLoading = false;
  bool _isSpeaking = false;

  static const List<String> _models = [
    'gemini-2.5-flash',
    'gemini-flash-latest',
    'gemini-2.5-pro',
  ];

  static const String _systemPrompt =
      'You are Suhana, a sweet, smart, friendly female AI assistant. '
      'Reply in the same language as the user: Hindi, Hinglish or English. '
      'Keep answers short, natural and conversational. '
      'Do not use markdown symbols like * or #.';

  @override
  void initState() {
    super.initState();
    _setupTts();
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
      _model = prefs.getString('gemini_model') ?? 'gemini-2.5-flash';
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
    final nonInfo = _messages.where((m) => !m.isInfo).toList();
    final lastMessages =
        nonInfo.length > 12 ? nonInfo.sublist(nonInfo.length - 12) : nonInfo;

    final contents = <Map<String, dynamic>>[];

    for (final msg in lastMessages) {
      contents.add({
        'role': msg.isUser ? 'user' : 'model',
        'parts': [
          {'text': msg.text}
        ],
      });
    }

    contents.add({
      'role': 'user',
      'parts': [
        {'text': userText}
      ],
    });

    return contents;
  }

  Future<String> _callGemini(String userText) async {
    final contents = _buildHistory(userText);

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$_apiKey',
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

    try {
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final candidates = data['candidates'] as List?;

        if (candidates == null || candidates.isEmpty) {
          return '⚠️ Gemini ne empty response diya. Dobara try karo.';
        }

        final parts = (candidates[0]['content']?['parts'] as List?) ?? [];
        final text = parts.map((e) => '${e['text'] ?? ''}').join().trim();

        if (text.isEmpty) {
          return '⚠️ Blank response aaya. Dobara try karo.';
        }

        return text;
      }

      if (response.statusCode == 404) {
        return '⚠️ Model "$_model" tumhari API key par available nahi hai. Settings me gemini-2.5-flash ya gemini-flash-latest select karo.';
      }

      if (response.statusCode == 429) {
        return '⚠️ Rate limit lag gayi. 30-60 second ruk ke phir message bhejo.';
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        return '⚠️ API key invalid ya permission issue hai. Nayi Gemini key daalo.';
      }

      if (response.statusCode == 500 || response.statusCode == 503) {
        return '⚠️ Gemini server busy hai. 20-30 second baad try karo.';
      }

      return '⚠️ Error ${response.statusCode}.';
    } catch (_) {
      return '⚠️ Internet ya request issue. Dobara try karo.';
    }
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
                  'Recommended: gemini-2.5-flash',
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
                    onSubmitted: _sendMessage,
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Colors.cyanAccent,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.black),
                    onPressed: () => _sendMessage(_inputController.text),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
