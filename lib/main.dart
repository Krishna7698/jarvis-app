import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const SuhanaApp());

class SuhanaApp extends StatelessWidget {
  const SuhanaApp({super.key});
  @override
  Widget build(BuildContext c) => MaterialApp(
        title: 'Suhana',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF070B18)),
        home: const Home(),
      );
}

class Msg {
  final String t; final bool me; final bool info;
  Msg(this.t, this.me, {this.info = false});
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with SingleTickerProviderStateMixin {
  final _in = TextEditingController();
  final _sc = ScrollController();
  final _tts = FlutterTts();
  final _msgs = <Msg>[];

  String _key = '';
  String _model = 'gemini-1.5-pro';
  bool _busy = false;
  bool _talk = false;

  late AnimationController _pulse;

  static const _sys =
      'You are Suhana, a beautiful, friendly female AI assistant. '
      'Reply naturally in Hinglish, Hindi or English depending on user. '
      'Keep it short (2-3 lines max), sweet, slightly playful. No markdown like * or #. '
      'Always respond as a real girl talking to a friend.';

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);
    _setupTts();
    _load();
  }

  @override
  void dispose() { _pulse.dispose(); _tts.stop(); _in.dispose(); _sc.dispose(); super.dispose(); }

  Future<void> _setupTts() async {
    await _tts.setSpeechRate(0.48);
    await _tts.setPitch(1.12);
    await _tts.setVolume(1.0);
    await _tts.setLanguage('hi-IN');
    _tts.setStartHandler(() { if (mounted) setState(() => _talk = true); });
    _tts.setCompletionHandler(() { if (mounted) setState(() => _talk = false); });
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _key = p.getString('gkey') ?? '';
      _model = p.getString('model') ?? 'gemini-1.5-pro';
    });
    if (_key.isEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _settings());
  }

  Future<void> _save(String k, String m) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('gkey', k);
    await p.setString('model', m.isEmpty ? 'gemini-1.5-pro' : m);
    if (!mounted) return;
    setState(() {
      _key = k;
      _model = m.isEmpty ? 'gemini-1.5-pro' : m;
    });
  }

  void _info(String s) {
    setState(() => _msgs.add(Msg(s, false, info: true)));
    _down();
  }

  void _down() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_sc.hasClients) _sc.animateTo(_sc.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  List<Map<String, String>> _hist() {
    final h = _msgs.where((m) => !m.info).toList();
    final r = h.length > 14 ? h.sublist(h.length - 14) : h;
    return r.map((m) => {'role': m.me ? 'user' : 'model', 'text': m.t}).toList();
  }

  Future<String?> _geminiCall(String user, List<Map<String, String>> hist) async {
    final contents = hist.map((e) => {'role': e['role'] == 'model' ? 'model' : 'user', 'parts': [{'text': e['text']!}]}).toList();
    contents.add({'role': 'user', 'parts': [{'text': user}]});

    final body = {
      'system_instruction': {'parts': [{'text': _sys}]},
      'contents': contents,
      'generationConfig': {'temperature': 0.7},
    };

    final res = await http.post(
      Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$_key'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 55));

    if (res.statusCode == 200) {
      final d = jsonDecode(utf8.decode(res.bodyBytes));
      final c = d['candidates'] as List?;
      if (c != null && c.isNotEmpty) {
        final parts = (c[0]['content']?['parts'] as List?) ?? [];
        final txt = parts.map((p) => '${p['text'] ?? ''}').join().trim();
        if (txt.isNotEmpty) return txt;
      }
      return null;
    }

    // Error mapping
    final errMsg = utf8.decode(res.bodyBytes, allowMalformed: true);
    if (res.statusCode == 404) return '⚠️ Model $_model available nahi. Tumhari key sahi hai? Check Settings.';
    if (res.statusCode == 429) return '⚠️ Rate limit. Free Gemini quota khatam. 30 sec baad ek message bhejo.';
    if (res.statusCode == 401 || res.statusCode == 403) return '⚠️ API key galat. Settings me sahi key daalo. Key screenshot mat dikhana.';
    if (res.statusCode == 503 || res.statusCode == 500) return '⚠️ Gemini server busy. 30 sec baad try karo.';
    return '⚠️ Error ${res.statusCode}: ${errMsg.isNotEmpty ? errMsg : 'Unknown error'}';
  }

  Future<String?> _ask(String user) async {
    final reply = await _geminiCall(user, _hist());
    return reply;
  }

  // App actions
  Future<void> _handleAppAction(String text) async {
    final lower = text.toLowerCase();
    if (lower.contains('youtube') || lower.contains('youtube kholo')) {
      await launchUrl(Uri.parse('https://youtube.com'), mode: LaunchMode.externalApplication);
      setState(() => _msgs.add(Msg('YouTube open kar rahi hoon! 🔥', false)));
    } else if (lower.contains('whatsapp') || lower.contains('whatsapp kholo')) {
      await launchUrl(Uri.parse('https://whatsapp.com'), mode: LaunchMode.externalApplication);
      setState(() => _msgs.add(Msg('WhatsApp open ho gaya! 📱', false)));
    } else if (lower.contains('instagram') || lower.contains('instagram kholo')) {
      await launchUrl(Uri.parse('https://instagram.com'), mode: LaunchMode.externalApplication);
      setState(() => _msgs.add(Msg('Instagram khul gaya! ✨', false)));
    } else if (lower.contains('google par') || lower.contains('google search') || lower.contains('search karo')) {
      final q = text.replaceAll(RegExp(r'google par|search karo|search|google pe|google'), '').trim();
      final url = Uri.parse('https://www.google.com/search?q=${Uri.encodeComponent(q.isEmpty ? 'Suhana' : q)}');
      await launchUrl(url, mode: LaunchMode.externalApplication);
      setState(() => _msgs.add(Msg('Google par "$q" search kar diya! 🔍', false)));
    } else {
      // Nothing to open
    }
  }

  Future<void> _speak(String s) async {
    var t = s.replaceAll(RegExp(r'[*#`_>]|⚠️|🔥|✨|📱|🔍'), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty) return;
    final hi = RegExp(r'[\u0900-\u097F]').hasMatch(t);
    try { await _tts.setLanguage(hi ? 'hi-IN' : 'en-IN'); await _tts.speak(t); } catch (_) {}
  }

  Future<void> _send(String text) async {
    text = text.trim();
    if (text.isEmpty || _busy) return;

    // Check for app commands first
    final lower = text.toLowerCase();
    if (lower.contains('youtube') || lower.contains('whatsapp') || lower.contains('instagram') ||
        lower.contains('google par') || lower.contains('search karo') || lower.contains('khol')) {
      await _handleAppAction(text);
      return;
    }

    if (_key.isEmpty) {
      _settings();
      return;
    }

    _in.clear();
    setState(() => _msgs.add(Msg(text, true)));
    _down();
    setState(() => _busy = true);

    try {
      final reply = await _ask(text);
      if (!mounted) return;
      setState(() {
        _msgs.add(Msg(reply ?? 'Hmm... kuch galat ho gaya.', false));
        _busy = false;
      });
      _down();
      if (reply != null && !reply.startsWith('⚠️')) {
        await _speak(reply);
      }
    } catch (e) {
      setState(() => _busy = false);
      setState(() => _msgs.add(Msg('⚠️ Error: $e', false)));
    }
  }

  void _settings() {
    final g = TextEditingController(text: _key);
    final m = TextEditingController(text: 'gemini-1.5-pro'); // Fixed!
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF12182B),
        title: const Text('Suhana Settings', style: TextStyle(color: Colors.cyanAccent, fontSize: 20)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: g,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Gemini API Key',
              hintText: 'AIza... (aistudio.google.com)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Text('Model:', style: TextStyle(color: Colors.white54)),
          Text('gemini-1.5-pro (Fixed like MYRAA)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              _save(g.text.trim(), m.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('Save', style: TextStyle(color: Colors.cyanAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = _key.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        centerTitle: true,
        title: const Text('SUHANA', style: TextStyle(letterSpacing: 8, color: Colors.cyanAccent, fontSize: 22)),
        actions: [
          IconButton(icon: const Icon(Icons.delete_outline, color: Colors.white38), onPressed: () => setState(_msgs.clear)),
          IconButton(icon: const Icon(Icons.settings, color: Colors.cyanAccent), onPressed: _settings),
        ],
      ),
      body: Column(children: [
        const SizedBox(height: 8),
        ScaleTransition(
          scale: Tween(begin: 0.94, end: 1.06).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
          child: Container(
            width: 125,
            height: 125,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: _talk ? [Colors.pinkAccent, Colors.deepPurple] : [Colors.cyanAccent, Colors.indigo.shade900]),
              boxShadow: [BoxShadow(color: (_talk ? Colors.pinkAccent : Colors.cyanAccent).withOpacity(0.45), blurRadius: 30, spreadRadius: 8)],
            ),
            child: const Icon(Icons.face_3, size: 60, color: Colors.white70),
          ),
        ),
        Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(ready ? 'Suhana • gemini-1.5-pro' : 'Setup pending', style: const TextStyle(color: Colors.white54, fontSize: 12))),
        Expanded(
          child: ListView.builder(
            controller: _sc,
            padding: const EdgeInsets.all(14),
            itemCount: _msgs.length,
            itemBuilder: (_, i) {
              final msg = _msgs[i];
              return Align(
                alignment: msg.me ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding: const EdgeInsets.all(12),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
                  decoration: BoxDecoration(
                    color: msg.info ? Colors.orange.withOpacity(0.1)
                        : msg.me ? Colors.cyan.shade800
                        : const Color(0xFF12182B),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: SelectableText(msg.t, style: TextStyle(color: msg.info ? Colors.orange.shade200 : Colors.white, fontSize: 15)),
                ),
              );
            },
          ),
        ),
        if (_busy) const Padding(padding: EdgeInsets.all(6), child: CircularProgressIndicator(color: Colors.cyanAccent)),
        Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 18),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _in,
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  hintText: 'Suhana se kuch bhi poochho...',
                  filled: true,
                  fillColor: const Color(0xFF12182B),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                ),
                onSubmitted: _send,
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: Colors.cyanAccent,
              child: IconButton(icon: const Icon(Icons.send, color: Colors.black87, size: 22), onPressed: () => _send(_in.text)),
            ),
          ]),
        ),
      ]),
    );
  }
}
