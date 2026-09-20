import "dart:convert";
import "package:flutter/material.dart";
import "package:flutter_tts/flutter_tts.dart";
import "package:http/http.dart" as http;
import "package:shared_preferences/shared_preferences.dart";
import "package:url_launcher/url_launcher.dart";

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF070B18)),
      home: const Home(),
    );
  }
}

class Chat {
  final String text;
  final bool me;
  final bool info;
  Chat(this.text, this.me, {this.info = false});
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with SingleTickerProviderStateMixin {
  final box = TextEditingController();
  final scroll = ScrollController();
  final tts = FlutterTts();
  final chats = <Chat>[];
  String key = "";
  String model = "gemini-2.5-flash";
  bool busy = false;
  bool talk = false;
  late AnimationController pulse;

  static const sys =
      "You are Suhana, a beautiful and playful AI girl assistant. Reply naturally in Hindi, Hinglish or English like the user. Keep it short (1-2 lines), sweet and warm. No markdown symbols.";

  @override
  void initState() {
    super.initState();
    pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    tts.setSpeechRate(0.45);
    tts.setPitch(1.2);
    tts.setStartHandler(() { if (mounted) setState(() => talk = true); });
    tts.setCompletionHandler(() { if (mounted) setState(() => talk = false); });
    tts.setCancelHandler(() { if (mounted) setState(() => talk = false); });
    SharedPreferences.getInstance().then((p) {
      setState(() {
        key = p.getString("gkey") ?? "";
        model = p.getString("model") ?? "gemini-2.5-flash";
      });
      if (key.isEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => settings());
    });
  }

  @override
  void dispose() { pulse.dispose(); tts.stop(); box.dispose(); scroll.dispose(); super.dispose(); }

  void down() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  Future<bool> appCmd(String t) async {
    final s = t.toLowerCase();
    String url = "";
    String appName = "";
    if (s.contains("youtube")) { url = "https://youtube.com"; appName = "YouTube"; }
    else if (s.contains("whatsapp")) { url = "https://wa.me/"; appName = "WhatsApp"; }
    else if (s.contains("instagram")) { url = "https://instagram.com"; appName = "Instagram"; }
    else if (s.contains("snapchat")) { url = "https://snapchat.com"; appName = "Snapchat"; }
    else if (s.contains("facebook")) { url = "https://facebook.com"; appName = "Facebook"; }
    else if (s.contains("spotify")) { url = "https://spotify.com"; appName = "Spotify"; }
    else if (s.contains("google") || s.contains("search")) {
      final q = t.replaceAll(RegExp(r"(google par|google pe|google|search karo|search|karo)", caseSensitive: false), "").trim();
      url = "https://www.google.com/search?q=${Uri.encodeComponent(q.isEmpty ? "Suhana AI" : q)}";
      appName = "Google Search";
    }
    if (url.isNotEmpty) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      setState(() => chats.add(Chat("$appName open kar rahi hoon! ✨", false)));
      tts.speak("$appName open kar rahi hoon");
      return true;
    }
    return false;
  }

  Future<String> ask(String user) async {
    final hist = <Map<String, dynamic>>[];
    for (final c in chats.where((x) => !x.info).take(10)) {
      hist.add({"role": c.me ? "user" : "model", "parts": [{"text": c.text}]});
    }
    hist.add({"role": "user", "parts": [{"text": user}]});
    final res = await http.post(
      Uri.parse("https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$key"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "system_instruction": {"parts": [{"text": sys}]},
        "contents": hist,
        "generationConfig": {"temperature": 0.7},
      }),
    ).timeout(const Duration(seconds: 40));
    if (res.statusCode == 200) {
      final d = jsonDecode(utf8.decode(res.bodyBytes));
      final cands = d["candidates"] as List?;
      if (cands == null || cands.isEmpty) return "Suhana busy hai.";
      final parts = (cands[0]['content']?['parts'] as List?) ?? [];
      return parts.map((p) => "${p['text'] ?? ""}").join().trim();
    }
    if (res.statusCode == 429) return "LIMIT: Rate limit! 30 second ruko.";
    if (res.statusCode == 401 || res.statusCode == 403) return "LIMIT: Key galat hai.";
    return "LIMIT: Server busy hai (Status ${res.statusCode})";
  }

  Future<void> send(String t) async {
    t = t.trim(); if (t.isEmpty || busy) return;
    if (await appCmd(t)) { down(); return; }
    if (key.isEmpty) { settings(); return; }
    box.clear();
    setState(() { chats.add(Chat(t, true)); busy = true; });
    down();
    try {
      final r = await ask(t);
      if (!mounted) return;
      final isLimit = r.startsWith("LIMIT:");
      setState(() {
        chats.add(Chat(isLimit ? r.substring(6) : r, false, info: isLimit));
        busy = false;
      });
      down();
      if (!isLimit) {
        final hi = RegExp(r"[\u0900-\u097F]").hasMatch(r);
        await tts.setLanguage(hi ? "hi-IN" : "en-IN");
        await tts.speak(r.replaceAll(RegExp(r"[*#`]"), " "));
      }
    } catch (e) {
      setState(() { busy = false; chats.add(Chat("Error: $e", false, info: true)); });
    }
  }

  void settings() {
    final k = TextEditingController(text: key);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF12182B),
        title: const Text("Suhana Settings", style: TextStyle(color: Colors.cyanAccent)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: k, obscureText: true, decoration: const InputDecoration(labelText: "Gemini API Key", border: OutlineInputBorder())),
            const SizedBox(height: 12),
            const Text("Model: gemini-2.5-flash (Fixed)", style: TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          TextButton(
            onPressed: () async {
              final p = await SharedPreferences.getInstance();
              await p.setString("gkey", k.text.trim());
              await p.setString("model", "gemini-2.5-flash");
              setState(() { key = k.text.trim(); model = "gemini-2.5-flash"; });
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text("Save", style: TextStyle(color: Colors.cyanAccent)),
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
        centerTitle: true,
        title: const Text("SUHANA", style: TextStyle(letterSpacing: 6, color: Colors.cyanAccent)),
        actions: [
          IconButton(icon: const Icon(Icons.delete_outline, color: Colors.white38), onPressed: () => setState(chats.clear)),
          IconButton(icon: const Icon(Icons.settings, color: Colors.cyanAccent), onPressed: settings),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          ScaleTransition(
            scale: Tween(begin: 0.95, end: 1.05).animate(CurvedAnimation(parent: pulse, curve: Curves.easeInOut)),
            child: Container(
              width: 140, height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: talk ? Colors.pinkAccent : Colors.cyanAccent, width: 3),
                boxShadow: [BoxShadow(color: (talk ? Colors.pinkAccent : Colors.cyanAccent).withOpacity(0.45), blurRadius: 30, spreadRadius: 8)],
                image: const DecorationImage(
                  image: NetworkImage("https://i.imgur.com/K3yZ8fD.png"),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(key.isEmpty ? "Setup pending" : "Suhana • $model", style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              padding: const EdgeInsets.all(12),
              itemCount: chats.length,
              itemBuilder: (_, i) {
                final c = chats[i];
                return Align(
                  alignment: c.me ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                    decoration: BoxDecoration(
                      color: c.info ? Colors.orange.withOpacity(0.12) : c.me ? Colors.cyan.shade800 : const Color(0xFF12182B),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: SelectableText(c.text, style: TextStyle(color: c.info ? Colors.orange.shade200 : Colors.white)),
                  ),
                );
              },
            ),
          ),
          if (busy) const Padding(padding: EdgeInsets.all(6), child: CircularProgressIndicator(color: Colors.cyanAccent)),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 18),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: box,
                    textInputAction: TextInputAction.send,
                    decoration: InputDecoration(
                      hintText: "Suhana se baat karo...",
                      filled: true, fillColor: const Color(0xFF12182B),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                    ),
                    onSubmitted: send,
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Colors.cyanAccent,
                  child: IconButton(icon: const Icon(Icons.send, color: Colors.black), onPressed: () => send(box.text)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
