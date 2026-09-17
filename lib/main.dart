import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const JarvisApp());

class JarvisApp extends StatelessWidget {
  const JarvisApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JARVIS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0E21),
        primaryColor: Colors.cyanAccent,
      ),
      home: const HomeScreen(),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  ChatMessage(this.text, this.isUser);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FlutterTts _tts = FlutterTts();

  final List<ChatMessage> _messages = [];
  String _provider = 'Groq (FREE)';
  String _apiKey = '';
  String _model = 'llama-3.3-70b-versatile';
  String _customUrl = '';
  bool _isLoading = false;
  bool _isSpeaking = false;

  late AnimationController _animController;
  late Animation<double> _pulse;

  static const String systemPrompt =
      'You are JARVIS, a friendly female AI assistant. Reply in the same language the user speaks (Hindi or English). Keep replies short and helpful.';

  static const Map<String, Map<String, String>> providers = {
    'Groq (FREE)': {
      'url': 'https://api.groq.com/openai/v1/chat/completions',
      'model': 'llama-3.3-70b-versatile',
      'type': 'openai',
      'hint': 'gsk_... console.groq.com se free lo',
    },
    'Google Gemini (FREE)': {
      'url': 'https://generativelanguage.googleapis.com/v1beta/models/',
      'model': 'gemini-2.0-flash',
      'type': 'gemini',
      'hint': 'AIza... aistudio.google.com se free lo',
    },
    'OpenRouter (FREE)': {
      'url': 'https://openrouter.ai/api/v1/chat/completions',
      'model': 'meta-llama/llama-3.3-70b-instruct:free',
      'type': 'openai',
      'hint': 'sk-or-... openrouter.ai se free lo',
    },
    'OpenAI (Paid)': {
      'url': 'https://api.openai.com/v1/chat/completions',
      'model': 'gpt-4o-mini',
      'type': 'openai',
      'hint': 'sk-... platform.openai.com',
    },
    'DeepSeek': {
      'url': 'https://api.deepseek.com/chat/completions',
      'model': 'deepseek-chat',
      'type': 'openai',
      'hint': 'sk-... platform.deepseek.com',
    },
    'Custom': {
      'url': '',
      'model': '',
      'type': 'openai',
      'hint': 'Apna URL, model aur key daalo',
    },
  };

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.9, end: 1.15).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
    _loadSettings();
    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('hi-IN');
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.1);
    _tts.setStartHandler(() => setState(() => _isSpeaking = true));
    _tts.setCompletionHandler(() => setState(() => _isSpeaking = false));
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _provider = prefs.getString('provider') ?? 'Groq (FREE)';
      _apiKey = prefs.getString('api_key') ?? '';
      _model = prefs.getString('model') ?? providers[_provider]!['model']!;
      _customUrl = prefs.getString('custom_url') ?? '';
    });
    if (_apiKey.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showSettings());
    }
  }

  Future<void> _saveSettings(
      String provider, String key, String model, String customUrl) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('provider', provider);
    await prefs.setString('api_key', key);
    await prefs.setString('model', model);
    await prefs.setString('custom_url', customUrl);
    setState(() {
      _provider = provider;
      _apiKey = key;
      _model = model;
      _customUrl = customUrl;
    });
  }

  void _showSettings() {
    String selectedProvider = _provider;
    final keyController = TextEditingController(text: _apiKey);
    final modelController = TextEditingController(text: _model);
    final urlController = TextEditingController(text: _customUrl);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1D1E33),
          title: const Text('AI Settings',
              style: TextStyle(color: Colors.cyanAccent)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedProvider,
                  dropdownColor: const Color(0xFF1D1E33),
                  decoration: const InputDecoration(
                    labelText: 'AI Provider',
                    border: OutlineInputBorder(),
                  ),
                  items: providers.keys
                      .map((p) => DropdownMenuItem(
                          value: p,
                          child: Text(p, style: const TextStyle(fontSize: 13))))
                      .toList(),
                  onChanged: (val) {
                    setDialogState(() {
                      selectedProvider = val!;
                      modelController.text = providers[val]!['model']!;
                    });
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  providers[selectedProvider]!['hint']!,
                  style: const TextStyle(fontSize: 11, color: Colors.white54),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: keyController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'API Key',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: modelController,
                  decoration: const InputDecoration(
                    labelText: 'Model Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (selectedProvider == 'Custom') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: urlController,
                    decoration: const InputDecoration(
                      labelText: 'API URL',
                      hintText: 'https://...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _saveSettings(
                  selectedProvider,
                  keyController.text.trim(),
                  modelController.text.trim(),
                  urlController.text.trim(),
                );
                Navigator.pop(ctx);
              },
              child: const Text('Save', style: TextStyle(color: Colors.cyanAccent)),
            ),
          ],
        ),
      ),
    );
  }

  Future<String> _callOpenAICompatible(List<Map<String, String>> history) async {
    final url = _provider == 'Custom' ? _customUrl : providers[_provider]!['url']!;
    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      },
      body: jsonEncode({
        'model': _model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          ...history,
        ],
        'temperature': 0.7,
      }),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return data['choices'][0]['message']['content'] as String;
    }
    throw Exception('API Error ${response.statusCode}');
  }

  Future<String> _callGemini(List<Map<String, String>> history) async {
    final url =
        '${providers[_provider]!['url']}$_model:generateContent?key=$_apiKey';
    final contents = history
        .map((m) => {
              'role': m['role'] == 'assistant' ? 'model' : 'user',
              'parts': [
                {'text': m['content']}
              ],
            })
        .toList();
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'systemInstruction': {
          'parts': [
            {'text': systemPrompt}
          ]
        },
        'contents': contents,
      }),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return data['candidates'][0]['content']['parts'][0]['text'] as String;
    }
    throw Exception('API Error ${response.statusCode}');
  }

  Future<void> _sendMessage(String text) async {
    text = text.trim();
    if (text.isEmpty) return;
    if (_apiKey.isEmpty) {
      _showSettings();
      return;
    }
    _textController.clear();
    setState(() {
      _messages.add(ChatMessage(text, true));
      _isLoading = true;
    });
    _scrollToBottom();
    try {
      final history = _messages
          .map((m) => {
                'role': m.isUser ? 'user' : 'assistant',
                'content': m.text,
              })
          .toList();
      final String reply = providers[_provider]!['type'] == 'gemini'
          ? await _callGemini(history)
          : await _callOpenAICompatible(history);
      setState(() {
        _messages.add(ChatMessage(reply, false));
        _isLoading = false;
      });
      _scrollToBottom();
      await _tts.speak(reply);
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage('Error: $e', false));
        _isLoading = false;
      });
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('J.A.R.V.I.S',
            style: TextStyle(letterSpacing: 4, color: Colors.cyanAccent)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.cyanAccent),
            onPressed: _showSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 160,
            child: Center(
              child: ScaleTransition(
                scale: _pulse,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: _isSpeaking
                          ? [Colors.pinkAccent, Colors.purple]
                          : [Colors.cyanAccent, Colors.blue.shade900],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (_isSpeaking ? Colors.pinkAccent : Colors.cyanAccent)
                            .withOpacity(0.5),
                        blurRadius: 40,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.face_3, size: 55, color: Colors.white),
                ),
              ),
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
                  alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75),
                    decoration: BoxDecoration(
                      color: msg.isUser
                          ? Colors.cyan.shade800
                          : const Color(0xFF1D1E33),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(msg.text, style: const TextStyle(fontSize: 15)),
                  ),
                );
              },
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(color: Colors.cyanAccent),
            ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: InputDecoration(
                      hintText: 'Message likho...',
                      filled: true,
                      fillColor: const Color(0xFF1D1E33),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    onSubmitted: _sendMessage,
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.cyanAccent,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.black),
                    onPressed: () => _sendMessage(_textController.text),
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
