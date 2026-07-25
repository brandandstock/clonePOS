import 'package:test/test.dart';
import 'package:clone_pos_core/models/unit.dart';
import 'package:clone_pos_core/models/transaction.dart';
import 'package:clone_pos_core/sync/hlc.dart';
import 'package:clone_pos_core/sync/reservation_engine.dart';

// A physical-time base to keep the test HLCs readable.
final int _base = DateTime.utc(2026, 1, 1, 10, 0, 0).millisecondsSinceEpoch;

HlcTimestamp _hlc(String node, {int physicalOffsetMs = 0, int logical = 0}) =>
    HlcTimestamp(
      physical: _base + physicalOffsetMs,
      logical: logical,
      nodeId: node,
    );

void main() {
  group('LedgerReconciler', () {
    test('earliest reservation wins when two devices race for the same unit', () {
      final unit = const Unit(id: 'unit-1', productId: 'prod-1', storeId: 'store-1');

      final earlier = Transaction(
        id: 'tx-a',
        unitId: 'unit-1',
        type: TransactionType.reservation,
        hlc: _hlc('device-A'),
        originatingDeviceId: 'device-A',
      );
      final later = Transaction(
        id: 'tx-b',
        unitId: 'unit-1',
        type: TransactionType.reservation,
        hlc: _hlc('device-B', physicalOffsetMs: 1000),
        originatingDeviceId: 'device-B',
      );

      // Deliberately reconcile with the later one appearing first in the
      // input list, to prove the reconciler sorts by HLC itself rather
      // than trusting arrival order.
      final result = LedgerReconciler.reconcile(
        units: [unit],
        transactions: [later, earlier],
      );

      expect(result.resolvedUnits.single.status, UnitStatus.reserved);
      expect(result.oversellConflicts, hasLength(1));
      expect(result.oversellConflicts.single.originatingDeviceId, 'device-B');
    });

    test('a sale after a reservation marks the unit sold', () {
      final unit = const Unit(id: 'unit-2', productId: 'prod-1', storeId: 'store-1');
      final reservation = Transaction(
        id: 'tx-1',
        unitId: 'unit-2',
        type: TransactionType.reservation,
        hlc: _hlc('device-A'),
        originatingDeviceId: 'device-A',
      );
      final sale = Transaction(
        id: 'tx-2',
        unitId: 'unit-2',
        type: TransactionType.sale,
        hlc: _hlc('device-A', physicalOffsetMs: 5 * 60 * 1000),
        originatingDeviceId: 'device-A',
      );

      final result = LedgerReconciler.reconcile(
        units: [unit],
        transactions: [reservation, sale],
      );

      expect(result.resolvedUnits.single.status, UnitStatus.sold);
      expect(result.oversellConflicts, isEmpty);
    });

    test('a return puts the unit back in stock and clears the claim', () {
      final unit = const Unit(id: 'unit-3', productId: 'prod-1', storeId: 'store-1', status: UnitStatus.sold);
      final ret = Transaction(
        id: 'tx-3',
        unitId: 'unit-3',
        type: TransactionType.returnToStock,
        hlc: _hlc('staff-terminal-1', physicalOffsetMs: 2 * 60 * 60 * 1000),
        originatingDeviceId: 'staff-terminal-1',
      );

      final result = LedgerReconciler.reconcile(
        units: [unit],
        transactions: [ret],
      );

      expect(result.resolvedUnits.single.status, UnitStatus.inStock);
    });

    test('originatingDeviceId is the final deterministic tiebreaker on identical HLCs', () {
      // The HLC's own compareTo already tiebreaks on nodeId, so a real
      // exact-HLC collision across two devices is nearly impossible. But
      // the reconciler adds originatingDeviceId as a belt-and-braces
      // final tiebreaker so that even if callers construct pathological
      // HLCs with matching nodeIds (e.g. in tests, or a misconfigured
      // device that reused a nodeId), the result is still deterministic
      // across every Master that runs it.
      final unit = const Unit(id: 'unit-4', productId: 'prod-1', storeId: 'store-1');
      final identical = _hlc('shared-node');
      final txZ = Transaction(
        id: 'tx-z',
        unitId: 'unit-4',
        type: TransactionType.reservation,
        hlc: identical,
        originatingDeviceId: 'device-Z',
      );
      final txA = Transaction(
        id: 'tx-a',
        unitId: 'unit-4',
        type: TransactionType.reservation,
        hlc: identical,
        originatingDeviceId: 'device-A',
      );

      final result = LedgerReconciler.reconcile(
        units: [unit],
        transactions: [txZ, txA],
      );

      expect(result.oversellConflicts, hasLength(1));
      expect(
        result.oversellConflicts.single.originatingDeviceId,
        'device-Z',
        reason: 'device-A sorts before device-Z, so Z should lose the race',
      );
    });
  });

  group('HybridLogicalClock — clock-skew defense', () {
    test('a slow-clocked device cannot silently win against a device it has heard from', () {
      // This is the scenario the previous wall-clock reservation engine
      // got wrong. Device B's clock is two hours behind reality. Without
      // HLC merging, whatever B stamps arrives with a "10:00" timestamp
      // that beats device A's real 12:00 reservation, and B silently
      // wins forever.
      //
      // With HLC: A reserves at real time 12:00. B receives A's
      // transaction (during sync) and merges A's HLC. B then attempts
      // its own reservation at wall-clock 10:00. B's HLC now must be
      // *after* what A produced, because receive() bumped B's clock.
      // A wins the race — the correct outcome.
      final clockA = HybridLogicalClock(
        nodeId: 'device-A',
        physical: DateTime.utc(2026, 1, 1, 12, 0, 0).millisecondsSinceEpoch,
      );
      final clockB = HybridLogicalClock(
        nodeId: 'device-B',
        physical: DateTime.utc(2026, 1, 1, 10, 0, 0).millisecondsSinceEpoch,
      );

      final hlcA = clockA.now();
      // Simulate B receiving A's transaction over the sync channel.
      clockB.receive(hlcA);
      final hlcB = clockB.now();

      expect(
        hlcB > hlcA,
        isTrue,
        reason: "B's next HLC must sort strictly after A's, even though "
            "B's wall clock is two hours behind — this is the whole "
            "point of the HLC merge",
      );

      // And now run it through the actual reconciler to confirm A wins.
      final unit = const Unit(id: 'unit-race', productId: 'prod-1', storeId: 'store-1');
      final txA = Transaction(
        id: 'tx-a',
        unitId: 'unit-race',
        type: TransactionType.reservation,
        hlc: hlcA,
        originatingDeviceId: 'device-A',
      );
      final txB = Transaction(
        id: 'tx-b',
        unitId: 'unit-race',
        type: TransactionType.reservation,
        hlc: hlcB,
        originatingDeviceId: 'device-B',
      );

      final result = LedgerReconciler.reconcile(
        units: [unit],
        transactions: [txB, txA], // arrival order shouldn't matter
      );

      expect(result.resolvedUnits.single.status, UnitStatus.reserved);
      expect(result.oversellConflicts, hasLength(1));
      expect(
        result.oversellConflicts.single.originatingDeviceId,
        'device-B',
        reason: 'the slow-clocked device must lose after the HLC merge',
      );
    });

    test('now() is strictly monotonic even when the wall clock stalls', () {
      // We can't force DateTime.now() to stall in a test, but repeated
      // now() calls in fast succession will almost certainly land in
      // the same physical millisecond. The logical counter must bump
      // to keep every timestamp strictly greater than the last.
      final clock = HybridLogicalClock(nodeId: 'device-solo');
      final stamps = List.generate(200, (_) => clock.now());
      for (var i = 1; i < stamps.length; i++) {
        expect(
          stamps[i] > stamps[i - 1],
          isTrue,
          reason: 'HLC $i (${stamps[i]}) must sort after '
              'HLC ${i - 1} (${stamps[i - 1]})',
        );
      }
    });

    test('receive() bumps logical counter when both clocks share a physical stamp', () {
      // Anchor the local clock far enough in the future that the current
      // wall time definitely can't overtake it inside this test — this
      // is what forces the tied-physical branch of receive() to fire.
      final farFuturePhysical =
          DateTime.now().toUtc().add(const Duration(days: 3650)).millisecondsSinceEpoch;
      final clock = HybridLogicalClock(
        nodeId: 'device-local',
        physical: farFuturePhysical,
        logical: 2,
      );
      final remote = HlcTimestamp(
        physical: farFuturePhysical,
        logical: 5,
        nodeId: 'device-remote',
      );
      clock.receive(remote);
      final produced = clock.now();

      expect(produced.physical, farFuturePhysical);
      expect(
        produced.logical,
        greaterThan(5),
        reason: 'local counter must jump past the remote logical value',
      );
      expect(produced > remote, isTrue);
    });
  });
}
