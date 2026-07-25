import 'package:flutter/material.dart';
import 'package:clone_pos_core/models/product.dart';
import '../data/seed_catalog.dart' show iconFor;
import '../data/seed_products_300.dart';

/// The Inventory tab's card view — one product at a time, laid out to
/// match the reference cards the client shared. Replaces the earlier
/// scrollable list wholesale.
///
/// Follows the "Boolean logic as primary state" pattern the client
/// asked for:
///   - _favorites   : `Set<String>` of SKUs; heart bound to
///                    contains(product.id).
///   - _inCart      : `Set<String>` of SKUs; Add-to-Cart button label,
///                    colour, and onPressed all bound to
///                    contains(product.id).
///   - product.inStock : bool derived from stock>0; the "In Stock"
///                    pill's visibility is bound to it.
///
/// Every interactive element flips exactly one boolean and re-reads
/// the same boolean on the next build — no divergent state paths.
class InventoryCardView extends StatefulWidget {
  final List<Product>? products;

  const InventoryCardView({super.key, this.products});

  @override
  State<InventoryCardView> createState() => _InventoryCardViewState();
}

class _InventoryCardViewState extends State<InventoryCardView> {
  late final List<Product> _products = widget.products ?? seedProducts300();
  final Set<String> _favorites = <String>{};
  final Set<String> _inCart = <String>{};
  int _currentIndex = 0;

  bool get _hasPrev => _currentIndex > 0;
  bool get _hasNext => _currentIndex < _products.length - 1;

  void _prev() {
    if (!_hasPrev) return;
    setState(() => _currentIndex -= 1);
  }

  void _next() {
    if (!_hasNext) return;
    setState(() => _currentIndex += 1);
  }

  void _toggleFavorite(String sku) {
    setState(() {
      if (_favorites.contains(sku)) {
        _favorites.remove(sku);
      } else {
        _favorites.add(sku);
      }
    });
  }

  void _toggleCart(String sku) {
    setState(() {
      if (_inCart.contains(sku)) {
        _inCart.remove(sku);
      } else {
        _inCart.add(sku);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final product = _products[_currentIndex];
    final isFavorite = _favorites.contains(product.id);
    final isInCart = _inCart.contains(product.id);

    return Container(
      color: Colors.white,
      child: Stack(
        children: [
          // Horizontal swipe navigates products; card itself absorbs
          // taps normally.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragEnd: (details) {
              final vx = details.velocity.pixelsPerSecond.dx;
              if (vx < -300) {
                _next();
              } else if (vx > 300) {
                _prev();
              }
            },
            child: _ProductCard(
              product: product,
              isFavorite: isFavorite,
              isInCart: isInCart,
              onToggleFavorite: () => _toggleFavorite(product.id),
              onToggleCart: () => _toggleCart(product.id),
            ),
          ),

          // Navigation arrows — enabled conditionally on _hasPrev /
          // _hasNext (Conditional Execution pattern).
          Positioned(
            left: 12,
            top: 0,
            bottom: 0,
            child: Center(
              child: _NavArrow(
                icon: Icons.chevron_left,
                enabled: _hasPrev,
                onTap: _prev,
              ),
            ),
          ),
          Positioned(
            right: 12,
            top: 0,
            bottom: 0,
            child: Center(
              child: _NavArrow(
                icon: Icons.chevron_right,
                enabled: _hasNext,
                onTap: _next,
              ),
            ),
          ),

          // Position indicator — small dots at the bottom-center.
          Positioned(
            left: 0,
            right: 0,
            bottom: 4,
            child: Center(
              child: _PositionDots(
                total: _products.length,
                current: _currentIndex,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Product card — the visual composition matching the Figma reference.
// ---------------------------------------------------------------------------

class _ProductCard extends StatelessWidget {
  final Product product;
  final bool isFavorite;
  final bool isInCart;
  final VoidCallback onToggleFavorite;
  final VoidCallback onToggleCart;

  const _ProductCard({
    required this.product,
    required this.isFavorite,
    required this.isInCart,
    required this.onToggleFavorite,
    required this.onToggleCart,
  });

  static const Color _brandBlue = Color(0xFF2563EB);
  static const Color _ink = Color(0xFF111827);
  static const Color _dim = Color(0xFF6B7280);
  static const Color _hair = Color(0xFFE5E7EB);
  static const Color _inStockBg = Color(0xFFDCFCE7);
  static const Color _inStockFg = Color(0xFF166534);
  static const Color _star = Color(0xFFF59E0B);
  static const Color _warrantyGreen = Color(0xFF16A34A);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildTop()),
          const Divider(height: 1, thickness: 1, color: _hair),
          _buildBottomInfoBar(),
        ],
      ),
    );
  }

  Widget _buildTop() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 5, child: _buildImageColumn()),
        const SizedBox(width: 24),
        Expanded(flex: 6, child: _buildDetailColumn()),
      ],
    );
  }

  Widget _buildImageColumn() {
    return Stack(
      children: [
        Positioned.fill(
          child: Center(
            child: product.imageUrl != null
                ? Image.network(
                    product.imageUrl!,
                    fit: BoxFit.contain,
                    // Fall back to the category icon if the CDN image
                    // can't load (offline, blocked, or 404) so the card
                    // never renders empty.
                    errorBuilder: (_, __, ___) => Icon(
                      iconFor(product),
                      size: 180,
                      color: _ink.withValues(alpha: 0.8),
                    ),
                  )
                : Icon(
                    iconFor(product),
                    size: 180,
                    color: _ink.withValues(alpha: 0.8),
                  ),
          ),
        ),
        // Boolean visibility: In-Stock pill only when product.inStock.
        if (product.inStock)
          const Positioned(
            top: 0,
            left: 0,
            child: _InStockPill(),
          ),
        // Heart is always present but its icon and colour flip on
        // isFavorite — single-boolean toggle, no divergent paths.
        Positioned(
          top: 0,
          right: 0,
          child: _FavoriteButton(
            isFavorite: isFavorite,
            onTap: onToggleFavorite,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${(product.category).toUpperCase()} / '
          '${(product.subCategory ?? '').toUpperCase()}',
          style: const TextStyle(
            color: _brandBlue,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          product.name,
          style: const TextStyle(
            color: _ink,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        _RatingRow(rating: product.rating ?? 0, count: product.ratingCount ?? 0),
        const SizedBox(height: 12),
        Text(
          product.description ?? '',
          style: const TextStyle(
            color: _dim,
            fontSize: 12.5,
            height: 1.5,
          ),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 14),
        const Divider(height: 1, thickness: 1, color: _hair),
        const SizedBox(height: 14),
        _buildPriceRow(),
        const SizedBox(height: 14),
        _buildActionRow(),
      ],
    );
  }

  Widget _buildPriceRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '₹${_formatPrice(product.price)}',
                style: const TextStyle(
                  color: _ink,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'MRP incl. of all taxes',
                style: TextStyle(color: _dim, fontSize: 11),
              ),
            ],
          ),
        ),
        // Warranty is visibility-bound: only rendered when the
        // product actually carries one.
        if (product.warrantyText != null)
          _WarrantyBadge(text: product.warrantyText!),
      ],
    );
  }

  Widget _buildActionRow() {
    return Row(
      children: [
        const _QtyPicker(),
        const SizedBox(width: 10),
        Expanded(
          child: _AddToCartButton(
            isInCart: isInCart,
            enabled: product.inStock,
            onTap: onToggleCart,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomInfoBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          _InfoCell(label: 'SKU', value: product.id),
          _InfoCell(label: 'BRAND', value: product.brand ?? '—'),
          _InfoCell(label: 'CATEGORY', value: product.category),
          _InfoCell(label: 'SUB-CATEGORY', value: product.subCategory ?? '—'),
          _InfoCell(
            label: 'STOCK',
            value: product.stock != null ? '${product.stock} Units' : '—',
          ),
          _InfoCell(
            label: 'AVAILABILITY',
            value: product.inStock ? 'In Stock' : 'Out of Stock',
            valueColor: product.inStock ? _warrantyGreen : Colors.red.shade600,
          ),
        ],
      ),
    );
  }
}

String _formatPrice(double v) {
  final s = v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);
  final buf = StringBuffer();
  final digits = s.split('.').first;
  final rest = s.contains('.') ? '.${s.split('.').last}' : '';
  // Indian numbering: last 3 digits, then groups of 2.
  // 189990 -> 1,89,990
  final n = digits.length;
  if (n <= 3) {
    buf.write(digits);
  } else {
    final tail = digits.substring(n - 3);
    var head = digits.substring(0, n - 3);
    final parts = <String>[];
    while (head.length > 2) {
      parts.insert(0, head.substring(head.length - 2));
      head = head.substring(0, head.length - 2);
    }
    if (head.isNotEmpty) parts.insert(0, head);
    buf.write(parts.join(','));
    buf.write(',');
    buf.write(tail);
  }
  buf.write(rest);
  return buf.toString();
}

// ---------------------------------------------------------------------------
// Small pieces — pill, heart, rating, warranty, qty, buttons.
// ---------------------------------------------------------------------------

class _InStockPill extends StatelessWidget {
  const _InStockPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _ProductCard._inStockBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.circle, size: 8, color: _ProductCard._inStockFg),
          SizedBox(width: 6),
          Text(
            'In Stock',
            style: TextStyle(
              color: _ProductCard._inStockFg,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoriteButton extends StatelessWidget {
  final bool isFavorite;
  final VoidCallback onTap;
  const _FavoriteButton({required this.isFavorite, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 1,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            isFavorite ? Icons.favorite : Icons.favorite_border,
            color: isFavorite ? Colors.red.shade500 : _ProductCard._ink,
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _RatingRow extends StatelessWidget {
  final double rating;
  final int count;
  const _RatingRow({required this.rating, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 1; i <= 5; i++) _star(i),
        const SizedBox(width: 8),
        Text(
          '($count)',
          style: const TextStyle(
            color: _ProductCard._dim,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _star(int position) {
    IconData icon;
    if (rating >= position) {
      icon = Icons.star_rounded;
    } else if (rating >= position - 0.5) {
      icon = Icons.star_half_rounded;
    } else {
      icon = Icons.star_outline_rounded;
    }
    return Icon(icon, color: _ProductCard._star, size: 18);
  }
}

class _WarrantyBadge extends StatelessWidget {
  final String text;
  const _WarrantyBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.verified_user_rounded,
          color: _ProductCard._warrantyGreen,
          size: 18,
        ),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 130),
          child: Text(
            text,
            style: const TextStyle(
              color: _ProductCard._ink,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

class _QtyPicker extends StatelessWidget {
  const _QtyPicker();

  @override
  Widget build(BuildContext context) {
    // Static visual — quantity is deliberately not a stateful counter
    // in this pass because the client asked to keep the Boolean-only
    // architecture. When numeric tracking is turned on, this becomes
    // a real +/- widget backed by an int per SKU.
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _ProductCard._hair),
      ),
      child: Row(
        children: const [
          Icon(Icons.remove, size: 18, color: _ProductCard._dim),
          SizedBox(width: 14),
          Text(
            '1',
            style: TextStyle(
              color: _ProductCard._ink,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(width: 14),
          Icon(Icons.add, size: 18, color: _ProductCard._ink),
        ],
      ),
    );
  }
}

class _AddToCartButton extends StatelessWidget {
  final bool isInCart;
  final bool enabled;
  final VoidCallback onTap;

  const _AddToCartButton({
    required this.isInCart,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Every visual property flips off a single boolean (isInCart);
    // enable/disable flips off the second (enabled). Conditional
    // execution — if !enabled, onPressed is null so the button
    // greys out and doesn't fire.
    final bg = !enabled
        ? _ProductCard._hair
        : isInCart
            ? _ProductCard._warrantyGreen
            : _ProductCard._brandBlue;
    final label = !enabled
        ? 'Out of Stock'
        : isInCart
            ? 'In Cart'
            : 'Add to Cart';
    final icon = isInCart
        ? Icons.check_rounded
        : Icons.shopping_cart_outlined;

    return SizedBox(
      height: 44,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled ? onTap : null,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoCell extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _InfoCell({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _ProductCard._dim,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? _ProductCard._ink,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _NavArrow extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _NavArrow({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.35,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, color: _ProductCard._ink),
          ),
        ),
      ),
    );
  }
}

class _PositionDots extends StatelessWidget {
  final int total;
  final int current;
  const _PositionDots({required this.total, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == current ? 16 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == current
                  ? _ProductCard._brandBlue
                  : _ProductCard._hair,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}
