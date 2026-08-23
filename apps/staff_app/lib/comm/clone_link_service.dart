import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// What the master grants a clone when it signs in: its identity + the feature
/// labels it's allowed to open.
class LinkGrant {
  final String name;
  final String department;
  final List<String> features;
  const LinkGrant(this.name, this.department, this.features);
}

/// Master-side resolver: given a satellite's Business ID + Clone ID, return its
/// grant, or null if the pairing is unknown/rejected.
typedef GrantResolver = LinkGrant? Function(String businessId, String cloneId);

enum CloneLinkState { searching, connected, rejected }

/// LAN control-plane that pairs a clone (Satellite) device to its master and
/// carries the master's granted permissions to it — the same UDP-broadcast
/// approach as the walkie ([WalkieService]) but on its own port and for control
/// messages, not voice.
///
/// - **Clone mode:** broadcasts `login {biz, clone}` until the master answers
///   with a `grant`; then heartbeats `ping` and keeps the granted features
///   fresh. Exposes [linkState] + [grant].
/// - **Master mode:** answers each `login`/`ping` by resolving the pairing to a
///   grant, tracks which clones are live in [onlineClones], and can
///   [pushUpdate] fresh grants when permissions change.
class CloneLinkService {
  static const int _port = 47772;
  static const Duration _searchEvery = Duration(milliseconds: 1500);
  // Presence/link-loss grace. Matched to the voice leg's tolerance (WalkieService
  // holds a call ~20s of silence) so a weak cross-floor link that drops a run of
  // heartbeats doesn't flap the clone offline or make the clone drop the call
  // while the voice is still riding through the dip. Reaping is swept on its own
  // faster cadence ([_reapEvery]) so a peer that truly left is still noticed.
  static const Duration _onlineTtl = Duration(seconds: 20);
  static const Duration _reapEvery = Duration(seconds: 4);

  RawDatagramSocket? _socket;
  bool _isMaster = false;

  // ── Clone side ──
  String _biz = '';
  String _clone = '';
  Timer? _cloneTimer;
  DateTime? _lastGrant;
  final ValueNotifier<CloneLinkState> linkState =
      ValueNotifier(CloneLinkState.searching);
  final ValueNotifier<LinkGrant?> grant = ValueNotifier(null);
  // True while the voice leg is live (a call has been *accepted*). Cleared if
  // the link drops so a stale call can't linger.
  final ValueNotifier<bool> onCall = ValueNotifier(false);
  // Ring states, distinct from [onCall]. At most one is true at a time:
  //   incomingCall — the master is ringing us; show Receive / Decline.
  //   outgoingCall — we're ringing the master; awaiting their answer.
  final ValueNotifier<bool> incomingCall = ValueNotifier(false);
  final ValueNotifier<bool> outgoingCall = ValueNotifier(false);
  // Master's address, learned from the source of its unicast messages, so
  // clone→master call-control can be sent unicast — that keeps the clone from
  // hearing its own broadcast back and re-processing it.
  InternetAddress? _masterAddr;

  /// The master's LAN address, learned once linked. Used by the catalog sync
  /// ([CatalogSyncService]) to pull the master's Inventory over HTTP.
  InternetAddress? get masterAddress => _masterAddr;

  // ── Master side ──
  GrantResolver? _resolve;
  String _businessId = '';
  Timer? _reapTimer;
  // cloneId -> (address, lastSeen) for currently-live clones.
  final Map<String, (InternetAddress, DateTime)> _live = {};
  // Demo-only: clone IDs the operator has flagged as "linked" to demonstrate
  // the master's presence indicator without a second physical device. Unioned
  // into [onlineClones] alongside real LAN presence, so the UI path is
  // identical — nothing downstream can tell a demo link from a real one.
  final Set<String> _demoLinked = {};
  final ValueNotifier<Set<String>> onlineClones = ValueNotifier(<String>{});
  // The clone currently ringing the master (its id), or null — drives the
  // incoming-call chime + Receive/Decline sheet on the POS.
  final ValueNotifier<String?> incomingFromClone = ValueNotifier(null);
  // Master-side call-control callbacks, set by the dashboard:
  //   onCloneAccepted — a clone answered a master-placed call (open voice).
  //   onCloneEnded    — a clone declined / cancelled / hung up (hang up card).
  void Function(String cloneId)? onCloneAccepted;
  void Function(String cloneId)? onCloneEnded;

  Future<bool> _bind() async {
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _port,
          reuseAddress: true);
      _socket!.broadcastEnabled = true;
      _socket!.listen(_onEvent);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Master ────────────────────────────────────────────────────────

  Future<bool> startMaster({
    required String businessId,
    required GrantResolver resolve,
  }) async {
    _isMaster = true;
    _businessId = businessId;
    _resolve = resolve;
    if (!await _bind()) return false;
    _reapTimer = Timer.periodic(_reapEvery, (_) => _reap());
    return true;
  }

  /// Re-send fresh grants to every live clone — call when the roster or access
  /// grants change so connected satellites update immediately.
  void pushUpdate() {
    if (!_isMaster) return;
    for (final entry in _live.entries.toList()) {
      _answer(entry.key, entry.value.$1);
    }
  }

  /// Ring ([on] = true) or hang up / cancel ([on] = false) a specific clone.
  /// A ring is an *invitation*: the clone rings and voice starts only when it
  /// taps Receive (which sends back `accept`). Sent unicast to the clone's
  /// last-known address; a no-op if the clone isn't currently linked.
  void callClone(String cloneId, bool on) {
    if (!_isMaster) return;
    // Prefer the clone's last-known unicast address. If it briefly fell out of
    // the live roster (a cross-floor heartbeat gap), fall back to broadcast so a
    // hang-up still lands — the message carries `clone`, so only that clone acts
    // on it. This is why CUT can never be silently swallowed mid-dropout.
    final to = _live[cloneId]?.$1;
    _sendReliable(
      on
          ? {
              't': 'ring',
              'dir': 'to_clone',
              'clone': cloneId,
              'name': 'Master',
              'from': 'master',
            }
          : {'t': 'decline', 'clone': cloneId, 'from': 'master'},
      to,
    );
  }

  /// Answer a clone that is ringing us (a clone-placed call): tell it to go
  /// voice and clear the incoming-call state.
  void acceptClone(String cloneId) {
    if (!_isMaster) return;
    _sendReliable({'t': 'accept', 'clone': cloneId, 'from': 'master'},
        _live[cloneId]?.$1);
    if (incomingFromClone.value == cloneId) incomingFromClone.value = null;
  }

  /// Decline a clone that is ringing us, or hang up an active clone-placed call.
  void declineClone(String cloneId) {
    if (!_isMaster) return;
    _sendReliable({'t': 'decline', 'clone': cloneId, 'from': 'master'},
        _live[cloneId]?.$1);
    if (incomingFromClone.value == cloneId) incomingFromClone.value = null;
  }

  // Route the clone→master call-control messages (a clone dialling in, or
  // answering / ending a master-placed call).
  void _onMasterCallControl(Map<String, dynamic> msg) {
    final clone = msg['clone'] as String?;
    if (clone == null) return;
    switch (msg['t']) {
      case 'ring':
        if (msg['dir'] == 'to_master') incomingFromClone.value = clone;
        break;
      case 'accept':
        onCloneAccepted?.call(clone);
        break;
      case 'decline':
        if (incomingFromClone.value == clone) incomingFromClone.value = null;
        onCloneEnded?.call(clone);
        break;
    }
  }

  void _answer(String cloneId, InternetAddress to) {
    final g = _resolve?.call(_businessId, cloneId);
    if (g == null) {
      _send({'t': 'grant', 'clone': cloneId, 'ok': false}, to);
      return;
    }
    _send({
      't': 'grant',
      'clone': cloneId,
      'ok': true,
      'name': g.name,
      'dept': g.department,
      'features': g.features,
    }, to);
  }

  void _onMasterMsg(Map<String, dynamic> msg, InternetAddress from) {
    final biz = msg['biz'] as String?;
    final clone = msg['clone'] as String?;
    if (biz == null || clone == null) return;
    final g = _resolve?.call(biz, clone);
    if (g != null) {
      final wasOffline = !_live.containsKey(clone);
      _live[clone] = (from, DateTime.now());
      if (wasOffline) _publishOnline();
    }
    _answer(clone, from); // always reply (ok:true or ok:false)
  }

  void _reap() {
    final now = DateTime.now();
    final gone = _live.entries
        .where((e) => now.difference(e.value.$2) > _onlineTtl)
        .map((e) => e.key)
        .toList();
    if (gone.isEmpty) return;
    for (final id in gone) {
      _live.remove(id);
    }
    _publishOnline();
  }

  void _publishOnline() =>
      onlineClones.value = {..._live.keys, ..._demoLinked};

  // ── Demo mode ─────────────────────────────────────────────────────

  /// True while any clone is being simulated as linked.
  bool get demoActive => _demoLinked.isNotEmpty;

  bool isDemoLinked(String cloneId) => _demoLinked.contains(cloneId);

  /// Simulate (or stop simulating) a satellite sign-in for [cloneId]. Drives
  /// the same [onlineClones] notifier real presence uses.
  void setDemoLinked(String cloneId, bool linked) {
    if (cloneId.isEmpty) return;
    final changed =
        linked ? _demoLinked.add(cloneId) : _demoLinked.remove(cloneId);
    if (changed) _publishOnline();
  }

  /// Clear every simulated link.
  void clearDemo() {
    if (_demoLinked.isEmpty) return;
    _demoLinked.clear();
    _publishOnline();
  }

  // ── Clone ─────────────────────────────────────────────────────────

  Future<bool> startClone({
    required String businessId,
    required String cloneId,
  }) async {
    _isMaster = false;
    _biz = businessId;
    _clone = cloneId;
    if (!await _bind()) return false;
    _tick(); // announce immediately
    _cloneTimer = Timer.periodic(_searchEvery, (_) => _tick());
    return true;
  }

  void _tick() {
    // Announce/heartbeat. Fall back to searching if the master went silent.
    final connected = linkState.value == CloneLinkState.connected;
    if (connected &&
        _lastGrant != null &&
        DateTime.now().difference(_lastGrant!) > _onlineTtl) {
      linkState.value = CloneLinkState.searching;
      // Lost the master → drop any active or pending call.
      onCall.value = false;
      incomingCall.value = false;
      outgoingCall.value = false;
    }
    _send({'t': 'login', 'biz': _biz, 'clone': _clone});
  }

  // ── Clone-side call actions ───────────────────────────────────────

  /// Ring the master (a clone-placed call). The master rings; voice starts
  /// when it answers (we receive `accept`).
  void callMaster() {
    if (_isMaster) return;
    outgoingCall.value = true;
    incomingCall.value = false;
    _sendToMaster({
      't': 'ring',
      'dir': 'to_master',
      'clone': _clone,
      'name': grant.value?.name ?? _clone,
    });
  }

  /// Answer the master's incoming ring — go voice.
  void acceptIncoming() {
    if (_isMaster || !incomingCall.value) return;
    incomingCall.value = false;
    onCall.value = true; // the satellite screen opens the mic off this
    _sendToMaster({'t': 'accept', 'clone': _clone});
  }

  /// Decline the master's incoming ring.
  void declineIncoming() {
    if (_isMaster) return;
    incomingCall.value = false;
    _sendToMaster({'t': 'decline', 'clone': _clone});
  }

  /// Hang up an active call, or cancel one we're placing.
  void hangUp() {
    if (_isMaster) return;
    onCall.value = false;
    outgoingCall.value = false;
    incomingCall.value = false;
    _sendToMaster({'t': 'decline', 'clone': _clone});
  }

  // All clone→master call-control (ring / accept / decline) goes out reliably.
  void _sendToMaster(Map<String, dynamic> msg) => _sendReliable(msg, _masterAddr);

  void _onCloneMsg(Map<String, dynamic> msg, InternetAddress from) {
    if (msg['clone'] != _clone) return;
    switch (msg['t']) {
      case 'ring':
        // Only an invite *to us* rings. Ignore the echo of our own to_master
        // broadcast entirely — learning _masterAddr from it would point us at
        // our own address and silently break accept/decline delivery.
        if (msg['dir'] == 'to_clone') {
          _masterAddr = from;
          if (!onCall.value) incomingCall.value = true;
        }
        return;
      case 'accept': // master answered the call we placed
        _masterAddr = from;
        incomingCall.value = false;
        outgoingCall.value = false;
        onCall.value = true;
        return;
      case 'decline': // master declined / cancelled / hung up
        _masterAddr = from;
        incomingCall.value = false;
        outgoingCall.value = false;
        onCall.value = false;
        return;
      case 'grant':
        _masterAddr = from;
        break;
      default:
        return;
    }
    _lastGrant = DateTime.now();
    if (msg['ok'] == true) {
      grant.value = LinkGrant(
        (msg['name'] as String?) ?? _clone,
        (msg['dept'] as String?) ?? '',
        [for (final f in (msg['features'] as List? ?? const [])) f.toString()],
      );
      linkState.value = CloneLinkState.connected;
    } else {
      grant.value = null;
      linkState.value = CloneLinkState.rejected;
    }
  }

  // ── Shared ────────────────────────────────────────────────────────

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _socket?.receive();
    if (dg == null) return;
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (_isMaster) {
      // Ignore the loopback of our OWN broadcasts. Master call-control that
      // falls back to broadcast (a clone briefly out of the live roster) is
      // echoed back to this socket; without this guard a broadcast `decline`
      // (CUT) re-enters as a clone-ended event, which re-broadcasts CUT — an
      // infinite loop. Clone→master messages never carry `from:'master'`, so
      // only our own echoes are dropped.
      if (msg['from'] == 'master') return;
      final t = msg['t'];
      if (t == 'login' || t == 'ping') {
        _onMasterMsg(msg, dg.address);
      } else if (t == 'ring' || t == 'accept' || t == 'decline') {
        _onMasterCallControl(msg);
      }
    } else {
      _onCloneMsg(msg, dg.address);
    }
  }

  void _send(Map<String, dynamic> msg, [InternetAddress? to]) {
    final sock = _socket;
    if (sock == null) return;
    final data = utf8.encode(jsonEncode(msg));
    sock.send(data, to ?? InternetAddress('255.255.255.255'), _port);
  }

  // Send a one-shot call-control message ([times]) over, spaced out, so a single
  // lost UDP packet on a weak link doesn't drop a ring / accept / decline —
  // the "sometimes the ring doesn't come" case. The receivers are idempotent
  // (they guard on current call state), so the duplicates are harmless: it
  // rings, answers or hangs up exactly once. Heartbeats (login/ping/grant) are
  // NOT sent this way — they already repeat on their own timer.
  void _sendReliable(Map<String, dynamic> msg, [InternetAddress? to]) {
    _send(msg, to);
    for (var i = 1; i < 3; i++) {
      Future<void>.delayed(
          Duration(milliseconds: 45 * i), () => _send(msg, to));
    }
  }

  Future<void> stop() async {
    _cloneTimer?.cancel();
    _reapTimer?.cancel();
    _cloneTimer = null;
    _reapTimer = null;
    _socket?.close();
    _socket = null;
    _live.clear();
    _demoLinked.clear();
    _masterAddr = null;
    onCall.value = false;
    incomingCall.value = false;
    outgoingCall.value = false;
    incomingFromClone.value = null;
  }

  void dispose() {
    stop();
    linkState.dispose();
    grant.dispose();
    onCall.dispose();
    incomingCall.dispose();
    outgoingCall.dispose();
    onlineClones.dispose();
    incomingFromClone.dispose();
  }
}
