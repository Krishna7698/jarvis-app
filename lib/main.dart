import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
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
  final bool isInfo;
  ChatMessage(this.text, this.isUser, {this.isInfo = false});
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FlutterTts _tts = FlutterTts();

  final List<ChatMessage> _messages = [];

  String _provider = 'Groq (FREE)';
  String _apiKey = '';
  String _model = 'llama-3.3-70b-versatile';
  String _customUrl = '';
  String _ttsProvider = 'Android TTS';
  String _elevenKey = '';
  String _elevenVoice =
      '21m00Tcm4TlvDq8ikWAM'; // Rachel — soft female, free tier
  bool _isLoading = false;
  bool _isSpeaking = false;
  bool _streaming = false;

  late AnimationController _avatarController;
  late AnimationController _blinkController;
  late AnimationController _mouthController;
  late Animation<double> _breath;
  late Animation<double> _blink;

  double _mouthOpen = 0;
  String _avatarMood = 'happy';

  static const String geminiBase =
      'https://generativelanguage.googleapis.com/v1beta/models';

  static const Map<String, Map<String, String>> providers = {
    'Groq (FREE)': {
      'url': 'https://api.groq.com/openai/v1/chat/completions',
      'models': 'https://api.groq.com/openai/v1/models',
      'model': 'llama-3.3-70b-versatile',
      'type': 'openai',
      'hint': 'gsk_... (console.groq.com — super fast + free)',
    },
    'Google Gemini (FREE)': {
      'url': geminiBase,
      'models': geminiBase,
      'model': 'gemini-flash-latest',
      'type': 'gemini',
      'hint': 'AIza... (aistudio.google.com — free)',
    },
    'OpenRouter (FREE)': {
      'url': 'https://openrouter.ai/api/v1/chat/completions',
      'models': 'https://openrouter.ai/api/v1/models',
      'model': 'meta-llama/llama-3.3-70b-instruct:free',
      'type': 'openai',
      'hint': 'sk-or-... (openrouter.ai)',
    },
    'OpenAI (Paid)': {
      'url': 'https://api.openai.com/v1/chat/completions',
      'models': 'https://api.openai.com/v1/models',
      'model': 'gpt-4o-mini',
      'type': 'openai',
      'hint': 'sk-... (platform.openai.com)',
    },
    'DeepSeek (Paid)': {
      'url': 'https://api.deepseek.com/chat/completions',
      'models': 'https://api.deepseek.com/models',
      'model': 'deepseek-chat',
      'type': 'openai',
      'hint': 'sk-... (platform.deepseek.com)',
    },
    'Custom (OpenAI-style)': {
      'url': '',
      'models': '',
      'model': '',
      'type': 'openai',
      'hint': 'Apna URL, model aur key',
    },
  };

  static const Map<String, String> elevenLabsVoices = {
    'Rachel (soft)': '21m00Tcm4TlvDq8ikWAM',
    'Bella (warm)': 'EXAVITQu4vr4xnSDxMaL',
    'Elli (young)': 'MF3d2xWhKpnwSf6rjNn2',
    'Dorothy (kind)': 'ThT5KcBeYPX3keUQqHPh',
    'Freya (bright)': 'jsCqWAovK2LkecY7zXl4',
    'Grace (calm)': 'hpp4J3GqjHrEIb2eVgTk',
  };

  // ==================== LIFECYCLE ====================

  @override
  void initState() {
    super.initState();

    _avatarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _mouthController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );

    _breath = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _avatarController, curve: Curves.easeInOut),
    );
    _blink = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _blinkController, curve: Curves.easeInOut),
    );

    _blinkController.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        _blinkController.reverse();
      }
    });

    Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_blinkController.isAnimating) {
        _blinkController.forward();
      }
    });

    _mouthController.addListener(() {
      if (mounted) setState(() => _mouthOpen = _mouthController.value);
    });

    _initTts();
    _loadSettings();
  }

  @override
  void dispose() {
    _avatarController.dispose();
    _blinkController.dispose();
    _mouthController.dispose();
    _tts.stop();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ==================== TTS ====================

  Future<void> _initTts() async {
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.15);
    await _tts.setVolume(1.0);
    _tts.setStartHandler(() {
      if (mounted) {
        setState(() {
          _isSpeaking = true;
          _streaming = true;
        });
        _avatarController.repeat(reverse: true);
        _mouthController.repeat(reverse: true);
      }
    });
    _tts.setCompletionHandler(() {
      if (mounted) {
        setState(() {
          _isSpeaking = false;
          _streaming = false;
          _mouthOpen = 0;
        });
        _mouthController.stop();
        _avatarController.repeat(reverse: true);
      }
    });
    _tts.setCancelHandler(() {
      if (mounted) {
        setState(() {
          _isSpeaking = false;
          _streaming = false;
          _mouthOpen = 0;
        });
        _mouthController.stop();
      }
    });
  }

  Future<void> _speak(String text) async {
    var clean = text.replaceAll(RegExp(r'[*#`>~|]'), ' ').trim();
    clean = clean.replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) return;
    final hasHindi = RegExp(r'[\u0900-\u097F]').hasMatch(clean);

    try {
      await _tts.stop();
    } catch (_) {}

    if (_ttsProvider == 'ElevenLabs (High Quality)' && _elevenKey.isNotEmpty) {
      await _speakElevenLabs(clean);
      return;
    }

    try {
      await _tts.setLanguage(hasHindi ? 'hi-IN' : 'en-IN');
      final sentences = clean.split(RegExp(r'(?<=[.!?।])\s+'));
      for (final s in sentences) {
        if (s.trim().isEmpty) continue;
        await _tts.speak(s.trim());
      }
    } catch (e) {
      _addInfo('🔊 Voice error: $e');
    }
  }

  Future<void> _speakElevenLabs(String text) async {
    try {
      final voiceId = _elevenVoice.isEmpty
          ? elevenLabsVoices.values.first
          : _elevenVoice;
      final url = Uri.parse(
          'https://api.elevenlabs.io/v1/text-to-speech/$voiceId');
      final res = await http.post(
        url,
        headers: {
          'xi-api-key': _elevenKey,
          'Content-Type': 'application/json',
          'Accept': 'audio/mpeg',
        },
        body: jsonEncode({
          'text': text,
          'model_id': 'eleven_turbo_v2_5',
          'voice_settings': {
            'stability': 0.55,
            'similarity_boost': 0.80,
            'style': 0.35,
            'use_speaker_boost': true,
          },
        }),
      ).timeout(const Duration(seconds: 30));

      if (res.statusCode != 200) {
        _addInfo(
            '⚠️ ElevenLabs API Error ${res.statusCode}: key check karo.');
        return;
      }
      // Audio bytes mil jayenge — real device pe humein audio play karne ke liye
      // package kaam aayega. Yahan simple feedback:
      _addInfo(
          '🔊 ElevenLabs ne ${text.length} chars ka audio bhej diya (Premium).');
    } on TimeoutException {
      _addInfo('⚠️ ElevenLabs se time pe jawab nahi aaya.');
    } catch (e) {
      _addInfo('⚠️ ElevenLabs error: $e');
    }
  }

  // ==================== SETTINGS ====================

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('provider') ?? 'Groq (FREE)';
    final provider = providers.containsKey(saved) ? saved : 'Groq (FREE)';
    final savedModel = (prefs.getString('model') ?? '').trim();
    final savedTts = prefs.getString('tts_provider') ?? 'Android TTS';
    final savedEKey = prefs.getString('eleven_key') ?? '';
    final savedEVoice = prefs.getString('eleven_voice') ?? '';
    if (!mounted) return;
    setState(() {
      _provider = provider;
      _apiKey = prefs.getString('api_key') ?? '';
      _model = savedModel.isEmpty
          ? providers[provider]!['model']!
          : savedModel;
      _customUrl = prefs.getString('custom_url') ?? '';
      _ttsProvider =
          ['Android TTS', 'ElevenLabs (High Quality)'].contains(savedTts)
              ? savedTts
              : 'Android TTS';
      _elevenKey = savedEKey;
      _elevenVoice = savedEVoice.isEmpty
          ? elevenLabsVoices.values.first
          : savedEVoice;
    });
    if (_apiKey.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showSettings());
    }
  }

  Future<void> _saveAll({
    String? provider,
    String? apiKey,
    String? model,
    String? customUrl,
    String? ttsProvider,
    String? elevenKey,
    String? elevenVoice,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (provider != null) await prefs.setString('provider', provider);
    if (apiKey != null) await prefs.setString('api_key', apiKey);
    if (model != null) await prefs.setString('model', model.trim());
    if (customUrl != null) await prefs.setString('custom_url', customUrl);
    if (ttsProvider != null) {
      await prefs.setString('tts_provider', ttsProvider);
    }
    if (elevenKey != null) await prefs.setString('eleven_key', elevenKey);
    if (elevenVoice != null) {
      await prefs.setString('eleven_voice', elevenVoice);
    }
    if (!mounted) return;
    setState(() {
      if (provider != null) _provider = provider;
      if (apiKey != null) _apiKey = apiKey;
      if (model != null) {
        _model = model.trim().isEmpty
            ? providers[provider ?? _provider]!['model']!
            : model.trim();
      }
      if (customUrl != null) _customUrl = customUrl;
      if (ttsProvider != null) _ttsProvider = ttsProvider;
      if (elevenKey != null) _elevenKey = elevenKey;
      if (elevenVoice != null) _elevenVoice = elevenVoice;
    });
  }

  Future<void> _setModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('model', model);
    if (mounted) setState(() => _model = model);
  }

  // ==================== MODEL DISCOVERY ====================

  static const List<String> _chatSkip = [
    'whisper', 'tts', 'embed', 'guard', 'moderation', 'image', 'audio',
    'live', 'realtime', 'transcri', 'aqa', 'robotics', 'computer-use',
    'dall-e', 'veo', 'imagen', 'learnlm', 'preview-exp',
  ];

  static bool _isChatModel(String name) {
    final s = name.toLowerCase();
    for (final w in _chatSkip) {
      if (s.contains(w)) return false;
    }
    return true;
  }

  static int _score(String name) {
    final s = name.toLowerCase();
    if (s.contains('flash') && s.contains('latest') && !s.contains('lite')) {
      return 0;
    }
    if (s.contains('latest')) return 1;
    if (s.contains('flash') && !s.contains('lite') && !s.contains('exp')) {
      return 2;
    }
    if (s.contains('llama') &&
        (s.contains('70b') ||
            s.contains('versatile') ||
            s.contains('maverick') ||
            s.contains('scout'))) {
      return 2;
    }
    if (s.contains('gpt') && s.contains('mini')) return 2;
    if (s == 'deepseek-chat') return 2;
    if (s.contains('flash') ||
        s.contains('llama') ||
        s.contains('gpt') ||
        s.contains('deepseek') ||
        s.contains('gemma') ||
        s.contains('qwen') ||
        s.contains('mistral')) {
      return 3;
    }
    return 4;
  }

  static int _rank(String a, String b) {
    final c = _score(a).compareTo(_score(b));
    if (c != 0) return c;
    return b.compareTo(a);
  }

  Future<List<String>> _fetchModels(
      String provider, String key, String customUrl) async {
    final p = providers[provider]!;
    final names = <String>[];

    if (p['type'] == 'gemini') {
      final res = await http.get(
        Uri.parse('$geminiBase?pageSize=200'),
        headers: {'x-goog-api-key': key},
      ).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw Exception(_shortError(res));
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      final List list = (data['models'] as List?) ?? [];
      for (final m in list) {
        final methods = (m['supportedGenerationMethods'] as List?) ?? [];
        if (!methods.contains('generateContent')) continue;
        var n = (m['name'] ?? '').toString();
        if (n.startsWith('models/')) n = n.substring(7);
        if (_isChatModel(n)) names.add(n);
      }
    } else {
      if (provider == 'Custom (OpenAI-style)' && customUrl.isEmpty) {
        throw Exception('Custom ke liye pehle Chat API URL daalo.');
      }
      final url = provider == 'Custom (OpenAI-style)'
          ? customUrl.replaceFirst(RegExp(r'/chat/completions/?$'), '/models')
          : p['models']!;
      final res = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $key'},
      ).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw Exception(_shortError(res));
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      final List list = (data['data'] as List?) ?? [];
      for (final m in list) {
        final id = (m['id'] ?? '').toString();
        if (!_isChatModel(id)) continue;
        if (provider == 'OpenRouter (FREE)' && !id.endsWith(':free')) continue;
        names.add(id);
      }
    }
    names.sort(_rank);
    return names;
  }

  // ==================== ERROR DECODE ====================

  String _shortError(http.Response res) {
    String msg = '';
    try {
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      final err = data is Map ? data['error'] : null;
      if (err is Map) {
        msg = (err['message'] ?? '').toString();
      } else if (err is String) {
        msg = err;
      } else if (data is Map && data['message'] != null) {
        msg = data['message'].toString();
      }
    } catch (_) {}
    if (msg.isEmpty) {
      msg = utf8
          .decode(res.bodyBytes, allowMalformed: true)
          .trim()
          .replaceAll('\n', ' ');
      if (msg.length > 250) msg = '${msg.substring(0, 250)}…';
      if (msg.isEmpty) msg = 'Server ne khali jawab diya';
    }
    String hint = '';
    final low = msg.toLowerCase();
    if (res.statusCode == 401 || res.statusCode == 403 || low.contains('api key')) {
      hint = 'API key galat/expired lagti hai. Nayi key banao.';
    } else if (res.statusCode == 404 || low.contains('model')) {
      hint = 'Model available nahi. Settings → "Models dhundo" → list se chuno.';
    } else if (res.statusCode == 429) {
      hint = 'Free limit khatam. Provider badlo (Groq sabse fast + free).';
    } else if (res.statusCode == 503 ||
        low.contains('overloaded') ||
        low.contains('unavailable')) {
      hint = 'Server abhi busy hai (Gemini overloaded). Groq try karo.';
    } else if (res.statusCode >= 500) {
      hint = 'Server side problem. 30 second baad dobara bhejo.';
    }
    return 'HTTP ${res.statusCode}: $msg${hint.isEmpty ? '' : '\n👉 $hint'}';
  }

  // ==================== WEB SEARCH (live data) ====================

  Future<String> _webSearch(String query) async {
    final url = Uri.parse('https://duckduckgo.com/html/?q=${Uri.encodeQueryComponent(query)}');
    try {
      final res = await http.get(
        url,
        headers: {'User-Agent': 'Mozilla/5.0 (JarvisApp/1.0)'},
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return '';
      final body = utf8.decode(res.bodyBytes);
      // Extract top 5 snippets from <a class="result__a"> and <a class="result__snippet">
      final titleRe = RegExp(r'class="result__a"[^>]*>([^<]+)</a>');
      final snipRe = RegExp(r'class="result__snippet"[^>]*>([\s\S]*?)</a>');
      final titles = titleRe.allMatches(body).map((m) => m.group(1)!.trim()).take(5).toList();
      final snips = snipRe.allMatches(body).map((m) {
        final t = m.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
        return t;
      }).take(5).toList();
      final out = StringBuffer();
      for (var i = 0; i < titles.length; i++) {
        out.writeln('${i + 1}. ${titles[i]}');
        if (i < snips.length) out.writeln('   ${snips[i]}');
      }
      return out.toString();
    } catch (_) {
      return '';
    }
  }

  bool _needsWebSearch(String userText) {
    final t = userText.toLowerCase();
    const keywords = [
      'news', 'aaj ki', 'latest', 'abhi', 'today', 'now', 'current',
      'score', 'match', 'cricket', 'weather', 'price', 'kitna',
      'kab', 'kaha', 'kaise', 'why', 'when', 'where',
      '2026', '2025', 'this year', 'is year', 'abhi ka',
      'live', 'breaking', 'update', 'updates',
    ];
    for (final k in keywords) {
      if (t.contains(k)) return true;
    }
    return false;
  }

  // ==================== AI CALLS ====================

  Future<String> _askAI({
    required List<Map<String, String>> history,
    required String userText,
  }) async {
    final isGemini = providers[_provider]!['type'] == 'gemini';

    // Optionally fetch live data first
    String liveContext = '';
    if (_needsWebSearch(userText)) {
      liveContext = await _webSearch(
          '$userText (live data, latest info from internet)');
      if (liveContext.isNotEmpty) {
        _addInfo('🔎 Live web data le liya — AI use karega.');
      }
    }

    final sysPrompt =
        'You are JARVIS, a friendly female AI assistant. Reply in the same '
        'language the user speaks (Hindi, Hinglish or English). Keep replies '
        'short and natural. Do not use markdown symbols.\n'
        '${liveContext.isEmpty ? '' : '\nLatest live web data (from internet):\n$liveContext\n\nIf the user asks about current news or latest data, prioritize this info over your training data and clearly mention it is from live web search.'}';

    Future<http.Response> call(String m) {
      final h = history;
      if (isGemini) {
        final contents = h
            .map((e) => {
                  'role': e['role'] == 'assistant' ? 'model' : 'user',
                  'parts': [
                    {'text': e['content']}
                  ],
                })
            .toList();
        return http
            .post(
              Uri.parse('$geminiBase/$m:generateContent'),
              headers: {
                'Content-Type': 'application/json',
                'x-goog-api-key': _apiKey,
              },
              body: jsonEncode({
                'system_instruction': {
                  'parts': [
                    {'text': sysPrompt}
                  ]
                },
                'contents': contents,
                'generationConfig': {'temperature': 0.7},
              }),
            )
            .timeout(const Duration(seconds: 60));
      }
      final url = _provider == 'Custom (OpenAI-style)'
          ? _customUrl
          : providers[_provider]!['url']!;
      final headers = <String, String>{
        'Content-Type': 'application/json',
        
