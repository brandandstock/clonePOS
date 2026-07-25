import 'dart:math';
import 'dart:ui' show Color;
import 'package:clone_pos_core/models/product.dart';
import 'seed_products_300.dart';

/// A live shopping cart currently in progress on the store floor.
/// Tied to exactly one satellite device (a paired handheld running the
/// clone-pos client). Times are elapsed-from-start; the UI computes
/// "12:34 ago" from [startedAt] against DateTime.now() so the display
/// keeps ticking without the model needing to store the current time.
///
/// [customerTotalSpend] is the customer's cumulative purchase total at
/// THIS store (all previous carts, not including the current one). It
/// derives the loyalty [tier] and drives the tier badge on the tile.
class ActiveCart {
  final String id;
  final String customerName;
  final int satelliteNumber; // 1, 2, 3 …
  final DateTime startedAt;
  final List<CartLine> lines;
  final double customerTotalSpend;

  const ActiveCart({
    required this.id,
    required this.customerName,
    required this.satelliteNumber,
    required this.startedAt,
    required this.lines,
    required this.customerTotalSpend,
  });

  double get total => lines.fold(0.0, (sum, l) => sum + l.subtotal);
  int get itemCount => lines.fold(0, (sum, l) => sum + l.quantity);

  LoyaltyTier get tier => LoyaltyTier.fromSpend(customerTotalSpend);
}

/// Loyalty ladder bucketed by lifetime spend at the store. Thresholds
/// are placeholders — swap for whatever the client eventually confirms.
enum LoyaltyTier {
  bronze,
  silver,
  gold,
  premium,
  elite;

  static LoyaltyTier fromSpend(double totalSpend) {
    if (totalSpend >= 1000000) return LoyaltyTier.elite;
    if (totalSpend >= 500000) return LoyaltyTier.premium;
    if (totalSpend >= 100000) return LoyaltyTier.gold;
    if (totalSpend >= 25000) return LoyaltyTier.silver;
    return LoyaltyTier.bronze;
  }

  String get label {
    switch (this) {
      case LoyaltyTier.bronze:  return 'Bronze';
      case LoyaltyTier.silver:  return 'Silver';
      case LoyaltyTier.gold:    return 'Gold';
      case LoyaltyTier.premium: return 'Premium';
      case LoyaltyTier.elite:   return 'Elite';
    }
  }

  /// Solid fill for the loyalty badge — deliberately different hues so
  /// staff can spot a tier at a glance across the wall of cart tiles.
  Color get color {
    switch (this) {
      case LoyaltyTier.bronze:  return const Color(0xB8975A2E); // copper
      case LoyaltyTier.silver:  return const Color(0xB8848B94); // steel
      case LoyaltyTier.gold:    return const Color(0xB8B8891E); // gold
      case LoyaltyTier.premium: return const Color(0xB8A78C07); // olive-gold (per Figma)
      case LoyaltyTier.elite:   return const Color(0xB84A2ECC); // regal purple
    }
  }
}

class CartLine {
  final Product product;
  final int quantity;
  const CartLine({required this.product, required this.quantity});

  double get subtotal => product.price * quantity;
}

/// Seed 26 fake active carts for the Master dashboard's Active Carts
/// tab. Deterministic — same output every run so the UI is stable in
/// screenshots and demos. Real carts flow through a repository later.
List<ActiveCart> seedActiveCarts() {
  final products = seedProducts300();
  final rng = Random(42);
  final now = DateTime.now();

  const names = [
    'Ramesh K.',   'Priya S.',    'Aarav Mehta',  'Divya Rao',
    'Rohan Nair',  'Sneha Iyer',  'Vikram Singh', 'Kavya Patel',
    'Arjun Verma', 'Meera Joshi', 'Yash Kapoor',  'Anaya Bose',
    'Ishaan Das',  'Tara Kulkarni','Neil Malhotra','Riya Ghosh',
    'Kabir Menon', 'Aditi Shah',  'Devansh Roy',  'Ananya Pai',
    'Nikhil Sen',  'Zara Khan',   'Aryan Reddy',  'Isha Bhatt',
    'Rahul Chopra','Pooja Deshmukh',
  ];

  // Hand-picked lifetime spend for the first 6 customers so the demo
  // shows one of each tier. The rest are seeded from the RNG.
  const knownSpend = <double>[
    635870, // Ramesh K.   → Premium
    32450,  // Priya S.    → Silver
    128900, // Aarav Mehta → Gold
    8500,   // Divya Rao   → Bronze
    78500,  // Rohan Nair  → Silver
    1250000,// Sneha Iyer  → Elite
  ];

  return List.generate(names.length, (i) {
    final lineCount = 2 + rng.nextInt(6); // 2..7 lines per cart
    final lines = List.generate(lineCount, (_) {
      final p = products[rng.nextInt(products.length)];
      return CartLine(product: p, quantity: 1 + rng.nextInt(3));
    });
    // Started somewhere between 30 seconds and 45 minutes ago.
    final ageSeconds = 30 + rng.nextInt(45 * 60);
    final totalSpend = i < knownSpend.length
        ? knownSpend[i]
        // Rest: bell-ish distribution from 2k-800k so we get tiers spread.
        : (2000 + rng.nextDouble() * rng.nextDouble() * 800000);
    return ActiveCart(
      id: 'CART-${(i + 1).toString().padLeft(3, '0')}',
      customerName: names[i],
      satelliteNumber: 1 + rng.nextInt(4), // Satellites 1-4
      startedAt: now.subtract(Duration(seconds: ageSeconds)),
      lines: lines,
      customerTotalSpend: totalSpend,
    );
  });
}

/// Format elapsed as "12:34" (mm:ss) or "1:02:34" once past an hour.
String formatElapsed(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  String two(int n) => n.toString().padLeft(2, '0');
  if (h > 0) return '$h:${two(m)}:${two(s)}';
  return '${two(m)}:${two(s)}';
}
