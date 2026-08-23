import 'package:flutter/material.dart';

import '../comm/walkie_service.dart';
import 'master_dashboard_screen.dart' show AppTheme;

/// Control surface for the LAN walkie-talkie. Started from the SESSIONS
/// console on the Clones tab. Holding PUSH-TO-TALK broadcasts your mic to
/// every clone on the same WiFi; the self-test loops your own mic back so the
/// audio pipeline can be verified on a single device.
class WalkieDialog extends StatefulWidget {
  final WalkieService walkie;
  final AppTheme theme;
  const WalkieDialog({super.key, required this.walkie, required this.theme});

  @override
  State<WalkieDialog> createState() => _WalkieDialogState();
}

class _WalkieDialogState extends State<WalkieDialog> {
  WalkieService get _w => widget.walkie;

  @override
  void initState() {
    super.initState();
    _w.start(); // idempotent — requests mic + starts discovery
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    return AlertDialog(
      backgroundColor: t.panelBg,
      title: Row(
        children: [
          const Icon(Icons.settings_input_antenna, color: Color(0xFFE87722)),
          const SizedBox(width: 10),
          Text(
            'LAN Walkie-Talkie',
            style: TextStyle(
              color: t.panelText,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: ValueListenableBuilder<WalkieState>(
          valueListenable: _w.state,
          builder: (_, state, __) {
            if (state == WalkieState.denied) {
              return _message(
                t,
                Icons.mic_off,
                'Microphone permission is required for voice. Enable it in '
                'system settings, then reopen this panel.',
              );
            }
            if (state == WalkieState.error) {
              return _message(
                t,
                Icons.error_outline,
                'Could not start the walkie-talkie (audio or network error).',
              );
            }
            if (state != WalkieState.ready) {
              return _message(t, Icons.hourglass_top, 'Starting…');
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _peerList(t),
                const SizedBox(height: 14),
                _selfTestRow(t),
                const SizedBox(height: 16),
                _pttButton(t),
                const SizedBox(height: 10),
                Text(
                  'Hold to talk — your voice goes to every clone on this WiFi. '
                  'For the self-test, use headphones to avoid feedback.',
                  style: TextStyle(
                    color: t.panelText.withValues(alpha: 0.7),
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            _w.setTalking(false);
            Navigator.of(context).pop();
          },
          style: TextButton.styleFrom(foregroundColor: t.panelText),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _message(AppTheme t, IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: t.panelText.withValues(alpha: 0.7), size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: t.panelText, fontSize: 13.5, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _peerList(AppTheme t) {
    return ValueListenableBuilder<List<WalkiePeer>>(
      valueListenable: _w.peers,
      builder: (_, peers, __) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              peers.isEmpty
                  ? 'No clones found yet on this WiFi'
                  : '${peers.length} clone(s) on this WiFi',
              style: TextStyle(
                color: t.panelText,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            if (peers.isEmpty)
              Text(
                'Open the app on another device on the same network to see it '
                'here.',
                style: TextStyle(
                  color: t.panelText.withValues(alpha: 0.6),
                  fontSize: 11.5,
                ),
              ),
            for (final p in peers)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: p.connected
                            ? const Color(0xFF1E7A3B)
                            : const Color(0xFFB26B00),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      p.name,
                      style: TextStyle(color: t.panelText, fontSize: 13),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      p.connected ? 'connected' : 'connecting…',
                      style: TextStyle(
                        color: t.panelText.withValues(alpha: 0.6),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _selfTestRow(AppTheme t) {
    return ValueListenableBuilder<bool>(
      valueListenable: _w.loopback,
      builder: (_, on, __) {
        return Row(
          children: [
            Switch(
              value: on,
              activeThumbColor: const Color(0xFFE87722),
              onChanged: (v) => v ? _w.startLoopback() : _w.stopLoopback(),
            ),
            Expanded(
              child: Text(
                'Self-test (hear yourself) — verify audio on this device',
                style: TextStyle(color: t.panelText, fontSize: 12.5),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _pttButton(AppTheme t) {
    return ValueListenableBuilder<bool>(
      valueListenable: _w.talking,
      builder: (_, talking, __) {
        return GestureDetector(
          onTapDown: (_) => _w.setTalking(true),
          onTapUp: (_) => _w.setTalking(false),
          onTapCancel: () => _w.setTalking(false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 84,
            width: double.infinity,
            decoration: BoxDecoration(
              color: talking ? const Color(0xFF1E7A3B) : const Color(0xFFE87722),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: (talking
                          ? const Color(0xFF1E7A3B)
                          : const Color(0xFFE87722))
                      .withValues(alpha: 0.4),
                  blurRadius: talking ? 22 : 8,
                  spreadRadius: talking ? 2 : 0,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(talking ? Icons.mic : Icons.mic_none,
                    color: Colors.white, size: 30),
                const SizedBox(height: 4),
                Text(
                  talking ? 'TALKING…' : 'PUSH TO TALK',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
