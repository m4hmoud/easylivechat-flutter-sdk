import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as IO;

import 'models/chat_message.dart';
import 'models/results.dart';

/// Socket.IO client for the `/widgets` namespace (full chat; JWT required).
///
/// Handshake: JWT in `handshake.auth.token` (NOT query, NOT header),
/// `withCredentials:false`, transports `['websocket','polling']`. The server
/// auto-joins `tenant:{id}:conv:{convId}` from the JWT — the client joins
/// nothing. The token MUST be re-supplied on every (re)connect (Dart does not
/// persist it like a browser tab).
///
/// Server is `socket.io@4.8.x` (Engine.IO v4) — use `socket_io_client ^3.x`
/// which speaks EIO4. A protocol mismatch fails the handshake SILENTLY; pin
/// the dependency and integration-test it.
class WidgetSocket {
  final String apiBase;
  String _token;

  WidgetSocket({required this.apiBase, required String token}) : _token = token;

  IO.Socket? _socket;
  bool _disposed = false;

  // ── inbound streams (broadcast) ──
  final _onMessageNew = StreamController<ChatMessage>.broadcast();
  final _onMessageUpdated = StreamController<ChatMessage>.broadcast();
  final _onAgentTyping = StreamController<bool>.broadcast();
  final _onAvailability = StreamController<bool>.broadcast();
  final _onAgentsAccepting = StreamController<bool>.broadcast();
  final _onConversationClosed = StreamController<String>.broadcast();
  final _onProactive = StreamController<ProactiveMessage>.broadcast();
  final _onConnectionChange = StreamController<bool>.broadcast();
  final _onConnectError = StreamController<String>.broadcast();

  /// `message:new` — raw Prisma row (parse via [ChatMessage.fromAny]).
  Stream<ChatMessage> get onMessageNew => _onMessageNew.stream;

  /// `message:updated` — media re-host swap (replace by id). The web client
  /// does NOT register this; we DO.
  Stream<ChatMessage> get onMessageUpdated => _onMessageUpdated.stream;

  /// `agent:typing` — payload is `{ isTyping }` only; never an explicit false,
  /// so the controller arms a ~4s auto-clear.
  Stream<bool> get onAgentTyping => _onAgentTyping.stream;

  /// `workspace:availability` — the working-hours gate, fired on connect and
  /// whenever it changes (a shift boundary, or an admin editing the schedule).
  Stream<bool> get onAvailability => _onAvailability.stream;

  /// The second availability gate from the same event: whether any agent is
  /// currently accepting chats. Only decides anything for tenants running
  /// `chatAvailabilityMode = WHEN_ACCEPTING`; emits `true` against servers that
  /// don't send the field.
  Stream<bool> get onAgentsAccepting => _onAgentsAccepting.stream;

  /// `conversation:closed` — `{ conversationId }`. NOTE: the server emits on
  /// ANY *→CLOSED PATCH (not only OPEN→CLOSED) — consumers must guard against
  /// re-firing CSAT.
  Stream<String> get onConversationClosed => _onConversationClosed.stream;

  /// `widget:proactive-message` — also delivered on the conv room.
  Stream<ProactiveMessage> get onProactive => _onProactive.stream;

  /// true on connect, false on disconnect.
  Stream<bool> get onConnectionChange => _onConnectionChange.stream;

  /// `connect_error` — emits the error/code (e.g. WIDGET_TOKEN_MISSING / a
  /// jose verify failure) so the controller can trigger a token re-mint.
  Stream<String> get onConnectError => _onConnectError.stream;

  bool get isConnected => _socket?.connected ?? false;

  /// Open the socket with the current token and wire all handlers.
  void connect() {
    // Idempotent: if a socket already exists, just (re)connect it.
    if (_socket != null) {
      _applyAuth();
      _socket!.connect();
      return;
    }

    final socket = IO.io(
      '$apiBase/widgets',
      IO.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          // Re-mintable JWT in the handshake auth payload (NOT query/header).
          .setAuth({'token': _token})
          // withCredentials:false — no cookies; the JWT is the only credential.
          .disableForceNew()
          // Explicit socket.connect() below is the single connection trigger.
          .disableAutoConnect()
          // Auto-reconnect with exponential backoff; the mobile socket drops
          // constantly (cellular↔wifi, lock screen). The controller backfills
          // the newest /messages page after any gap.
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(8000)
          .build(),
    );
    _socket = socket;
    _wire(socket);
    socket.connect();
  }

  void _wire(IO.Socket socket) {
    // ── connection lifecycle ──
    socket.onConnect((_) {
      if (!_onConnectionChange.isClosed) _onConnectionChange.add(true);
    });
    socket.onDisconnect((_) {
      if (!_onConnectionChange.isClosed) _onConnectionChange.add(false);
    });
    socket.onConnectError((err) {
      if (!_onConnectError.isClosed) _onConnectError.add(_describeError(err));
    });
    socket.onError((err) {
      if (!_onConnectError.isClosed) _onConnectError.add(_describeError(err));
    });
    // Re-supply auth.token on every reconnect attempt — Dart does not persist
    // the handshake auth across reconnects the way a browser tab does.
    socket.onReconnectAttempt((_) => _applyAuth());

    // ── inbound events ──
    socket.on('message:new', (data) {
      final m = _asMap(data);
      if (m != null && !_onMessageNew.isClosed) {
        _onMessageNew.add(ChatMessage.fromAny(m));
      }
    });

    socket.on('message:updated', (data) {
      final m = _asMap(data);
      if (m != null && !_onMessageUpdated.isClosed) {
        _onMessageUpdated.add(ChatMessage.fromAny(m));
      }
    });

    socket.on('agent:typing', (data) {
      // Payload is `{ isTyping }`; the server only ever sends true and lets the
      // controller's ~4s timer clear it. Require an explicit true so a malformed
      // or empty payload can't show a phantom "agent is typing".
      final m = _asMap(data);
      final isTyping = m?['isTyping'] == true;
      if (!_onAgentTyping.isClosed) _onAgentTyping.add(isTyping);
    });

    socket.on('workspace:availability', (data) {
      final m = _asMap(data);
      final isOpen = m?['isOpen'] == true;
      if (!_onAvailability.isClosed) _onAvailability.add(isOpen);
      // Older servers omit `agentsAccepting`; absent means "don't let this gate
      // close the widget", hence `!= false` rather than `== true`.
      final accepting = m?['agentsAccepting'] != false;
      if (!_onAgentsAccepting.isClosed) _onAgentsAccepting.add(accepting);
    });

    socket.on('conversation:closed', (data) {
      final m = _asMap(data);
      final convId = (m?['conversationId'] ?? '').toString();
      if (convId.isNotEmpty && !_onConversationClosed.isClosed) {
        _onConversationClosed.add(convId);
      }
    });

    socket.on('widget:proactive-message', (data) {
      final m = _asMap(data);
      if (m != null && !_onProactive.isClosed) {
        _onProactive.add(ProactiveMessage.fromJson(m));
      }
    });
  }

  /// Swap the token (after a re-mint) and re-supply it on the next connect.
  void updateToken(String token) {
    _token = token;
    // Update the live socket so the NEXT (re)connect uses the fresh token.
    _applyAuth();
  }

  /// Force a fresh handshake carrying the current (re-minted) token. A LIVE
  /// socket does NOT re-read its handshake auth on a no-op connect(), so a
  /// stale token would keep flowing until the next natural drop — we disconnect
  /// first, then connect re-handshakes with [_token]. onDisconnect/onConnect
  /// fire as usual (the controller backfills the gap on connect).
  void reconnectWithFreshAuth() {
    final socket = _socket;
    if (socket == null) {
      connect();
      return;
    }
    _applyAuth();
    socket.disconnect();
    socket.connect();
  }

  /// Push [_token] into both the live socket auth and the underlying manager
  /// options, so every reconnect handshake carries the current token.
  void _applyAuth() {
    final socket = _socket;
    if (socket == null) return;
    final auth = {'token': _token};
    socket.auth = auth;
    // Belt-and-suspenders: the manager re-reads its own options on reconnect
    // in some versions, so keep them in sync too.
    try {
      socket.io.options?['auth'] = auth;
    } catch (_) {
      // options shape varies across socket_io_client minor versions; the
      // socket.auth assignment above is the authoritative path.
    }
  }

  String get token => _token;

  /// Emit `message:send { body, attachmentUrls?, contentType? }` and await the
  /// ack `{ ok, messageId? } | { ok:false, error }`. `contentType` omitted =>
  /// server infers FILE for attachment-only/empty body, else TEXT.
  Future<SendAck> sendMessage({
    required String body,
    List<String> attachmentUrls = const [],
    String? contentType,
  }) async {
    final socket = _socket;
    if (socket == null) {
      return const SendAck(ok: false, error: 'NOT_CONNECTED');
    }
    final payload = <String, dynamic>{
      'body': body,
      if (attachmentUrls.isNotEmpty) 'attachmentUrls': attachmentUrls,
      if (contentType != null) 'contentType': contentType,
    };
    try {
      // socket_io_client 3.x: emitWithAck() returns void (callback-only);
      // emitWithAckAsync() returns the Future. Bound it so a socket that drops
      // between emit and ack yields a terminal failure (=> optimistic message
      // flips to failed) instead of hanging forever.
      final raw = await socket
          .emitWithAckAsync('message:send', payload)
          .timeout(const Duration(seconds: 20), onTimeout: () => null);
      return SendAck.fromAck(raw);
    } catch (e) {
      return SendAck(ok: false, error: _describeError(e));
    }
  }

  /// Emit `typing { isTyping }` (caller debounces).
  void setTyping(bool isTyping) {
    _socket?.emit('typing', {'isTyping': isTyping});
  }

  Future<void> disconnect() async {
    _socket?.disconnect();
  }

  void dispose() {
    // Idempotent: teardown can race (controller _teardownSocket's whenComplete
    // + a re-mint failure path + controller dispose). Closing an already-closed
    // StreamController throws, so guard the whole thing.
    if (_disposed) return;
    _disposed = true;
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      socket.clearListeners();
      socket.dispose();
    }
    _onMessageNew.close();
    _onMessageUpdated.close();
    _onAgentTyping.close();
    _onAvailability.close();
    _onAgentsAccepting.close();
    _onConversationClosed.close();
    _onProactive.close();
    _onConnectionChange.close();
    _onConnectError.close();
  }

  // ── helpers ──

  /// Socket.IO payloads arrive as `dynamic`; normalize the common map shape.
  static Map<String, dynamic>? _asMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.cast<String, dynamic>();
    return null;
  }

  /// Turn a `connect_error`/ack error (Error wrapper, map, or string) into a
  /// stable code/message string. The server passes `WIDGET_TOKEN_MISSING` and
  /// jose verify messages as the Error's `message`.
  static String _describeError(Object? err) {
    if (err == null) return 'UNKNOWN';
    if (err is String) return err;
    if (err is Map) {
      final m = err.cast<String, dynamic>();
      final code = m['code'] ?? m['message'] ?? m['type'] ?? m['error'];
      if (code != null) return code.toString();
      return m.toString();
    }
    return err.toString();
  }
}
