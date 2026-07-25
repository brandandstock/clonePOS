import 'dart:async';
import '../models/transaction.dart';
import '../models/unit.dart';
import 'hlc.dart';

/// How long a soft reservation holds a unit before it releases back to
/// the available pool. Confirmed spec: 20 minutes, tracked locally on the
/// device that created the reservation — NOT by Master. This is
/// deliberate: Master may be offline for the entire window (the system is
/// explicitly designed to keep selling while Master is unreachable), so a
/// Master-side timer would never even start in that scenario.
const Duration reservationTimeout = Duration(minutes: 20);

/// Result of attempting to reserve a unit on a single device.
enum ReservationOutcome { reserved, alreadyReserved, alreadySold }

class ReservationResult {
  final ReservationOutcome outcome;
  final Transaction? transaction;
  const ReservationResult(this.outcome, this.transaction);
}

/// Runs on every device (Master, Satellite, Clone-POS client). Holds this
/// device's own pending reservations, their local expiry timers, and its
/// [HybridLogicalClock] — the HLC is stamped onto every transaction this
/// device originates, and updated via [observeRemote] whenever an event
/// from another device is seen. Transactions are appended to [pendingLog]
/// and handed off to Master's [LedgerReconciler] whenever connectivity
/// allows — the device does not need to be online for a reservation to
/// be created or to expire correctly.
class ReservationEngine {
  final String deviceId;
  final HybridLogicalClock clock;
  final Map<String, Timer> _expiryTimers = {};
  final List<Transaction> pendingLog = [];

  ReservationEngine({required this.deviceId, HybridLogicalClock? clock})
      : clock = clock ?? HybridLogicalClock(nodeId: deviceId);

  /// Called the instant a customer scans a unit's QR code. Does not touch
  /// the network — this must work fully offline.
  ReservationResult reserve(Unit unit, {required void Function(String unitId) onExpire}) {
    if (unit.status == UnitStatus.sold) {
      return const ReservationResult(ReservationOutcome.alreadySold, null);
    }
    if (unit.status == UnitStatus.reserved) {
      return const ReservationResult(ReservationOutcome.alreadyReserved, null);
    }

    final hlc = clock.now();
    final tx = Transaction(
      id: '${deviceId}_${hlc.physical}_${hlc.logical}',
      unitId: unit.id,
      type: TransactionType.reservation,
      hlc: hlc,
      originatingDeviceId: deviceId,
    );
    pendingLog.add(tx);

    // Local-only timer. Fires even if this device never talks to Master
    // again inside the window — matches the confirmed offline-first rule.
    _expiryTimers[unit.id] = Timer(reservationTimeout, () => onExpire(unit.id));

    return ReservationResult(ReservationOutcome.reserved, tx);
  }

  /// Feed a remotely-originated transaction (from Master, another
  /// Satellite, or a Clone-POS client) into this engine's clock so that
  /// any timestamp this device produces next is guaranteed to sort after
  /// what it has already observed. Must be called on every incoming
  /// transaction before the reconciler runs — otherwise the whole
  /// point of the HLC is lost.
  void observeRemote(Transaction tx) {
    clock.receive(tx.hlc);
  }

  /// Call when a sale completes before the timer fires.
  void cancelExpiry(String unitId) {
    _expiryTimers.remove(unitId)?.cancel();
  }
}

/// Runs on Master only. Applies every transaction it has received — from
/// its own Staff App UI, from Satellites, and from Clone-POS clients — in
/// strict HLC order, and derives the real status of every Unit. This is
/// the single source of truth calculation described in the spec: no
/// device ever writes a stock number directly, Master always derives it.
class LedgerReconciler {
  /// Replays [transactions] in HLC order against [units] and returns the
  /// resulting unit states plus any oversell conflicts detected (i.e.
  /// two reservations racing for the same unit — the earlier HLC wins).
  ///
  /// Ordering: physical → logical → nodeId (the HLC's own compareTo),
  /// with [Transaction.originatingDeviceId] as the final deterministic
  /// tiebreaker for the theoretical case where two devices produce
  /// exactly-identical HLCs. This makes the sort total and stable across
  /// every device that runs it — every Master reaches the same answer.
  static ReconciliationResult reconcile({
    required List<Unit> units,
    required List<Transaction> transactions,
  }) {
    final sorted = [...transactions]..sort((a, b) {
      final byHlc = a.hlc.compareTo(b.hlc);
      if (byHlc != 0) return byHlc;
      return a.originatingDeviceId.compareTo(b.originatingDeviceId);
    });
    final unitById = {for (final u in units) u.id: u};
    final oversellConflicts = <Transaction>[];
    final claimedBy = <String, Transaction>{}; // unitId -> winning reservation

    for (final tx in sorted) {
      final unit = unitById[tx.unitId];
      if (unit == null) continue;

      switch (tx.type) {
        case TransactionType.reservation:
          final existingClaim = claimedBy[tx.unitId];
          if (existingClaim == null) {
            claimedBy[tx.unitId] = tx;
            unitById[tx.unitId] = unit.copyWith(status: UnitStatus.reserved);
          } else {
            // Sort is total, so anything reaching here lost the race —
            // the existing claim's HLC precedes this one.
            oversellConflicts.add(tx);
          }
          break;

        case TransactionType.sale:
          unitById[tx.unitId] = unit.copyWith(status: UnitStatus.sold);
          break;

        case TransactionType.returnToStock:
          unitById[tx.unitId] = unit.copyWith(status: UnitStatus.inStock);
          claimedBy.remove(tx.unitId);
          break;
      }
    }

    return ReconciliationResult(
      resolvedUnits: unitById.values.toList(),
      oversellConflicts: oversellConflicts,
    );
  }
}

class ReconciliationResult {
  final List<Unit> resolvedUnits;
  final List<Transaction> oversellConflicts;
  const ReconciliationResult({
    required this.resolvedUnits,
    required this.oversellConflicts,
  });
}
