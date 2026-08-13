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
  static const Duration _onlineTtl = Duration(seconds: 6);

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
  // True while the master has this clone on an active call (CALL → true,
  // CUT → false). Cleared if the link drops so a stale call can't linger.
  final ValueNotifier<bool> onCall = ValueNotifier(false);

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
    _reapTimer = Timer.periodic(_onlineTtl, (_) => _reap());
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

  /// Dial ([on] = true) or hang up ([on] = false) a specific clone. Sent
  /// unicast to the clone's last-known address; a no-op if the clone isn't
  /// currently linked (you can only dial a device that's signed in).
  void callClone(String cloneId, bool on) {
    if (!_isMaster) return;
    final entry = _live[cloneId];
    if (entry == null) return;
    _send({'t': 'call', 'clone': cloneId, 'on': on}, entry.$1);
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
      onCall.value = false; // lost the master → drop any active call
    }
    _send({'t': 'login', 'biz': _biz, 'clone': _clone});
  }

  void _onCloneMsg(Map<String, dynamic> msg) {
    if (msg['clone'] != _clone) return;
    // Master dialling this clone (CALL) or hanging up (CUT).
    if (msg['t'] == 'call') {
      onCall.value = msg['on'] == true;
      return;
    }
    if (msg['t'] != 'grant') return;
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
      if (msg['t'] == 'login' || msg['t'] == 'ping') {
        _onMasterMsg(msg, dg.address);
      }
    } else {
      _onCloneMsg(msg);
    }
  }

  void _send(Map<String, dynamic> msg, [InternetAddress? to]) {
    final sock = _socket;
    if (sock == null) return;
    final data = utf8.encode(jsonEncode(msg));
    sock.send(data, to ?? InternetAddress('255.255.255.255'), _port);
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
    onCall.value = false;
  }

  void dispose() {
    stop();
    linkState.dispose();
    grant.dispose();
    onCall.dispose();
    onlineClones.dispose();
  }
}
