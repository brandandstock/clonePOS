import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../data/clone_access_store.dart';
import 'master_dashboard_screen.dart' show AppTheme;

const Color _orange = Color(0xFFE87722);

/// Icon per feature — mirrors the landing-tile glyphs so the access editor
/// reads the same as the dashboard grid.
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

/// Master-side control: which app features each clone (Satellite) is allowed
/// to open. PER-CLONE — the master picks one of the created satellites from
/// the selector, then grants/revokes features for just that device. Opened
/// from the Settings panel's "Clone Access" row.
///
/// Toggling a row updates the selected clone's grant and calls [onChanged]
/// with the full per-clone list so the parent can persist it. None / All jump
/// the selected clone's whole set for quick resets.
class CloneAccessDialog extends StatefulWidget {
  final AppTheme theme;
  final List<Set<String>> granted; // one set per clone, index-aligned to fleet
  // Display names index-aligned to [granted]; a null entry is an empty slot
  // (not yet created) and is skipped in the selector.
  final List<String?> cloneNames;
  final ValueChanged<List<Set<String>>> onChanged;
  const CloneAccessDialog({
    super.key,
    required this.theme,
    required this.granted,
    required this.cloneNames,
    required this.onChanged,
  });

  @override
  State<CloneAccessDialog> createState() => _CloneAccessDialogState();
}

class _CloneAccessDialogState extends State<CloneAccessDialog> {
  // Deep working copy so edits stay local until pushed through onChanged.
  late final List<Set<String>> _grants = [
    for (final g in widget.granted) {...g},
  ];
  // Fleet indices that hold a created clone — the only grantable slots.
  late final List<int> _created = [
    for (var i = 0; i < widget.cloneNames.length; i++)
      if (widget.cloneNames[i] != null) i,
  ];
  late int _sel = _created.isNotEmpty ? _created.first : 0; // fleet index

  Set<String> get _current => _grants[_sel];

  void _pushChange() =>
      widget.onChanged([for (final g in _grants) {...g}]);

  void _apply(Set<String> next) {
    setState(() {
      _current
        ..clear()
        ..addAll(next);
    });
    _pushChange();
  }

  void _toggle(String feature, bool on) {
    final next = {..._current};
    on ? next.add(feature) : next.remove(feature);
    _apply(next);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    if (_created.isEmpty) return _emptyDialog(t);
    final name = widget.cloneNames[_sel] ?? 'Clone ${_sel + 1}';
    // Bound the dialog to the screen so it never runs past the bottom edge
    // (the tablet is only ~686 logical px tall). The header and footer are
    // pinned; only the feature list scrolls if it can't all fit.
    final maxH = MediaQuery.of(context).size.height - 28;
    return Dialog(
      backgroundColor: t.panelBg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 440, maxHeight: maxH),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Pinned header ──
              Row(
                children: [
                  const Icon(Icons.shield_outlined, color: _orange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Clone Access',
                      style: TextStyle(
                        color: t.panelText,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Select a satellite, then choose which features it may open. '
                'Each clone is granted independently.',
                style: TextStyle(
                  color: t.panelText.withValues(alpha: 0.7),
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              _cloneSelector(t),
              const SizedBox(height: 10),
              Text(
                'ACCESS FOR ${name.toUpperCase()}',
                style: TextStyle(
                  color: _orange,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              // ── Scrollable feature list (only this scrolls) ──
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final f in kCloneAccessFeatures) _featureRow(t, f),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Divider(color: t.divider, height: 1),
              const SizedBox(height: 6),
              // ── Pinned footer ──
              Row(
                children: [
                  Text(
                    '${_current.length}/${kCloneAccessFeatures.length} granted',
                    style: TextStyle(
                      color: t.panelText.withValues(alpha: 0.6),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  _quickButton(t, 'None', () => _apply(<String>{})),
                  _quickButton(
                    t,
                    'All',
                    () => _apply(kCloneAccessFeatures.toSet()),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: t.panelText,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
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

  /// Horizontal, scrollable row of selectable clone pills — one per created
  /// satellite. Each shows its number + name and its granted-feature count.
  Widget _cloneSelector(AppTheme t) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _created.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, listIdx) {
          final i = _created[listIdx]; // real fleet index
          final sel = i == _sel;
          final count = _grants[i].length;
          return GestureDetector(
            onTap: () => setState(() => _sel = i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: sel ? _orange : t.panelText.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(22),
                border: sel
                    ? null
                    : Border.all(color: t.panelText.withValues(alpha: 0.15)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${i + 1}',
                    style: TextStyle(
                      color: sel ? Colors.white : _orange,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.cloneNames[i] ?? 'Clone ${i + 1}',
                    style: TextStyle(
                      color: sel ? Colors.white : t.panelText,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$count/${kCloneAccessFeatures.length}',
                    style: TextStyle(
                      color: (sel ? Colors.white : t.panelText)
                          .withValues(alpha: 0.6),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Shown when no clones exist yet — nothing to grant. Points the master at
  /// the Clones tab to create one first.
  Widget _emptyDialog(AppTheme t) {
    return Dialog(
      backgroundColor: t.panelBg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.shield_outlined, color: _orange),
                  const SizedBox(width: 10),
                  Text(
                    'Clone Access',
                    style: TextStyle(
                      color: t.panelText,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'No clones yet. Create a satellite from the Clones tab, then '
                'come back here to choose what it can open.',
                style: TextStyle(
                  color: t.panelText.withValues(alpha: 0.75),
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(foregroundColor: t.panelText),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _featureRow(AppTheme t, String feature) {
    final on = _current.contains(feature);
    return InkWell(
      onTap: () => _toggle(feature, !on),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(
              _featureIcons[feature] ?? Symbols.help,
              size: 20,
              color: on ? _orange : t.panelText.withValues(alpha: 0.45),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                feature,
                style: TextStyle(
                  color: on
                      ? t.panelText
                      : t.panelText.withValues(alpha: 0.55),
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Switch(
              value: on,
              activeThumbColor: _orange,
              onChanged: (v) => _toggle(feature, v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickButton(AppTheme t, String label, VoidCallback onTap) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: _orange,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    );
  }
}
