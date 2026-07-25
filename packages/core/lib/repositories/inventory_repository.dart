import '../models/product.dart';
import '../models/unit.dart';
import '../models/transaction.dart';
import '../sync/reservation_engine.dart';

/// In-memory reference implementation for this prototype. A production
/// build swaps this for a real local database (drift/sqlite is the
/// recommended choice per the build roadmap) without changing anything
/// that calls into this repository — screens and the sync engine only
/// ever depend on this interface, never on storage details directly.
class InventoryRepository {
  final List<Product> _products = [];
  final List<Unit> _units = [];
  final List<Transaction> _transactions = [];

  List<Product> get products => List.unmodifiable(_products);
  List<Unit> get units => List.unmodifiable(_units);
  List<Transaction> get transactions => List.unmodifiable(_transactions);

  void seed({required List<Product> products, required List<Unit> units}) {
    _products
      ..clear()
      ..addAll(products);
    _units
      ..clear()
      ..addAll(units);
  }

  Unit? unitById(String id) {
    try {
      return _units.firstWhere((u) => u.id == id);
    } catch (_) {
      return null;
    }
  }

  void recordTransaction(Transaction tx) => _transactions.add(tx);

  /// Runs Master's reconciliation over everything logged so far and
  /// applies the resolved unit states back into this repository.
  ReconciliationResult reconcileNow() {
    final result = LedgerReconciler.reconcile(
      units: _units,
      transactions: _transactions,
    );
    _units
      ..clear()
      ..addAll(result.resolvedUnits);
    return result;
  }

  int get activeCartCount =>
      _units.where((u) => u.status == UnitStatus.reserved).length;

  int get unitsInStockCount =>
      _units.where((u) => u.status == UnitStatus.inStock).length;

  int get soldTodayCount =>
      _units.where((u) => u.status == UnitStatus.sold).length;
}
