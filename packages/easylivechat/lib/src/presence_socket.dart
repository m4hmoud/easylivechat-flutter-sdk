import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import 'models/results.dart';

/// Socket.IO client for the `/widget-presence` namespace — receive-only, NO
/// JWT. Handshake `query: { tenantSlug, visitorId }`; the server joins
/// `tenant:{id}:visitor:{vid}`. Used pre-chat to receive proactive outreach
/// (`widget:proactive-message`) before a conversation/JWT exists.
///
/// Security note: `visitorId` is the only secret (122 bits of UUID entropy);
/// anyone who knows it can subscribe. It is receive-only and low-value.
class PresenceSocket {
  final String apiBase;
  final String tenantSlug;
  final String visitorId;

  PresenceSocket({
    required this.apiBase,
    required this.tenantSlug,
    required this.visitorId,
  });

  io.Socket? _socket;

  final _onProactive = StreamController<ProactiveMessage>.broadcast();
  Stream<ProactiveMessage> get onProactive => _onProactive.stream;

  /// Connect to `<apiBase>/widget-presence` with the query handshake and
  /// auto-reconnect (reconnectionDelay ~1500ms). Receive-only.
  void connect() {
    // Idempotent: a second connect() while already wired is a no-op.
    if (_socket != null) return;

    final socket = io.io(
      '$apiBase/widget-presence',
      io.OptionBuilder()
          .setQuery({'tenantSlug': tenantSlug, 'visitorId': visitorId})
          .setTransports(['websocket', 'polling'])
          .setReconnectionDelay(1500)
          .build(),
    );
    _socket = socket;

    // Receive-only: the sole inbound event on this namespace.
    socket.on('widget:proactive-message', (data) {
      if (data is Map) {
        _onProactive.add(
          ProactiveMessage.fromJson(data.cast<String, dynamic>()),
        );
      }
    });
  }

  Future<void> disconnect() async {
    final socket = _socket;
    if (socket == null) return;
    _socket = null;
    socket.clearListeners();
    socket.dispose();
  }

  void dispose() {
    // Tear down the socket first, then close the broadcast stream.
    unawaited(disconnect());
    _onProactive.close();
  }
}
