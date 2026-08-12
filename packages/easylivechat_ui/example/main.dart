// Prebuilt-UI example for `easylivechat_ui`.
//
// Shows the two ways to surface support in a host app:
//  1. `EasyLiveChatLauncher` — the floating bubble, dropped into a `Stack`
//     over your own UI. It opens the session lazily on tap and pushes the
//     chat screen itself, so this is the whole integration.
//  2. `EasyLiveChatScreen` — the same chat surface pushed as your own route,
//     for apps that want a "Support" row in a settings list instead of a
//     bubble.
//
// Run it against your own workspace by editing `_tenantSlug` below. For a
// UI-free integration (your own widgets over the protocol), use the headless
// `easylivechat` package directly.

import 'package:easylivechat_ui/easylivechat_ui.dart';
import 'package:flutter/material.dart';

/// Your EasyLiveChat workspace slug (dashboard → Settings → Widget).
const _tenantSlug = 'acme';

/// The API host your workspace lives on.
const _apiBase = 'https://api.livechattools.com';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await EasyLiveChat.instance.boot(
    const EasyLiveChatConfig(apiBase: _apiBase, tenantSlug: _tenantSlug),
    // SecurePrefsStorage is this package's durable default: the JWT and the
    // visitor profile go to the Keychain / EncryptedSharedPreferences, the
    // visitorId to shared_preferences. It MUST be durable — without it the
    // visitorId is regenerated on every cold start and the visitor loses the
    // conversation they had.
    storage: SecurePrefsStorage(),
  );

  // Optional: attach the signed-in user so agents see who they are talking to.
  // Anonymous visitors work fine without this.
  EasyLiveChat.instance.identify(name: 'Jane Doe', email: 'jane@example.com');

  runApp(const ExampleApp());
}

/// Host app that renders its own content with the launcher bubble on top.
class ExampleApp extends StatelessWidget {
  /// Creates the example app.
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EasyLiveChat UI example',
      home: Stack(
        children: [
          const HomePage(),
          // The bubble positions itself from the workspace's widget config
          // (bottom-left / bottom-right) and carries its own unread badge.
          // `themeOverride:` would let this app's brand colors win over the
          // server config; left off here so the workspace theme shows through.
          const EasyLiveChatLauncher(),
        ],
      ),
    );
  }
}

/// A stand-in for the host app's own screen.
class HomePage extends StatelessWidget {
  /// Creates the example home page.
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My app')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Tap the bubble, or open support as a route:'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _openSupport(context),
              child: const Text('Contact support'),
            ),
          ],
        ),
      ),
    );
  }

  void _openSupport(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: const Text('Support'),
            // Backing out of the chat leaves the conversation open and
            // resumable; ending it is this explicit button, which confirms
            // and then shows the workspace's post-chat survey in place.
            actions: const [EasyLiveChatEndChatButton()],
          ),
          // `locale:` forces the chrome language when the host app already
          // knows it; without it the workspace locale is used.
          body: const EasyLiveChatScreen(),
        ),
      ),
    );
  }
}
