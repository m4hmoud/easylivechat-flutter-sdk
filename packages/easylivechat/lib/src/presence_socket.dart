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
  bool _disposed = false;

  final _onProactive = StreamController<ProactiveMessage>.broadcast();
  Stream<ProactiveMessage> get onProactive => _onProactive.stream;

  /// `connect_error` — last handshake error (e.g. bad tenantSlug/visitorId).
  /// Presence is receive-only and non-fatal, so we expose the last error for
  /// diagnostics rather than a stream; pre-chat outreach just won't arrive.
  final _onConnectError = StreamController<String>.broadcast();
  Stream<String> get onConnectError => _onConnectError.stream;

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

    // Surface handshake failures (bad tenantSlug/visitorId) instead of failing
    // silently. Non-fatal: presence is receive-only outreach.
    socket.onConnectError((err) {
      if (!_onConnectError.isClosed) _onConnectError.add('$err');
    });
    socket.onError((err) {
      if (!_onConnectError.isClosed) _onConnectError.add('$err');
    });

    // Receive-only: the sole inbound event on this namespace. Guard the add —
    // an event can race teardown (clearListeners is best-effort) after the
    // controller closed the stream.
    socket.on('widget:proactive-message', (data) {
      if (data is Map && !_onProactive.isClosed) {
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
    // Idempotent: dispose can be called more than once (teardown + controller
    // dispose); closing an already-closed StreamController throws.
    if (_disposed) return;
    _disposed = true;
    // disconnect() synchronously clears listeners before we close the streams,
    // so no late proactive event can land after close.
    unawaited(disconnect());
    _onProactive.close();
    _onConnectError.close();
  }
}
