import 'dart:async';

import 'package:flutter/material.dart';
import 'package:clone_pos_core/models/product.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:permission_handler/permission_handler.dart';

import '../comm/catalog_sync_service.dart';
import '../comm/clone_link_service.dart';
import '../comm/ringtone_service.dart';
import '../comm/walkie_service.dart';
import 'active_carts_view.dart';
import 'inventory_browser.dart';
import 'master_dashboard_screen.dart' show AppTheme;
import 'sales_kit_opened_view.dart';

const Color _orange = Color(0xFFE87722);
const Color _green = Color(0xFF2ECC71);
const Color _bg = Color(0xFF1A1A1A);
const Color _card = Color(0xFF262626);

// Master clone-card palette — the call panel mirrors the master's live card so
// both ends of a call share one visual language.
const Color _cardLive = Color(0xFFF4C75D); // mustard — live card
const Color _cardText = Color(0xFF63605B); // card label/number/time
const Color _callGreen = Color(0xFF00C700); // CALL / live mic
const Color _cutRed = Color(0xFFF64900); // CUT / muted

const Map<String, IconData> _featureIcons = {
  'Carts': Symbols.shopping_cart,
  'Clones': Symbols.devices_other,
  'Inventory': Symbols.inventory_2,
  'Logistics': Symbols.local_shipping,
  'Analytics': Symbols.bar_chart,
  'Accounts': Symbols.receipt_long,
  'Sales Kit': Symbols.slideshow,
  'Data': Symbols.database,
};

/// The Clone (Satellite) device's screen. Signs in over the LAN with the
/// Business ID + Clone ID; once the master answers, it shows the clone's
/// identity and only the feature tiles the master granted. Until then it shows
/// a connecting / rejected state. Sign-out returns to the role chooser.
class SatelliteViewScreen extends StatefulWidget {
  final String businessId;
  final String cloneId;
  final VoidCallback onSignOut;
  const SatelliteViewScreen({
    super.key,
    required this.businessId,
    required this.cloneId,
    required this.onSignOut,
  });

  @override
  State<SatelliteViewScreen> createState() => _SatelliteViewScreenState();
}

class _SatelliteViewScreenState extends State<SatelliteViewScreen> {
  final CloneLinkService _link = CloneLinkService();

  // Clone-side call clock — runs while the master has us on a call.
  Timer? _callTimer;
  int _callSeconds = 0;

  // Hands-free voice for the active call (WebRTC, same mesh as the walkie).
  WalkieService? _walkie;
  bool _micMuted = false;

  // Incoming-call chime (master ringing this clone).
  final RingtoneService _ring = RingtoneService();

  // Live mirror of the master's Inventory, pulled over the LAN once linked.
  // Null until the first successful sync — Inventory then falls back to seed
  // data. Passed into InventoryBrowser so the clone shows the master's catalog
  // (imports, edits, deletions) instead of its own bundled seed.
  List<Product>? _catalog;
  String? _catVersion;
  bool _syncing = false;
  Timer? _catalogPoll;

  @override
  void initState() {
    super.initState();
    _link.onCall.addListener(_onCallChanged);
    _link.incomingCall.addListener(_onIncomingChanged);
    _link.outgoingCall.addListener(_onRingStateChanged);
    _link.linkState.addListener(_onLinkStateChanged);
    _link.startClone(
      businessId: widget.businessId,
      cloneId: widget.cloneId,
    );
    // Ask for the mic up-front (at sign-in) so the first incoming call
    // connects instantly instead of prompting mid-call. Best-effort — if the
    // operator declines, the call panel still surfaces a "mic blocked" state.
    Permission.microphone.request();
  }

  void _onCallChanged() {
    if (_link.onCall.value) {
      _ring.stop(); // answered — silence any ring
      _callSeconds = 0;
      _callTimer?.cancel();
      _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _callSeconds++);
      });
      _startVoice();
    } else {
      _callTimer?.cancel();
      _callTimer = null;
      _stopVoice();
    }
    if (mounted) setState(() {});
  }

  // Master is ringing us: chime + Receive/Decline banner. If it rings the full
  // 30s unanswered, it's a missed call — decline it so the master hangs up.
  void _onIncomingChanged() {
    if (_link.incomingCall.value) {
      _ring.start(onTimeout: _link.declineIncoming);
    } else {
      _ring.stop();
    }
    if (mounted) setState(() {});
  }

  void _onRingStateChanged() {
    if (mounted) setState(() {});
  }

  // Once linked, pull the master's catalog and keep it fresh. A cheap version
  // token (file size + mtime) is polled every few seconds; the full catalog is
  // re-downloaded only when that token changes.
  void _onLinkStateChanged() {
    if (_link.linkState.value == CloneLinkState.connected) {
      _syncCatalog(); // immediate first pull
      _catalogPoll ??= Timer.periodic(
          const Duration(seconds: 4), (_) => _syncCatalog());
    } else {
      _catalogPoll?.cancel();
      _catalogPoll = null;
      _catVersion = null; // force a fresh pull on the next link
    }
  }

  Future<void> _syncCatalog() async {
    final addr = _link.masterAddress;
    if (addr == null || _syncing) return;
    _syncing = true;
    try {
      final ver = await CatalogSyncService.fetchVersion(addr);
      // Unchanged since our last successful pull — skip the heavy download.
      if (ver != null && ver == _catVersion && _catalog != null) return;
      final products = await CatalogSyncService.fetchCatalog(addr);
      if (products != null && mounted) {
        setState(() {
          _catalog = products;
          _catVersion = ver;
        });
      }
    } finally {
      _syncing = false;
    }
  }

  // Open the mic and join the voice mesh so master↔clone hear each other.
  void _startVoice() {
    _micMuted = false;
    () async {
      final w = _walkie ??=
          WalkieService(name: _link.grant.value?.name ?? widget.cloneId);
      if (!w.isReady) {
        final ok = await w.start();
        if (!ok) {
          if (mounted) setState(() {}); // reflect denied/error in the banner
          return;
        }
      }
      w.setTalking(true); // hands-free
      if (mounted) setState(() {});
    }();
  }

  void _stopVoice() {
    final w = _walkie;
    if (w == null) return;
    () async {
      w.setTalking(false);
      await w.stop();
    }();
  }

  void _toggleMute() {
    final w = _walkie;
    if (w == null || !w.isReady) return;
    setState(() => _micMuted = !_micMuted);
    w.setTalking(!_micMuted);
  }

  String _fmt(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _callTimer?.cancel();
    _catalogPoll?.cancel();
    _link.onCall.removeListener(_onCallChanged);
    _link.incomingCall.removeListener(_onIncomingChanged);
    _link.outgoingCall.removeListener(_onRingStateChanged);
    _link.linkState.removeListener(_onLinkStateChanged);
    _ring.dispose();
    _walkie?.dispose();
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: ValueListenableBuilder<CloneLinkState>(
          valueListenable: _link.linkState,
          builder: (_, state, __) {
            return ValueListenableBuilder<LinkGrant?>(
              valueListenable: _link.grant,
              builder: (_, grant, __) {
                if (state == CloneLinkState.connected && grant != null) {
                  return _connected(grant);
                }
                return _status(state);
              },
            );
          },
        ),
      ),
    );
  }

  // ── Connecting / rejected ──
  Widget _status(CloneLinkState state) {
    final rejected = state == CloneLinkState.rejected;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (rejected)
                const Icon(Icons.error_outline, color: _orange, size: 44)
              else
                const SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(
                      color: _orange, strokeWidth: 3),
                ),
              const SizedBox(height: 20),
              Text(
                rejected ? 'Couldn’t sign in' : 'Connecting to master…',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                rejected
                    ? 'The master didn’t recognise these IDs. Check them, and '
                        'make sure the master is on this WiFi.'
                    : 'Looking for the master on this WiFi…',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              _idChips(),
              const SizedBox(height: 22),
              TextButton(
                onPressed: widget.onSignOut,
                style: TextButton.styleFrom(
                    foregroundColor: Colors.white.withValues(alpha: 0.8)),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _idChips() {
    Widget chip(String label, String value) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Text(label,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      color: _orange,
                      fontSize: 15,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        chip('BUSINESS', widget.businessId),
        const SizedBox(width: 10),
        chip('CLONE', widget.cloneId),
      ],
    );
  }

  // ── Connected: identity + granted tiles ──
  Widget _connected(LinkGrant grant) {
    return Column(
      children: [
        _header(grant),
        if (_link.incomingCall.value)
          _incomingBanner()
        else if (_link.outgoingCall.value)
          _outgoingBanner()
        else if (_link.onCall.value)
          _callBanner(),
        Expanded(
          child: grant.features.isEmpty
              ? Center(
                  child: Text(
                    'No features granted yet.\nAsk the master to grant access.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 15,
                        height: 1.5),
                  ),
                )
              : GridView.count(
                  padding: const EdgeInsets.all(20),
                  crossAxisCount: 4,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 1.05,
                  children: [
                    for (final f in grant.features) _tile(f),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _header(LinkGrant grant) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 20, 18),
      decoration: const BoxDecoration(
        border: Border(
            bottom: BorderSide(color: Color(0xFF333333), width: 1)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
                color: _green, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                grant.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '${grant.department}  ·  Linked to master',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            widget.cloneId,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 16),
          // Call the master POS. Hidden while a call is already ringing or
          // live — those states own the banner below.
          if (!_link.onCall.value &&
              !_link.incomingCall.value &&
              !_link.outgoingCall.value) ...[
            FilledButton.icon(
              onPressed: _link.callMaster,
              style: FilledButton.styleFrom(
                backgroundColor: _callGreen,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              icon: const Icon(Symbols.call, size: 18),
              label: const Text('Call master',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
          ],
          OutlinedButton.icon(
            onPressed: widget.onSignOut,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
            ),
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }

  // Active-call panel — shown while the master has this satellite on a call.
  // Styled like the master's live clone card (mustard + card text + a circular
  // CALL/CUT-style button) so both ends of the call read as one interface.
  // The master peer on the voice mesh (there's normally just one). Prefers a
  // connected peer, else the most-recently-heard — used for the live link
  // readout below.
  WalkiePeer? _primaryPeer() {
    final list = _walkie?.peers.value ?? const <WalkiePeer>[];
    WalkiePeer? best;
    for (final p in list) {
      if (best == null ||
          (p.connected && !best.connected) ||
          (p.connected == best.connected && p.lastSeen.isAfter(best.lastSeen))) {
        best = p;
      }
    }
    return best;
  }

  Widget _callBanner() {
    final state = _walkie?.state.value;
    final denied = state == WalkieState.denied || state == WalkieState.error;
    final connecting = state == null || state == WalkieState.starting;

    // Live link readout — this banner rebuilds once a second off the call
    // clock, so these values update as you walk. `heardAgo` is the practical
    // signal meter: 0–1s means a strong link (the master announces every 1s);
    // it climbs as heartbeats start dropping, and the leg flips to RECONNECTING
    // at the point voice actually breaks. Note the physical spot when it does.
    final peer = _primaryPeer();
    final voiceUp = peer?.connected ?? false;
    final heardAgo =
        peer == null ? null : DateTime.now().difference(peer.lastSeen).inSeconds;

    // Status line + accent, matching master-card semantics.
    final String label;
    Color dotColor;
    if (denied) {
      label = 'MIC BLOCKED — ENABLE IN SETTINGS';
      dotColor = _cutRed;
    } else if (connecting) {
      label = 'CONNECTING AUDIO…';
      dotColor = _cutRed;
    } else if (!voiceUp) {
      label = heardAgo == null
          ? 'RECONNECTING…'
          : 'RECONNECTING · heard ${heardAgo}s ago';
      dotColor = const Color(0xFFB26B00); // amber: link degraded / recovering
    } else {
      final base = _micMuted ? 'ON CALL — MUTED' : 'ON CALL';
      label = heardAgo == null ? base : '$base · LINK OK · ${heardAgo}s';
      dotColor = _callGreen;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
      decoration: BoxDecoration(
        color: _cardLive, // mustard live card
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Live indicator + caller identity + running clock.
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _cardText,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Master  ·  ${_fmt(_callSeconds)}',
                  style: const TextStyle(
                    color: _cardText,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                // Live link-quality readout (packet loss / jitter) so the voice
                // break-up can be measured on-device while walking: high loss %
                // means it's the WiFi, not the app.
                if (_walkie != null)
                  ValueListenableBuilder<String>(
                    valueListenable: _walkie!.diag,
                    builder: (_, d, __) => d.isEmpty
                        ? const SizedBox(height: 2)
                        : Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              d,
                              style: TextStyle(
                                color: _cardText.withValues(alpha: 0.85),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                  ),
              ],
            ),
          ),
          // Circular mic button — the clone's control, mirroring the master's
          // CALL/CUT button. Green = live mic, red = muted.
          _micButton(denied: denied, connecting: connecting),
          const SizedBox(width: 12),
          // Hang up the call from the clone side.
          _roundBtn(
              color: _cutRed,
              icon: Symbols.call_end,
              label: 'END',
              onTap: _link.hangUp),
        ],
      ),
    );
  }

  // Master is ringing this clone — Receive to answer, Decline to reject.
  Widget _incomingBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
      decoration: BoxDecoration(
        color: _cardLive,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Symbols.ring_volume, color: _cardText, size: 30),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('INCOMING CALL',
                    style: TextStyle(
                        color: _cardText,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1)),
                SizedBox(height: 2),
                Text('Master',
                    style: TextStyle(
                        color: _cardText,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          _roundBtn(
              color: _cutRed,
              icon: Symbols.call_end,
              label: 'DECLINE',
              onTap: _link.declineIncoming),
          const SizedBox(width: 12),
          _roundBtn(
              color: _callGreen,
              icon: Symbols.call,
              label: 'RECEIVE',
              onTap: _link.acceptIncoming),
        ],
      ),
    );
  }

  // We're ringing the master — waiting for an answer; Cancel to abort.
  Widget _outgoingBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
      decoration: BoxDecoration(
        color: _cardLive,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Symbols.call_made, color: _cardText, size: 28),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CALLING…',
                    style: TextStyle(
                        color: _cardText,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1)),
                SizedBox(height: 2),
                Text('Master',
                    style: TextStyle(
                        color: _cardText,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          _roundBtn(
              color: _cutRed,
              icon: Symbols.call_end,
              label: 'CANCEL',
              onTap: _link.hangUp),
        ],
      ),
    );
  }

  // Small round action button shared by the call banners.
  Widget _roundBtn({
    required Color color,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      elevation: 3,
      shadowColor: color.withValues(alpha: 0.5),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 60,
          height: 60,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(height: 2),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _micButton({required bool denied, required bool connecting}) {
    final live = !_micMuted && !denied && !connecting;
    final color = _micMuted || denied ? _cutRed : _callGreen;
    return Material(
      color: color,
      shape: const CircleBorder(),
      elevation: 3,
      shadowColor: color.withValues(alpha: 0.5),
      child: InkWell(
        onTap: denied ? null : _toggleMute,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 60,
          height: 60,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(live ? Symbols.mic : Symbols.mic_off,
                  color: Colors.white, size: 22),
              const SizedBox(height: 2),
              Text(
                _micMuted ? 'UNMUTE' : 'MUTE',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(String feature) {
    return Material(
      color: _card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openFeature(feature),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_featureIcons[feature] ?? Symbols.help,
                color: _orange, size: 40),
            const SizedBox(height: 12),
            Text(
              feature,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Open a granted feature full-screen. The heavy views are reused from the
  // master (Carts/Inventory/Sales Kit); features without a dedicated view yet
  // land on a placeholder rather than a dead tap.
  void _openFeature(String feature) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            _SatelliteFeatureScreen(feature: feature, products: _catalog),
      ),
    );
  }
}

/// A granted feature opened full-screen on the satellite. Reuses the master's
/// feature views where they exist; otherwise shows a placeholder so a granted
/// tile always leads somewhere.
class _SatelliteFeatureScreen extends StatelessWidget {
  final String feature;
  // The master's synced catalog (null → Inventory falls back to seed data).
  final List<Product>? products;
  const _SatelliteFeatureScreen({required this.feature, this.products});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            Icon(_featureIcons[feature] ?? Symbols.help,
                color: _orange, size: 22),
            const SizedBox(width: 10),
            Text(
              feature,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    switch (feature) {
      case 'Carts':
        return const Padding(
          padding: EdgeInsets.all(16),
          child: ActiveCartsGrid(),
        );
      case 'Inventory':
        return Padding(
          padding: const EdgeInsets.all(16),
          child: InventoryBrowser(products: products),
        );
      case 'Sales Kit':
        // SalesKitOpenedView reads AppTheme.of(context); provide a dark one.
        return AppTheme(
          dark: true,
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: SalesKitOpenedView(),
          ),
        );
      default:
        return _placeholder();
    }
  }

  Widget _placeholder() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_featureIcons[feature] ?? Symbols.help,
                color: _orange, size: 56),
            const SizedBox(height: 18),
            Text(
              feature,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Access granted. This feature isn’t available on satellite '
              'devices yet — it’s coming soon.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
