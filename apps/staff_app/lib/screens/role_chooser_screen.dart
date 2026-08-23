import 'package:flutter/material.dart';

const Color _orange = Color(0xFFE87722);
const Color _bg = Color(0xFF1A1A1A);
const Color _card = Color(0xFF262626);
const Color _field = Color(0xFF333333);

/// First-launch role selection: set this device up as the Master POS, or sign
/// in as a Clone (Satellite) with the Business ID + Clone ID the master issued.
/// The choice is persisted by the caller so it isn't asked again until sign-out.
class RoleChooserScreen extends StatefulWidget {
  final VoidCallback onMaster;
  final void Function(String businessId, String cloneId) onClone;
  const RoleChooserScreen({
    super.key,
    required this.onMaster,
    required this.onClone,
  });

  @override
  State<RoleChooserScreen> createState() => _RoleChooserScreenState();
}

class _RoleChooserScreenState extends State<RoleChooserScreen> {
  bool _cloneForm = false;
  final _biz = TextEditingController();
  final _clone = TextEditingController();
  bool _error = false;

  @override
  void dispose() {
    _biz.dispose();
    _clone.dispose();
    super.dispose();
  }

  void _connect() {
    final biz = _biz.text.trim().toUpperCase();
    final clone = _clone.text.trim().toUpperCase();
    if (biz.isEmpty || clone.isEmpty) {
      setState(() => _error = true);
      return;
    }
    widget.onClone(biz, clone);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(18),
              ),
              child: _cloneForm ? _clonePane() : _choicePane(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _choicePane() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.hub_outlined, color: _orange, size: 40),
        const SizedBox(height: 14),
        const Text(
          'Clone-POS',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Set up this device',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 24),
        _bigButton(
          icon: Icons.point_of_sale,
          title: 'Set up as Master',
          sub: 'This device runs the POS and manages the fleet',
          filled: true,
          onTap: widget.onMaster,
        ),
        const SizedBox(height: 12),
        _bigButton(
          icon: Icons.devices_other,
          title: 'Sign in as Clone',
          sub: 'Pair this device to a master with its Clone ID',
          filled: false,
          onTap: () => setState(() => _cloneForm = true),
        ),
      ],
    );
  }

  Widget _clonePane() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => setState(() => _cloneForm = false),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 10),
            const Text(
              'Sign in as Clone',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Enter the Business ID and Clone ID from your master device '
          '(Settings → Clone Access → Device sign-in IDs).',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 13,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 20),
        _input('BUSINESS ID', _biz, 'BIZ-XXXXXX', autofocus: true),
        const SizedBox(height: 16),
        _input('CLONE ID', _clone, 'CLN-XXXX'),
        if (_error)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Enter both IDs to connect.',
              style: const TextStyle(
                color: _orange,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        const SizedBox(height: 22),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _connect,
            style: FilledButton.styleFrom(
              backgroundColor: _orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.login),
            label: const Text(
              'Connect',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }

  Widget _bigButton({
    required IconData icon,
    required String title,
    required String sub,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: filled ? _orange : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: filled
                ? null
                : Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(icon, color: filled ? Colors.white : _orange, size: 26),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: filled ? Colors.white : Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      sub,
                      style: TextStyle(
                        color: (filled ? Colors.white : Colors.white)
                            .withValues(alpha: 0.7),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _input(String label, TextEditingController ctrl, String hint,
      {bool autofocus = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          autofocus: autofocus,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
          cursorColor: _orange,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
            filled: true,
            fillColor: _field,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _orange, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}
