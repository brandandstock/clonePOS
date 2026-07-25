import '../sync/hlc.dart';

/// The type of event a device logs against a Unit. Note there is
/// deliberately no "stock update" type — Clone-POS never lets a device
/// write a stock number directly. Master derives real state by replaying
/// these events in HLC order.
enum TransactionType { reservation, sale, returnToStock }

/// A single, immutable ledger entry. Every Master, Satellite, and
/// Clone-POS client device produces these — locally first, synced to
/// Master when connectivity allows (see reservation_engine.dart).
///
/// The timestamp is an [HlcTimestamp], not a wall-clock [DateTime]. See
/// hlc.dart for the reason: raw wall clocks let a slow-clocked device
/// silently win every reservation race.
class Transaction {
  final String id;
  final String unitId;
  final TransactionType type;
  final HlcTimestamp hlc;
  final String originatingDeviceId;

  const Transaction({
    required this.id,
    required this.unitId,
    required this.type,
    required this.hlc,
    required this.originatingDeviceId,
  });

  @override
  String toString() =>
      'Transaction($type, unit=$unitId, at=$hlc, from=$originatingDeviceId)';
}
