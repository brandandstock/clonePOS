import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:clone_pos_core/models/product.dart';
import '../data/seed_products_300.dart';
import '../theme/clone_pos_theme.dart';

/// Alphabetized inventory list on the Master display. Reacts to the
/// A-Z rail on the Secondary display via [letterCue]: whenever a new
/// non-null letter arrives, this list scrolls (jumps) to the first
/// product whose name starts with that letter.
///
/// jumpTo is deliberate rather than animateTo — the rail fires letter
/// changes on every drag boundary, and queuing a 200ms animation per
/// change stacks up cancellations that make the list feel laggy. An
/// immediate jump matches the rail's own feel: the finger travels and
/// the list travels with it.
///
/// Section headers are intentionally *not* rendered here yet. The rail
/// itself is the visual index; adding on-screen A/B/C headers would
/// duplicate that signal. Easy to add later if we decide otherwise.
class InventoryListScreen extends StatefulWidget {
  final List<Product>? products;

  /// Optional broadcast channel from the Secondary display's A-Z rail.
  /// Emits the letter under the finger; null when the finger is up.
  final ValueListenable<String?>? letterCue;

  const InventoryListScreen({super.key, this.products, this.letterCue});

  @override
  State<InventoryListScreen> createState() => _InventoryListScreenState();
}

class _InventoryListScreenState extends State<InventoryListScreen> {
  // Fixed row height so scroll offsets can be computed exactly by
  // index — no measurement pass, no jumpy scroll under a drag.
  static const double _itemExtent = 44;

  late final List<Product> _items;

  /// Map from uppercase first letter → index of the first product in
  /// [_items] whose name starts with that letter. Built once from the
  /// sorted list. Letters with no matching product are absent.
  late final Map<String, int> _firstIndexByLetter;

  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _items = [...(widget.products ?? seedProducts300())]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _firstIndexByLetter = _computeFirstIndexMap(_items);
    widget.letterCue?.addListener(_onLetterCue);
  }

  @override
  void didUpdateWidget(covariant InventoryListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.letterCue != widget.letterCue) {
      oldWidget.letterCue?.removeListener(_onLetterCue);
      widget.letterCue?.addListener(_onLetterCue);
    }
  }

  @override
  void dispose() {
    widget.letterCue?.removeListener(_onLetterCue);
    _controller.dispose();
    super.dispose();
  }

  static Map<String, int> _computeFirstIndexMap(List<Product> items) {
    final map = <String, int>{};
    for (var i = 0; i < items.length; i++) {
      final name = items[i].name;
      if (name.isEmpty) continue;
      final letter = name[0].toUpperCase();
      map.putIfAbsent(letter, () => i);
    }
    return map;
  }

  void _onLetterCue() {
    final letter = widget.letterCue?.value;
    if (letter == null) return;
    final index = _firstIndexByLetter[letter];
    if (index == null) return; // no product starts with this letter
    if (!_controller.hasClients) return;

    final targetOffset = index * _itemExtent;
    final maxOffset = _controller.position.maxScrollExtent;
    _controller.jumpTo(targetOffset.clamp(0.0, maxOffset));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: ClonePosColors.creamCard,
      child: ListView.builder(
        controller: _controller,
        itemExtent: _itemExtent,
        itemCount: _items.length,
        itemBuilder: (context, i) => _InventoryRow(product: _items[i]),
      ),
    );
  }
}

class _InventoryRow extends StatelessWidget {
  final Product product;
  const _InventoryRow({required this.product});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              product.name,
              style: const TextStyle(
                fontSize: 14,
                color: ClonePosColors.walnut,
                letterSpacing: -0.56,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(
              product.category,
              style: TextStyle(
                fontSize: 11,
                color: ClonePosColors.walnut.withValues(alpha: 0.6),
                letterSpacing: -0.44,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              '\$${product.price.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ClonePosColors.rust,
                letterSpacing: -0.52,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
