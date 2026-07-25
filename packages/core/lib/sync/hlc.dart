/// Hybrid Logical Clock — the timestamp Clone-POS uses on every ledger
/// event instead of a raw wall clock. It is the fix for the clock-skew
/// vulnerability that Session 3 flagged as the top-priority open bug.
///
/// **Why not just [DateTime.now()]?**
/// The previous implementation sorted reservations by `DateTime.now().toUtc()`.
/// A device with a slow or misconfigured clock would silently and
/// *permanently* win every reservation race against devices with correct
/// clocks — because in the reconciler, "earliest wall-clock time" wins.
/// This is not a theoretical concern in a store where a Master may go
/// offline for hours and a Satellite tablet has been unplugged over a
/// weekend: clock drift accumulates and cannot be observed until sync.
///
/// **How HLC fixes it.**
/// Each device maintains an [HybridLogicalClock]. It combines
/// - a *physical* component (ms since epoch), and
/// - a *logical* counter that increments to preserve causality when
///   physical time doesn't advance or when a merged remote timestamp is
///   ahead of local physical time.
///
/// The critical property is [receive]: whenever a device observes a
/// remote HLC on a message it did not originate, it merges the remote
/// timestamp into its own clock. From that point on, this device's next
/// [now] is guaranteed to be *later* than the remote timestamp it saw —
/// so a slow-clocked device can never generate a timestamp that beats
/// something it has already seen. This is what makes the reservation
/// race fair regardless of wall-clock skew.
///
/// **Ties.**
/// [compareTo] orders by physical, then logical, then [nodeId]. The
/// [nodeId] tiebreaker only matters in the theoretical case where two
/// devices independently produce the *exact same* physical+logical pair
/// — extremely rare, but this makes the ordering total and deterministic
/// across all devices, which is what the reconciler needs.
class HybridLogicalClock {
  int _physical;
  int _logical;
  final String nodeId;

  HybridLogicalClock({required this.nodeId, int? physical, int logical = 0})
      : _physical = physical ?? DateTime.now().toUtc().millisecondsSinceEpoch,
        _logical = logical;

  int get physical => _physical;
  int get logical => _logical;

  /// Produce a fresh timestamp for a locally-originated event. If the
  /// wall clock advanced since we last spoke, we adopt it and reset the
  /// counter; if it didn't (or went backwards, which is what a bad clock
  /// looks like), we bump the counter to keep timestamps strictly
  /// monotonic.
  HlcTimestamp now() {
    final wall = DateTime.now().toUtc().millisecondsSinceEpoch;
    if (wall > _physical) {
      _physical = wall;
      _logical = 0;
    } else {
      _logical += 1;
    }
    return HlcTimestamp(physical: _physical, logical: _logical, nodeId: nodeId);
  }

  /// Merge a remote timestamp into this clock. Called whenever a device
  /// observes a transaction it did not originate — during Satellite→
  /// Master sync, Master→Clone-POS-client push, ledger replay, etc.
  ///
  /// After this returns, any subsequent [now] on this device is
  /// guaranteed to sort *after* [remote]. That is the whole point.
  void receive(HlcTimestamp remote) {
    final wall = DateTime.now().toUtc().millisecondsSinceEpoch;
    final maxPhysical = [wall, _physical, remote.physical]
        .reduce((a, b) => a > b ? a : b);

    if (maxPhysical == _physical && maxPhysical == remote.physical) {
      _logical = (_logical > remote.logical ? _logical : remote.logical) + 1;
    } else if (maxPhysical == _physical) {
      _logical = _logical + 1;
    } else if (maxPhysical == remote.physical) {
      _logical = remote.logical + 1;
    } else {
      _logical = 0;
    }
    _physical = maxPhysical;
  }
}

/// An immutable HLC reading attached to a single event. Transactions
/// carry one of these instead of a [DateTime] so reconciliation is safe
/// under clock skew.
class HlcTimestamp implements Comparable<HlcTimestamp> {
  final int physical;
  final int logical;
  final String nodeId;

  const HlcTimestamp({
    required this.physical,
    required this.logical,
    required this.nodeId,
  });

  /// The wall-clock instant embedded in this HLC. Useful for display —
  /// never for ordering; use [compareTo] for that.
  DateTime get wallTime =>
      DateTime.fromMillisecondsSinceEpoch(physical, isUtc: true);

  @override
  int compareTo(HlcTimestamp other) {
    final byPhysical = physical.compareTo(other.physical);
    if (byPhysical != 0) return byPhysical;
    final byLogical = logical.compareTo(other.logical);
    if (byLogical != 0) return byLogical;
    return nodeId.compareTo(other.nodeId);
  }

  bool operator <(HlcTimestamp other) => compareTo(other) < 0;
  bool operator >(HlcTimestamp other) => compareTo(other) > 0;
  bool operator <=(HlcTimestamp other) => compareTo(other) <= 0;
  bool operator >=(HlcTimestamp other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is HlcTimestamp &&
      other.physical == physical &&
      other.logical == logical &&
      other.nodeId == nodeId;

  @override
  int get hashCode => Object.hash(physical, logical, nodeId);

  Map<String, dynamic> toJson() => {
        'p': physical,
        'l': logical,
        'n': nodeId,
      };

  factory HlcTimestamp.fromJson(Map<String, dynamic> json) => HlcTimestamp(
        physical: json['p'] as int,
        logical: json['l'] as int,
        nodeId: json['n'] as String,
      );

  @override
  String toString() =>
      'HLC(${wallTime.toIso8601String()}+$logical@$nodeId)';
}
