import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../data/active_cart.dart';

// Reused colour tokens (kept local to avoid depending on the dashboard
// screen; if we ever centralise a design-tokens file, swap for that).
const Color _tileFill = Color(0xFFD9D9D9);
const Color _ink = Color(0xFF2E2E2E);
const Color _orange = Color(0xFFE87722);
const Color _green = Color(0xFF2ECC71);
const double _tileRadius = 10;

/// Right-pane content of the Active Carts opened state.
///
/// Layout:
///   * scrollable 3-column grid of [_CartTile]s, each surfacing a
///     live cart (customer, elapsed timer that reticks each second,
///     total, and its satellite badge).
///   * tapping a tile opens [_CartDetailPage] as a full-canvas
///     overlay via Navigator.push — that page lists items and hosts
///     the Pay button, which flips into the scanner view.
///
/// The tall left cell (title + big number) stays owned by the parent
/// dashboard; this widget only occupies the right side (cols 2-4).
class ActiveCartsGrid extends StatefulWidget {
  const ActiveCartsGrid({super.key});

  @override
  State<ActiveCartsGrid> createState() => _ActiveCartsGridState();
}

class _ActiveCartsGridState extends State<ActiveCartsGrid> {
  late final List<ActiveCart> _carts = seedActiveCarts();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Ticker forces the elapsed labels to update once per second. Cheap
    // — only the timer Text rebuilds because it's wrapped in a Builder
    // inside _CartTile that consumes DateTime.now() directly.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        childAspectRatio: 250 / 349,
      ),
      itemCount: _carts.length,
      itemBuilder: (ctx, i) {
        final cart = _carts[i];
        return _CartTile(
          cart: cart,
          onTap: () => _openDetail(cart),
        );
      },
    );
  }

  void _openDetail(ActiveCart cart) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.6),
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) => _CartDetailPage(cart: cart),
        transitionsBuilder: (_, anim, __, child) {
          final slide = Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(anim);
          return FadeTransition(
            opacity: anim,
            child: SlideTransition(position: slide, child: child),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cart tile — one entry in the 3-column grid.
// ---------------------------------------------------------------------------

class _CartTile extends StatelessWidget {
  final ActiveCart cart;
  final VoidCallback onTap;
  const _CartTile({required this.cart, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(cart.startedAt);
    return Material(
      color: _tileFill,
      borderRadius: BorderRadius.circular(_tileRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_tileRadius),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Big cart-id number + Sat pill — sized to match Ramesh's
              // reference tile in Figma exactly.
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    // Two-digit padding: #01, #02, … #26.
                    '#${cart.id.split('-').last.substring(1)}',
                    style: TextStyle(
                      color: _ink.withValues(alpha: 0.5),
                      fontSize: 60,
                      fontWeight: FontWeight.w500,
                      height: 1,
                    ),
                  ),
                  const Spacer(),
                  _SatellitePill(number: cart.satelliteNumber),
                ],
              ),
              const SizedBox(height: 2),
              // Customer name — 40 px, extra light per Figma.
              // FittedBox scales down for names that overflow (e.g.
              // "Aarav Mehta") so every tile stays consistent visually
              // without needing per-tile font tweaks.
              SizedBox(
                width: double.infinity,
                height: 42,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    cart.customerName,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 40,
                      fontWeight: FontWeight.w200,
                      height: 1.05,
                      letterSpacing: -1.2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              // Meta row: elapsed + item count.
              _MetaRow(
                icon: Symbols.schedule,
                text: formatElapsed(elapsed),
              ),
              const SizedBox(height: 1),
              _MetaRow(
                icon: Symbols.shopping_bag,
                text: '${cart.itemCount} '
                    '${cart.itemCount == 1 ? "item" : "items"}',
              ),
              const SizedBox(height: 6),
              // Loyalty tier badge.
              _LoyaltyBadge(
                tier: cart.tier,
                totalSpend: cart.customerTotalSpend,
              ),
              const Spacer(),
              // Current cart total — 40 px, regular weight, dark ink.
              Text(
                '₹ ${_formatMoney(cart.total)}',
                style: const TextStyle(
                  color: _ink,
                  fontSize: 40,
                  fontWeight: FontWeight.w400,
                  height: 1,
                  letterSpacing: -1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SatellitePill extends StatelessWidget {
  final int number;
  const _SatellitePill({required this.number});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 93,
      height: 53,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _green,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'Sat:$number',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 32,
          fontWeight: FontWeight.w200,
          height: 1,
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MetaRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon,
            size: 18, weight: 300, color: _ink.withValues(alpha: 0.75)),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: _ink.withValues(alpha: 0.75),
            fontSize: 16,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

/// Small square badge sitting inside a cart tile — shows loyalty tier
/// name, lifetime spend at this store, and an ↑ affordance hinting the
/// spend is trending up (placeholder — real telemetry can drive this).
class _LoyaltyBadge extends StatelessWidget {
  final LoyaltyTier tier;
  final double totalSpend;
  const _LoyaltyBadge({required this.tier, required this.totalSpend});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: tier.color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // ↑ arrow chip
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFFD4CD0E),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Symbols.arrow_upward,
                  size: 14,
                  color: Colors.white,
                  weight: 500,
                ),
              ),
              const Spacer(),
              const Text(
                'Loyalty\nTier',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: Color(0xD1FFFFFF),
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  height: 1.05,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            tier.label,
            style: const TextStyle(
              color: Color(0xE6161616),
              fontSize: 18,
              fontWeight: FontWeight.w600,
              height: 1.05,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '₹${_formatMoney(totalSpend)}',
            style: const TextStyle(
              color: Color(0xFF161616),
              fontSize: 15,
              fontWeight: FontWeight.w400,
              height: 1,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 1),
          const Text(
            'Total Spend',
            style: TextStyle(
              color: Color(0x80161616),
              fontSize: 8,
              fontWeight: FontWeight.w500,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Full-canvas cart detail — list of items + Pay CTA + scanner overlay.
// ---------------------------------------------------------------------------

class _CartDetailPage extends StatefulWidget {
  final ActiveCart cart;
  const _CartDetailPage({required this.cart});

  @override
  State<_CartDetailPage> createState() => _CartDetailPageState();
}

class _CartDetailPageState extends State<_CartDetailPage> {
  bool _paying = false;

  @override
  Widget build(BuildContext context) {
    // Centre a large card over the whole canvas — reads as an overlay
    // rather than a full route swap.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: _paying
                    ? _PaymentScannerPane(
                        cart: widget.cart,
                        onBack: () => setState(() => _paying = false),
                      )
                    : _CartDetailPane(
                        cart: widget.cart,
                        onClose: () => Navigator.of(context).pop(),
                        onPay: () => setState(() => _paying = true),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail pane — items list + total + Pay button.
// ---------------------------------------------------------------------------

class _CartDetailPane extends StatelessWidget {
  final ActiveCart cart;
  final VoidCallback onClose;
  final VoidCallback onPay;

  const _CartDetailPane({
    required this.cart,
    required this.onClose,
    required this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header row.
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
          color: const Color(0xFFF3F3F3),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cart.customerName,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${cart.id}  ·  Satellite ${cart.satelliteNumber}  ·  '
                    '${formatElapsed(DateTime.now().difference(cart.startedAt))} '
                    'active',
                    style: TextStyle(
                      color: _ink.withValues(alpha: 0.65),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Symbols.close),
                color: _ink,
              ),
            ],
          ),
        ),

        // Item list.
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            itemCount: cart.lines.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final line = cart.lines[i];
              return _LineRow(line: line);
            },
          ),
        ),

        // Payment CTA — the "down container" the client asked for.
        Material(
          color: _orange,
          child: InkWell(
            onTap: onPay,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
              child: Row(
                children: [
                  const Icon(Symbols.qr_code_2,
                      color: Colors.white, size: 26, weight: 400),
                  const SizedBox(width: 12),
                  const Text(
                    'PAY',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '₹${_formatMoney(cart.total)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Symbols.chevron_right, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  final CartLine line;
  const _LineRow({required this.line});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Thumbnail — from the product's image URL when available.
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: 52,
              height: 52,
              color: const Color(0xFFEDEDED),
              alignment: Alignment.center,
              child: (line.product.imageUrl ?? '').isNotEmpty
                  ? Image.network(
                      line.product.imageUrl!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Symbols.image_not_supported,
                        color: Color(0xFF888888),
                        size: 24,
                      ),
                    )
                  : const Icon(
                      Symbols.image_not_supported,
                      color: Color(0xFF888888),
                      size: 24,
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '₹${_formatMoney(line.product.price)} × ${line.quantity}',
                  style: TextStyle(
                    color: _ink.withValues(alpha: 0.65),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '₹${_formatMoney(line.subtotal)}',
            style: const TextStyle(
              color: _ink,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Payment scanner pane — displays a mock QR (customer scans with their
// bank/UPI app). Real UPI integration is out of scope for the prototype.
// ---------------------------------------------------------------------------

class _PaymentScannerPane extends StatelessWidget {
  final ActiveCart cart;
  final VoidCallback onBack;
  const _PaymentScannerPane({required this.cart, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
          color: const Color(0xFFF3F3F3),
          child: Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Symbols.arrow_back),
                color: _ink,
              ),
              const SizedBox(width: 4),
              const Text(
                'Scan to pay',
                style: TextStyle(
                  color: _ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFDDDDDD)),
                  ),
                  child: CustomPaint(
                    size: const Size(260, 260),
                    painter: _MockQrPainter(
                      seed: cart.id.hashCode ^ cart.total.hashCode,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  '₹${_formatMoney(cart.total)}',
                  style: const TextStyle(
                    color: _orange,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${cart.customerName}  ·  ${cart.id}',
                  style: TextStyle(
                    color: _ink.withValues(alpha: 0.65),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Ask the customer to scan this code with any UPI app.',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Deterministic mock QR — a 25×25 grid with the three position-
/// detection squares in the corners, filled from a seeded RNG so the
/// same cart always shows the same pattern. Not scannable; that's out
/// of scope for the prototype.
class _MockQrPainter extends CustomPainter {
  final int seed;
  const _MockQrPainter({required this.seed});

  static const int _grid = 25;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / _grid;
    final black = Paint()..color = Colors.black;
    final rng = math.Random(seed);

    // Random dots (avoiding the corner finder-square zones).
    for (var r = 0; r < _grid; r++) {
      for (var c = 0; c < _grid; c++) {
        if (_isInFinderZone(r, c)) continue;
        if (rng.nextBool()) {
          canvas.drawRect(
            Rect.fromLTWH(c * cell, r * cell, cell, cell),
            black,
          );
        }
      }
    }
    // Three finder squares.
    _drawFinder(canvas, cell, 0, 0);
    _drawFinder(canvas, cell, 0, _grid - 7);
    _drawFinder(canvas, cell, _grid - 7, 0);
  }

  bool _isInFinderZone(int r, int c) {
    bool near(int r0, int c0) => r >= r0 && r < r0 + 8 && c >= c0 && c < c0 + 8;
    return near(0, 0) ||
        near(0, _grid - 8) ||
        near(_grid - 8, 0);
  }

  void _drawFinder(Canvas canvas, double cell, int row, int col) {
    void rect(int r, int c, int rs, int cs, Color color) => canvas.drawRect(
          Rect.fromLTWH(
              (col + c) * cell, (row + r) * cell, cs * cell, rs * cell),
          Paint()..color = color,
        );
    rect(0, 0, 7, 7, Colors.black);
    rect(1, 1, 5, 5, Colors.white);
    rect(2, 2, 3, 3, Colors.black);
  }

  @override
  bool shouldRepaint(covariant _MockQrPainter old) => old.seed != seed;
}

// ---------------------------------------------------------------------------
// Helpers.
// ---------------------------------------------------------------------------

String _formatMoney(double n) {
  final s = n.toStringAsFixed(0);
  // Indian-style grouping: last three, then pairs. e.g. 12,34,567.
  final b = StringBuffer();
  final chars = s.split('').reversed.toList();
  for (var i = 0; i < chars.length; i++) {
    b.write(chars[i]);
    final atGroup = i == 2 || (i > 2 && (i - 2) % 2 == 0);
    if (atGroup && i != chars.length - 1) b.write(',');
  }
  return b.toString().split('').reversed.join();
}
