import 'package:flutter/material.dart';
import 'package:clone_pos_core/models/product.dart';
import '../data/seed_products_300.dart';
import '../theme/clone_pos_theme.dart';
import 'inventory_card_view.dart';

/// Three-level hierarchical inventory browser.
///
///   Level 1: Categories    (e.g. "Kitchen", "Smartphones", "Watches")
///   Level 2: Sub-categories (within the tapped category)
///   Level 3: Products       (the existing card view, filtered)
///
/// Drops into the Inventory tab wherever [InventoryCardView] was used.
/// Navigation state lives in this widget — an AnimatedSwitcher cross-
/// fades between levels, and a back header sits above every screen after
/// Level 1 so the user can pop up one level at a time.
class InventoryBrowser extends StatefulWidget {
  final List<Product>? products;
  const InventoryBrowser({super.key, this.products});

  @override
  State<InventoryBrowser> createState() => _InventoryBrowserState();
}

class _InventoryBrowserState extends State<InventoryBrowser> {
  late final List<Product> _all = widget.products ?? seedProducts300();

  String? _category;
  String? _subCategory;

  // Category -> ordered list of sub-categories -> ordered list of products.
  // Built once from _all; keeps rendering cheap even at 300+ SKUs.
  late final Map<String, Map<String, List<Product>>> _tree = _buildTree(_all);

  static Map<String, Map<String, List<Product>>> _buildTree(List<Product> ps) {
    final tree = <String, Map<String, List<Product>>>{};
    for (final p in ps) {
      final sub = (p.subCategory?.trim().isNotEmpty ?? false)
          ? p.subCategory!
          : 'General';
      tree
          .putIfAbsent(p.category, () => <String, List<Product>>{})
          .putIfAbsent(sub, () => <Product>[])
          .add(p);
    }
    // Sort products alphabetically inside each sub-category for a stable feel.
    for (final subs in tree.values) {
      for (final list in subs.values) {
        list.sort((a, b) => a.name.compareTo(b.name));
      }
    }
    return tree;
  }

  void _openCategory(String cat) => setState(() {
        _category = cat;
        _subCategory = null;
      });

  void _openSubCategory(String sub) => setState(() => _subCategory = sub);

  void _back() => setState(() {
        if (_subCategory != null) {
          _subCategory = null;
        } else {
          _category = null;
        }
      });

  @override
  Widget build(BuildContext context) {
    // WillPopScope-style: intercept device back so it pops one level in
    // the browser before leaving the inventory tab entirely.
    return PopScope(
      canPop: _category == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Container(
        color: ClonePosColors.creamCard,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final slide = Tween<Offset>(
              begin: const Offset(0.06, 0),
              end: Offset.zero,
            ).animate(animation);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: slide, child: child),
            );
          },
          child: _buildCurrentLevel(),
        ),
      ),
    );
  }

  Widget _buildCurrentLevel() {
    if (_category == null) {
      return _CategoriesGrid(
        key: const ValueKey('L1'),
        tree: _tree,
        onOpen: _openCategory,
      );
    }
    if (_subCategory == null) {
      return _SubCategoriesGrid(
        key: ValueKey('L2:$_category'),
        category: _category!,
        subs: _tree[_category!]!,
        onBack: _back,
        onOpen: _openSubCategory,
      );
    }
    final products = _tree[_category!]![_subCategory!]!;
    return _ProductsLevel(
      key: ValueKey('L3:$_category/$_subCategory'),
      category: _category!,
      subCategory: _subCategory!,
      products: products,
      onBack: _back,
    );
  }
}

// ---------------------------------------------------------------------------
// Level 1 — categories
// ---------------------------------------------------------------------------

class _CategoriesGrid extends StatelessWidget {
  final Map<String, Map<String, List<Product>>> tree;
  final ValueChanged<String> onOpen;
  const _CategoriesGrid({super.key, required this.tree, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final cats = tree.keys.toList()..sort();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _BrowserTitle(text: 'Browse by Category'),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 1.1,
              ),
              itemCount: cats.length,
              itemBuilder: (ctx, i) {
                final name = cats[i];
                final subs = tree[name]!;
                final itemCount =
                    subs.values.fold<int>(0, (s, l) => s + l.length);
                final preview = _firstImage(subs);
                return _CategoryTile(
                  name: name,
                  subCount: subs.length,
                  itemCount: itemCount,
                  previewImage: preview,
                  onTap: () => onOpen(name),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static String? _firstImage(Map<String, List<Product>> subs) {
    for (final list in subs.values) {
      for (final p in list) {
        if (p.imageUrl != null && p.imageUrl!.isNotEmpty) return p.imageUrl;
      }
    }
    return null;
  }
}

class _CategoryTile extends StatelessWidget {
  final String name;
  final int subCount;
  final int itemCount;
  final String? previewImage;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.name,
    required this.subCount,
    required this.itemCount,
    required this.previewImage,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ClonePosColors.cream,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    color: ClonePosColors.creamCard,
                    alignment: Alignment.center,
                    child: previewImage != null
                        ? Image.network(
                            previewImage!,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.inventory_2_outlined,
                              size: 48,
                              color: ClonePosColors.walnut,
                            ),
                          )
                        : const Icon(
                            Icons.inventory_2_outlined,
                            size: 48,
                            color: ClonePosColors.walnut,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: ClonePosColors.walnut,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$subCount sub · $itemCount items',
                style: TextStyle(
                  color: ClonePosColors.walnut.withValues(alpha: 0.65),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Level 2 — sub-categories within a category
// ---------------------------------------------------------------------------

class _SubCategoriesGrid extends StatelessWidget {
  final String category;
  final Map<String, List<Product>> subs;
  final VoidCallback onBack;
  final ValueChanged<String> onOpen;

  const _SubCategoriesGrid({
    super.key,
    required this.category,
    required this.subs,
    required this.onBack,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final names = subs.keys.toList()..sort();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CrumbBar(
            crumbs: [category],
            onBack: onBack,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 1.15,
              ),
              itemCount: names.length,
              itemBuilder: (ctx, i) {
                final name = names[i];
                final list = subs[name]!;
                final preview = list
                    .firstWhere(
                      (p) => (p.imageUrl ?? '').isNotEmpty,
                      orElse: () => list.first,
                    )
                    .imageUrl;
                return _CategoryTile(
                  name: name,
                  subCount: list.length,
                  itemCount: list.length,
                  previewImage: preview,
                  onTap: () => onOpen(name),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Level 3 — products (reuses the existing card view + a back crumb bar)
// ---------------------------------------------------------------------------

class _ProductsLevel extends StatelessWidget {
  final String category;
  final String subCategory;
  final List<Product> products;
  final VoidCallback onBack;

  const _ProductsLevel({
    super.key,
    required this.category,
    required this.subCategory,
    required this.products,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CrumbBar(
            crumbs: [category, subCategory],
            onBack: onBack,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              // Reuse existing single-card carousel with a filtered list.
              child: InventoryCardView(products: products),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared header bits
// ---------------------------------------------------------------------------

class _BrowserTitle extends StatelessWidget {
  final String text;
  const _BrowserTitle({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: ClonePosColors.walnut,
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _CrumbBar extends StatelessWidget {
  final List<String> crumbs;
  final VoidCallback onBack;
  const _CrumbBar({required this.crumbs, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Material(
          color: ClonePosColors.orangeButton,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onBack,
            customBorder: const CircleBorder(),
            child: const SizedBox(
              width: 36,
              height: 36,
              child: Icon(Icons.arrow_back, color: Colors.white, size: 20),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Inventory',
                style: TextStyle(
                  color: ClonePosColors.walnut,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              for (final c in crumbs) ...[
                _crumbSep(),
                Text(
                  c,
                  style: const TextStyle(
                    color: ClonePosColors.rust,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _crumbSep() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6),
        child: Text(
          '/',
          style: TextStyle(
            color: ClonePosColors.walnut,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}
