/// Status of a single physical Unit. This is the state Master calculates
/// from the Transaction log — no device ever writes this value directly.
enum UnitStatus { inStock, reserved, sold, missing }

/// A single physical, uniquely QR-coded item belonging to a [Product].
/// Unlike SKU-level barcoding, every unit Clone-POS sells has its own
/// identity — this is what makes the reservation/oversell-prevention
/// logic in reservation_engine.dart work cleanly: a reservation locks
/// one specific unit, never a shared count.
class Unit {
  final String id; // the literal QR code payload printed on the label
  final String productId;
  final String storeId;
  final UnitStatus status;

  const Unit({
    required this.id,
    required this.productId,
    required this.storeId,
    this.status = UnitStatus.inStock,
  });

  Unit copyWith({UnitStatus? status}) {
    return Unit(
      id: id,
      productId: productId,
      storeId: storeId,
      status: status ?? this.status,
    );
  }

  @override
  String toString() => 'Unit($id, product=$productId, status=$status)';
}
