import "dart:convert";
import "package:flutter/material.dart";
import "package:flutter_tts/flutter_tts.dart";
import "package:http/http.dart" as http;
import "package:shared_preferences/shared_preferences.dart";
import "package:url_launcher/url_launcher.dart";

void main() {
  runApp(const SuhanaApp());
}

class SuhanaApp extends StatelessWidget {
  const SuhanaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Suhana",
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF070B18),
      ),
      home: const HomePage(),
    );
  }
}

class ChatMsg {
  final String text;
  final bool isUser;

  ChatMsg(this.text, this.isUser);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  final TextEditingController input = TextEditingController();
  final ScrollController scroll = ScrollController();
  final FlutterTts tts = FlutterTts();

  final List<ChatMsg> chats = [];

  String apiKey = "";
  String model = "gemini-2.0-flash";

  bool loading = false;
  bool speaking = false;

  late AnimationController pulse;

  final List<String> models = const [
    "gemini-2.0-flash",
    "gemini-1.5-flash",
    "gemini-2.5-flash",
    "gemini-flash-latest",
    "gemini-1.5-pro",
  ];

  static const String systemPrompt =
      "You are Suhana, a beautiful friendly AI girl assistant. "
      "Reply naturally in Hindi, Hinglish, or English depending on the user. "
      "Talk like a real friendly girl, not like a robot. "
      "Keep replies short, helpful, sweet, and natural. "
      "Do not use markdown symbols like * or #.";

  @override
  void initState() {
    super.initState();

    pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    setupTts();
    loadSettings();
  }

  @override
  void dispose() {
    pulse.dispose();
    tts.stop();
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> setupTts() async {
    await tts.setSpeechRate(0.48);
    await tts.setPitch(1.15);
    await tts.setVolume(1.0);

    tts.setStartHandler(() {
      if (mounted) {
        setState(() {
          speaking = true;
        });
      }
    });

    tts.setCompletionHandler(() {
      if (mounted) {
        setState(() {
          speaking = false;
        });
      }
    });

    tts.setCancelHandler(() {
      if (mounted) {
        setState(() {
          speaking = false;
        });
      }
    });
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final savedModel = prefs.getString("model") ?? "gemini-2.0-flash";

    setState(() {
      apiKey = prefs.getString("api_key") ?? "";
      model = models.contains(savedModel) ? savedModel : "gemini-2.0-flash";
    });

    if (apiKey.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        openSettings();
      });
    }
  }

  Future<void> saveSettings(String key, String selectedModel) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString("api_key", key);
    await prefs.setString("model", selectedModel);

    setState(() {
      apiKey = key;
      model = selectedModel;
    });
  }

  void scrollDown() {
    Future.delayed(const Duration(milliseconds: 120), () {
      if (scroll.hasClients) {
        scroll.animateTo(
          scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> speak(String text) async {
    String clean = text.replaceAll(RegExp(r"[*#`_>~|]"), " ");
    clean = clean.replaceAll(RegExp(r"\s+"), " ").trim();

    if (clean.isEmpty) return;

    final bool hasHindi = RegExp(r"[\u0900-\u097F]").hasMatch(clean);

    try {
      await tts.stop();
      await tts.setLanguage(hasHindi ? "hi-IN" : "en-IN");
      await tts.speak(clean);
    } catch (_) {}
  }

  List<Map<String, dynamic>> buildGeminiHistory(String currentUserMessage) {
    final normalChats = chats.toList();

    final recentChats = normalChats.length > 12
        ? normalChats.sublist(normalChats.length - 12)
        : normalChats;

    final List<Map<String, dynamic>> contents = [];

    for (final msg in recentChats) {
      contents.add({
        "role": msg.isUser ? "user" : "model",
        "parts": [
          {"text": msg.text}
        ]
      });
    }

    contents.add({
      "role": "user",
      "parts": [
        {"text": currentUserMessage}
      ]
    });

    while (contents.isNotEmpty && contents.first["role"] != "user") {
      contents.removeAt(0);
    }

    return contents;
  }

  String makeErrorMessage(http.Response response) {
    String serverMessage = "";

    try {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final err = data is Map ? data["error"] : null;

      if (err is Map) {
        serverMessage = "${err["message"] ?? ""}";
      } else if (err is String) {
        serverMessage = err;
      }
    } catch (_) {}

    if (response.statusCode == 404) {
      return "Model $model is key par available nahi hai. Settings me model badlo. Pehle gemini-2.0-flash try karo, na chale to gemini-1.5-flash.";
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      return "API key galat ya expired hai. Settings me nayi Gemini API key daalo.";
    }

    if (response.statusCode == 429) {
      return "Rate limit aa gayi. 1 minute ruk kar sirf ek message bhejo.";
    }

    if (response.statusCode == 500 || response.statusCode == 503) {
      return "Gemini server busy hai. 30 second baad try karo.";
    }

    return "Error ${response.statusCode}: ${serverMessage.isEmpty ? "Unknown error" : serverMessage}";
  }

  Future<String> askGemini(String userMessage) async {
    final uri = Uri.parse(
      "https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey",
    );

    final response = await http
        .post(
          uri,
          headers: {
            "Content-Type": "application/json",
          },
          body: jsonEncode({
            "system_instruction": {
              "parts": [
                {"text": systemPrompt}
              ]
            },
            "contents": buildGeminiHistory(userMessage),
            "generationConfig": {
              "temperature": 0.7,
            }
          }),
        )
        .timeout(const Duration(seconds: 50));

    if (response.statusCode != 200) {
      return makeErrorMessage(response);
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes));
    final candidates = data["candidates"] as List?;

    if (candidates == null || candidates.isEmpty) {
      return "Suhana ko abhi answer nahi mila. Dobara try karo.";
    }

    final parts = (candidates[0]["content"]?["parts"] as List?) ?? [];

    final text = parts.map((p) => "${p["text"] ?? ""}").join().trim();

    if (text.isEmpty) {
      return "Suhana ka answer empty aaya. Dobara try karo.";
    }

    return text;
  }

  Future<bool> handlePhoneCommand(String text) async {
    final lower = text.toLowerCase();

    if (lower.contains("youtube")) {
      await launchUrl(
        Uri.parse("https://youtube.com"),
        mode: LaunchMode.externalApplication,
      );

      setState(() {
        chats.add(ChatMsg("YouTube open kar diya.", false));
      });

      speak("YouTube open kar diya.");
      return true;
    }

    if (lower.contains("whatsapp")) {
      await launchUrl(
        Uri.parse("https://wa.me/"),
        mode: LaunchMode.externalApplication,
      );

      setState(() {
        chats.add(ChatMsg("WhatsApp open kar diya.", false));
      });

      speak("WhatsApp open kar diya.");
      return true;
    }

    if (lower.contains("instagram")) {
      await launchUrl(
        Uri.parse("https://instagram.com"),
        mode: LaunchMode.externalApplication,
      );

      setState(() {
        chats.add(ChatMsg("Instagram open kar diya.", false));
      });

      speak("Instagram open kar diya.");
      return true;
    }

    if (lower.contains("google") || lower.contains("search")) {
      String query = text
          .replaceAll(
            RegExp(
              r"google par|google pe|google|search karo|search|karo",
              caseSensitive: false,
            ),
            "",
          )
          .trim();

      if (query.isEmpty) {
        query = "Suhana AI assistant";
      }

      await launchUrl(
        Uri.parse(
          "https://www.google.com/search?q=${Uri.encodeComponent(query)}",
        ),
        mode: LaunchMode.externalApplication,
      );

      setState(() {
        chats.add(ChatMsg("Google par search open kar diya.", false));
      });

      speak("Google par search open kar diya.");
      return true;
    }

    return false;
  }

  Future<void> sendMessage(String text) async {
    text = text.trim();

    if (text.isEmpty || loading) return;

    input.clear();

    setState(() {
      chats.add(ChatMsg(text, true));
    });

    scrollDown();

    final commandHandled = await handlePhoneCommand(text);

    if (commandHandled) {
      scrollDown();
      return;
    }

    if (apiKey.isEmpty) {
      openSettings();
      return;
    }

    setState(() {
      loading = true;
    });

    try {
      final reply = await askGemini(text);

      if (!mounted) return;

      setState(() {
        chats.add(ChatMsg(reply, false));
        loading = false;
      });

      scrollDown();

      if (!reply.startsWith("Error") &&
          !reply.startsWith("Model") &&
          !reply.startsWith("API") &&
          !reply.startsWith("Rate")) {
        await speak(reply);
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        chats.add(ChatMsg("Error: $e", false));
        loading = false;
      });

      scrollDown();
    }
  }

  void openSettings() {
    final keyController = TextEditingController(text: apiKey);
    String selectedModel = models.contains(model) ? model : models.first;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF12182B),
              title: const Text(
                "Suhana Settings",
                style: TextStyle(
                  color: Colors.cyanAccent,
                  fontSize: 22,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: keyController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: "Gemini API Key",
                        hintText: "AIza...",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: selectedModel,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF12182B),
                      decoration: const InputDecoration(
                        labelText: "Gemini Model",
                        border: OutlineInputBorder(),
                      ),
                      items: models.map((m) {
                        return DropdownMenuItem(
                          value: m,
                          child: Text(
                            m,
                            style: const TextStyle(fontSize: 13),
                          ),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() {
                            selectedModel = v;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Tip: Pehle gemini-2.0-flash try karo. Na chale to gemini-1.5-flash select karo.",
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                  },
                  child: const Text("Cancel"),
                ),
                TextButton(
                  onPressed: () {
                    saveSettings(
                      keyController.text.trim(),
                      selectedModel,
                    );
                    Navigator.pop(ctx);
                  },
                  child: const Text(
                    "Save",
                    style: TextStyle(
                      color: Colors.cyanAccent,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget avatar() {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.94, end: 1.06).animate(
        CurvedAnimation(
          parent: pulse,
          curve: Curves.easeInOut,
        ),
      ),
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: speaking
                ? [Colors.pinkAccent, Colors.purple]
                : [Colors.cyanAccent, Colors.indigo.shade900],
          ),
          boxShadow: [
            BoxShadow(
              color: (speaking ? Colors.pinkAccent : Colors.cyanAccent)
                  .withOpacity(0.45),
              blurRadius: 28,
              spreadRadius: 6,
            ),
          ],
        ),
        child: const Icon(
          Icons.face_3,
          size: 58,
          color: Colors.white,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = apiKey.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          "SUHANA",
          style: TextStyle(
            letterSpacing: 6,
            color: Colors.cyanAccent,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(
              Icons.delete_outline,
              color: Colors.white38,
            ),
            onPressed: () {
              setState(() {
                chats.clear();
              });
            },
          ),
          IconButton(
            icon: const Icon(
              Icons.settings,
              color: Colors.cyanAccent,
            ),
            onPressed: openSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          avatar(),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              ready ? "Suhana • $model" : "Setup pending",
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              padding: const EdgeInsets.all(12),
              itemCount: chats.length,
              itemBuilder: (context, index) {
                final msg = chats[index];

                return Align(
                  alignment: msg.isUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.80,
                    ),
                    decoration: BoxDecoration(
                      color: msg.isUser
                          ? Colors.cyan.shade800
                          : const Color(0xFF12182B),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: SelectableText(
                      msg.text,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(6),
              child: CircularProgressIndicator(
                color: Colors.cyanAccent,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 18),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: input,
                    textInputAction: TextInputAction.send,
                    decoration: InputDecoration(
                      hintText: "Suhana se baat karo...",
                      filled: true,
                      fillColor: const Color(0xFF12182B),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: sendMessage,
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Colors.cyanAccent,
                  child: IconButton(
                    icon: const Icon(
                      Icons.send,
                      color: Colors.black,
                    ),
                    onPressed: () {
                      sendMessage(input.text);
                    },
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
