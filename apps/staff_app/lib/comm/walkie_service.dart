import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

/// A peer (Master or Satellite) discovered on the LAN.
class WalkiePeer {
  final String id;
  String name;
  InternetAddress address;
  DateTime lastSeen;
  RTCPeerConnection? pc;
  bool connected;
  WalkiePeer({
    required this.id,
    required this.name,
    required this.address,
    required this.lastSeen,
    this.pc,
    this.connected = false,
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
  static const Duration _announceEvery = Duration(seconds: 2);
  static const Duration _peerTtl = Duration(seconds: 8);

  final String selfId = _randomId();
  String selfName;

  final ValueNotifier<WalkieState> state =
      ValueNotifier<WalkieState>(WalkieState.off);
  final ValueNotifier<List<WalkiePeer>> peers =
      ValueNotifier<List<WalkiePeer>>(const []);
  final ValueNotifier<bool> talking = ValueNotifier<bool>(false);
  final ValueNotifier<bool> loopback = ValueNotifier<bool>(false);

  final Map<String, WalkiePeer> _peers = {};
  RawDatagramSocket? _socket;
  MediaStream? _localStream;
  Timer? _announceTimer;
  Timer? _reapTimer;

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
      // Route audio out of the loudspeaker (walkie-talkie style).
      await Helper.setSpeakerphoneOn(true);

      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _port,
          reuseAddress: true);
      _socket!.broadcastEnabled = true;
      _socket!.listen(_onSocketEvent);

      _announce();
      _announceTimer = Timer.periodic(_announceEvery, (_) => _announce());
      _reapTimer = Timer.periodic(_peerTtl, (_) => _reapStalePeers());

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
    _announceTimer = null;
    _reapTimer = null;
    setTalking(false);
    await stopLoopback();
    for (final p in _peers.values) {
      await p.pc?.close();
    }
    _peers.clear();
    _publishPeers();
    _socket?.close();
    _socket = null;
    await _localStream?.dispose();
    _localStream = null;
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
        _onOffer(from, msg);
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
        _send({
          't': 'ice',
          'id': selfId,
          'to': peer.id,
          'candidate': c.toMap(),
        }, peer.address);
      }
    };
    pc.onConnectionState = (s) {
      peer.connected =
          s == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
      _publishPeers();
    };
    // Remote audio auto-plays on Android via onTrack.
    return pc;
  }

  Future<void> _dial(WalkiePeer peer) async {
    final pc = await _ensurePc(peer);
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    _send({
      't': 'offer',
      'id': selfId,
      'to': peer.id,
      'sdp': offer.sdp,
      'type': offer.type,
    }, peer.address);
  }

  Future<void> _onOffer(String from, Map<String, dynamic> msg) async {
    final peer = _peers[from];
    if (peer == null) return;
    final pc = await _ensurePc(peer);
    await pc.setRemoteDescription(
        RTCSessionDescription(msg['sdp'] as String?, msg['type'] as String?));
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    _send({
      't': 'answer',
      'id': selfId,
      'to': from,
      'sdp': answer.sdp,
      'type': answer.type,
    }, peer.address);
  }

  Future<void> _onAnswer(String from, Map<String, dynamic> msg) async {
    final pc = _peers[from]?.pc;
    if (pc == null) return;
    await pc.setRemoteDescription(
        RTCSessionDescription(msg['sdp'] as String?, msg['type'] as String?));
  }

  Future<void> _onIce(String from, Map<String, dynamic> msg) async {
    final pc = _peers[from]?.pc;
    final c = msg['candidate'] as Map<String, dynamic>?;
    if (pc == null || c == null) return;
    await pc.addCandidate(RTCIceCandidate(
      c['candidate'] as String?,
      c['sdpMid'] as String?,
      c['sdpMLineIndex'] as int?,
    ));
  }

  void _reapStalePeers() {
    final now = DateTime.now();
    final gone = _peers.values
        .where((p) => now.difference(p.lastSeen) > _peerTtl)
        .toList();
    if (gone.isEmpty) return;
    for (final p in gone) {
      p.pc?.close();
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
  }

  static String _randomId() {
    final r = Random();
    return List.generate(8, (_) => r.nextInt(16).toRadixString(16)).join();
  }
}
