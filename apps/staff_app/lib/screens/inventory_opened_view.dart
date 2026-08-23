import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:clone_pos_core/models/product.dart';
import '../data/catalog_importer.dart';
import '../data/product_store.dart';
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

  // Runtime catalog, loaded from disk in initState (seeded from the bundled
  // 500 on first run). The "+ Add product" action appends and deletes remove,
  // and every mutation is written back via _store so it survives a restart.
  final ProductStore _store = ProductStore();
  List<Product> _all = <Product>[];
  bool _loading = true;

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
    _rebuildDrillCaches(); // empty scope until the catalog loads
    _load();
  }

  Future<void> _load() async {
    final products = await _store.load();
    if (!mounted) return;
    setState(() {
      _all = products;
      _loading = false;
      _rebuildDrillCaches();
    });
  }

  /// Fire-and-forget write of the current catalog after any mutation.
  void _persist() => _store.save(_all);

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
      // Match the SAME bucketing the sub-category grid uses (_subOf), so a
      // product with no sub-category — grouped under the 'General' tile —
      // is actually reachable when you drill into that tile. Comparing the
      // raw p.subCategory here dropped those products (they showed a count
      // but no products on drill-in).
      if (_subCategory != null && _subOf(p) != _subCategory) continue;
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

  // ----- Add product / categories -----------------------------------------

  /// Every category across the whole catalog (not just the drill scope),
  /// sorted A-Z. Feeds the "Category" suggestion menu in the add-product form.
  List<String> get _allCategories {
    final set = <String>{};
    for (final p in _all) {
      if (p.category.trim().isNotEmpty) set.add(p.category);
    }
    return set.toList()..sort();
  }

  /// Known sub-categories grouped by their parent category, each list
  /// sorted A-Z. Feeds the form's "Sub-category" suggestions, filtered to
  /// whatever category the user has entered.
  Map<String, List<String>> get _subsByCategory {
    final map = <String, Set<String>>{};
    for (final p in _all) {
      final sub = (p.subCategory ?? '').trim();
      if (sub.isEmpty) continue;
      map.putIfAbsent(p.category, () => <String>{}).add(sub);
    }
    return {
      for (final e in map.entries) e.key: (e.value.toList()..sort()),
    };
  }

  Future<void> _openAddProduct() async {
    if (_loading) return; // catalog still loading — _load() would overwrite it
    // Resolve the theme here — the context under this State is a descendant
    // of the AppTheme InheritedWidget, but the dialog route's own context is
    // not, so AppTheme.of() would fail inside the dialog. Pass it in instead.
    final theme = AppTheme.of(context);
    final created = await showDialog<Product>(
      context: context,
      builder: (_) => _AddProductDialog(
        categories: _allCategories,
        subsByCategory: _subsByCategory,
        theme: theme,
      ),
    );
    if (created == null || !mounted) return;
    setState(() {
      _all.add(created);
      // Drill straight to the product list for the new product's
      // category + sub-category bucket, so the product itself is on screen
      // right away instead of the user having to tap down two levels. Using
      // _subOf keeps null/empty sub-categories on the 'General' bucket that
      // the grids and the drill filter agree on.
      _category = created.category;
      _subCategory = _subOf(created);
      _focusedProduct = null;
      _level = _Level.products;
      _rebuildDrillCaches();
    });
    _persist();
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text('Added "${created.name}" to ${created.category}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ----- Bulk import (CSV / XLSX) -----------------------------------------

  Future<void> _openImport() async {
    if (_loading) return; // catalog still loading — _load() would overwrite it
    final theme = AppTheme.of(context);
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx'],
      withData: true, // load bytes directly — no path/permission dance
    );
    if (picked == null || picked.files.isEmpty) return; // cancelled
    final file = picked.files.first;
    final bytes = file.bytes;
    // file_picker can return a null extension for some Android content URIs —
    // fall back to the name's suffix so a valid .csv/.xlsx isn't rejected.
    final ext = (file.extension ??
            (file.name.contains('.') ? file.name.split('.').last : ''))
        .toLowerCase();
    if (bytes == null) {
      if (!mounted) return;
      _showImportResult(theme, fatal: 'Could not read the selected file.');
      return;
    }

    final report = CatalogImporter.parse(bytes: bytes, extension: ext);
    if (!mounted) return;

    if (report.fatal != null) {
      _showImportResult(theme, fatal: report.fatal);
      return;
    }

    // Merge by id: replace an existing product with the same id, else append.
    var added = 0, updated = 0;
    setState(() {
      for (final p in report.products) {
        final idx = _all.indexWhere((x) => x.id == p.id);
        if (idx >= 0) {
          _all[idx] = p;
          updated++;
        } else {
          _all.add(p);
          added++;
        }
      }
      // Drop back to the categories root so the freshly-imported catalog is
      // visible from the top rather than inside a stale drill scope.
      _category = null;
      _subCategory = null;
      _focusedProduct = null;
      _level = _Level.categories;
      _rebuildDrillCaches();
    });
    _persist();

    _showImportResult(
      theme,
      added: added,
      updated: updated,
      imagesMatched: report.imagesMatched,
      issues: report.issues,
    );
  }

  void _showImportResult(
    AppTheme theme, {
    String? fatal,
    int added = 0,
    int updated = 0,
    int imagesMatched = 0,
    List<String> issues = const [],
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.panelBg,
        title: Text(
          fatal != null ? 'Import failed' : 'Import complete',
          style: TextStyle(
            color: theme.panelText,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: SizedBox(
          width: 420,
          child: fatal != null
              ? Text(
                  fatal,
                  style: TextStyle(color: theme.panelText, fontSize: 14),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$added added · $updated updated'
                      '${imagesMatched > 0 ? ' · $imagesMatched image(s) matched' : ''}',
                      style: TextStyle(
                        color: theme.panelText,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (issues.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        '${issues.length} row(s) skipped:',
                        style: TextStyle(
                          color: theme.panelText,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final msg in issues)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    msg,
                                    style: TextStyle(
                                      color: theme.panelText
                                          .withValues(alpha: 0.8),
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE87722),
              foregroundColor: Colors.white,
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  // ----- Delete (long-press → confirm) ------------------------------------

  /// Sub-category bucket a product falls into — mirrors the grouping in
  /// _SubCategoriesGrid so a 'General' tile (products with no sub-category)
  /// deletes exactly the products that tile represents.
  String _subOf(Product p) =>
      (p.subCategory?.trim().isNotEmpty ?? false) ? p.subCategory! : 'General';

  /// Removes every product matching [test], refreshes caches, then walks the
  /// drill up out of any scope that just became empty so we never sit on a
  /// blank grid or a detail view for a deleted product.
  void _removeWhere(bool Function(Product) test) {
    if (!mounted) return;
    setState(() {
      _all.removeWhere(test);
      _persist();
      _rebuildDrillCaches();
      // Detail view whose product is gone → back to the products grid.
      if (_level == _Level.productDetail &&
          (_focusedProduct == null || !_all.contains(_focusedProduct))) {
        _focusedProduct = null;
        _level = _Level.products;
      }
      // Products grid emptied (last product in the sub gone) → up to subs.
      if (_level == _Level.products && _cachedInScope.isEmpty) {
        _subCategory = null;
        _level = _Level.subCategories;
        _rebuildDrillCaches();
      }
      // Sub grid emptied (category has no products left) → up to categories.
      if (_level == _Level.subCategories && _cachedInScope.isEmpty) {
        _category = null;
        _level = _Level.categories;
        _rebuildDrillCaches();
      }
    });
  }

  Future<bool> _confirmDelete(String title, String message) async {
    final theme = AppTheme.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.panelBg,
        title: Text(
          title,
          style: TextStyle(
            color: theme.panelText,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          message,
          style: TextStyle(color: theme.panelText, fontSize: 14, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(foregroundColor: theme.panelText),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _confirmDeleteCategory(String cat) async {
    final count = _all.where((p) => p.category == cat).length;
    final ok = await _confirmDelete(
      'Delete category',
      'Delete "$cat" and its $count product${count == 1 ? '' : 's'}?\n'
          'This cannot be undone.',
    );
    if (ok) _removeWhere((p) => p.category == cat);
  }

  Future<void> _confirmDeleteSubCategory(String sub) async {
    final cat = _category;
    if (cat == null) return;
    bool match(Product p) => p.category == cat && _subOf(p) == sub;
    final count = _all.where(match).length;
    final ok = await _confirmDelete(
      'Delete sub-category',
      'Delete "$sub" in $cat and its $count product${count == 1 ? '' : 's'}?\n'
          'This cannot be undone.',
    );
    if (ok) _removeWhere(match);
  }

  Future<void> _confirmDeleteProduct(Product p) async {
    final ok = await _confirmDelete(
      'Delete product',
      'Delete "${p.name}"?\nThis cannot be undone.',
    );
    if (ok) _removeWhere((x) => x.id == p.id);
  }

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
              child: FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add product'),
                onPressed: _loading ? null : _openAddProduct,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE87722),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.upload_file, size: 16),
                label: const Text('Import spreadsheet'),
                onPressed: _loading ? null : _openImport,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFE87722),
                  side: const BorderSide(color: Color(0xFFE87722)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            const SizedBox(height: 8),
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
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    switch (_level) {
      case _Level.categories:
        return _CategoriesGrid(
          products: _applyFilters(_productsInScope),
          onOpen: _drillIntoCategory,
          onDelete: _confirmDeleteCategory,
          scrollController: widget.scrollController,
        );
      case _Level.subCategories:
        return _SubCategoriesGrid(
          category: _category!,
          products: _applyFilters(_productsInScope),
          onOpen: _drillIntoSubCategory,
          onDelete: _confirmDeleteSubCategory,
          scrollController: widget.scrollController,
        );
      case _Level.products:
        final list = _applyFilters(_productsInScope).toList()
          ..sort(_compareByMode);
        return _ProductsGrid(
          products: list,
          onOpen: _drillIntoProduct,
          onDelete: _confirmDeleteProduct,
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
  final ValueChanged<String> onDelete;
  final ScrollController? scrollController;
  const _CategoriesGrid({
    required this.products,
    required this.onOpen,
    required this.onDelete,
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
          (p) =>
              (p.imageUrl ?? '').isNotEmpty ||
              (p.imageBytes?.isNotEmpty ?? false),
          orElse: () => e.value.first,
        );
        return _BrowseTile(
          title: e.key,
          subtitle: '${e.value.length} items',
          imageUrl: preview.imageUrl,
          imageBytes: preview.imageBytes,
          onTap: () => onOpen(e.key),
          onLongPress: () => onDelete(e.key),
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
  final ValueChanged<String> onDelete;
  final ScrollController? scrollController;
  const _SubCategoriesGrid({
    required this.category,
    required this.products,
    required this.onOpen,
    required this.onDelete,
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
          (p) =>
              (p.imageUrl ?? '').isNotEmpty ||
              (p.imageBytes?.isNotEmpty ?? false),
          orElse: () => e.value.first,
        );
        return _BrowseTile(
          title: e.key,
          subtitle: '${e.value.length} items',
          imageUrl: preview.imageUrl,
          imageBytes: preview.imageBytes,
          onTap: () => onOpen(e.key),
          onLongPress: () => onDelete(e.key),
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
  final ValueChanged<Product> onDelete;
  final ScrollController? scrollController;
  const _ProductsGrid({
    required this.products,
    required this.onOpen,
    required this.onDelete,
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
        return _ProductTile(
          product: p,
          onTap: () => onOpen(p),
          onLongPress: () => onDelete(p),
        );
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

/// Builds the image for a product/preview, preferring uploaded [bytes]
/// (Image.memory) over a remote [url] (Image.network), and falling back to
/// [fallback] when neither is usable or fails to load. Centralises the
/// bytes-vs-URL branch so every tile and the detail view render the same way.
Widget _productImage({
  Uint8List? bytes,
  String? url,
  required Widget fallback,
  int? cacheWidth,
  BoxFit fit = BoxFit.contain,
  FilterQuality quality = FilterQuality.low,
}) {
  if (bytes != null && bytes.isNotEmpty) {
    return Image.memory(
      bytes,
      fit: fit,
      cacheWidth: cacheWidth,
      filterQuality: quality,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
  if ((url ?? '').isNotEmpty) {
    return Image.network(
      url!,
      fit: fit,
      cacheWidth: cacheWidth,
      filterQuality: quality,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
  return fallback;
}

class _BrowseTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? imageUrl;
  final Uint8List? imageBytes;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _BrowseTile({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    this.imageBytes,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Material(
      color: t.panelBg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
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
                    // Downsample during decode — the tile only paints at
                    // ~180 dp; a bigger bitmap only wastes memory + decode
                    // time. Uploaded bytes win over a remote URL.
                    child: _productImage(
                      bytes: imageBytes,
                      url: imageUrl,
                      cacheWidth: 200,
                      fallback: Icon(
                        Icons.inventory_2_outlined,
                        size: 48,
                        color: t.cardSubtleText,
                      ),
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
  final VoidCallback? onLongPress;
  const _ProductTile({
    required this.product,
    required this.onTap,
    this.onLongPress,
  });

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
        onLongPress: onLongPress,
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
                    child: _productImage(
                      bytes: product.imageBytes,
                      url: product.imageUrl,
                      cacheWidth: 200,
                      fallback: Icon(
                        Icons.image_not_supported_outlined,
                        size: 40,
                        color: t.cardSubtleText,
                      ),
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
          Expanded(
            flex: 4,
            child: _DetailImage(
              imageUrl: product.imageUrl,
              imageBytes: product.imageBytes,
            ),
          ),
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
  final Uint8List? imageBytes;
  const _DetailImage({required this.imageUrl, this.imageBytes});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF3F3F3),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: _productImage(
        bytes: imageBytes,
        url: imageUrl,
        quality: FilterQuality.medium,
        fallback: const Icon(
          Icons.image_not_supported_outlined,
          size: 96,
          color: Color(0xFF888888),
        ),
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
        if ((product.specifications ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 18),
          Container(height: 1, color: const Color(0xFFEDEDED)),
          const SizedBox(height: 14),
          const Text(
            'SPECIFICATIONS',
            style: TextStyle(
              color: Color(0xFF888888),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          _SpecTable(raw: product.specifications!),
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

/// Renders a pasted spec block as an aligned table. Each non-empty line is a
/// row; a line is split into cells by tab, else by the first ':' (so
/// "Key: Value" lines work too), else it's a single spanning cell. The first
/// column is treated as the label and shown bold.
class _SpecTable extends StatelessWidget {
  final String raw;
  const _SpecTable({required this.raw});

  List<List<String>> _parse() {
    final rows = <List<String>>[];
    for (final line in raw.split(RegExp(r'\r?\n'))) {
      if (line.trim().isEmpty) continue;
      List<String> cells;
      if (line.contains('\t')) {
        cells = line.split('\t').map((c) => c.trim()).toList();
      } else if (line.contains(':')) {
        final idx = line.indexOf(':');
        cells = [
          line.substring(0, idx).trim(),
          line.substring(idx + 1).trim(),
        ];
      } else {
        cells = [line.trim()];
      }
      rows.add(cells);
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _parse();
    if (rows.isEmpty) return const SizedBox.shrink();
    final cols =
        rows.fold<int>(1, (m, r) => r.length > m ? r.length : m);
    const border = Color(0xFFEDEDED);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Table(
        border: const TableBorder(
          horizontalInside: BorderSide(color: border),
          verticalInside: BorderSide(color: border),
        ),
        columnWidths: cols == 2
            ? const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()}
            : null,
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          for (var i = 0; i < rows.length; i++)
            TableRow(
              decoration: BoxDecoration(
                color: i.isEven ? const Color(0xFFFAFAFA) : Colors.white,
              ),
              children: [
                for (var c = 0; c < cols; c++)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    child: Text(
                      c < rows[i].length ? rows[i][c] : '',
                      style: TextStyle(
                        color: const Color(0xFF444444),
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight:
                            c == 0 ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add-product form — opened as a modal dialog from the filter panel's
// "Add product" button. Lets the user type a brand-new category and/or
// sub-category (free text) OR pick an existing one from the suggestion
// menus. Returns the built Product via Navigator.pop, or null on cancel.
// This is an overlay: it does not touch the inventory panel/grid layout.
// ---------------------------------------------------------------------------

class _AddProductDialog extends StatefulWidget {
  final List<String> categories;
  final Map<String, List<String>> subsByCategory;

  /// Resolved by the caller — see _openAddProduct. Passed in rather than
  /// looked up via AppTheme.of(dialogContext), which would be null here.
  final AppTheme theme;
  const _AddProductDialog({
    required this.categories,
    required this.subsByCategory,
    required this.theme,
  });

  @override
  State<_AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<_AddProductDialog> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _category = TextEditingController();
  final _subCategory = TextEditingController();
  final _brand = TextEditingController();
  final _stock = TextEditingController();
  final _description = TextEditingController();
  final _specs = TextEditingController();
  final _imageUrl = TextEditingController();
  final _picker = ImagePicker();

  /// Bytes of an image uploaded from the device gallery. When set, this wins
  /// over any pasted URL both in the preview here and on the product tiles.
  Uint8List? _pickedBytes;
  String? _error;

  // Guards against stacking multiple discard prompts if the barrier is
  // tapped repeatedly while the warning is already up.
  bool _discardPromptOpen = false;

  // True while the photo picker is open — a second tap would throw
  // image_picker's "already_active" error, so we ignore re-entry.
  bool _picking = false;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _category.dispose();
    _subCategory.dispose();
    _brand.dispose();
    _stock.dispose();
    _description.dispose();
    _specs.dispose();
    _imageUrl.dispose();
    super.dispose();
  }

  /// Sub-category suggestions for whatever the user has typed as category,
  /// matched case-insensitively. Empty when the category is new/unknown.
  List<String> get _subOptions {
    final cat = _category.text.trim().toLowerCase();
    if (cat.isEmpty) return const [];
    for (final e in widget.subsByCategory.entries) {
      if (e.key.toLowerCase() == cat) return e.value;
    }
    return const [];
  }

  Future<void> _pickImage() async {
    if (_picking) return;
    _picking = true;
    try {
      // A form text field usually still holds keyboard focus when this is
      // tapped. Launching the photo picker while the soft keyboard is
      // mid-animation makes the picker flicker and fail to open on MIUI, so
      // drop focus and let the keyboard finish hiding first.
      FocusManager.instance.primaryFocus?.unfocus();
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() => _pickedBytes = bytes);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not load image: $e');
    } finally {
      _picking = false;
    }
  }

  void _submit() {
    final name = _name.text.trim();
    final category = _category.text.trim();
    final price = double.tryParse(_price.text.trim());
    if (name.isEmpty || category.isEmpty || price == null) {
      setState(() => _error =
          'Name, Category and a numeric Price are required.');
      return;
    }
    final sub = _subCategory.text.trim();
    final brand = _brand.text.trim();
    final desc = _description.text.trim();
    final specs = _specs.text.trim();
    final img = _imageUrl.text.trim();
    final stock = int.tryParse(_stock.text.trim());
    final id = 'USR-${DateTime.now().microsecondsSinceEpoch}';
    Navigator.of(context).pop(
      Product(
        id: id,
        name: name,
        price: price,
        category: category,
        subCategory: sub.isEmpty ? null : sub,
        brand: brand.isEmpty ? null : brand,
        description: desc.isEmpty ? null : desc,
        specifications: specs.isEmpty ? null : specs,
        stock: stock,
        imageUrl: img.isEmpty ? null : img,
        imageBytes: _pickedBytes,
      ),
    );
  }

  /// Shown when the form is dismissed by an accidental outside-tap or the
  /// system back button (not the explicit Cancel/Add buttons). "Continue"
  /// keeps the form exactly as-is with all entered data; "Exit" discards it
  /// and closes without saving.
  Future<void> _confirmDiscard() async {
    if (_discardPromptOpen) return;
    _discardPromptOpen = true;
    final t = widget.theme;
    final exit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.panelBg,
        title: Text(
          'Discard new product?',
          style: TextStyle(
            color: t.panelText,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          'Your entered details will be lost if you exit.\n'
          'Continue editing, or exit without saving?',
          style: TextStyle(color: t.panelText, fontSize: 14, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false), // keep editing
            style: TextButton.styleFrom(foregroundColor: t.panelText),
            child: const Text('Continue'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true), // discard + close
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
              foregroundColor: Colors.white,
            ),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    _discardPromptOpen = false;
    if (exit == true && mounted) {
      Navigator.of(context).pop(); // close the add form, returning no product
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        // Barrier tap or system back tried to close the form — intercept and
        // confirm instead of silently losing what's been typed.
        if (!didPop) _confirmDiscard();
      },
      child: AlertDialog(
        backgroundColor: t.panelBg,
        title: Text(
          'Add product',
        style: TextStyle(
          color: t.panelText,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fieldLabel('NAME *'),
              _plainField(_name, 'Product name'),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fieldLabel('PRICE (₹) *'),
                        _plainField(_price, '0',
                            keyboard: TextInputType.number),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fieldLabel('STOCK'),
                        _plainField(_stock, '0',
                            keyboard: TextInputType.number),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _fieldLabel('CATEGORY *'),
              _ComboField(
                controller: _category,
                hint: 'Pick or type a new category',
                options: widget.categories,
                // Re-typing/clearing the category changes which sub-category
                // suggestions apply, so refresh the menu.
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 12),
              _fieldLabel('SUB-CATEGORY'),
              _ComboField(
                controller: _subCategory,
                hint: 'Pick or type a new sub-category',
                options: _subOptions,
              ),
              const SizedBox(height: 12),
              _fieldLabel('BRAND'),
              _plainField(_brand, 'Brand (optional)'),
              const SizedBox(height: 12),
              _fieldLabel('IMAGE'),
              _imagePicker(),
              const SizedBox(height: 8),
              _plainField(_imageUrl, 'or paste an image URL (https://)'),
              const SizedBox(height: 12),
              _fieldLabel('DESCRIPTION'),
              _plainField(_description, 'Optional', maxLines: 3),
              const SizedBox(height: 12),
              _fieldLabel('SPECIFICATIONS'),
              _plainField(
                _specs,
                'Paste rows from Excel, or "Key: Value" per line',
                maxLines: 5,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFC62828),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: t.panelText,
          ),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFE87722),
            foregroundColor: Colors.white,
          ),
          child: const Text('Add'),
        ),
      ],
      ),
    );
  }

  Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: widget.theme.panelText.withValues(alpha: 0.6),
          ),
        ),
      );

  /// Upload row: a thumbnail of the picked image (or a placeholder) beside
  /// an "Upload from device" button. When an image is picked the button
  /// becomes "Replace" and a "Remove" text button appears.
  Widget _imagePicker() {
    final has = _pickedBytes != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
          ),
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          child: has
              ? Image.memory(_pickedBytes!, fit: BoxFit.cover,
                  width: 56, height: 56)
              : const Icon(Icons.image_outlined,
                  size: 24, color: Color(0xFF888888)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _pickImage,
            icon: Icon(has ? Icons.swap_horiz : Icons.upload, size: 16),
            label: Text(has ? 'Replace' : 'Upload from device'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF2E2E2E),
              side: const BorderSide(color: Color(0xFF888888)),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        if (has) ...[
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => setState(() => _pickedBytes = null),
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Remove image',
            color: const Color(0xFFC62828),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ],
    );
  }

  Widget _plainField(
    TextEditingController c,
    String hint, {
    TextInputType? keyboard,
    int maxLines = 1,
  }) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 13, color: Color(0xFF2E2E2E)),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
    );
  }
}

/// Text field with a dropdown-arrow menu of existing [options]. Typing is
/// always allowed (so a brand-new category/sub can be entered); picking a
/// menu item just fills the field. [onChanged] fires on both paths.
class _ComboField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final List<String> options;
  final VoidCallback? onChanged;
  const _ComboField({
    required this.controller,
    required this.hint,
    required this.options,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: (_) => onChanged?.call(),
      style: const TextStyle(fontSize: 13, color: Color(0xFF2E2E2E)),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        suffixIcon: options.isEmpty
            ? null
            : PopupMenuButton<String>(
                icon: const Icon(Icons.arrow_drop_down,
                    color: Color(0xFF888888)),
                tooltip: 'Existing',
                onSelected: (v) {
                  controller.text = v;
                  controller.selection = TextSelection.collapsed(
                    offset: v.length,
                  );
                  onChanged?.call();
                },
                itemBuilder: (_) => [
                  for (final o in options)
                    PopupMenuItem<String>(
                      value: o,
                      child: Text(o, style: const TextStyle(fontSize: 13)),
                    ),
                ],
              ),
      ),
    );
  }
}
