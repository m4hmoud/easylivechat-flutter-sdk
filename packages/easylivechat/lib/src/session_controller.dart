import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:uuid/uuid.dart';

import 'config.dart';
import 'errors.dart';
import 'models/chat_message.dart';
import 'models/enums.dart';
import 'models/pre_chat_form.dart';
import 'models/results.dart';
import 'models/widget_config.dart';
import 'rest_client.dart';
import 'storage.dart';
import 'widget_socket.dart';
import 'presence_socket.dart';

/// High-level UI phase.
enum ChatPhase { idle, loading, offline, resuming, prechat, chat, feedback }

/// Realtime connection state (derived from the `/widgets` socket).
enum ConnectionState { disconnected, connecting, connected, reconnecting }

/// App foreground/background, fed by the host (drives heartbeat + presence).
enum EasyLiveChatLifecycle { resumed, paused }

/// The brain. Owns the protocol clients, the [ChatPhase] state machine, the
/// reactive state, optimistic-send + reconcile, reconnect + gap-safe backfill,
/// and token re-mint. UI binds the listenables/streams; it never touches the
/// transport directly.
///
/// Implementation contract (for the body):
///  • boot(): load/generate durable visitorId + cached profile (no network).
///  • loadConfig(): GET /config; if !isOpen => phase=offline; build theme.
///  • open(): orchestrate config → silentResume → (prechat | anonymous start)
///    → connect /widgets.
///  • silentResume(): POST /session resumeOnly:true; if hasActiveConversation
///    && token => store JWT, seed messages, connect, phase=chat, return true;
///    else false (do NOT connect a socket without a token).
///  • startSession(): POST /session with fields; on 400 {fieldId} surface a
///    per-field error; on success persist profile + token, connect.
///  • sendMessage(): push optimistic 'tmp-' message, emit message:send, on ack
///    ok reconcile (match senderType==customer + body, since clientId is not
///    echoed); on ok:false mark failed.
///  • message:new dedup by id + reconcile optimistic; message:updated replace
///    by id; agent:typing => agentTyping true + 4s auto-clear; availability =>
///    isOpen; conversation:closed => phase=feedback (GUARD against re-fire /
///    already-rated); proactive => onProactiveMessage (+ silentResume()).
///  • token re-mint (single-flight): on connect_error auth failure, HTTP 401/
///    403, or exp within config.tokenRefreshLeeway => silentResume() to mint a
///    fresh 24h token on the same conversation, reconnect, backfill.
///  • reconnect backfill: server delivers message:new live-only. On reconnect,
///    page GET /messages from newest and WALK the cursor backward until it
///    overlaps known ids (gap-safe beyond one 50-msg page), merge by id.
///  • heartbeat: only while EasyLiveChatLifecycle.resumed; pause on background.
class SessionController {
  final EasyLiveChatConfig config;
  final EasyLiveChatStorage storage;
  late final RestClient rest;

  SessionController({required this.config, required this.storage}) {
    rest = RestClient(config);
  }

  // ── reactive state ──
  final ValueNotifier<ChatPhase> phase = ValueNotifier(ChatPhase.idle);
  final ValueNotifier<WidgetConfigModel?> widgetConfig = ValueNotifier(null);
  final ValueNotifier<bool> isOpen = ValueNotifier(true);

  /// Whether any agent is accepting chats. Only gates the UI for tenants
  /// running `chatAvailabilityMode = WHEN_ACCEPTING`.
  final ValueNotifier<bool> agentsAccepting = ValueNotifier(true);
  final ValueNotifier<ConnectionState> connection =
      ValueNotifier(ConnectionState.disconnected);
  final ValueNotifier<List<ChatMessage>> messages = ValueNotifier(const []);
  final ValueNotifier<bool> agentTyping = ValueNotifier(false);
  final ValueNotifier<int> unreadCount = ValueNotifier(0);

  final _onMessage = StreamController<ChatMessage>.broadcast();
  final _onProactive = StreamController<ProactiveMessage>.broadcast();
  final _onError = StreamController<EasyLiveChatError>.broadcast();
  Stream<ChatMessage> get onMessage => _onMessage.stream;
  Stream<ProactiveMessage> get onProactiveMessage => _onProactive.stream;
  Stream<EasyLiveChatError> get onError => _onError.stream;

  // ── internal state ──
  static const _uuid = Uuid();

  String? _visitorId;
  StoredProfile? _profile;

  // Host-supplied identity for a known (logged-in) visitor. When set, [open]
  // skips the pre-chat form and starts the session directly as this person.
  bool _hasIdentity = false;
  String? _identityName;
  String? _identityEmail;
  String? _phone;
  Map<String, String>? _identityFields;

  String? _token;
  String? _conversationId;

  /// Which conversation the LIVE socket handshook with. The server binds that
  /// at connect time, so this is the only way to notice the socket is now
  /// pointed at a conversation we've since moved on from.
  String? _socketConversationId;

  /// Oldest-message cursor for `loadOlderMessages()` (id of the oldest known
  /// message; null => no more history / not yet loaded).
  String? _oldestCursor;

  /// Distinguishes the two meanings of a null [_oldestCursor]: "never asked"
  /// (fetch the newest page) from "reached the beginning" (stop).
  bool _historyLoadedOnce = false;

  WidgetSocket? _socket;
  PresenceSocket? _presence;
  StreamSubscription<ProactiveMessage>? _presenceSub;
  final List<StreamSubscription<Object?>> _socketSubs = [];

  /// True once the chat socket has connected at least once this session — used
  /// to skip a redundant backfill on the FIRST connect (the session payload
  /// already seeded the newest page) and only backfill on real reconnects.
  bool _hasConnectedOnce = false;

  EasyLiveChatLifecycle _lifecycle = EasyLiveChatLifecycle.resumed;
  Timer? _heartbeatTimer;
  Timer? _typingTimer; // agent:typing auto-clear

  /// Single-flight guard for token re-mint (`silentResume`-based).
  Completer<bool>? _remintInFlight;

  /// Single-flight guard for [silentResume]. `open()` awaits it while an
  /// incoming proactive message also fires it fire-and-forget; without this
  /// two concurrent resumes adopt two sessions (duplicate sockets, clobbered
  /// conversation state).
  Completer<bool>? _silentResumeInFlight;

  /// Conversations whose CSAT prompt has already been shown — guards against
  /// `conversation:closed` re-fire (server emits on ANY *→CLOSED PATCH).
  final Set<String> _closedHandled = {};

  /// Conversations whose post-chat step is finished — rated, surveyed, or
  /// terminal. One set for both, because the visitor only ever sees one of the
  /// two and neither should reappear after it is done.
  final Set<String> _ratedConversations = {};

  bool _disposed = false;

  // ── accessors ──
  String get visitorId {
    final v = _visitorId;
    if (v == null) {
      throw StateError('SessionController.boot() must run before visitorId.');
    }
    return v;
  }

  String? get conversationId => _conversationId;

  // ── lifecycle ──

  /// Load (or generate) the durable visitorId + cached profile. No network.
  Future<void> boot() async {
    var vid = await storage.read(StorageKeys.visitorId);
    if (vid == null || vid.trim().isEmpty) {
      vid = _uuid.v4();
      await storage.write(StorageKeys.visitorId, vid);
    }
    _visitorId = vid;

    final rawProfile = await storage.read(StorageKeys.profile);
    if (rawProfile != null && rawProfile.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawProfile);
        if (decoded is Map) {
          _profile = StoredProfile.fromJson(decoded.cast<String, dynamic>());
        }
      } catch (_) {
        // Corrupt cache — ignore; treat as no profile.
      }
    }
  }

  /// Pre-identify a known (logged-in) visitor. Call before [open]; [open] then
  /// skips the pre-chat form and starts directly as this person. A fully-null
  /// identity is ignored (stays anonymous). Also seeds the cached profile so
  /// [silentResume] carries the name/email.
  void identify(
      {String? name,
      String? email,
      String? phone,
      Map<String, String>? fields}) {
    final hasAny = (name != null && name.trim().isNotEmpty) ||
        (email != null && email.trim().isNotEmpty) ||
        (phone != null && phone.trim().isNotEmpty) ||
        (fields != null && fields.isNotEmpty);
    if (!hasAny) return;
    _hasIdentity = true;
    _identityName = name;
    _identityEmail = email;
    _phone = phone;
    _identityFields = fields;
    // identify() is AUTHORITATIVE: the host is declaring the full visitor
    // identity for this session, so replace the persisted profile rather than
    // merging stale fields. A value the host no longer supplies (e.g. email)
    // must be cleared — otherwise an old (or a previous user's) email leaks
    // into the new session from secure storage.
    _profile = StoredProfile(
      name: name,
      email: email,
      preChat: fields,
    );
  }

  /// `GET /config`. Sets [widgetConfig] + [isOpen]. If the workspace is outside
  /// working hours, drops to [ChatPhase.offline].
  Future<WidgetConfigModel> loadConfig() async {
    _setPhase(ChatPhase.loading);
    final res = await _guardAuth(() => rest.getConfig());
    widgetConfig.value = res.config;
    isOpen.value = res.isOpen;
    agentsAccepting.value = res.agentsAccepting;
    // Remember the tenant's gating rules so a later `workspace:availability`
    // push is judged exactly as this first decision was.
    _chatAvailabilityMode = res.chatAvailabilityMode;
    _asyncEnabled = res.asyncEnabled;
    visitorMode.value = res.visitorMode;
    availabilityReason.value = res.reason;
    nextOpenAt.value = res.nextOpenAt;
    closureLabel.value = res.closureLabel;
    nextOpenLocal.value = res.nextOpenLocal;
    workspaceTimezone.value = res.timezone;
    // Deliberately NOT ChatPhase.offline. A visitor who arrives out of hours
    // continues into the ordinary chat and simply sees a notice (bind
    // [workspaceClosed]) — their message becomes a PENDING conversation that is
    // auto-assigned when the team returns. The old behaviour dropped them onto
    // a ticket form, a dead end whose submissions never became conversations.
    return res.config;
  }

  /// Full orchestration: config → silentResume → (prechat | anonymous start)
  /// → connect /widgets.
  Future<void> open() async {
    // ALWAYS re-fetch. This used to be `widgetConfig.value ?? await
    // loadConfig()`, so reopening the chat within one app session reused the
    // config captured at startup — `isOpen` was frozen at whatever it was then,
    // and no amount of server-side correctness could reach the UI.
    final cfg = await loadConfig();

    // Open the receive-only presence socket for pre-chat proactive outreach.
    if (config.enablePresenceSocket) {
      _connectPresence();
    }

    // The tenant chose to show a notice and take nothing NEW. An existing
    // conversation is still worth showing — a visitor reopening the chat after
    // hours is usually coming back to read the reply they were promised, and
    // hiding it behind a notice loses them their own history. So resume first
    // and fall back to the bare notice only when there is nothing to show.
    // Sending stays blocked either way: the composer is locked here and the
    // server refuses the write regardless of what the client renders.
    if (composerLocked) {
      final resumed = await silentResume();
      if (!resumed) _setPhase(ChatPhase.offline);
      return;
    }

    final resumed = await silentResume();
    if (resumed) return;

    if (_hasIdentity) {
      // Known (logged-in) visitor: skip the pre-chat form, start directly as
      // this person. The host vouches for the identity, so don't re-validate
      // against the server form fields.
      await startSession(
        name: _identityName,
        email: _identityEmail,
        phone: _phone,
        fields: _identityFields,
        skipValidation: true,
      );
    } else if (!cfg.preChatForm.enabled) {
      // Anonymous start: no pre-chat gate.
      await startSession();
    } else {
      _setPhase(ChatPhase.prechat);
    }
  }

  /// `POST /session resumeOnly:true`. Returns true and connects when an active
  /// conversation + token come back; never connects a socket without a token.
  /// On false, restores a sensible phase (prechat / idle / offline) so the
  /// controller never strands at [ChatPhase.resuming]; callers (e.g. [open])
  /// may then override it.
  Future<bool> silentResume() {
    final inflight = _silentResumeInFlight;
    if (inflight != null) return inflight.future;
    final completer = _silentResumeInFlight = Completer<bool>();
    _silentResumeImpl().then(
      (v) {
        if (!completer.isCompleted) completer.complete(v);
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
    ).whenComplete(() => _silentResumeInFlight = null);
    return completer.future;
  }

  Future<bool> _silentResumeImpl() async {
    _setPhase(ChatPhase.resuming);
    final SessionResult res;
    try {
      res = await _guardAuth(() => rest.postSession(
            visitorId: visitorId,
            name: _profile?.name,
            email: _profile?.email,
            locale: _effectiveLocale,
            resumeOnly: true,
          ));
    } catch (e) {
      _emitError(e);
      _setPhase(_idlePhase());
      // No active session we can resume into.
      return false;
    }

    if (res.hasActiveConversation && res.token != null) {
      await _adoptSession(res);
      return true;
    }
    _setPhase(_idlePhase());
    return false;
  }

  /// The phase to fall back to when there is no active conversation: offline
  /// outside working hours, prechat when a form is configured, else idle.
  /// Re-read availability from the server and re-gate the UI.
  ///
  /// Cheap and safe to call whenever the chat becomes visible. [open] only
  /// runs its full flow from an idle phase, so reopening the screen on a
  /// singleton still sitting in `chat` used to refresh nothing at all — the
  /// visitor kept whatever availability was true when they first opened it,
  /// which could be hours earlier and several shift boundaries ago.
  ///
  /// Deliberately does NOT touch the conversation, socket or messages: this is
  /// about whether the workspace is open, not about restarting the session.
  Future<void> refreshAvailability() async {
    if (_disposed) return;
    try {
      final res = await rest.getConfig();
      if (_disposed) return;
      widgetConfig.value = res.config;
      isOpen.value = res.isOpen;
      agentsAccepting.value = res.agentsAccepting;
      visitorMode.value = res.visitorMode;
      availabilityReason.value = res.reason;
      nextOpenAt.value = res.nextOpenAt;
      closureLabel.value = res.closureLabel;
      nextOpenLocal.value = res.nextOpenLocal;
      workspaceTimezone.value = res.timezone;
      _chatAvailabilityMode = res.chatAvailabilityMode;
      _asyncEnabled = res.asyncEnabled;

      // The tenant takes no messages now. Showing the notice is the honest
      // thing to do — the server would refuse a send anyway. The rating screen
      // is left alone; it has no composer and replacing it loses the rating.
      if (composerLocked &&
          phase.value != ChatPhase.offline &&
          phase.value != ChatPhase.feedback) {
        _setPhase(ChatPhase.offline);
      }
    } catch (_) {
      // Availability is a refinement of what we already show; a failed refresh
      // must never break a working chat.
    }
  }

  /// Tenant gating rules, captured from `GET /config` so a later live
  /// availability push is judged by the same rules as the initial load.
  String _chatAvailabilityMode = 'ALWAYS';
  bool _asyncEnabled = false;

  /// The server's decision, mirrored for the UI to bind.
  final ValueNotifier<String> visitorMode = ValueNotifier('CHAT');
  final ValueNotifier<String> availabilityReason = ValueNotifier('OPEN');
  final ValueNotifier<DateTime?> nextOpenAt = ValueNotifier(null);
  final ValueNotifier<String?> closureLabel = ValueNotifier(null);

  /// When the workspace reopens, as `HH:mm` on the BUSINESS's clock. Formatted
  /// server-side — Dart has no IANA database, so the device could only ever
  /// render its own zone, which is the wrong answer for a visitor abroad.
  final ValueNotifier<String?> nextOpenLocal = ValueNotifier(null);

  /// The tenant's configured IANA timezone, e.g. `Asia/Baghdad`.
  final ValueNotifier<String?> workspaceTimezone = ValueNotifier(null);

  /// True when the tenant chose "show a notice only" — the composer must be
  /// disabled, not hidden: an input that vanishes reads as breakage, whereas a
  /// disabled one under the notice explains itself.
  bool get composerLocked => visitorMode.value == 'NOTICE_ONLY';

  /// True when either availability gate says the workspace is unavailable:
  /// outside working hours, or (for WHEN_ACCEPTING tenants) nobody accepting.
  ///
  /// Presentational only — bind it to show a notice. It never blocks writing,
  /// because a message sent while closed is still a real conversation that the
  /// team picks up when they are back.
  bool get workspaceClosed => _workspaceClosed;

  bool get _workspaceClosed {
    if (!isOpen.value) return true;
    return _chatAvailabilityMode == 'WHEN_ACCEPTING' &&
        !agentsAccepting.value &&
        _asyncEnabled;
  }

  /// Availability changed mid-session.
  ///
  /// Nothing to do for the phase any more: closing time shows a notice, it does
  /// not move the visitor anywhere. [isOpen]/[agentsAccepting] have already
  /// been updated by the caller, and [workspaceClosed] derives from them, so
  /// any bound UI re-renders on its own. Kept as a named no-op hook so the
  /// intent is explicit at the call sites rather than looking like an omission.
  void _applyAvailabilityChange() {}

  /// Adopt a server availability verdict, from the socket or a config fetch.
  void _applyWorkspaceAvailability(WorkspaceAvailability a) {
    isOpen.value = a.isOpen;
    agentsAccepting.value = a.agentsAccepting;
    visitorMode.value = a.visitorMode;
    availabilityReason.value = a.reason;
    nextOpenAt.value = a.nextOpenAt;
    closureLabel.value = a.closureLabel;
    nextOpenLocal.value = a.nextOpenLocal;
    workspaceTimezone.value = a.timezone;
    // Same rule as refreshAvailability(): a visitor with a conversation keeps
    // it (minus the composer); one without gets the notice.
    if (composerLocked &&
        _conversationId == null &&
        phase.value != ChatPhase.offline &&
        phase.value != ChatPhase.feedback) {
      _setPhase(ChatPhase.offline);
    }
  }

  ChatPhase _idlePhase() {
    final cfg = widgetConfig.value;
    if (cfg != null && cfg.preChatForm.enabled) return ChatPhase.prechat;
    return ChatPhase.idle;
  }

  /// `POST /session` with optional pre-chat [fields]. Validates client-side for
  /// UX; treats server 400 `{fieldId}` as authority. Persists profile + token,
  /// then connects.
  Future<void> startSession({
    String? name,
    String? email,
    String? phone,
    Map<String, String>? fields,
    bool skipValidation = false,
  }) async {
    // Client-side validation mirroring the server (server stays the authority).
    // Skipped for a host-identified visitor (see [identify]).
    final cfg = widgetConfig.value;
    if (!skipValidation &&
        cfg != null &&
        cfg.preChatForm.enabled &&
        fields != null) {
      for (final PreChatField field in cfg.preChatForm.fields) {
        final err = field.validate(fields[field.id]);
        if (err != null) {
          throw _surface(EasyLiveChatError(err, fieldId: field.id));
        }
      }
    }

    _setPhase(ChatPhase.loading);
    final SessionResult res;
    try {
      res = await _guardAuth(() => rest.postSession(
            visitorId: visitorId,
            name: name ?? _profile?.name,
            email: email ?? _profile?.email,
            phone: phone ?? _phone,
            locale: _effectiveLocale,
            fields: fields,
          ));
    } catch (e) {
      _setPhase(cfg?.preChatForm.enabled == true
          ? ChatPhase.prechat
          : ChatPhase.idle);
      throw _surface(e);
    }

    // Persist the (possibly enriched) profile for future silent-resume calls.
    await _persistProfile(StoredProfile(
      name: name ?? _profile?.name,
      email: email ?? _profile?.email,
      preChat: fields ?? _profile?.preChat,
    ));

    if (res.token != null) {
      await _adoptSession(res);
    }
  }

  /// Adopt a freshly-minted/resumed session: store JWT, seed messages, connect
  /// the /widgets socket, move to [ChatPhase.chat]. Used by both resume + start.
  Future<void> _adoptSession(SessionResult res) async {
    _token = res.token;
    _conversationId = res.conversationId;
    _oldestCursor = res.nextCursor;
    // The payload IS the newest page, so the next fetch continues from its
    // cursor — or stops, when the whole conversation already arrived.
    _historyLoadedOnce = true;
    await storage.write(StorageKeys.token, res.token!);
    if (res.conversationId != null) {
      await storage.write(StorageKeys.conversationId, res.conversationId!);
    }

    _setMessages(_dedupSort(res.messages));
    _connectSocket();
    // Presence (`/widget-presence`) is the pre-chat proactive channel. Once the
    // full chat socket is up, the `/widgets` namespace delivers proactive too —
    // keeping presence open would double-deliver outreach and waste a socket.
    _teardownPresence();
    _setPhase(ChatPhase.chat);
    _startHeartbeat();
  }

  /// Tear down sockets + heartbeat; keep reactive state for the UI.
  void closeSession() {
    _stopHeartbeat();
    _teardownSocket();
    _teardownPresence();
    connection.value = ConnectionState.disconnected;
  }

  // ── messaging ──

  /// Optimistically append a `tmp-` message and emit `message:send`. The
  /// returned [SendResult.serverMessageId] resolves to the server id on ack
  /// (or throws [EasyLiveChatError] on `ok:false`).
  SendResult sendMessage(String body,
      {List<String> attachmentUrls = const []}) {
    final tempId = 'tmp-${_uuid.v4()}';
    final convId = _conversationId ?? '';
    final optimistic = ChatMessage.optimistic(
      tempId: tempId,
      conversationId: convId,
      body: body,
      attachmentUrls: attachmentUrls,
      createdAt: DateTime.now(),
    );
    _appendMessage(optimistic);

    final completer = Completer<String>();
    final socket = _socket;
    if (socket == null) {
      _failOptimistic(tempId);
      final err = const EasyLiveChatError(EasyLiveChatErrorCode.noToken,
          message: 'No active socket — call open()/startSession() first.');
      _emitError(err);
      completer.completeError(err);
      return SendResult(
          optimistic: optimistic, serverMessageId: completer.future);
    }

    socket.sendMessage(body: body, attachmentUrls: attachmentUrls).then((ack) {
      if (ack.ok) {
        final serverId = ack.messageId;
        if (serverId != null) {
          _reconcileOptimistic(
            tempId: tempId,
            serverId: serverId,
            body: body,
          );
          if (!completer.isCompleted) completer.complete(serverId);
        } else {
          // ok but no id — leave optimistic in place, mark as sent.
          _markSent(tempId);
          if (!completer.isCompleted) completer.complete(tempId);
        }
      } else {
        _failOptimistic(tempId);
        final err = EasyLiveChatError(
          EasyLiveChatErrorCode.sendRejected,
          message: ack.error,
        );
        _emitError(err);
        if (!completer.isCompleted) completer.completeError(err);
      }
    }).catchError((Object e) {
      _failOptimistic(tempId);
      final err = e is EasyLiveChatError
          ? e
          : EasyLiveChatError(EasyLiveChatErrorCode.socket,
              message: e.toString(), cause: e);
      _emitError(err);
      if (!completer.isCompleted) completer.completeError(err);
    });

    return SendResult(
        optimistic: optimistic, serverMessageId: completer.future);
  }

  /// Re-send a previously failed message (tap-to-retry). Drops the failed row
  /// and re-sends its body + attachments as a fresh optimistic message. Returns
  /// null when [message] is not in a failed state.
  SendResult? resend(ChatMessage message) {
    if (!message.failed) return null;
    _removeMessage(message.id);
    return sendMessage(
      message.body ?? '',
      attachmentUrls: message.attachmentUrls,
    );
  }

  /// Emit `typing { isTyping }` (caller debounces).
  void setTyping(bool isTyping) {
    _socket?.setTyping(isTyping);
  }

  /// End this conversation on the visitor's behalf.
  ///
  /// Returns whether a POST-CHAT STEP WILL FOLLOW — i.e. whether the caller
  /// should keep the chat on screen for the survey (or CSAT prompt), or has
  /// nothing left to show and should just leave.
  ///
  /// That answer cannot be inferred from the phase afterwards. The phase is
  /// driven by the server's `conversation:closed` echo, and
  /// [_handleConversationClosed] deliberately ignores the echo for a
  /// conversation that has already been closed or already rated — which is
  /// right (the server re-emits on any *→CLOSED transition, and nobody should
  /// be asked to rate the same chat twice) but means "end" can legitimately
  /// change nothing at all. A caller that waited for a phase change in that
  /// case waited forever: the visitor confirmed leaving and stayed put.
  ///
  /// Decided BEFORE the socket call, because the echo can arrive while we are
  /// still awaiting it and would otherwise flip the very sets being read.
  ///
  /// The stored conversation is dropped either way. The server only ever
  /// resumes an OPEN/PENDING thread, so reopening starts a fresh conversation;
  /// clearing the local copy keeps the two from disagreeing. The in-memory id
  /// and token stay put so the post-chat submission can still reach the
  /// conversation it belongs to.
  Future<bool> endChat() async {
    final socket = _socket;
    final id = _conversationId;
    final willShowPostChat = id != null &&
        !_closedHandled.contains(id) &&
        !_ratedConversations.contains(id);
    if (socket == null) return false;
    await socket.endChat();
    await storage.delete(StorageKeys.conversationId);
    await storage.delete(StorageKeys.token);
    if (!willShowPostChat) {
      // Nothing left to ask, so the session is genuinely over — drop the
      // socket and forget the conversation. Leaving them live let a visitor
      // keep typing into a chat they had already ended, and the server treats
      // a customer message to a CLOSED conversation as re-opening it: the
      // thread came back from the dead, already rated, and could then never
      // be closed again (its post-chat step was spent).
      _finishEndedSession();
    }
    return willShowPostChat;
  }

  /// Page older history via `GET /messages?cursor=` (walks backward in time).
  Future<MessagePage> loadOlderMessages() async {
    final token = _token;
    if (token == null) {
      return const MessagePage(messages: [], nextCursor: null);
    }
    // A null cursor means the session payload already reached the start of the
    // conversation. Passing it to the API would re-fetch the NEWEST page
    // instead — harmless (the merge dedupes) but a wasted round trip on every
    // short thread, and now that loading is automatic it happens unprompted.
    if (_oldestCursor == null && _historyLoadedOnce) {
      return const MessagePage(messages: [], nextCursor: null);
    }
    _historyLoadedOnce = true;
    final page = await _guardAuth(() => rest.getMessages(
          token: token,
          cursor: _oldestCursor,
          limit: 50,
        ));
    if (page.messages.isNotEmpty) {
      _mergeMessages(page.messages);
    }
    _oldestCursor = page.nextCursor;
    return page;
  }

  /// Local-only: clear the unread badge (UI calls this when the thread shows).
  void markRead() {
    if (unreadCount.value != 0) unreadCount.value = 0;
  }

  // ── attachments ──

  /// Upload bytes via the current widget JWT; returns the first array element.
  Future<UploadedFile> uploadBytes({
    required List<int> bytes,
    required String filename,
    String? contentType,
    void Function(double progress)? onProgress,
  }) {
    final token = _token;
    if (token == null) {
      throw const EasyLiveChatError(EasyLiveChatErrorCode.noToken,
          message: 'Upload requires an active session token.');
    }
    return _guardAuth(() => rest.uploadBytes(
          token: token,
          bytes: bytes,
          filename: filename,
          contentType: contentType,
          onProgress: onProgress,
        ));
  }

  /// Join a server-relative `/uploads/*` (or placeholder) onto [normalizedApiBase].
  /// Absolute URLs pass through unchanged; non-resolvable placeholders
  /// (e.g. `wa:media:{id}`) pass through so the UI can render an inert chip.
  String resolveUrl(String relativeOrAbsolute) {
    final s = relativeOrAbsolute.trim();
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    if (s.startsWith('/')) return '${config.normalizedApiBase}$s';
    return s;
  }

  // ── offline + CSAT ──

  /// `POST /offline-form` — terminal "we'll get back to you" (no socket).
  Future<String> submitOfflineForm({
    String? name,
    String? email,
    required String message,
  }) async {
    final id = await rest.postOfflineForm(
      name: name ?? _profile?.name,
      email: email ?? _profile?.email,
      message: message,
    );
    return id;
  }

  /// `POST /conversations/:id/feedback` — one-shot CSAT on the current
  /// conversation; marks it rated so the prompt never re-fires.
  Future<FeedbackResult> submitFeedback({
    required int rating,
    String? comment,
  }) async {
    final token = _token;
    final convId = _conversationId;
    if (token == null || convId == null) {
      throw const EasyLiveChatError(EasyLiveChatErrorCode.noToken,
          message: 'Feedback requires an active session token.');
    }
    try {
      final res = await _guardAuth(() => rest.postFeedback(
            token: token,
            conversationId: convId,
            rating: rating,
            comment: comment,
          ));
      _ratedConversations.add(convId);
      return res;
    } on EasyLiveChatError catch (e) {
      // Already rated — treat as terminal so the prompt won't reappear.
      if (e.code == EasyLiveChatErrorCode.alreadyRated) {
        _ratedConversations.add(convId);
      }
      rethrow;
    }
  }

  /// Submit the tenant's post-chat survey for the conversation just closed.
  ///
  /// [fields] is keyed by field **id** — what
  /// [WidgetConfigModel.postChatForm] declares and what the dashboard reads
  /// back. Validation is client-side for UX only; the server re-checks.
  ///
  /// Like [submitFeedback], a 409 from the server means someone already
  /// answered, which is a finished state rather than a failure — swallowed so
  /// the survey doesn't reappear on the next close event.
  Future<void> submitPostChat(Map<String, String> fields) async {
    final token = _token;
    final convId = _conversationId;
    if (token == null || convId == null) {
      throw const EasyLiveChatError(EasyLiveChatErrorCode.noToken,
          message: 'The post-chat survey requires an active session token.');
    }
    try {
      await _guardAuth(() => rest.postChat(
            token: token,
            conversationId: convId,
            fields: fields,
            locale: config.contentLocale ?? config.locale,
          ));
      _ratedConversations.add(convId);
      _finishEndedSession();
    } on EasyLiveChatError catch (e) {
      if (e.code == EasyLiveChatErrorCode.alreadySubmitted) {
        _ratedConversations.add(convId);
        _finishEndedSession();
        return;
      }
      rethrow;
    }
  }

  /// The conversation is over and its post-chat step is done — let go of it.
  ///
  /// Holding the socket open kept the visitor attached to a closed
  /// conversation: their next message re-opened it server-side instead of
  /// starting the fresh chat they were looking at.
  void _finishEndedSession() {
    _teardownSocket();
    _socketConversationId = null;
    _conversationId = null;
    _token = null;
  }

  // ── presence / lifecycle ──

  /// Foreground/background. resumed => heartbeat + presence on; paused => off
  /// (the chat socket has its own auto-reconnect and is left to the transport).
  void setAppLifecycle(EasyLiveChatLifecycle state) {
    if (_lifecycle == state) return;
    _lifecycle = state;
    if (state == EasyLiveChatLifecycle.resumed) {
      _startHeartbeat();
      if (config.enablePresenceSocket && _socket == null) _connectPresence();
    } else {
      _stopHeartbeat();
      _teardownPresence();
    }
  }

  /// Fire-and-forget `POST /visitor/heartbeat` (tolerant). Only meaningful
  /// while foregrounded; the periodic timer calls this directly.
  void heartbeat({String? currentUrl, String? currentTitle}) {
    if (!config.enableHeartbeat) return;
    // Guard the visitorId getter: heartbeat() is public and can be called (e.g.
    // via setAppLifecycle) before boot() finishes, when _visitorId is null.
    if (_visitorId == null) return;
    // Tolerant endpoint (always 2xx) — swallow transport errors silently.
    rest
        .heartbeat(
          visitorId: visitorId,
          currentUrl: currentUrl,
          currentTitle: currentTitle,
          language: _effectiveLocale,
        )
        .catchError((_) {});
  }

  // ──────────────────────────────────────────────────────────────────────
  //  Socket wiring
  // ──────────────────────────────────────────────────────────────────────

  void _connectSocket() {
    final token = _token;
    if (token == null) return;
    if (_socket != null) {
      // Already wired — just re-supply the token (e.g. after a re-mint).
      _socket!.updateToken(token);
      // …but a token for a DIFFERENT conversation needs a new handshake, not
      // just a stored value. The server reads `conversationId` off the token
      // once, when the socket connects, and routes everything sent on that
      // socket there forever. `updateToken` only affects the NEXT connect, so
      // a visitor who ended one chat and started another kept sending into
      // the old, closed conversation — and ending "this" chat closed the old
      // one too, whose id no longer matched, so the close echo was ignored
      // and the exit confirmation appeared to do nothing.
      if (_socketConversationId != _conversationId) {
        _socketConversationId = _conversationId;
        _socket!.reconnectWithFreshAuth();
      }
      return;
    }
    _socketConversationId = _conversationId;
    final socket =
        WidgetSocket(apiBase: config.normalizedApiBase, token: token);
    _socket = socket;
    connection.value = ConnectionState.connecting;

    _socketSubs.add(socket.onMessageNew.listen(_handleMessageNew));
    _socketSubs.add(socket.onMessageUpdated.listen(_handleMessageUpdated));
    _socketSubs.add(socket.onAgentTyping.listen(_handleAgentTyping));
    _socketSubs.add(socket.onAvailability.listen((open) {
      isOpen.value = open;
      _applyAvailabilityChange();
    }));
    _socketSubs.add(socket.onAgentsAccepting.listen((accepting) {
      agentsAccepting.value = accepting;
      _applyAvailabilityChange();
    }));
    // The verdict itself, so a workspace that closes (or reopens) mid-session
    // reaches the visitor without waiting for them to reopen the screen.
    _socketSubs.add(socket.onWorkspaceMode.listen(_applyWorkspaceAvailability));
    _socketSubs
        .add(socket.onConversationClosed.listen(_handleConversationClosed));
    _socketSubs.add(socket.onProactive.listen(_handleProactive));
    _socketSubs.add(socket.onConnectionChange.listen(_handleConnectionChange));
    _socketSubs.add(socket.onConnectError.listen(_handleConnectError));

    socket.connect();
  }

  void _teardownSocket() {
    for (final s in _socketSubs) {
      s.cancel();
    }
    _socketSubs.clear();
    final socket = _socket;
    _socket = null;
    _hasConnectedOnce = false;
    if (socket != null) {
      socket.disconnect().whenComplete(socket.dispose);
    }
  }

  void _connectPresence() {
    if (_presence != null) return;
    final p = PresenceSocket(
      apiBase: config.normalizedApiBase,
      tenantSlug: config.tenantSlug,
      visitorId: visitorId,
    );
    _presence = p;
    _presenceSub = p.onProactive.listen(_handleProactive);
    p.connect();
  }

  void _teardownPresence() {
    _presenceSub?.cancel();
    _presenceSub = null;
    final p = _presence;
    _presence = null;
    if (p != null) {
      p.disconnect().whenComplete(p.dispose);
    }
  }

  // ── inbound handlers ──

  void _handleMessageNew(ChatMessage msg) {
    // 1) Dedup by id.
    final list = messages.value;
    final existingIdx = list.indexWhere((m) => m.id == msg.id);
    if (existingIdx != -1) {
      // Already have it (e.g. our own echo already reconciled) — refresh row.
      final next = List<ChatMessage>.of(list)..[existingIdx] = msg;
      _setMessages(_dedupSort(next));
      return;
    }

    // 2) Reconcile a still-unreconciled local send of ours. The widget protocol
    //    does NOT echo a clientId, so we match the OLDEST local row that still
    //    carries a `tmp-` id (the list is createdAt-sorted, so indexWhere is
    //    FIFO) with the same trimmed body, then consume it (its id becomes the
    //    server id, so a second identical echo matches the next pending temp —
    //    not this one). Keying on the `tmp-` id rather than `isOptimistic` also
    //    catches an ack'd-but-id-less send (`_markSent` clears `isOptimistic`
    //    but keeps the `tmp-` id), so its echo replaces it instead of appending
    //    a duplicate.
    if (msg.isFromCustomer) {
      final optIdx = list.indexWhere((m) =>
          m.isLocalTemp &&
          m.isFromCustomer &&
          (m.body ?? '').trim() == (msg.body ?? '').trim());
      if (optIdx != -1) {
        final next = List<ChatMessage>.of(list)..[optIdx] = msg;
        _setMessages(_dedupSort(next));
        return;
      }
    }

    // 3) Genuinely new message. Unread counts only AGENT replies the user
    //    hasn't seen — never our own echoes, system/bot rows, or anything once
    //    the conversation has moved to the feedback/closed phase.
    _appendMessage(msg);
    if (msg.isFromAgent &&
        phase.value != ChatPhase.chat &&
        phase.value != ChatPhase.feedback) {
      unreadCount.value = unreadCount.value + 1;
    }
    if (!_onMessage.isClosed) _onMessage.add(msg);
  }

  void _handleMessageUpdated(ChatMessage msg) {
    final list = messages.value;
    final idx = list.indexWhere((m) => m.id == msg.id);
    if (idx == -1) {
      // Unknown id — treat as a new arrival (still deduped/sorted).
      _appendMessage(msg);
      return;
    }
    final next = List<ChatMessage>.of(list)..[idx] = msg;
    _setMessages(_dedupSort(next));
  }

  void _handleAgentTyping(bool isTyping) {
    _typingTimer?.cancel();
    if (!isTyping) {
      agentTyping.value = false;
      return;
    }
    agentTyping.value = true;
    // The server only ever sends `isTyping:true`, so arm a 4s auto-clear.
    _typingTimer = Timer(const Duration(seconds: 4), () {
      agentTyping.value = false;
    });
  }

  void _handleConversationClosed(String closedConversationId) {
    // GUARD: the server emits on ANY *→CLOSED PATCH; only fire CSAT once per
    // conversation, and never if already rated.
    if (_conversationId != null && closedConversationId != _conversationId) {
      return;
    }
    if (_closedHandled.contains(closedConversationId)) return;
    if (_ratedConversations.contains(closedConversationId)) return;
    _closedHandled.add(closedConversationId);
    _setPhase(ChatPhase.feedback);
  }

  void _handleProactive(ProactiveMessage msg) {
    if (!_onProactive.isClosed) _onProactive.add(msg);
    // Upgrade presence → full session so the visitor can reply.
    if (_socket == null) {
      silentResume();
    }
  }

  void _handleConnectionChange(bool connected) {
    if (connected) {
      final isReconnect = _hasConnectedOnce;
      _hasConnectedOnce = true;
      connection.value = ConnectionState.connected;
      if (isReconnect) {
        // Live-only delivery: backfill anything missed while we were down.
        // The first connect is skipped — the session payload already seeded
        // the newest page.
        _backfillAfterReconnect();
      }
    } else {
      // A drop while we still hold a token => transport is reconnecting.
      connection.value = _token != null
          ? ConnectionState.reconnecting
          : ConnectionState.disconnected;
    }
  }

  void _handleConnectError(String error) {
    connection.value = _token != null
        ? ConnectionState.reconnecting
        : ConnectionState.disconnected;
    // Auth-class handshake failures (missing/expired/invalid token) → re-mint.
    if (_isAuthHandshakeError(error)) {
      _remintToken();
    } else {
      _emitError(
          EasyLiveChatError(EasyLiveChatErrorCode.socket, message: error));
    }
  }

  /// Heuristic: does this `connect_error` look like an auth/JWT handshake
  /// rejection (→ re-mint) rather than a generic transport error? The server
  /// sends stable-ish codes (e.g. `WIDGET_TOKEN_MISSING`) and jose verify
  /// messages. We match specific token/JWT signals — NOT a bare `TOKEN` — so a
  /// benign message that merely contains the word "token" can't trigger a
  /// re-mint storm. (Ideally the server sends one machine code we match exactly.)
  static bool _isAuthHandshakeError(String error) {
    final e = error.toUpperCase();
    const signals = [
      'WIDGET_TOKEN',
      'TOKEN_MISSING',
      'TOKEN_EXPIRED',
      'TOKEN_INVALID',
      'INVALID_TOKEN',
      'UNAUTHORIZED',
      'UNAUTHENTICATED',
      'JWT',
      'JWS',
      'SIGNATURE',
      'ERR_JW', // jose: ERR_JWS_INVALID / ERR_JWT_EXPIRED / ERR_JWK_*
    ];
    return signals.any(e.contains);
  }

  // ──────────────────────────────────────────────────────────────────────
  //  Token re-mint (single-flight) + reconnect backfill
  // ──────────────────────────────────────────────────────────────────────

  /// Run [op]; if it fails with an auth error (401/403) or the token is about
  /// to expire, re-mint once (single-flight) and retry. The protocol has no
  /// refresh route, so re-mint == `POST /session resumeOnly:true`.
  Future<T> _guardAuth<T>(Future<T> Function() op) async {
    // Pre-emptive re-mint if the current token is within the refresh leeway.
    if (_token != null && _isTokenExpiring(_token!)) {
      await _remintToken();
    }
    try {
      return await op();
    } on EasyLiveChatError catch (e) {
      if (e.isAuthError) {
        final reminted = await _remintToken();
        if (reminted) {
          return await op();
        }
      }
      rethrow;
    }
  }

  /// Single-flight re-mint. Returns true when a fresh token was obtained and
  /// the socket reconnected; false when the conversation is gone (CLOSED) and
  /// we dropped back to pre-chat/anonymous.
  Future<bool> _remintToken() {
    final inflight = _remintInFlight;
    if (inflight != null) return inflight.future;

    final completer = Completer<bool>();
    _remintInFlight = completer;

    () async {
      try {
        final res = await rest.postSession(
          visitorId: visitorId,
          name: _profile?.name,
          email: _profile?.email,
          locale: _effectiveLocale,
          resumeOnly: true,
        );
        if (res.hasActiveConversation && res.token != null) {
          _token = res.token;
          _conversationId = res.conversationId ?? _conversationId;
          await storage.write(StorageKeys.token, res.token!);
          // Apply the fresh token. A LIVE socket won't re-read its handshake
          // auth on a no-op connect(), so force a fresh handshake — its
          // onConnect (with _hasConnectedOnce already true) then owns the gap
          // backfill. A cold socket connects for the first time, which is NOT
          // treated as a reconnect, so backfill inline only in that case.
          final socket = _socket;
          if (socket != null) {
            socket.updateToken(res.token!);
            socket.reconnectWithFreshAuth();
          } else {
            _connectSocket();
            await _backfillAfterReconnect();
          }
          if (!completer.isCompleted) completer.complete(true);
        } else {
          // Conversation CLOSED — don't loop. Drop to pre-chat / anonymous.
          _token = null;
          await storage.delete(StorageKeys.token);
          _teardownSocket();
          connection.value = ConnectionState.disconnected;
          final cfg = widgetConfig.value;
          _setPhase(cfg != null && cfg.preChatForm.enabled
              ? ChatPhase.prechat
              : ChatPhase.idle);
          if (!completer.isCompleted) completer.complete(false);
        }
      } catch (e) {
        _emitError(e);
        if (!completer.isCompleted) completer.complete(false);
      } finally {
        _remintInFlight = null;
      }
    }();

    return completer.future;
  }

  /// Reconnect backfill: the server delivers `message:new` live-only, so on
  /// every reconnect we page `GET /messages` from the newest end and WALK the
  /// cursor backward until the page overlaps ids we already hold (gap-safe
  /// beyond a single 50-message page). Merge by id, sort by createdAt.
  Future<void> _backfillAfterReconnect() async {
    final token = _token;
    if (token == null) return;

    final known =
        messages.value.where((m) => !m.isOptimistic).map((m) => m.id).toSet();

    final fetched = <ChatMessage>[];
    String? cursor;
    // Bound the walk so a pathological gap can't loop forever.
    for (var pages = 0; pages < 20; pages++) {
      final MessagePage page;
      try {
        page = await rest.getMessages(token: token, cursor: cursor, limit: 50);
      } on EasyLiveChatError catch (_) {
        // Stop walking on any failure (incl. auth). We may be inside an
        // in-flight re-mint here, so do NOT recurse into _remintToken (it
        // would deadlock on its own completer). The connect_error handler /
        // next _guardAuth call re-mints and re-backfills cleanly.
        break;
      }
      if (page.messages.isEmpty) break;
      fetched.addAll(page.messages);

      // Overlap check: if any message in this page is already known, we've
      // closed the gap.
      final overlaps = page.messages.any((m) => known.contains(m.id));
      cursor = page.nextCursor;
      if (overlaps || cursor == null) break;
    }

    if (fetched.isNotEmpty) {
      _mergeMessages(fetched);
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  //  Heartbeat
  // ──────────────────────────────────────────────────────────────────────

  void _startHeartbeat() {
    if (!config.enableHeartbeat) return;
    if (_lifecycle != EasyLiveChatLifecycle.resumed) return;
    if (_heartbeatTimer != null) return;
    // Fire one immediately, then on the configured cadence.
    heartbeat();
    _heartbeatTimer = Timer.periodic(config.heartbeatInterval, (_) {
      if (_lifecycle == EasyLiveChatLifecycle.resumed) {
        heartbeat();
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  // ──────────────────────────────────────────────────────────────────────
  //  Message-list helpers (always assign new immutable lists)
  // ──────────────────────────────────────────────────────────────────────

  void _setMessages(List<ChatMessage> next) {
    messages.value = List<ChatMessage>.unmodifiable(next);
  }

  void _appendMessage(ChatMessage msg) {
    _setMessages(_dedupSort([...messages.value, msg]));
  }

  void _mergeMessages(Iterable<ChatMessage> incoming) {
    _setMessages(_dedupSort([...messages.value, ...incoming]));
  }

  /// Dedup by id (last write wins, so server rows replace optimistic temps that
  /// happen to share an id only after reconcile) and sort by createdAt.
  List<ChatMessage> _dedupSort(List<ChatMessage> input) {
    final byId = <String, ChatMessage>{};
    for (final m in input) {
      byId[m.id] = m;
    }
    final list = byId.values.toList()
      ..sort((a, b) {
        final c = a.createdAt.compareTo(b.createdAt);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    return list;
  }

  /// Replace the optimistic `tmp-` row with the server row. If a server row of
  /// the same id already arrived (via `message:new`), just drop the temp.
  void _reconcileOptimistic({
    required String tempId,
    required String serverId,
    required String body,
  }) {
    final list = messages.value;
    final tmpIdx = list.indexWhere((m) => m.id == tempId);
    final alreadyHaveServer = list.any((m) => m.id == serverId);

    if (tmpIdx == -1) return; // already reconciled by the echo.

    if (alreadyHaveServer) {
      // The live echo beat the ack — drop the optimistic temp.
      final next = List<ChatMessage>.of(list)..removeAt(tmpIdx);
      _setMessages(_dedupSort(next));
      return;
    }

    final reconciled = list[tmpIdx].copyWith(
      id: serverId,
      isOptimistic: false,
      failed: false,
      deliveryStatus: MessageDeliveryStatus.sent,
    );
    final next = List<ChatMessage>.of(list)..[tmpIdx] = reconciled;
    _setMessages(_dedupSort(next));
  }

  void _markSent(String tempId) {
    final list = messages.value;
    final idx = list.indexWhere((m) => m.id == tempId);
    if (idx == -1) return;
    final next = List<ChatMessage>.of(list)
      ..[idx] = list[idx].copyWith(
        isOptimistic: false,
        failed: false,
        deliveryStatus: MessageDeliveryStatus.sent,
      );
    _setMessages(next);
  }

  void _failOptimistic(String tempId) {
    final list = messages.value;
    final idx = list.indexWhere((m) => m.id == tempId);
    if (idx == -1) return;
    final next = List<ChatMessage>.of(list)
      ..[idx] = list[idx].copyWith(
        failed: true,
        deliveryStatus: MessageDeliveryStatus.failed,
      );
    _setMessages(next);
  }

  void _removeMessage(String id) {
    final list = messages.value;
    final idx = list.indexWhere((m) => m.id == id);
    if (idx == -1) return;
    final next = List<ChatMessage>.of(list)..removeAt(idx);
    _setMessages(next);
  }

  // ──────────────────────────────────────────────────────────────────────
  //  Misc helpers
  // ──────────────────────────────────────────────────────────────────────

  void _setPhase(ChatPhase next) {
    if (_disposed) return;
    if (phase.value != next) phase.value = next;
  }

  String? get _effectiveLocale => config.locale;

  bool _isTokenExpiring(String token) {
    try {
      final exp = JwtDecoder.getExpirationDate(token);
      final threshold = DateTime.now().add(config.tokenRefreshLeeway);
      return exp.isBefore(threshold);
    } catch (_) {
      // Undecodable → treat as not-expiring; the auth-error path will recover.
      return false;
    }
  }

  Future<void> _persistProfile(StoredProfile profile) async {
    _profile = profile;
    await storage.write(StorageKeys.profile, jsonEncode(profile.toJson()));
  }

  /// Normalize any throwable into an [EasyLiveChatError].
  EasyLiveChatError _surface(Object e) {
    if (e is EasyLiveChatError) return e;
    return EasyLiveChatError(EasyLiveChatErrorCode.unknown,
        message: e.toString(), cause: e);
  }

  void _emitError(Object e) {
    if (_onError.isClosed) return;
    _onError.add(_surface(e));
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _typingTimer?.cancel();
    _stopHeartbeat();
    for (final s in _socketSubs) {
      s.cancel();
    }
    _socketSubs.clear();
    _presenceSub?.cancel();
    _presenceSub = null;
    _socket?.dispose();
    _presence?.dispose();
    _onMessage.close();
    _onProactive.close();
    _onError.close();
    phase.dispose();
    widgetConfig.dispose();
    isOpen.dispose();
    agentsAccepting.dispose();
    visitorMode.dispose();
    nextOpenLocal.dispose();
    workspaceTimezone.dispose();
    availabilityReason.dispose();
    nextOpenAt.dispose();
    closureLabel.dispose();
    connection.dispose();
    messages.dispose();
    agentTyping.dispose();
    unreadCount.dispose();
  }
}
