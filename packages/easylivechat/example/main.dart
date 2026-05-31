// Headless usage example for the `easylivechat` core (no UI package).
//
// Demonstrates booting, opening a session, listening for messages, and
// sending — binding the reactive [ValueListenable]s to a tiny widget.
// For the prebuilt UI, use `easylivechat_ui` (EasyLiveChatLauncher) instead.

import 'package:easylivechat/easylivechat.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await EasyLiveChat.instance.boot(
    const EasyLiveChatConfig(
      apiBase: 'https://api.livechattools.com',
      tenantSlug: 'acme', // ← your workspace slug
    ),
    // NOTE: InMemoryStorage is the default and is NOT durable — the visitorId
    // is lost on restart (orphaning conversations). In a real app inject a
    // persistent EasyLiveChatStorage (easylivechat_ui ships SecurePrefsStorage).
  );

  runApp(const _ExampleApp());
}

class _ExampleApp extends StatefulWidget {
  const _ExampleApp();
  @override
  State<_ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<_ExampleApp> {
  final _chat = EasyLiveChat.instance;
  final _input = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Kick off: config → resume → prechat/anonymous → connect /widgets.
    _chat.open();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('EasyLiveChat — headless example')),
        body: Column(
          children: [
            // Connection + phase banner.
            ValueListenableBuilder(
              valueListenable: _chat.connection,
              builder: (_, conn, __) => ValueListenableBuilder(
                valueListenable: _chat.phase,
                builder: (_, phase, __) => Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('phase: $phase   connection: $conn'),
                ),
              ),
            ),
            // Message list.
            Expanded(
              child: ValueListenableBuilder<List<ChatMessage>>(
                valueListenable: _chat.messages,
                builder: (_, msgs, __) => ListView.builder(
                  itemCount: msgs.length,
                  itemBuilder: (_, i) {
                    final m = msgs[i];
                    return ListTile(
                      title: Text(m.body ?? '(attachment)'),
                      subtitle: Text(m.isFromCustomer ? 'you' : (m.senderName ?? 'agent')),
                      trailing: m.failed ? const Icon(Icons.error, color: Colors.red) : null,
                    );
                  },
                ),
              ),
            ),
            // Agent typing.
            ValueListenableBuilder<bool>(
              valueListenable: _chat.agentTyping,
              builder: (_, typing, __) =>
                  typing ? const Padding(padding: EdgeInsets.all(8), child: Text('agent is typing…')) : const SizedBox.shrink(),
            ),
            // Composer.
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    onChanged: (v) => _chat.setTyping(v.isNotEmpty),
                    decoration: const InputDecoration(hintText: 'Type a message'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () {
                    final text = _input.text.trim();
                    if (text.isEmpty) return;
                    _chat.sendMessage(text);
                    _input.clear();
                    _chat.setTyping(false);
                  },
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }
}
