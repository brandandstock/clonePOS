import 'package:flutter/material.dart';

import '../data/plan_store.dart';
import 'master_dashboard_screen.dart' show AppTheme;

const Color _orange = Color(0xFFE87722);

/// The panel that opens when the master taps Settings → Clone Access. It's the
/// fleet-management hub: shows the current subscription plan and clone usage,
/// lets the master CREATE a new clone (Satellite) up to the plan's capacity
/// (locked with an upgrade prompt when full), switch plans (demo — billing
/// drives this in production), and jump into per-clone feature access.
class CloneHubDialog extends StatefulWidget {
  final AppTheme theme;
  final SubscriptionPlan plan;
  final int usedCount;
  final String businessId;
  final VoidCallback onCreate;
  final VoidCallback onManageAccess;
  final VoidCallback onCredentials;
  final ValueChanged<SubscriptionPlan> onPlanChange;
  const CloneHubDialog({
    super.key,
    required this.theme,
    required this.plan,
    required this.usedCount,
    required this.businessId,
    required this.onCreate,
    required this.onManageAccess,
    required this.onCredentials,
    required this.onPlanChange,
  });

  @override
  State<CloneHubDialog> createState() => _CloneHubDialogState();
}

class _CloneHubDialogState extends State<CloneHubDialog> {
  bool _showPlans = false;
  // Tracked locally so the card/usage/lock update immediately on a plan
  // switch (showDialog won't rebuild this route on the parent's setState).
  late SubscriptionPlan _plan = widget.plan;

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final plan = _plan;
    final capacity = plan.capacity;
    final used = widget.usedCount;
    final atCapacity = used >= capacity;

    return Dialog(
      backgroundColor: t.panelBg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 440,
          maxHeight: MediaQuery.of(context).size.height - 32,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              const SizedBox(height: 14),
              _planCard(t, _plan, used, capacity),
              if (_showPlans) ...[
                const SizedBox(height: 10),
                _planSwitcher(t, _plan),
              ],
              const SizedBox(height: 10),
              _businessRow(t),
              const SizedBox(height: 16),
              _createRow(t, atCapacity),
              const SizedBox(height: 10),
              _actionButton(
                t,
                icon: Icons.key_outlined,
                label: 'Device sign-in IDs',
                sub: 'Business + Clone IDs to pair each satellite',
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onCredentials();
                },
              ),
              const SizedBox(height: 10),
              _actionButton(
                t,
                icon: Icons.tune,
                label: 'Manage feature access',
                sub: 'Grant each clone what it can open',
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onManageAccess();
                },
              ),
              const SizedBox(height: 14),
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

  Widget _planCard(AppTheme t, SubscriptionPlan plan, int used, int capacity) {
    final frac = capacity == 0 ? 0.0 : (used / capacity).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: t.panelText.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.panelText.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'PLAN',
                style: TextStyle(
                  color: t.panelText.withValues(alpha: 0.55),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: _orange,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  plan.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _showPlans = !_showPlans),
                style: TextButton.styleFrom(
                  foregroundColor: _orange,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  _showPlans ? 'Close' : 'Change plan',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '$used of $capacity clones used',
            style: TextStyle(
              color: t.panelText,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 7,
              backgroundColor: t.panelText.withValues(alpha: 0.12),
              valueColor: const AlwaysStoppedAnimation(_orange),
            ),
          ),
        ],
      ),
    );
  }

  Widget _businessRow(AppTheme t) {
    return Row(
      children: [
        Icon(Icons.business_outlined,
            size: 18, color: t.panelText.withValues(alpha: 0.6)),
        const SizedBox(width: 10),
        Text(
          'BUSINESS ID',
          style: TextStyle(
            color: t.panelText.withValues(alpha: 0.55),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const Spacer(),
        Text(
          widget.businessId,
          style: const TextStyle(
            color: _orange,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _planSwitcher(AppTheme t, SubscriptionPlan current) {
    return Row(
      children: [
        for (final p in SubscriptionPlan.values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () {
                  widget.onPlanChange(p);
                  setState(() {
                    _plan = p;
                    _showPlans = false;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: p == current
                        ? _orange
                        : t.panelText.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: p == current
                          ? _orange
                          : t.panelText.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        p.label,
                        style: TextStyle(
                          color: p == current ? Colors.white : t.panelText,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${p.capacity}',
                        style: TextStyle(
                          color: (p == current ? Colors.white : t.panelText)
                              .withValues(alpha: 0.7),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _createRow(AppTheme t, bool atCapacity) {
    if (atCapacity) {
      final next = _plan.next;
      return _actionButton(
        t,
        icon: Icons.lock_outline,
        label: 'Create clone — locked',
        sub: next == null
            ? 'You are at the maximum fleet size'
            : 'Upgrade to ${next.label} for ${next.capacity} clones',
        locked: true,
        onTap: () => setState(() => _showPlans = true),
      );
    }
    return _actionButton(
      t,
      icon: Icons.add_circle_outline,
      label: 'Create clone',
      sub: 'Register a new satellite device',
      accent: true,
      onTap: () {
        Navigator.of(context).pop();
        widget.onCreate();
      },
    );
  }

  Widget _actionButton(
    AppTheme t, {
    required IconData icon,
    required String label,
    required String sub,
    required VoidCallback onTap,
    bool accent = false,
    bool locked = false,
  }) {
    final fg = locked ? t.panelText.withValues(alpha: 0.55) : t.panelText;
    return Material(
      color: accent
          ? _orange.withValues(alpha: 0.14)
          : t.panelText.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: accent
                  ? _orange.withValues(alpha: 0.5)
                  : t.panelText.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: accent ? _orange : fg, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: accent ? _orange : fg,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: TextStyle(
                        color: fg.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: fg.withValues(alpha: 0.5), size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
