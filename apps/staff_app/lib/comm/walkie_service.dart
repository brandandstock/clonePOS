import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// A peer (Master or Satellite) discovered on the LAN.
class WalkiePeer {
  final String id;
  String name;
  InternetAddress address;
  DateTime lastSeen;
  RTCPeerConnection? pc;
  bool connected;
  // When we last (re)sent an offer to this peer — used to retry a handshake
  // whose offer/answer/ICE was lost on a weak link, without hammering it.
  DateTime? lastDialAt;
  // True once this peer's media has connected at least once. A partner we've
  // actually talked to is NEVER reaped for heartbeat silence — a cross-floor
  // signal dip pauses the audio and reconnects, instead of ending the call.
  bool everConnected;
  // SDP of the last offer we answered for this peer. Offers are now sent
  // reliably (3×) so a lost first packet doesn't cost a 10s connect; this lets
  // the answerer dedupe the retransmits — only the first builds a connection,
  // the identical repeats are ignored so there's no fresh-pc churn.
  String? lastOfferSdp;
  WalkiePeer({
    required this.id,
    required this.name,
    required this.address,
    required this.lastSeen,
    this.pc,
    this.connected = false,
    this.everConnected = false,
    this.lastOfferSdp,
  });
}

enum WalkieState { off, starting, ready, denied, error }

/// LAN push-to-talk walkie-talkie for the Clones (Satellite) fleet.
///
/// - **Discovery/signaling:** UDP *broadcast* on [_port]. Broadcast (not
///   multicast) is used deliberately — receiving multicast on Android needs a
///   native WifiManager.MulticastLock that Dart's RawDatagramSocket doesn't
///   hold, whereas limited broadcast is delivered without it.
/// - **Voice:** flutter_webrtc audio PeerConnections, one per peer (mesh).
///   Empty ICE servers → host candidates only, so it works fully offline on
///   the same subnet. Push-to-talk enables/disables the local mic track, so
///   holding the button broadcasts your voice to every connected peer.
/// - **Self-test:** with a single device, [startLoopback] wires the mic
///   through a local WebRTC offer/answer so you hear yourself — proving the
///   capture→encode→playback pipeline without a second device.
class WalkieService {
  WalkieService({String? name}) : selfName = name ?? 'Master';

  static const int _port = 47771;
  // Weak-WiFi resilient: announce often, but only reap a peer after a long
  // silence. On a couple of signal bars, broadcast `hello`s get dropped — an
  // 8s TTL would reap a still-present peer mid-call and cut the voice. A 1s
  // announce with a 20s TTL tolerates losing many hellos in a row.
  static const Duration _announceEvery = Duration(seconds: 1);
  // How long a peer we've NEVER connected to may go silent before we forget it
  // (a transient discovery entry). A peer we've actually talked to is exempt
  // from reaping entirely (see [WalkiePeer.everConnected]) so an in-progress
  // call is never dropped — only stalled handshakes to a device that truly went
  // away are cleaned up. Generous, because a weak cross-floor link drops many
  // hellos in a row while the media handshake is still climbing to connected.
  static const Duration _peerTtl = Duration(seconds: 45);
  // How often to sweep for stale peers (decoupled from the TTL above).
  static const Duration _reapEvery = Duration(seconds: 4);
  // Retry an un-connected handshake. On a weak link the single-shot
  // offer/answer/ICE can be lost; re-offering with a fresh connection until the
  // media actually connects is what makes voice come up at range. The cooldown
  // is deliberately generous: at range ICE needs several seconds of its own
  // retransmits to succeed, so we must NOT re-dial and tear that down early —
  // the retry loop is only a backstop for a handshake that never progresses.
  // A definitively-failed connection is re-dialed immediately (see
  // [_resetPeerConn]), so the cooldown never delays recovery from a real drop.
  static const Duration _retryEvery = Duration(seconds: 2);
  // Backstop for a handshake that never progresses. Was 9s — far too long as
  // the *first-connect* path: a single lost offer left the caller silent for
  // ~10s. The offer is now sent reliably (3×, see [_dial]), so a shorter
  // cooldown is safe; on a same-subnet host-only ICE the media connects in
  // well under a second, so 4s cannot prematurely tear down a working leg.
  static const Duration _dialCooldown = Duration(seconds: 4);
  // Audio send cap for weak-link robustness. Dropped 32k → 24k: on a lossy AP
  // fewer/smaller packets break up far less, and Opus voice stays clear at 24k.
  static const int _voiceMaxBitrate = 24000;
  // Remote playback gain. The in-call stream is quiet by default; the native
  // range tops out ~10, so this is a strong (but non-distorting) boost.
  static const double _remoteVolume = 10;

  final String selfId = _randomId();
  String selfName;

  final ValueNotifier<WalkieState> state =
      ValueNotifier<WalkieState>(WalkieState.off);
  final ValueNotifier<List<WalkiePeer>> peers =
      ValueNotifier<List<WalkiePeer>>(const []);
  final ValueNotifier<bool> talking = ValueNotifier<bool>(false);
  final ValueNotifier<bool> loopback = ValueNotifier<bool>(false);
  // Live link quality for the on-screen field readout: inbound packet-loss %
  // (over the last sample window), jitter and rx count. Empty until the first
  // stats sample. This is what decides network-vs-code when voice breaks up.
  final ValueNotifier<String> diag = ValueNotifier<String>('');
  final Map<String, (int, int)> _lastRtp = {}; // peerId -> (recv, lost)

  final Map<String, WalkiePeer> _peers = {};
  RawDatagramSocket? _socket;
  MediaStream? _localStream;
  Timer? _announceTimer;
  Timer? _reapTimer;
  Timer? _retryTimer;
  // Diagnostics: periodic getStats + connect-time logging (tag WALKIEDIAG).
  Timer? _statsTimer;
  int _startMs = 0;

  // Loopback self-test pair.
  RTCPeerConnection? _lbA;
  RTCPeerConnection? _lbB;

  static const Map<String, dynamic> _rtcConfig = {
    // No STUN/TURN — same-LAN host candidates only, fully offline-safe.
    'iceServers': <Map<String, dynamic>>[],
    'sdpSemantics': 'unified-plan',
  };

  bool get isReady => state.value == WalkieState.ready;

  /// Requests the mic, opens the mic stream (muted until PTT), and starts LAN
  /// discovery. Returns false if the mic permission was denied.
  Future<bool> start() async {
    if (state.value == WalkieState.ready ||
        state.value == WalkieState.starting) {
      return true;
    }
    state.value = WalkieState.starting;
    try {
      final granted = await Permission.microphone.request();
      if (!granted.isGranted) {
        state.value = WalkieState.denied;
        return false;
      }
      _localStream = await navigator.mediaDevices
          .getUserMedia({'audio': true, 'video': false});
      _muteMic(true); // PTT: silent until the button is held
      // Put Android into in-communication audio mode, THEN force the
      // loudspeaker. Without communication mode the peer connects but the
      // REMOTE audio is never rendered — the "connected yet silent" case.
      await Helper.setAndroidAudioConfiguration(
          AndroidAudioConfiguration.communication);
      await Helper.setSpeakerphoneOn(true);

      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _port,
          reuseAddress: true);
      _socket!.broadcastEnabled = true;
      _socket!.listen(_onSocketEvent);

      _announce();
      _announceTimer = Timer.periodic(_announceEvery, (_) => _announce());
      _reapTimer = Timer.periodic(_reapEvery, (_) => _reapStalePeers());
      _retryTimer = Timer.periodic(_retryEvery, (_) => _retryUnconnected());
      _startMs = DateTime.now().millisecondsSinceEpoch;
      debugPrint('WALKIEDIAG start id=$selfId name=$selfName');
      _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) => _logStats());

      // Hold the screen awake for the whole session. On MIUI the default
      // ~1-minute display timeout drops WiFi into power-save, which stalls the
      // LAN heartbeats and gets the voice leg reaped — the "cuts after a
      // minute" bug. Best-effort: never let a wakelock failure abort start-up.
      try {
        await WakelockPlus.enable();
      } catch (_) {}

      state.value = WalkieState.ready;
      return true;
    } catch (e) {
      state.value = WalkieState.error;
      return false;
    }
  }

  Future<void> stop() async {
    _announceTimer?.cancel();
    _reapTimer?.cancel();
    _retryTimer?.cancel();
    _statsTimer?.cancel();
    _announceTimer = null;
    _reapTimer = null;
    _retryTimer = null;
    _statsTimer = null;
    diag.value = '';
    _lastRtp.clear();
    try {
      await WakelockPlus.disable();
    } catch (_) {}
    setTalking(false);
    await stopLoopback();
    for (final p in _peers.values) {
      final pc = p.pc;
      p.pc = null; // detach first so the close doesn't trigger a re-dial
      await pc?.close();
    }
    _peers.clear();
    _publishPeers();
    _socket?.close();
    _socket = null;
    await _localStream?.dispose();
    _localStream = null;
    // Return the device to normal media audio routing after the call.
    try {
      await Helper.setAndroidAudioConfiguration(
          AndroidAudioConfiguration.media);
    } catch (_) {}
    state.value = WalkieState.off;
  }

  // ---- Push-to-talk ---------------------------------------------------------

  /// Hold to talk: unmutes the mic so it streams to every connected peer (and
  /// the loopback, if the self-test is on). Release to go silent again.
  void setTalking(bool on) {
    if (talking.value == on) return;
    talking.value = on;
    _muteMic(!on);
  }

  void _muteMic(bool muted) {
    final tracks = _localStream?.getAudioTracks() ?? const [];
    for (final t in tracks) {
      t.enabled = !muted;
    }
  }

  // ---- Loopback self-test (single device) ----------------------------------

  /// Wires the mic through a local WebRTC connection so held-PTT audio plays
  /// back on this device. Use headphones to avoid feedback. Proves the audio
  /// pipeline works without a second device.
  Future<void> startLoopback() async {
    if (_localStream == null || _lbA != null) return;
    _lbA = await createPeerConnection(_rtcConfig);
    _lbB = await createPeerConnection(_rtcConfig);
    _lbA!.onIceCandidate = (c) {
      if (c.candidate != null) _lbB?.addCandidate(c);
    };
    _lbB!.onIceCandidate = (c) {
      if (c.candidate != null) _lbA?.addCandidate(c);
    };
    // Remote audio on B plays automatically on Android once negotiated.
    for (final track in _localStream!.getAudioTracks()) {
      await _lbA!.addTrack(track, _localStream!);
    }
    final offer = await _lbA!.createOffer();
    await _lbA!.setLocalDescription(offer);
    await _lbB!.setRemoteDescription(offer);
    final answer = await _lbB!.createAnswer();
    await _lbB!.setLocalDescription(answer);
    await _lbA!.setRemoteDescription(answer);
    loopback.value = true;
  }

  Future<void> stopLoopback() async {
    await _lbA?.close();
    await _lbB?.close();
    _lbA = null;
    _lbB = null;
    loopback.value = false;
  }

  // ---- LAN discovery + signaling -------------------------------------------

  void _announce() {
    _send({'t': 'hello', 'id': selfId, 'name': selfName});
  }

  void _send(Map<String, dynamic> msg, [InternetAddress? to]) {
    final sock = _socket;
    if (sock == null) return;
    final data = utf8.encode(jsonEncode(msg));
    sock.send(data, to ?? InternetAddress('255.255.255.255'), _port);
  }

  // Send a small signaling message [times] over, spaced out, so a lost packet
  // on a weak link doesn't sink the whole handshake. Used for the offer, the
  // answer and ICE candidates — the make-or-break packets when only a couple of
  // host candidates exist. The offer's retransmits are deduped on the answer
  // side ([WalkiePeer.lastOfferSdp]) so repeating it can't reset a negotiation.
  void _sendReliable(Map<String, dynamic> msg, InternetAddress? to,
      {int times = 3}) {
    _send(msg, to);
    for (var i = 1; i < times; i++) {
      Future<void>.delayed(
          Duration(milliseconds: 45 * i), () => _send(msg, to));
    }
  }

  void _onSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _socket?.receive();
    if (dg == null) return;
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final from = msg['id'] as String?;
    if (from == null || from == selfId) return; // ignore our own broadcasts
    final to = msg['to'] as String?;
    if (to != null && to != selfId) return; // targeted at someone else

    switch (msg['t']) {
      case 'hello':
        _onHello(from, (msg['name'] as String?) ?? 'Clone', dg.address);
        break;
      case 'offer':
        _onOffer(from, msg, dg.address);
        break;
      case 'answer':
        _onAnswer(from, msg);
        break;
      case 'ice':
        _onIce(from, msg);
        break;
    }
  }

  void _onHello(String id, String name, InternetAddress address) {
    final existing = _peers[id];
    if (existing == null) {
      final peer = WalkiePeer(
        id: id,
        name: name,
        address: address,
        lastSeen: DateTime.now(),
      );
      _peers[id] = peer;
      _publishPeers();
      // Deterministic offerer to avoid glare: the lexicographically-smaller
      // id dials the other, so exactly one side creates the offer.
      if (selfId.compareTo(id) < 0) {
        _dial(peer);
      }
    } else {
      existing
        ..name = name
        ..address = address
        ..lastSeen = DateTime.now();
    }
  }

  Future<RTCPeerConnection> _ensurePc(WalkiePeer peer) async {
    if (peer.pc != null) return peer.pc!;
    final pc = await createPeerConnection(_rtcConfig);
    peer.pc = pc;
    // Send our mic to this peer (muted until PTT).
    for (final track in _localStream?.getAudioTracks() ?? const []) {
      await pc.addTrack(track, _localStream!);
    }
    pc.onIceCandidate = (c) {
      if (c.candidate != null) {
        _sendReliable({
          't': 'ice',
          'id': selfId,
          'to': peer.id,
          'candidate': c.toMap(),
        }, peer.address);
      }
    };
    pc.onConnectionState = (s) {
      // Ignore late events from a superseded connection. _resetPeerConn (and
      // _onOffer) close a pc *after* detaching it, and that close fires this
      // handler again with `Closed`. By then peer.pc may already be a freshly
      // re-dialed connection — acting on this stale event would tear that new
      // leg down and kick off a redial storm, the "voice won't recover after a
      // drop" bug. Only the peer's current pc may drive presence or re-dial.
      if (peer.pc != pc) return;
      final connected =
          s == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
      debugPrint('WALKIEDIAG conn ${peer.name} -> $s '
          'at +${DateTime.now().millisecondsSinceEpoch - _startMs}ms');
      peer.connected = connected;
      if (connected) peer.everConnected = true;
      _publishPeers();
      if (connected) {
        // Re-assert loudspeaker + communication routing now that media flows.
        // The incoming-call ringtone plays on the MEDIA stream just before the
        // call connects, and on some devices that leaves the route on media /
        // earpiece so the connected call is silent — this forces it back.
        _forceCallAudioRoute();
        // Cap the send bitrate so a weak link isn't asked to carry more than it
        // can — fewer/smaller packets means far less break-up at range.
        _capSendBitrate(peer);
      }
      // A failed/closed leg never recovers on its own, and _ensurePc would
      // keep handing back the dead connection — the "re-call shows connected
      // but no voice" bug. Drop it so the next handshake re-dials fresh.
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _resetPeerConn(peer);
      }
    };
    // Explicitly enable the incoming audio track so remote voice is rendered,
    // and boost its playback — the in-call (communication) stream renders
    // quietly by default, which is the "voice is low" complaint.
    pc.onTrack = (RTCTrackEvent event) {
      if (event.track.kind == 'audio') {
        event.track.enabled = true;
        () async {
          try {
            await Helper.setVolume(_remoteVolume, event.track);
          } catch (_) {}
        }();
      }
    };
    return pc;
  }

  Future<void> _dial(WalkiePeer peer) async {
    peer.lastDialAt = DateTime.now();
    final pc = await _ensurePc(peer);
    // NOTE: Opus SDP is left EXACTLY as libwebrtc generates it. Munging it
    // (even just adding useinbandfec) is reverted — on-device it left the call
    // stuck "reconnecting", never establishing media. See the project rule:
    // do not touch the Opus SDP. FEC, if wanted, must come another way.
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    // Send the offer reliably (like the answer/ICE). On a lossy AP a single
    // offer packet dropping used to strand the call for a full retry cooldown;
    // sending it a few times spaced out gets it across on the first attempt.
    // The answerer dedupes identical retransmits via [WalkiePeer.lastOfferSdp].
    _sendReliable({
      't': 'offer',
      'id': selfId,
      'to': peer.id,
      'sdp': offer.sdp,
      'type': offer.type,
    }, peer.address);
  }

  Future<void> _onOffer(
      String from, Map<String, dynamic> msg, InternetAddress addr) async {
    // Create the peer if the offer beat its `hello` here (discovery race on a
    // lossy link) so an offer is never dropped for a not-yet-known peer.
    var peer = _peers[from];
    if (peer == null) {
      peer = WalkiePeer(
          id: from, name: 'Clone', address: addr, lastSeen: DateTime.now());
      _peers[from] = peer;
    } else {
      peer
        ..address = addr
        ..lastSeen = DateTime.now();
    }
    // Dedupe the reliable-offer retransmits: an identical offer we've already
    // begun answering must NOT tear down and rebuild the connection, or the 3×
    // send would thrash the negotiation. Only a genuinely new offer (a re-dial,
    // which carries fresh SDP) starts a new leg.
    final offerSdp = msg['sdp'] as String?;
    if (offerSdp != null && offerSdp == peer.lastOfferSdp && peer.pc != null) {
      return;
    }
    peer.lastOfferSdp = offerSdp;
    // Answer each (new) offer on a FRESH connection: a retried offer (the far
    // side re-dialing after a lost packet) then always starts a clean
    // negotiation instead of colliding with a half-open one.
    final old = peer.pc;
    if (old != null) {
      peer.pc = null;
      await old.close();
    }
    final pc = await _ensurePc(peer);
    await pc.setRemoteDescription(
        RTCSessionDescription(offerSdp, msg['type'] as String?));
    final answer = await pc.createAnswer(); // SDP left untouched (see _dial)
    await pc.setLocalDescription(answer);
    _sendReliable({
      't': 'answer',
      'id': selfId,
      'to': from,
      'sdp': answer.sdp,
      'type': answer.type,
    }, peer.address);
    _publishPeers();
  }

  // Retry only the INITIAL handshake that hasn't reached "connected" yet — the
  // fix for voice not coming up at range on a first dial. Once a peer HAS
  // connected, a transient WebRTC `Disconnected` recovers on its own in a
  // second or two; re-dialing it instead tears down the recovering leg and
  // forces a full renegotiation every cooldown — that churn is itself a cause
  // of break-up. A leg that truly dies goes `Failed`, which [_resetPeerConn]
  // re-dials immediately, so recovery from a real drop never depends on this.
  // Only the deterministic offerer retries, at most once per [_dialCooldown].
  void _retryUnconnected() {
    final now = DateTime.now();
    for (final peer in _peers.values) {
      if (peer.connected) continue;
      if (peer.everConnected) continue; // let ICE recover / Failed path handles it
      if (selfId.compareTo(peer.id) >= 0) continue; // we're the answerer here
      final last = peer.lastDialAt;
      if (last != null && now.difference(last) < _dialCooldown) continue;
      _redial(peer);
    }
  }

  Future<void> _redial(WalkiePeer peer) async {
    final old = peer.pc;
    if (old != null) {
      peer.pc = null;
      await old.close();
    }
    await _dial(peer);
  }

  Future<void> _onAnswer(String from, Map<String, dynamic> msg) async {
    final pc = _peers[from]?.pc;
    if (pc == null) return;
    // A retry can leave a late answer that belongs to a superseded offer; if
    // it doesn't fit this connection's state, ignore it — the next retry
    // reconciles both sides. Never let it throw uncaught.
    try {
      await pc.setRemoteDescription(
          RTCSessionDescription(msg['sdp'] as String?, msg['type'] as String?));
    } catch (_) {}
  }

  Future<void> _onIce(String from, Map<String, dynamic> msg) async {
    final pc = _peers[from]?.pc;
    final c = msg['candidate'] as Map<String, dynamic>?;
    if (pc == null || c == null) return;
    // Candidates for a torn-down/retried connection are harmless to drop.
    try {
      await pc.addCandidate(RTCIceCandidate(
        c['candidate'] as String?,
        c['sdpMid'] as String?,
        c['sdpMLineIndex'] as int?,
      ));
    } catch (_) {}
  }

  // Force the call onto the loudspeaker in communication mode. Called both at
  // start and again once a peer connects, to override any media/earpiece route
  // the incoming-call ringtone may have left behind. Best-effort.
  Future<void> _forceCallAudioRoute() async {
    try {
      await Helper.setAndroidAudioConfiguration(
          AndroidAudioConfiguration.communication);
      await Helper.setSpeakerphoneOn(true);
    } catch (_) {}
  }

  // Cap this peer's audio send bitrate. 32 kbps is clear mono voice yet light
  // enough to hold together on a weak (~2-bar) link where a higher rate breaks
  // up. Applied via setParameters (post-connection) so it can't disturb the SDP
  // negotiation. Best-effort.
  Future<void> _capSendBitrate(WalkiePeer peer) async {
    final pc = peer.pc;
    if (pc == null) return;
    try {
      final senders = await pc.getSenders();
      for (final s in senders) {
        if (s.track?.kind != 'audio') continue;
        final params = s.parameters;
        final encs = params.encodings ?? <RTCRtpEncoding>[];
        if (encs.isEmpty) {
          encs.add(RTCRtpEncoding(maxBitrate: _voiceMaxBitrate));
        } else {
          for (final e in encs) {
            e.maxBitrate = _voiceMaxBitrate;
          }
        }
        params.encodings = encs;
        await s.setParameters(params);
      }
    } catch (_) {}
  }

  // Diagnostics: log inbound/outbound audio RTP stats so we can see, on-device,
  // whether break-up is packet loss (network — needs better WiFi) or a clean
  // link (audio pipeline). Best-effort; never throws into the timer.
  Future<void> _logStats() async {
    for (final p in _peers.values) {
      final pc = p.pc;
      if (pc == null) continue;
      try {
        final reports = await pc.getStats();
        for (final r in reports) {
          final v = r.values;
          final kind = v['kind'] ?? v['mediaType'];
          if (r.type == 'inbound-rtp' && kind == 'audio') {
            final recv = (v['packetsReceived'] as num?)?.toInt() ?? 0;
            final lost = (v['packetsLost'] as num?)?.toInt() ?? 0;
            final jitterMs =
                (((v['jitter'] as num?)?.toDouble() ?? 0) * 1000).round();
            // Delta over this sample window → live loss %, not lifetime average.
            final prev = _lastRtp[p.id];
            final dRecv = prev == null ? recv : recv - prev.$1;
            final dLost = prev == null ? lost : lost - prev.$2;
            _lastRtp[p.id] = (recv, lost);
            final denom = dRecv + dLost;
            final lossPct = denom > 0 ? (100 * dLost / denom).round() : 0;
            diag.value = 'loss $lossPct%  ·  jitter ${jitterMs}ms  ·  rx $recv';
            debugPrint('WALKIEDIAG in ${p.name} recv=$recv lost=$lost '
                'loss=$lossPct% jitter=${jitterMs}ms '
                'fecPkts=${v['fecPacketsReceived']}');
          } else if (r.type == 'outbound-rtp' && kind == 'audio') {
            debugPrint('WALKIEDIAG out ${p.name} sent=${v['packetsSent']} '
                'rate=${v['targetBitrate']}');
          }
        }
      } catch (_) {}
    }
  }

  // Tear down a dead peer connection and, if the peer is still present, re-dial
  // from the deterministic offerer so voice returns without a manual re-call.
  // The pc is detached before closing so nothing (including the close-triggered
  // onConnectionState) reuses or double-heals it.
  void _resetPeerConn(WalkiePeer peer) {
    final pc = peer.pc;
    if (pc == null) return;
    peer.pc = null;
    peer.connected = false;
    pc.close();
    _publishPeers();
    if (_peers.containsKey(peer.id) && selfId.compareTo(peer.id) < 0) {
      _dial(peer);
    }
  }

  void _reapStalePeers() {
    final now = DateTime.now();
    final gone = _peers.values
        .where((p) =>
            // Never reap a call partner: once connected, we hold the entry and
            // keep (re)dialing so the voice returns by itself when the peer is
            // back in range. Only forget a peer we never reached and that has
            // gone quiet — an abandoned discovery entry, not a live call.
            !p.everConnected &&
            p.pc == null &&
            now.difference(p.lastSeen) > _peerTtl)
        .toList();
    if (gone.isEmpty) return;
    for (final p in gone) {
      final pc = p.pc;
      p.pc = null; // detach first so the close doesn't trigger a re-dial
      pc?.close();
      _peers.remove(p.id);
    }
    _publishPeers();
  }

  void _publishPeers() {
    peers.value = _peers.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  void dispose() {
    stop();
    state.dispose();
    peers.dispose();
    talking.dispose();
    loopback.dispose();
    diag.dispose();
  }

  static String _randomId() {
    final r = Random();
    return List.generate(8, (_) => r.nextInt(16).toRadixString(16)).join();
  }
}
