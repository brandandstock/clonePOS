import 'package:flutter/material.dart';
import 'package:clone_pos_core/models/product.dart';
import '../data/seed_products_cybergic_500.dart';
import 'master_dashboard_screen.dart' show AppTheme;

/// Inventory dashboard for the opened-state template. Fills the
/// tile-grid + summary-column area with two panes; `settingsMode`
/// flips which side the summary column lives on:
///
///   settingsMode = false (Image 1 / Figma 369:158)
///   ┌─────────────┬────────────────────────────────────┐
///   │  INVENTORY  │                                    │
///   ├─────────────┤     drill grid (categories →       │
///   │             │     sub-categories → products →    │
///   │  FILTERS    │     product detail),               │
///   │  search     │     vertical scroll via            │
///   │  sort       │     RIGHT flank rail.              │
///   │  brand      │                                    │
///   │  in-stock   │                                    │
///   │  reset      │                                    │
///   └─────────────┴────────────────────────────────────┘
///
///   settingsMode = true (Image 2 / Figma 369:184)
///   The two panes swap sides and the title cell reads "SETTINGS".
///
/// The category chip strip that briefly sat in the title cell has
/// been dropped for now — the top cell just shows a plain title.
/// The LEFT flank rail is therefore idle here; its controller stays
/// wired in case a horizontal-scrollable target is added later.
class InventoryOpenedView extends StatefulWidget {
  /// Vertical scroll controller for the drill grid — the parent
  /// dashboard wires this to the RIGHT flank rail (vertical scroll).
  final ScrollController? scrollController;

  /// Scroll controller for the filter panel in the summary column —
  /// the parent dashboard wires this to the LEFT flank rail so a
  /// vertical drag on the rail scrolls the filter section.
  final ScrollController? filterScrollController;

  /// Off (default) → summary column renders on the LEFT with title
  /// "INVENTORY" (matches Image 1 / Figma 369:158).
  /// On → summary column moves to the RIGHT and its title becomes
  /// "SETTINGS" (matches Image 2 / Figma 369:184). Toggled by the
  /// right-flank Settings badge in the master dashboard.
  final bool settingsMode;

  const InventoryOpenedView({
    super.key,
    this.scrollController,
    this.filterScrollController,
    this.settingsMode = false,
  });

  @override
  InventoryOpenedViewState createState() => InventoryOpenedViewState();
}

enum _Level { categories, subCategories, products, productDetail }

/// Public state class so the parent dashboard can drive the drill via
/// a GlobalKey. `maybePop()` steps one level up and returns true; it
/// returns false only when already at the categories root, letting the
/// parent close the whole Inventory tab.
class InventoryOpenedViewState extends State<InventoryOpenedView> {
  /// Called by the master dashboard's chevron_back so the same button
  /// can walk detail → products → subs → categories → (close tab).
  /// Returns true when a drill-up happened inside this view.
  bool maybePop() {
    if (_level == _Level.categories) return false;
    _back();
    return true;
  }

  late final List<Product> _all = seedProductsCybergic500();

  // Drill state.
  _Level _level = _Level.categories;
  String? _category;
  String? _subCategory;
  Product? _focusedProduct;

  // Filter state.
  String _search = '';
  String? _brandFilter;
  bool _inStockOnly = false;
  _SortMode _sort = _SortMode.aToZ;

  late final TextEditingController _searchCtrl = TextEditingController();

  // ── Derived-data caches ───────────────────────────────────────────────
  // Every rebuild used to iterate 500 products through _productsInScope,
  // _brandsInScope, and _allCategoriesSorted — multiple full passes per
  // rebuild, and the search TextField rebuilds on every keystroke. Cache
  // what depends only on the drill, and refresh it in
  // _rebuildDrillCaches() whenever the drill changes.
  late List<Product> _cachedInScope;
  late List<String> _cachedBrandsInScope;

  @override
  void initState() {
    super.initState();
    _rebuildDrillCaches();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Recomputes the drill-scoped caches from _all. Call inside setState
  /// whenever _category or _subCategory changes; filter fields (search,
  /// brand, in-stock, sort) don't invalidate these — they're applied
  /// downstream by _applyFilters/_compareByMode.
  void _rebuildDrillCaches() {
    final inScope = <Product>[];
    for (final p in _all) {
      if (_category != null && p.category != _category) continue;
      if (_subCategory != null && p.subCategory != _subCategory) continue;
      inScope.add(p);
    }
    _cachedInScope = inScope;

    final brandSet = <String>{};
    for (final p in inScope) {
      if ((p.brand ?? '').isNotEmpty) brandSet.add(p.brand!);
    }
    _cachedBrandsInScope = brandSet.toList()..sort();
  }

  // ----- Drilling helpers --------------------------------------------------

  void _drillIntoCategory(String cat) => setState(() {
        _category = cat;
        _subCategory = null;
        _level = _Level.subCategories;
        _rebuildDrillCaches();
      });

  void _drillIntoSubCategory(String sub) => setState(() {
        _subCategory = sub;
        _level = _Level.products;
        _rebuildDrillCaches();
      });

  void _drillIntoProduct(Product p) => setState(() {
        _focusedProduct = p;
        _level = _Level.productDetail;
        // Drill scope unchanged — focused product is a leaf; no cache reset.
      });

  void _back() => setState(() {
        switch (_level) {
          case _Level.productDetail:
            _focusedProduct = null;
            _level = _Level.products;
            break;
          case _Level.products:
            _subCategory = null;
            _level = _Level.subCategories;
            _rebuildDrillCaches();
            break;
          case _Level.subCategories:
            _category = null;
            _level = _Level.categories;
            _rebuildDrillCaches();
            break;
          case _Level.categories:
            break;
        }
      });

  void _resetFilters() => setState(() {
        _search = '';
        _searchCtrl.clear();
        _brandFilter = null;
        _inStockOnly = false;
        _sort = _SortMode.aToZ;
      });

  // ----- Derived data ------------------------------------------------------

  List<Product> get _productsInScope => _cachedInScope;

  /// Brands present in the currently-scoped products, sorted A-Z.
  List<String> get _brandsInScope => _cachedBrandsInScope;

  Iterable<Product> _applyFilters(Iterable<Product> src) {
    final q = _search.trim().toLowerCase();
    return src.where((p) {
      if (_brandFilter != null && p.brand != _brandFilter) return false;
      if (_inStockOnly && !p.inStock) return false;
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) ||
          (p.description ?? '').toLowerCase().contains(q) ||
          (p.brand ?? '').toLowerCase().contains(q);
    });
  }

  int _compareByMode(Product a, Product b) {
    switch (_sort) {
      case _SortMode.aToZ:
        return a.name.compareTo(b.name);
      case _SortMode.zToA:
        return b.name.compareTo(a.name);
      case _SortMode.priceAsc:
        return a.price.compareTo(b.price);
      case _SortMode.priceDesc:
        return b.price.compareTo(a.price);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Two layouts driven by `settingsMode`:
    //   OFF → summary column on the LEFT (Image 1, title "INVENTORY")
    //   ON  → summary column on the RIGHT (Image 2, title "SETTINGS")
    //
    // Each half sits inside its own RepaintBoundary so scrolling the
    // drill grid doesn't invalidate the chip-strip/filter layer.
    final drill = Expanded(
      child: RepaintBoundary(child: _buildRightPane()),
    );
    final summary = SizedBox(
      width: 250,
      child: RepaintBoundary(child: _buildSummaryColumn()),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widget.settingsMode
          ? [drill, const SizedBox(width: 2), summary]
          : [summary, const SizedBox(width: 2), drill],
    );
  }

  // ----- Summary column ----------------------------------------------------

  Widget _buildSummaryColumn() {
    // Column mirrors the master dashboard's summary geometry:
    // title cell (115 tall) + 2 gap + big cell (585 tall).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 115, child: _buildTitleCell()),
        const SizedBox(height: 2),
        Expanded(child: _buildFilterCell()),
      ],
    );
  }

  /// Top cell of the summary column — 250×115. Simple left-aligned
  /// title, matches the master dashboard's _OpenedTitleCell style so
  /// non-inventory tabs and Inventory look identical here. Reads
  /// "INVENTORY" by default, "SETTINGS" when settingsMode is on.
  Widget _buildTitleCell() {
    final title = widget.settingsMode ? 'SETTINGS' : 'INVENTORY';
    final t = AppTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.panelBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            title,
            style: TextStyle(
              color: t.panelText,
              fontSize: 26,
              fontWeight: FontWeight.w500,
              letterSpacing: 3,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterCell() {
    // Filter panel — fits comfortably in 585 tall so no scroll needed
    // at the current field count, but wrapped in a SingleChildScrollView
    // so the LEFT flank rail (via widget.filterScrollController) can
    // scroll it when the field list grows or the pane shrinks.
    final title = widget.settingsMode ? 'SETTINGS' : 'INVENTORY';
    final t = AppTheme.of(context);
    return Material(
      color: t.panelBg,
      borderRadius: BorderRadius.circular(10),
      child: SingleChildScrollView(
        controller: widget.filterScrollController,
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: t.panelText,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 6),
            Container(height: 2, width: 100, color: t.panelAccent),
            const SizedBox(height: 16),
            _breadcrumb(),
            const SizedBox(height: 16),
            _label('SEARCH'),
            TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: 'Name, brand, keyword',
                hintStyle: const TextStyle(fontSize: 12),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            _label('SORT'),
            _SortDropdown(
              value: _sort,
              onChanged: (v) => setState(() => _sort = v),
            ),
            const SizedBox(height: 12),
            _label('BRAND'),
            _BrandDropdown(
              options: _brandsInScope,
              value: _brandFilter,
              onChanged: (v) => setState(() => _brandFilter = v),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Checkbox(
                  value: _inStockOnly,
                  onChanged: (v) =>
                      setState(() => _inStockOnly = v ?? false),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const Text(
                  'In stock only',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2E2E2E),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Reset filters'),
                onPressed: _resetFilters,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2E2E2E),
                  side: const BorderSide(color: Color(0xFF2E2E2E)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _breadcrumb() {
    // Compact crumb line with a back arrow when we're not at the root.
    return Row(
      children: [
        if (_level != _Level.categories)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: InkWell(
              onTap: _back,
              child: const Icon(Icons.arrow_back_ios_new, size: 14),
            ),
          ),
        Expanded(
          child: Text(
            _crumbText(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2E2E2E),
              letterSpacing: 0.4,
            ),
          ),
        ),
      ],
    );
  }

  String _crumbText() {
    switch (_level) {
      case _Level.categories:
        return 'CATEGORIES';
      case _Level.subCategories:
        return '${_category!.toUpperCase()} › SUB';
      case _Level.products:
        return '${_category!.toUpperCase()} › ${_subCategory!.toUpperCase()}';
      case _Level.productDetail:
        return '${_subCategory!.toUpperCase()} › '
            '${_focusedProduct!.name.toUpperCase()}';
    }
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: const Color(0xFF2E2E2E).withValues(alpha: 0.6),
        ),
      ),
    );
  }

  // ----- Right pane --------------------------------------------------------

  Widget _buildRightPane() {
    // Every drill level renders a scrollable 3-column vertical grid
    // (or the product detail view). RIGHT flank rail drives vertical
    // scroll via widget.scrollController. LEFT rail scrolls the filter
    // panel in the summary column via widget.filterScrollController.
    switch (_level) {
      case _Level.categories:
        return _CategoriesGrid(
          products: _applyFilters(_productsInScope),
          onOpen: _drillIntoCategory,
          scrollController: widget.scrollController,
        );
      case _Level.subCategories:
        return _SubCategoriesGrid(
          category: _category!,
          products: _applyFilters(_productsInScope),
          onOpen: _drillIntoSubCategory,
          scrollController: widget.scrollController,
        );
      case _Level.products:
        final list = _applyFilters(_productsInScope).toList()
          ..sort(_compareByMode);
        return _ProductsGrid(
          products: list,
          onOpen: _drillIntoProduct,
          scrollController: widget.scrollController,
        );
      case _Level.productDetail:
        return _ProductDetailView(
          product: _focusedProduct!,
          scrollController: widget.scrollController,
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Sort + brand dropdowns.
// ---------------------------------------------------------------------------

enum _SortMode { aToZ, zToA, priceAsc, priceDesc }

class _SortDropdown extends StatelessWidget {
  final _SortMode value;
  final ValueChanged<_SortMode> onChanged;
  const _SortDropdown({required this.value, required this.onChanged});

  static const _labels = {
    _SortMode.aToZ: 'Name A → Z',
    _SortMode.zToA: 'Name Z → A',
    _SortMode.priceAsc: 'Price ↑',
    _SortMode.priceDesc: 'Price ↓',
  };

  @override
  Widget build(BuildContext context) {
    return _DropdownFrame(
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_SortMode>(
          isExpanded: true,
          value: value,
          isDense: true,
          style: const TextStyle(fontSize: 13, color: Color(0xFF2E2E2E)),
          items: [
            for (final e in _labels.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class _BrandDropdown extends StatelessWidget {
  final List<String> options;
  final String? value;
  final ValueChanged<String?> onChanged;
  const _BrandDropdown({
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _DropdownFrame(
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          isExpanded: true,
          value: value,
          isDense: true,
          hint: const Text(
            'All brands',
            style: TextStyle(fontSize: 13, color: Color(0xFF888888)),
          ),
          style: const TextStyle(fontSize: 13, color: Color(0xFF2E2E2E)),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('All brands'),
            ),
            for (final b in options)
              DropdownMenuItem<String?>(value: b, child: Text(b)),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _DropdownFrame extends StatelessWidget {
  final Widget child;
  const _DropdownFrame({required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Level 1 — categories grid.
// ---------------------------------------------------------------------------

class _CategoriesGrid extends StatelessWidget {
  final Iterable<Product> products;
  final ValueChanged<String> onOpen;
  final ScrollController? scrollController;
  const _CategoriesGrid({
    required this.products,
    required this.onOpen,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final byCat = <String, List<Product>>{};
    for (final p in products) {
      byCat.putIfAbsent(p.category, () => []).add(p);
    }
    final entries = byCat.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return _CardGrid(
      scrollController: scrollController,
      itemCount: entries.length,
      builder: (ctx, i) {
        final e = entries[i];
        final preview = e.value.firstWhere(
          (p) => (p.imageUrl ?? '').isNotEmpty,
          orElse: () => e.value.first,
        );
        return _BrowseTile(
          title: e.key,
          subtitle: '${e.value.length} items',
          imageUrl: preview.imageUrl,
          onTap: () => onOpen(e.key),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Level 2 — sub-categories within a category.
// ---------------------------------------------------------------------------

class _SubCategoriesGrid extends StatelessWidget {
  final String category;
  final Iterable<Product> products;
  final ValueChanged<String> onOpen;
  final ScrollController? scrollController;
  const _SubCategoriesGrid({
    required this.category,
    required this.products,
    required this.onOpen,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final bySub = <String, List<Product>>{};
    for (final p in products) {
      final sub = (p.subCategory?.trim().isNotEmpty ?? false)
          ? p.subCategory!
          : 'General';
      bySub.putIfAbsent(sub, () => []).add(p);
    }
    final entries = bySub.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return _CardGrid(
      scrollController: scrollController,
      itemCount: entries.length,
      builder: (ctx, i) {
        final e = entries[i];
        final preview = e.value.firstWhere(
          (p) => (p.imageUrl ?? '').isNotEmpty,
          orElse: () => e.value.first,
        );
        return _BrowseTile(
          title: e.key,
          subtitle: '${e.value.length} items',
          imageUrl: preview.imageUrl,
          onTap: () => onOpen(e.key),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Level 3 — products list.
// ---------------------------------------------------------------------------

class _ProductsGrid extends StatelessWidget {
  final List<Product> products;
  final ValueChanged<Product> onOpen;
  final ScrollController? scrollController;
  const _ProductsGrid({
    required this.products,
    required this.onOpen,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const Center(
        child: Text(
          'No products match your filters.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    return _CardGrid(
      scrollController: scrollController,
      itemCount: products.length,
      // Products drill uses 5 cols per client — fits ~15 tiles on
      // screen with vertical scroll for the rest.
      crossAxisCount: 5,
      childAspectRatio: 149 / 232,
      builder: (ctx, i) {
        final p = products[i];
        return _ProductTile(product: p, onTap: () => onOpen(p));
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Shared vertical card grid — defaults to 3 columns (categories +
// sub-categories); the products drill overrides to 5. RIGHT flank
// rail drives the vertical scroll via its ScrollController.
// ---------------------------------------------------------------------------

class _CardGrid extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext, int) builder;
  final ScrollController? scrollController;
  final int crossAxisCount;
  final double childAspectRatio;
  const _CardGrid({
    required this.itemCount,
    required this.builder,
    this.scrollController,
    this.crossAxisCount = 3,
    this.childAspectRatio = 250 / 349,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 2),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        childAspectRatio: childAspectRatio,
      ),
      itemCount: itemCount,
      itemBuilder: builder,
    );
  }
}

class _BrowseTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? imageUrl;
  final VoidCallback onTap;

  const _BrowseTile({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Material(
      color: t.panelBg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    color: t.chipBg,
                    alignment: Alignment.center,
                    child: (imageUrl ?? '').isNotEmpty
                        ? Image.network(
                            imageUrl!,
                            fit: BoxFit.contain,
                            // Downsample during decode — the tile only
                            // paints at ~180 dp; a bigger bitmap only
                            // wastes memory + decode time.
                            cacheWidth: 200,
                            filterQuality: FilterQuality.low,
                            gaplessPlayback: true,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.inventory_2_outlined,
                              size: 48,
                              color: t.cardSubtleText,
                            ),
                          )
                        : Icon(
                            Icons.inventory_2_outlined,
                            size: 48,
                            color: t.cardSubtleText,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.panelText,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: t.cardSubtleText,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  const _ProductTile({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final stock = product.stock ?? 0;
    final hasBrand = (product.brand ?? '').isNotEmpty;
    final t = AppTheme.of(context);
    return Material(
      color: t.panelBg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    color: t.chipBg,
                    alignment: Alignment.center,
                    child: (product.imageUrl ?? '').isNotEmpty
                        ? Image.network(
                            product.imageUrl!,
                            fit: BoxFit.contain,
                            cacheWidth: 200,
                            filterQuality: FilterQuality.low,
                            gaplessPlayback: true,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.image_not_supported_outlined,
                              size: 40,
                              color: t.cardSubtleText,
                            ),
                          )
                        : Icon(
                            Icons.image_not_supported_outlined,
                            size: 40,
                            color: t.cardSubtleText,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.panelText,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  height: 1.15,
                ),
              ),
              if (hasBrand) ...[
                const SizedBox(height: 2),
                Text(
                  product.brand!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.cardSubtleText,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    '₹${product.price.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: Color(0xFFE87722),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  _StockPill(stock: stock),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact stock indicator in the bottom-right of a product tile.
/// Green pill for stock > 0 (with the count), red "OOS" pill for 0.
class _StockPill extends StatelessWidget {
  final int stock;
  const _StockPill({required this.stock});

  @override
  Widget build(BuildContext context) {
    final oos = stock <= 0;
    final bg = oos ? const Color(0xFFFDECEA) : const Color(0xFFE6F4EA);
    final fg = oos ? const Color(0xFFC62828) : const Color(0xFF1E7A3B);
    final label = oos ? 'OOS' : '$stock in stock';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Product detail — replaces the right pane when a product tile is tapped.
// Left half: big image. Right half: meta + placeholder actions, scrollable
// so overflow past the pane bottom is reachable via the right flank rail.
// ---------------------------------------------------------------------------

class _ProductDetailView extends StatelessWidget {
  final Product product;
  final ScrollController? scrollController;
  const _ProductDetailView({required this.product, this.scrollController});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 4, child: _DetailImage(imageUrl: product.imageUrl)),
          Expanded(
            flex: 6,
            child: SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: _DetailMeta(product: product),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailImage extends StatelessWidget {
  final String? imageUrl;
  const _DetailImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF3F3F3),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: (imageUrl ?? '').isNotEmpty
          ? Image.network(
              imageUrl!,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.image_not_supported_outlined,
                size: 96,
                color: Color(0xFF888888),
              ),
            )
          : const Icon(
              Icons.image_not_supported_outlined,
              size: 96,
              color: Color(0xFF888888),
            ),
    );
  }
}

class _DetailMeta extends StatelessWidget {
  final Product product;
  const _DetailMeta({required this.product});

  @override
  Widget build(BuildContext context) {
    final stock = product.stock ?? 0;
    final hasBrand = (product.brand ?? '').isNotEmpty;
    final hasWarranty = (product.warrantyText ?? '').isNotEmpty;
    final hasRating = product.rating != null;
    final hasDescription = (product.description ?? '').isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category > subCategory chain, uppercase tracker line.
        Text(
          [
            product.category,
            if ((product.subCategory ?? '').isNotEmpty) product.subCategory,
          ].join(' › ').toUpperCase(),
          style: const TextStyle(
            color: Color(0xFF888888),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          product.name,
          style: const TextStyle(
            color: Color(0xFF2E2E2E),
            fontSize: 20,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'SKU · ${product.id}',
          style: const TextStyle(
            color: Color(0xFF999999),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (hasBrand) _MetaChip(label: product.brand!),
            if (hasRating)
              _MetaChip(
                icon: Icons.star_rounded,
                label: '${product.rating!.toStringAsFixed(1)}'
                    '${product.ratingCount != null ? ' (${product.ratingCount})' : ''}',
              ),
            if (hasWarranty)
              _MetaChip(
                icon: Icons.verified_outlined,
                label: '${product.warrantyText} warranty',
              ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '₹${product.price.toStringAsFixed(0)}',
              style: const TextStyle(
                color: Color(0xFFE87722),
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _StockPill(stock: stock),
            ),
          ],
        ),
        if (hasDescription) ...[
          const SizedBox(height: 18),
          Container(
            height: 1,
            color: const Color(0xFFEDEDED),
          ),
          const SizedBox(height: 14),
          const Text(
            'DESCRIPTION',
            style: TextStyle(
              color: Color(0xFF888888),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            product.description!,
            style: const TextStyle(
              color: Color(0xFF444444),
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.45,
            ),
          ),
        ],
        const SizedBox(height: 22),
        // Action buttons — not yet wired to the printer/ledger; these are
        // placeholders that map to spec sections 2.5 (intake/print) and
        // 2.6 (returns/adjust). Mock only until the repositories land.
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.qr_code_2, size: 18),
                label: const Text('Print QR label'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2E2E2E),
                  side: const BorderSide(color: Color(0xFF2E2E2E)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('Adjust stock'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE87722),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData? icon;
  final String label;
  const _MetaChip({this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(icon != null ? 8 : 10, 5, 10, 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F3F3),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: const Color(0xFF444444)),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF444444),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
