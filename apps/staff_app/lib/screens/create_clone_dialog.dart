import 'package:flutter/material.dart';

import '../data/clone_roster_store.dart';
import 'master_dashboard_screen.dart' show AppTheme;

const Color _orange = Color(0xFFE87722);

/// Master-side flow to create a clone (Satellite) into an empty fleet slot.
/// Captures a name + department (the card's title + subtitle). Returns the
/// new [CloneRecord] via [onCreate]; validation just requires a non-empty
/// name. Opened by tapping a "Create Clone" slot on the Clones tab.
class CreateCloneDialog extends StatefulWidget {
  final AppTheme theme;
  final int slotNumber; // 1-based slot the clone will occupy (badge numeral)
  final String businessId; // shown so the master can hand over the pair
  final String cloneId; // pre-assigned sign-in ID for this clone
  final ValueChanged<CloneRecord> onCreate;
  const CreateCloneDialog({
    super.key,
    required this.theme,
    required this.slotNumber,
    required this.businessId,
    required this.cloneId,
    required this.onCreate,
  });

  @override
  State<CreateCloneDialog> createState() => _CreateCloneDialogState();
}

class _CreateCloneDialogState extends State<CreateCloneDialog> {
  final _name = TextEditingController();
  final _dept = TextEditingController();
  bool _showError = false;

  @override
  void dispose() {
    _name.dispose();
    _dept.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _showError = true);
      return;
    }
    final dept = _dept.text.trim();
    widget.onCreate(CloneRecord(
      name,
      dept.isEmpty ? 'Satellite' : dept,
      cloneId: widget.cloneId,
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    return Dialog(
      backgroundColor: t.panelBg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.add_circle_outline, color: _orange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Create Clone',
                      style: TextStyle(
                        color: t.panelText,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    'Slot ${widget.slotNumber}',
                    style: TextStyle(
                      color: _orange,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _credentials(t),
              const SizedBox(height: 16),
              _field(t, 'NAME', _name, 'e.g. Mia', autofocus: true),
              if (_showError)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Enter a name for the clone.',
                    style: const TextStyle(
                      color: _orange,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              _field(t, 'DEPARTMENT', _dept, 'e.g. Cosmetics'),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(foregroundColor: t.panelText),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: _orange,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text(
                      'Create',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The sign-in credentials the master hands to the satellite operator:
  /// the shared Business ID + this clone's freshly-assigned Clone ID.
  Widget _credentials(AppTheme t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _orange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _orange.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Expanded(child: _idBlock(t, 'BUSINESS ID', widget.businessId)),
          Container(
            width: 1,
            height: 34,
            color: t.panelText.withValues(alpha: 0.15),
            margin: const EdgeInsets.symmetric(horizontal: 14),
          ),
          Expanded(child: _idBlock(t, 'CLONE ID', widget.cloneId)),
        ],
      ),
    );
  }

  Widget _idBlock(AppTheme t, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: t.panelText.withValues(alpha: 0.6),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            color: _orange,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _field(
    AppTheme t,
    String label,
    TextEditingController ctrl,
    String hint, {
    bool autofocus = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: t.panelText.withValues(alpha: 0.6),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          autofocus: autofocus,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _submit(),
          style: TextStyle(color: t.panelText, fontSize: 15),
          cursorColor: _orange,
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: TextStyle(color: t.panelText.withValues(alpha: 0.4)),
            filled: true,
            fillColor: t.fieldBg,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  BorderSide(color: t.panelText.withValues(alpha: 0.15)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _orange, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}
