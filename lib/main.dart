import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const SuhanaApp());

class SuhanaApp extends StatelessWidget {
  const SuhanaApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Suhana',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF070B18),
      ),
      home: const Home(),
    );
  }
}

class Msg {
  final String text;
  final bool me;
  final bool info;
  Msg(this.text, this.me, {this.info = false});
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with SingleTickerProviderStateMixin {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _tts = FlutterTts();
  final _msgs = <Msg>[];

  String _key = '';
  String _model = 'gemini-2.5-flash';
  bool _loading = false;
  bool _speaking = false;

  late AnimationController _pulse;

  static const _sys =
      'You are Suhana, a friendly female AI assistant. Reply in the same language '
      'the user speaks (Hindi, Hinglish or English). Keep answers short, warm and useful. '
      'Do not use markdown. If you are not sure about live/latest facts, say so clearly.';

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _setupTts();
    _load();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _tts.stop();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _setupTts() async {
    await _tts.setSpeechRate(0.47);
    await _tts.setPitch(1.18);
    await _tts.setVolume(1);
    _tts.setStartHandler(() {
      if (mounted) setState(() => _speaking = true);
    });
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _speaking = false);
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() => _speaking = false);
    });
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _key = p.getString('key') ?? '';
      _model = p.getString('model') ?? 'gemini-2.5-flash';
    });
    if (_key.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _settings());
    }
  }

  Future<void> _save(String key, String model) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('key', key);
    await p.setString('model', model);
    setState(() {
      _key = key;
      _model = model;
    });
  }

  void _info(String t) {
    setState(() => _msgs.add(Msg(t, false, info: true)));
    _goDown();
  }

  void _goDown() {
    Future.delayed(const Duration(milliseconds: 80), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _err(http.Response r) {
    var msg = '';
    try {
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      final e = d is Map ? d['error'] : null;
      if (e is Map) msg = '${e['message'] ?? ''}';
    } catch (_) {}
    if (msg.isEmpty) msg = 'Server error';
    if (r.statusCode == 404) {
      return 'Model nahi mila. Settings me gemini-2.5-flash try karo.';
    }
    if (r.statusCode == 401 || r.statusCode == 403) {
      return 'API key galat/expired. Nayi key daalo. Key screenshot me mat dikhana.';
    }
    if (r.statusCode == 429 || r.statusCode == 503) {
      return 'Gemini busy/limit. 30 sec baad try karo.';
    }
    return 'HTTP ${r.statusCode}: $msg';
  }

  Future<String> _ask(String user) async {
    final hist = <Map<String, dynamic>>[];
    for (final m in _msgs.where((x) => !x.info).take(16)) {
      hist.add({
        'role': m.me ? 'user' : 'model',
        'parts': [
          {'text': m.text}
        ],
      });
    }
    hist.add({
      'role': 'user',
      'parts': [
        {'text': user}
      ],
    });

    Future<http.Response> call(String model) {
      return http
          .post(
            Uri.parse(
              'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
            ),
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': _key,
            },
            body: jsonEncode({
              'system_instruction': {
                'parts': [
                  {'text': _sys}
                ]
              },
              'contents': hist,
              'generationConfig': {'temperature': 0.7},
            }),
          )
          .timeout(const Duration(seconds: 60));
    }

    var res = await call(_model);
    if (res.statusCode == 404) {
      for (final alt in ['gemini-2.5-flash', 'gemini-flash-latest', 'gemini-2.0-flash']) {
        if (alt == _model) continue;
        res = await call(alt);
        if (res.statusCode == 200) {
          setState(() => _model = alt);
          final p = await SharedPreferences.getInstance();
          await p.setString('model', alt);
          _info('Model switch: $alt');
          break;
        }
      }
    }
    if (res.statusCode != 200) throw Exception(_err(res));
    final d = jsonDecode(utf8.decode(res.bodyBytes));
    final cands = d['candidates'] as List?;
    if (cands == null || cands.isEmpty) {
      throw Exception('Suhana jawab nahi de paayi. Dobara try karo.');
    }
    final parts = (cands[0]['content']?['parts'] as List?) ?? [];
    final text = parts.map((p) => '${p['text'] ?? ''}').join().trim();
    if (text.isEmpty) throw Exception('Khali jawab aaya.');
    return text;
  }

  Future<void> _speak(String text) async {
    var t = text.replaceAll(RegExp(r'[*#`>~|]'), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty) return;
    final hindi = RegExp(r'[\u0900-\u097F]').hasMatch(t);
    try {
      await _tts.stop();
      await _tts.setLanguage(hindi ? 'hi-IN' : 'en-IN');
      await _tts.speak(t);
    } catch (_) {}
  }

  Future<void> _send(String text) async {
    text = text.trim();
    if (text.isEmpty || _loading) return;
    if (_key.isEmpty) {
      _settings();
      return;
    }
    _input.clear();
    setState(() {
      _msgs.add(Msg(text, true));
      _loading = true;
    });
    _goDown();
    try {
      final reply = await _ask(text);
      if (!mounted) return;
      setState(() {
        _msgs.add(Msg(reply, false));
        _loading = false;
      });
      _goDown();
      await _speak(reply);
    } catch (e) {
      setState(() => _loading = false);
      _info(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _settings() {
    final k = TextEditingController(text: _key);
    final m = TextEditingController(text: _model);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF12182B),
        title: const Text('Suhana Settings',
            style: TextStyle(color: Colors.cyanAccent)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: k,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Gemini API Key',
                hintText: 'AIza...  (aistudio.google.com)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: m,
              decoration: const InputDecoration(
                labelText: 'Model',
                hintText: 'gemini-2.5-flash',
                border: OutlineInputBorder(),
              ),
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
              _save(k.text.trim(), m.text.trim().isEmpty
                  ? 'gemini-2.5-flash'
                  : m.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('Save',
                style: TextStyle(color: Colors.cyanAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('SUHANA',
            style: TextStyle(letterSpacing: 5, color: Colors.cyanAccent)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white38),
            onPressed: () => setState(_msgs.clear),
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.cyanAccent),
            onPressed: _settings,
          ),
        ],
      ),
      body: Column(
        children: [
          ScaleTransition(
            scale: Tween(begin: 0.94, end: 1.06).animate(
              CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
            ),
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: _speaking
                      ? [Colors.pinkAccent, Colors.purple]
                      : [Colors.cyanAccent, Colors.indigo.shade900],
                ),
                boxShadow: [
                  BoxShadow(
                    color: (_speaking ? Colors.pinkAccent : Colors.cyanAccent)
                        .withOpacity(0.45),
                    blurRadius: 28,
                    spreadRadius: 6,
                  ),
                ],
              ),
              child: const Icon(Icons.face_3, size: 58, color: Colors.white),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              _speaking
                  ? 'Suhana bol rahi hai...'
                  : _loading
                      ? 'Suhana soch rahi hai...'
                      : 'Gemini • $_model',
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: _msgs.length,
              itemBuilder: (_, i) {
                final m = _msgs[i];
                return Align(
                  alignment:
                      m.me ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.8),
                    decoration: BoxDecoration(
                      color: m.info
                          ? Colors.orange.withOpacity(0.12)
                          : m.me
                              ? Colors.cyan.shade800
                              : const Color(0xFF12182B),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: SelectableText(
                      m.text,
                      style: TextStyle(
                        color: m.info ? Colors.orange.shade200 : Colors.white,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(6),
              child: CircularProgressIndicator(color: Colors.cyanAccent),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 18),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    textInputAction: TextInputAction.send,
                    decoration: InputDecoration(
                      hintText: 'Suhana se baat karo...',
                      filled: true,
                      fillColor: const Color(0xFF12182B),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: _send,
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Colors.cyanAccent,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.black),
                    onPressed: () => _send(_input.text),
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
