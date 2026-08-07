import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Physical upper bound on fleet slots — the Enterprise capacity. All the
/// per-clone lists are sized to this; the active [SubscriptionPlan] gates how
/// many of those slots are actually usable.
const int kMaxClones = 24;

/// SaaS subscription tier. Drives the clone (Satellite) capacity: Basic is the
/// standard 6, higher tiers unlock more. In production this is set by billing;
/// here it's a local, switchable setting so the locking can be demonstrated.
enum SubscriptionPlan { basic, standard, enterprise }

extension SubscriptionPlanX on SubscriptionPlan {
  /// Clones this plan unlocks.
  int get capacity => switch (this) {
        SubscriptionPlan.basic => 6,
        SubscriptionPlan.standard => 12,
        SubscriptionPlan.enterprise => 24,
      };

  String get label => switch (this) {
        SubscriptionPlan.basic => 'Basic',
        SubscriptionPlan.standard => 'Standard',
        SubscriptionPlan.enterprise => 'Enterprise',
      };

  /// The next tier up, or null at the top (Enterprise).
  SubscriptionPlan? get next => switch (this) {
        SubscriptionPlan.basic => SubscriptionPlan.standard,
        SubscriptionPlan.standard => SubscriptionPlan.enterprise,
        SubscriptionPlan.enterprise => null,
      };

  /// How many slots to SHOW on the fleet grid: this plan's usable slots plus a
  /// teaser of the next tier's locked slots (so the upsell is visible).
  int get displaySlots => (next?.capacity ?? capacity).clamp(0, kMaxClones);
}

/// Tiny JSON store for the active subscription plan. Best-effort like the
/// other clone stores: any failure degrades to "no saved state" (→ Basic).
class PlanStore {
  static const _fileName = 'clone_plan.json';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<SubscriptionPlan?> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final name = (await f.readAsString()).trim();
      for (final p in SubscriptionPlan.values) {
        if (p.name == name) return p;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(SubscriptionPlan plan) async {
    try {
      await (await _file()).writeAsString(plan.name);
    } catch (_) {
      // Best-effort.
    }
  }
}
