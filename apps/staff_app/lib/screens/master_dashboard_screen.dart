import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:clone_pos_widgets/clone_pos_widgets.dart';
import 'inventory_opened_view.dart';

/// ============================================================================
/// MASTER DASHBOARD — Figma nodes 133:229 (landing) + Active-Carts opened.
///
/// 1280×800 landscape canvas. Coords match the Figma frame exactly.
///
/// TWO STATES:
///   Landing         — 8 gray tiles in a 4×2 grid, selected tile shows
///                     a blue border. Sun icon top-right.
///   Opened (tile N) — column 1 (tiles at positions [0] and [4])
///                     MERGES into one tall cell showing the opened
///                     tile's content (e.g. "ACTIVE CARTS / 26"). The
///                     other 6 tiles remain as empty gray placeholders.
///                     Green Active-Clones badge appears on left flank,
///                     menu_open + chevron_backward appear on right.
///                     Inventory tile is special-cased: its merged
///                     content is the interactive InventoryBrowser.
///
/// Selection cue is the blue border ONLY — rails are static visuals.
/// Rails act as scroll-wheel input via full-height invisible gesture
/// strips overlaying the flanks.
/// ============================================================================

const double kMasterCanvasWidth = 1280;
const double kMasterCanvasHeight = 800;

// Tile geometry — from Figma node 133:229.
const double _tileW = 250;
const double _tileH = 349;
const double _tileGap = 2;
const double _gridLeft = 138;
const double _gridTop = 50;
const double _tileRadius = 10;
const Color _tileFill = Color(0xFFD9D9D9);

// Selection border on the highlighted tile.
const Color _selectionBlue = Color(0xFF3AA0FF);
const double _selectionBorderWidth = 3;

// Rail geometry — 30 × 300 per client. Bottom stays anchored to the
// grid bottom (y = 750); the top sits 300 px above that, at y = 450.
//   grid bottom = _gridTop + tileH*2 + tileGap = 750
//   rail top    = 750 - 300 = 450
// Gesture zone hugs the visible rail with a small comfort pad and
// never extends beyond it.
const double _railLeftX = 82;
const double _railRightX = 1196;
const double _railW = 30;
const double _railH = 300;
const double _railTop = _gridTop + (_tileH * 2 + _tileGap) - _railH; // 450
const double _railTouchPad = 8;

// Sun icon.
const double _sunX = 1181;
const double _sunY = 122;
const double _sunSize = 45;

// ============================================================================
// OPENED-STATE GEOMETRY — Figma nodes 369:158 (default) & 369:184 (settings).
// The template supports TWO layouts driven by a Settings toggle on the
// right-flank top badge:
//
//   DEFAULT (Image 1, node 369:158)
//   ────────────────────────────────
//   [L flank] [SUMMARY]  [tile 1] [tile 2] [tile 3]  [R flank]
//             [ Inventory]  ..              ..
//             [ Cats&Subs]  [tile 4] [tile 5] [tile 6]
//
//   SETTINGS ON (Image 2, node 369:184)
//   ────────────────────────────────
//   [L flank] [tile 1] [tile 2] [tile 3] [SUMMARY]  [R flank]
//              ..                        [Settings]
//             [tile 4] [tile 5] [tile 6] [Cats&Subs]
//
// The summary column and tile grid swap sides; everything else is fixed.
// ============================================================================

// Flank columns — 115 wide, symmetric on each side.
const double _oLeftColX = 20;
const double _oRightColX = 1145;
const double _oFlankW = 115;
const double _oFlankH = 115;
const double _oFlankTopY = 34;
const double _oFlankGap = 2;
// Second flank badge lands at y = _oFlankTopY + _oFlankH + _oFlankGap = 151.
const double _oFlankSecondY = _oFlankTopY + _oFlankH + _oFlankGap;

// Central content area — from the LEFT flank's right edge to the RIGHT
// flank's left edge. All summary-column and tile-grid coords live inside
// this rectangle regardless of which side the summary is on.
const double _oCentralStartX = 137;
const double _oCentralEndX = 1143; // 893 (summary right edge cap) + 250

// Summary column geometry — 250 wide, title cell (115 tall) + gap +
// big cell (585 tall). Its X flips based on `_settingsMode`.
const double _oSummaryLeftX = 137; // default (Image 1)
const double _oSummaryRightX = 893; // settings mode (Image 2)
const double _oTileW = 250;
const double _oTileH = 350;
const double _oGridGap = 2;
const double _oSummaryTopY = _oFlankTopY;
const double _oSummaryTopH = 115;
const double _oSummaryBigY = _oSummaryTopY + _oSummaryTopH + _oGridGap;
const double _oSummaryBigH = 585;

// 3×2 tile grid — 3 cols × 250w, 2 rows × 350h at y=34/386. Its start X
// flips: when summary is on the LEFT the tiles start at x=389; when the
// summary is on the RIGHT the tiles start at x=137.
const double _oTileGridDefaultX = 389; // summary on LEFT (Image 1)
const double _oTileGridSettingsX = 137; // summary on RIGHT (Image 2)
const double _oGridStartY = _oFlankTopY;

// Rails in opened state — bar height unchanged (300), y=344.
const double _oRailTop = 344;

// Chevron_back in opened state (70×70 white glyph, bottom-right area).
const double _oChevronX = 1172;
const double _oChevronY = 668;
const double _oChevronSize = 70;

// Fill colors used by the flank badges.
const Color _oCartsOrange = Color(0xFFE87722);
const Color _oClonesGreen = Color(0xFF2ECC71);

class MenuTile {
  final String label;
  final IconData icon;
  const MenuTile({required this.label, required this.icon});
}

class MasterDashboardScreen extends StatefulWidget {
  const MasterDashboardScreen({super.key});

  @override
  State<MasterDashboardScreen> createState() => _MasterDashboardScreenState();
}

class _MasterDashboardScreenState extends State<MasterDashboardScreen> {
  int _selectedIndex = 0;
  int? _openedIndex;

  /// One of the 6 right-tile slots the user tapped inside the opened
  /// tab (1..6). null = the tab is on its landing grid; non-null = the
  /// in-place sub-detail panel is shown covering the whole tile grid.
  int? _openSubIndex;
  bool _sunMenuOpen = false;
  bool _darkMode = true;

  /// Settings-mode toggle on the opened-tab layout. Off (default) →
  /// summary column on the LEFT (Image 1). On → summary column moves
  /// to the RIGHT and its title becomes "SETTINGS" (Image 2). Tap the
  /// right-flank top badge to toggle. Resets when the tab closes.
  bool _settingsMode = false;

  // Universal rail scroll controllers — live for the whole opened
  // session. LEFT rail = horizontal, RIGHT rail = vertical. Tabs that
  // have scrollable content attach their ScrollView to whichever
  // controller matches its axis; tabs without scrollable content
  // leave both controllers unattached and the rails idle harmlessly.
  //
  // Inventory-specific: LEFT rail scrolls the filter panel (attached
  // inside InventoryOpenedView via filterScrollController), RIGHT rail
  // scrolls the tile grid.
  final ScrollController _leftRailHorizontalCtrl = ScrollController();
  final ScrollController _rightRailVerticalCtrl = ScrollController();

  // Reference the currently-mounted InventoryOpenedView so the shared
  // chevron_back can drill up through its category/sub/product/detail
  // levels one step at a time. Null when Inventory isn't open.
  final GlobalKey<InventoryOpenedViewState> _inventoryKey =
      GlobalKey<InventoryOpenedViewState>();

  @override
  void dispose() {
    _leftRailHorizontalCtrl.dispose();
    _rightRailVerticalCtrl.dispose();
    super.dispose();
  }

  // Placeholder metrics — wire to real repositories later.
  int activeCarts = 26;
  int activeClones = 4;
  int totalClones = 6;

  // Ordered per client brief:
  //   row 1: [0][1][2][3], row 2: [4][5][6][7].
  // Material Symbols variants — variable-weight so the Icon widget's
  // `weight` parameter can dial stroke thickness. Rendered on the
  // landing tiles at weight 200 for a lighter feel per client.
  static const List<MenuTile> _tiles = [
    MenuTile(label: 'Active Carts', icon: Symbols.shopping_cart),
    MenuTile(label: 'Active Clones', icon: Symbols.devices_other),
    MenuTile(label: 'Inventory', icon: Symbols.inventory_2),
    MenuTile(label: 'Logistics', icon: Symbols.local_shipping),
    MenuTile(label: 'Analytics', icon: Symbols.bar_chart),
    MenuTile(label: 'Accounts', icon: Symbols.receipt_long),
    MenuTile(label: 'Sales Kit', icon: Symbols.slideshow),
    MenuTile(label: 'Data', icon: Symbols.database),
  ];

  bool get _isOpened => _openedIndex != null;

  void _selectTile(int i) {
    if (i != _selectedIndex) setState(() => _selectedIndex = i);
  }

  void _openTile(int i) {
    setState(() {
      _selectedIndex = i;
      _openedIndex = i;
      _openSubIndex = null;
      _settingsMode = false;
    });
  }

  /// Right-flank top badge — swaps the summary column side and its
  /// title. Persists until the user toggles again or closes the tab.
  void _toggleSettingsMode() => setState(() => _settingsMode = !_settingsMode);

  /// Right-flank back button. Pops one level at a time:
  ///   - if a sub-detail panel is up, close it → back to the tile grid
  ///   - else if Inventory is open and can drill up internally
  ///     (productDetail → products → subs → categories), do that
  ///   - else if a tab is opened, close it → back to landing
  ///   - else nothing to do
  void _handleBack() {
    if (_openSubIndex != null) {
      setState(() => _openSubIndex = null);
      return;
    }
    if (_openedIndex == null) return;

    // Inventory owns an internal drill stack; let it consume the back
    // before we collapse the whole tab. maybePop returns false only
    // when it's already at the categories root.
    if (_tiles[_openedIndex!].label == 'Inventory' &&
        (_inventoryKey.currentState?.maybePop() ?? false)) {
      return;
    }
    setState(() => _openedIndex = null);
  }

  void _closeOpened() {
    if (_openedIndex != null) {
      setState(() {
        _openedIndex = null;
        _openSubIndex = null;
        _settingsMode = false;
      });
    }
  }

  void _toggleSunMenu() => setState(() => _sunMenuOpen = !_sunMenuOpen);

  @override
  Widget build(BuildContext context) {
    // Responsive shell: the design lives inside a fixed 1280×800
    // canvas scaled to fit the device via FittedBox (preserves the
    // design aspect — no distortion). The mesh backdrop sits OUTSIDE
    // that canvas so it fills the entire device on any aspect ratio;
    // on iPad Pro 13" (~4:3) the extra space above/below the design
    // canvas is now the gradient continuing rather than a black bar.
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          const Positioned.fill(child: _MeshBackdrop()),
          Center(
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: kMasterCanvasWidth,
                height: kMasterCanvasHeight,
                child: Stack(
                  children: [
                    // Backdrop moved out to the device-fill layer above;
                    // the design stack no longer draws its own so the
                    // rails/tiles composite directly onto the shared
                    // gradient.

                    // Central content — landing 4x2 grid, or the new opened
                    // template (flank badges + title column + 6 right tiles).
                    if (_isOpened)
                      ..._buildOpenedLayout()
                    else
                      ..._buildTiles(),

                    // Visible L-hook rails. Position moves for opened state
                    // so the chevron_back can sit below without overlap.
                    //
                    // No scrollController here on purpose: the dot must stay
                    // parked at the hook tip regardless of scroll. Wiring it
                    // to the inner pane's scroll caused (a) the dot sliding
                    // down while browsing, and (b) a setState on every scroll
                    // pixel — the biggest source of scroll lag on the tablet.
                    // The invisible gesture zones below still take the
                    // controllers, so finger-drag on the rail still scrolls
                    // the pane.
                    Positioned(
                      left: _railLeftX,
                      top: _isOpened ? _oRailTop : _railTop,
                      width: _railW,
                      height: _railH,
                      child: const IgnorePointer(
                        child: FlankRail(
                          itemCount: 8,
                          side: RailSide.left,
                          showVisual: true,
                        ),
                      ),
                    ),
                    Positioned(
                      left: _railRightX,
                      top: _isOpened ? _oRailTop : _railTop,
                      width: _railW,
                      height: _railH,
                      child: const IgnorePointer(
                        child: FlankRail(
                          itemCount: 8,
                          side: RailSide.right,
                          showVisual: true,
                        ),
                      ),
                    ),

                    // Invisible flank gesture zones — LANDING ONLY.
                    // Vertical drag → step selection; horizontal → open.
                    if (!_isOpened) ...[
                      Positioned(
                        left: _railLeftX - _railTouchPad,
                        top: _railTop - _railTouchPad,
                        width: _railW + _railTouchPad * 2,
                        height: _railH + _railTouchPad * 2,
                        child: FlankRail(
                          itemCount: _tiles.length,
                          side: RailSide.left,
                          selectedIndex: _selectedIndex,
                          showVisual: false,
                          onSelected: _selectTile,
                          onSwipeOpen: _openTile,
                        ),
                      ),
                      Positioned(
                        left: _railRightX - _railTouchPad,
                        top: _railTop - _railTouchPad,
                        width: _railW + _railTouchPad * 2,
                        height: _railH + _railTouchPad * 2,
                        child: FlankRail(
                          itemCount: _tiles.length,
                          side: RailSide.right,
                          selectedIndex: _selectedIndex,
                          showVisual: false,
                          onSelected: _selectTile,
                          onSwipeOpen: _openTile,
                        ),
                      ),
                    ],

                    // Invisible flank gesture zones — ANY OPENED TAB
                    // (except while a sub-detail panel is up). Universal
                    // scroller roles per client:
                    //   LEFT rail  → horizontal scroll controller
                    //   RIGHT rail → vertical scroll controller
                    // Rails render on every feature page; when the current
                    // tab has nothing attached to a controller the rail is
                    // safely idle (FlankRail bails on !hasClients).
                    if (_isOpened && _openSubIndex == null) ...[
                      Positioned(
                        left: _railLeftX - _railTouchPad,
                        top: _oRailTop - _railTouchPad,
                        width: _railW + _railTouchPad * 2,
                        height: _railH + _railTouchPad * 2,
                        child: FlankRail(
                          itemCount: _tiles.length,
                          side: RailSide.left,
                          showVisual: false,
                          scrollController: _leftRailHorizontalCtrl,
                        ),
                      ),
                      Positioned(
                        left: _railRightX - _railTouchPad,
                        top: _oRailTop - _railTouchPad,
                        width: _railW + _railTouchPad * 2,
                        height: _railH + _railTouchPad * 2,
                        child: FlankRail(
                          itemCount: _tiles.length,
                          side: RailSide.right,
                          showVisual: false,
                          scrollController: _rightRailVerticalCtrl,
                        ),
                      ),
                    ],

                    // Sun icon — LANDING ONLY. In opened state the sun sits
                    // inside an orange flank badge (built by _buildOpenedLayout).
                    if (!_isOpened)
                      Positioned(
                        left: _sunX,
                        top: _sunY,
                        width: _sunSize,
                        height: _sunSize,
                        child: _SunButton(
                          active: _sunMenuOpen,
                          onTap: _toggleSunMenu,
                        ),
                      ),

                    // In-place sub-detail panel — fills the entire central
                    // rectangle (tile grid + summary column) when the user
                    // tapped one of the 6 tiles.
                    if (_isOpened && _openSubIndex != null)
                      Positioned(
                        left: _oCentralStartX,
                        top: _oFlankTopY,
                        width: _oCentralEndX - _oCentralStartX,
                        height: _oTileH * 2 + _oGridGap,
                        child: _SubDetailPanel(
                          title: _subDetailTitle(),
                        ),
                      ),

                    // Sun popover. Anchors under the sun in landing, or
                    // under the orange sun-badge in opened state.
                    if (_sunMenuOpen)
                      Positioned(
                        top: _isOpened
                            ? _oFlankTopY + _oFlankH + 8
                            : _sunY + _sunSize + 8,
                        left: _isOpened ? _oRightColX - 60 : _sunX - 140,
                        child: _SunMenu(
                          darkMode: _darkMode,
                          onDismiss: _toggleSunMenu,
                          onToggleTheme: () => setState(() {
                            _darkMode = !_darkMode;
                            _sunMenuOpen = false;
                          }),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build the entire opened-tab layout, honoring `_settingsMode`.
  ///
  /// Off (default): summary column on the LEFT, tile grid on the right.
  /// On:            tile grid on the LEFT, summary column on the right;
  ///                summary title becomes "SETTINGS".
  ///
  /// Inventory is special-cased: its InventoryOpenedView owns the whole
  /// central rectangle and reads `settingsMode` to flip its own layout.
  List<Widget> _buildOpenedLayout() {
    final openedLabel = _tiles[_openedIndex!].label;
    final isInventory = openedLabel == 'Inventory';

    const centralW = _oCentralEndX - _oCentralStartX;
    const centralH = _oTileH * 2 + _oGridGap;

    final summaryX = _settingsMode ? _oSummaryRightX : _oSummaryLeftX;
    final tileGridX = _settingsMode ? _oTileGridSettingsX : _oTileGridDefaultX;
    final summaryTitle = _settingsMode ? 'SETTINGS' : openedLabel.toUpperCase();

    return [
      // ─── LEFT FLANK ─── ACTIVE CARTS + ACTIVE CLONES badges.
      Positioned(
        left: _oLeftColX,
        top: _oFlankTopY,
        width: _oFlankW,
        height: _oFlankH,
        child: _OpenedValueBadge(
          color: _oCartsOrange,
          label: 'ACTIVE\nCARTS',
          value: '$activeCarts',
        ),
      ),
      Positioned(
        left: _oLeftColX,
        top: _oFlankSecondY,
        width: _oFlankW,
        height: _oFlankH,
        child: _OpenedValueBadge(
          color: _oClonesGreen,
          label: 'ACTIVE\nCLONES',
          value: '$activeClones',
        ),
      ),

      // ─── CENTRAL CONTENT ─── Inventory browser, or template.
      if (isInventory)
        Positioned(
          left: _oCentralStartX,
          top: _oFlankTopY,
          width: centralW,
          height: centralH,
          child: InventoryOpenedView(
            key: _inventoryKey,
            settingsMode: _settingsMode,
            scrollController: _rightRailVerticalCtrl,
            filterScrollController: _leftRailHorizontalCtrl,
          ),
        )
      else ...[
        // 3×2 tile grid — position depends on settingsMode.
        ..._buildOpenedTileGrid(openedLabel, tileGridX),

        // Summary column — position and title depend on settingsMode.
        Positioned(
          left: summaryX,
          top: _oSummaryTopY,
          width: _oTileW,
          height: _oSummaryTopH,
          child: _OpenedTitleCell(title: summaryTitle),
        ),
        Positioned(
          left: summaryX,
          top: _oSummaryBigY,
          width: _oTileW,
          height: _oSummaryBigH,
          child: const _OpenedPlaceholderCell(),
        ),
      ],

      // ─── RIGHT FLANK ─── Top badge is the SETTINGS toggle; bottom
      // stays as menu_open to close the tab.
      Positioned(
        left: _oRightColX,
        top: _oFlankTopY,
        width: _oFlankW,
        height: _oFlankH,
        child: _SettingsBadge(
          active: _settingsMode,
          onTap: _toggleSettingsMode,
        ),
      ),
      Positioned(
        left: _oRightColX,
        top: _oFlankSecondY,
        width: _oFlankW,
        height: _oFlankH,
        child: _OpenedIconBadge(
          icon: Icons.menu_open,
          onTap: _closeOpened,
        ),
      ),

      // ─── CHEVRON BACK ─── 70×70 white glyph, sits below the rail.
      Positioned(
        left: _oChevronX,
        top: _oChevronY,
        width: _oChevronSize,
        height: _oChevronSize,
        child: _OpenedChevronBack(onTap: _handleBack),
      ),
    ];
  }

  /// 3×2 tile grid — 3 columns × 2 rows of 250×350 tiles starting at
  /// `startX`. Labels come from _rightTileLabelsFor; tabs without them
  /// (e.g. Sales Kit) render as blank gray placeholders.
  List<Widget> _buildOpenedTileGrid(String openedLabel, double startX) {
    final labels = _rightTileLabelsFor(openedLabel);
    final widgets = <Widget>[];
    for (var i = 0; i < 6; i++) {
      final col = i % 3;
      final row = i ~/ 3;
      final x = startX + col * (_oTileW + _oGridGap);
      final y = _oGridStartY + row * (_oTileH + _oGridGap);
      widgets.add(Positioned(
        left: x,
        top: y,
        width: _oTileW,
        height: _oTileH,
        child: labels != null
            ? _LabelledTile(
                label: labels[i],
                onTap: () => setState(() => _openSubIndex = i + 1),
              )
            : const _BlankTile(),
      ));
    }
    return widgets;
  }

  /// Build the LANDING tile grid — 4×2 of menu tiles. The opened
  /// state uses _buildOpenedLayout() instead, so this method assumes
  /// !_isOpened when called from build().
  List<Widget> _buildTiles() {
    final widgets = <Widget>[];
    for (var i = 0; i < _tiles.length; i++) {
      final col = i % 4;
      final row = i ~/ 4;
      final x = _gridLeft + col * (_tileW + _tileGap);
      final y = _gridTop + row * (_tileH + _tileGap);
      widgets.add(Positioned(
        left: x,
        top: y,
        width: _tileW,
        height: _tileH,
        child: _MenuTileCell(
          tile: _tiles[i],
          selected: i == _selectedIndex,
          onTap: () => _openTile(i),
        ),
      ));
    }
    return widgets;
  }

  /// Returns the 6 right-tile labels for a given opened tab, or null
  /// when the tab renders empty gray placeholders. Order is row-major
  /// (top-left → top-right, then bottom-left → bottom-right).
  ///
  /// Logistics categories are the ones a medium-size enterprise
  /// actually operates day-to-day: inbound stock, outbound orders,
  /// live in-transit view, returns/RTO, fleet & drivers, supplier POs.
  List<String>? _rightTileLabelsFor(String openedLabel) {
    switch (openedLabel) {
      case 'Active Carts':
        return const [
          'Cart 1',
          'Cart 2',
          'Cart 3',
          'Cart 4',
          'Cart 5',
          'Cart 6'
        ];
      case 'Active Clones':
        return const [
          'Clone 1',
          'Clone 2',
          'Clone 3',
          'Clone 4',
          'Clone 5',
          'Clone 6'
        ];
      case 'Logistics':
        return const [
          'Inbound', // supplier deliveries landing at the warehouse
          'Outbound', // orders leaving to customers
          'In Transit', // active shipments on the road
          'Returns', // RTO + customer-initiated returns
          'Fleet', // vehicles + drivers status
          'Suppliers', // open POs + supplier contact
        ];
      case 'Analytics':
        return const [
          'Sales', // revenue trend — day / week / month
          'Top Sellers', // best-performing SKUs and categories
          'Slow Movers', // inventory ageing / underperforming SKUs
          'Customers', // repeat rate, tier distribution, lifetime value
          'Staff', // per-cashier throughput and conversion
          'Peak Hours', // footfall heatmap and busiest windows
        ];
      case 'Accounts':
        return const [
          'Invoices', // customer invoices issued
          'Payments', // money received (UPI, card, cash, bank)
          'Refunds', // money out — refunds against returns
          'Taxes', // GST returns and tax filings
          'Expenses', // rent, utilities, wages, other opex
          'Ledger', // general ledger + journal entries
        ];
      case 'Data':
        return const [
          'Customers', // customer master + contact directory
          'Employees', // staff/user master, roles, permissions
          'Suppliers', // vendor master + contract terms
          'Documents', // uploaded PDFs, invoices, receipts
          'Exports', // CSV / Excel data exports
          'Backups', // backup + restore operations
        ];
      default:
        return null;
    }
  }

  /// Compose the sub-detail title from the currently opened tab and
  /// the tapped slot. e.g. Active Carts + slot 3 → "Cart 3".
  String _subDetailTitle() {
    if (_openedIndex == null || _openSubIndex == null) return '';
    final openedLabel = _tiles[_openedIndex!].label;
    final labels = _rightTileLabelsFor(openedLabel);
    if (labels == null) return '';
    return labels[_openSubIndex! - 1];
  }
}

// ---------------------------------------------------------------------------
// Blank gray placeholder tile — used when an opened tab has no content
// yet (e.g. Sales Kit). Non-interactive.
// ---------------------------------------------------------------------------

class _BlankTile extends StatelessWidget {
  const _BlankTile();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _tileFill,
        borderRadius: BorderRadius.circular(_tileRadius),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Minimal labelled tile — used for "Cart N" (Active Carts opened) and
// "Clone N" (Active Clones opened). Pass a null [onTap] for a tile
// that renders but doesn't react to taps (used by Clones for now).
// ---------------------------------------------------------------------------

class _LabelledTile extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _LabelledTile({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _tileFill,
      borderRadius: BorderRadius.circular(_tileRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_tileRadius),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF2E2E2E),
              fontSize: 30,
              fontWeight: FontWeight.w400,
              letterSpacing: -0.6,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// In-place sub-detail panel — fills the tile-grid rectangle when the
// user drills into one of an opened tab's 6 right-tiles.
//
// No close button here: the right-flank chevron already pops sub-detail
// → tile grid → landing one step at a time.
// ---------------------------------------------------------------------------

class _SubDetailPanel extends StatelessWidget {
  final String title;
  const _SubDetailPanel({required this.title});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(_tileRadius),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
            color: const Color(0xFFF3F3F3),
            child: Text(
              title,
              style: const TextStyle(
                color: Color(0xFF2E2E2E),
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Expanded(child: SizedBox()),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mesh backdrop — dark base + heavily-blurred coloured blobs.
// ---------------------------------------------------------------------------

class _MeshBackdrop extends StatelessWidget {
  const _MeshBackdrop();

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary is load-bearing here: the blob blurs are
    // 120-sigma over a 1280×800 canvas, cripplingly expensive to
    // recomposite each frame. Without this, every scroll pixel in
    // the inventory grid re-rasters the entire backdrop. Isolating
    // it lets Flutter cache the layer and re-use it verbatim.
    return RepaintBoundary(
      child: Stack(
        children: [
          const Positioned.fill(
            child: ColoredBox(color: Color(0xFF1A1A1A)),
          ),
          _blob(top: -80, left: -60, size: 620, color: const Color(0xFF1E5B3E)),
          _blob(
              top: -100, right: -80, size: 500, color: const Color(0xFF0F5555)),
          _blob(
              bottom: -80,
              left: -60,
              size: 520,
              color: const Color(0xFF6E5820)),
          _blob(
              bottom: -100,
              right: -80,
              size: 600,
              color: const Color(0xFF6A2A3A)),
          _blob(top: 300, left: 400, size: 500, color: const Color(0xFF3A2A5A)),
        ],
      ),
    );
  }

  Widget _blob({
    double? top,
    double? left,
    double? right,
    double? bottom,
    required double size,
    required Color color,
  }) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: IgnorePointer(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 120, sigmaY: 120),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  color.withValues(alpha: 0.9),
                  color.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 1.0],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Landing tile (empty gray + optional blue border on selection).
// ---------------------------------------------------------------------------

class _MenuTileCell extends StatelessWidget {
  final MenuTile tile;
  final bool selected;
  final VoidCallback onTap;
  const _MenuTileCell({
    required this.tile,
    required this.selected,
    required this.onTap,
  });

  // Icon side = 20% of the tile width per client brief (0.20 * 250 = 50).
  static const double _iconSize = _tileW * 0.20;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _tileFill,
      borderRadius: BorderRadius.circular(_tileRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_tileRadius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_tileRadius),
            border: Border.all(
              color: selected ? _selectionBlue : Colors.transparent,
              width: _selectionBorderWidth,
            ),
          ),
          child: Center(
            child: Icon(
              tile.icon,
              size: _iconSize,
              weight: 200, // thin stroke — Material Symbols variable weight
              color: const Color(0xFF2E2E2E),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Icons.
// ---------------------------------------------------------------------------

class _SunButton extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const _SunButton({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_sunSize / 2),
        child: Icon(
          Icons.wb_sunny_outlined,
          size: 30,
          color: active ? const Color(0xFFFFB84B) : Colors.white,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sun popover — Light/Dark, Chime, Language, Logout.
// ---------------------------------------------------------------------------

class _SunMenu extends StatelessWidget {
  final bool darkMode;
  final VoidCallback onDismiss;
  final VoidCallback onToggleTheme;

  const _SunMenu({
    required this.darkMode,
    required this.onDismiss,
    required this.onToggleTheme,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 12,
      color: const Color(0xFF232323),
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 200,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SunMenuRow(
              icon: darkMode
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
              label: darkMode ? 'Light mode' : 'Dark mode',
              onTap: onToggleTheme,
            ),
            _SunMenuRow(
              icon: Icons.notifications_active_outlined,
              label: 'Chime',
              onTap: onDismiss,
            ),
            _SunMenuRow(
              icon: Icons.translate_outlined,
              label: 'Language',
              onTap: onDismiss,
            ),
            const Divider(color: Color(0xFF3A3A3A), height: 1),
            _SunMenuRow(
              icon: Icons.logout_outlined,
              label: 'Logout',
              onTap: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

class _SunMenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SunMenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// NEW OPENED-STATE WIDGETS — from Figma node 325:64 area.
// ============================================================================

/// Orange or green rounded-square flank badge — 115×115 — housing the
/// stacked label (e.g. "ACTIVE\nCARTS") and the big number below it.
class _OpenedValueBadge extends StatelessWidget {
  final Color color;
  final String label;
  final String value;
  const _OpenedValueBadge({
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(_tileRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
                height: 1.15,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 42,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Orange rounded-square icon badge — 115×115 — houses a single icon
/// (light_mode or menu_open) centred inside. Tap-through via [onTap].
class _OpenedIconBadge extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _OpenedIconBadge({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _oCartsOrange,
      borderRadius: BorderRadius.circular(_tileRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_tileRadius),
        child: Center(
          child: Icon(icon, size: 46, color: Colors.white),
        ),
      ),
    );
  }
}

/// Right-flank TOP badge — 115×115 rounded square labelled "Settings".
/// Toggles the whole opened-state layout between Image 1 (summary col
/// on the left) and Image 2 (summary col on the right, title becomes
/// SETTINGS). Active state renders with the rust accent so the user
/// can see which mode is engaged from across the room.
class _SettingsBadge extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const _SettingsBadge({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bg = active ? const Color(0xFFC1551C) : _oCartsOrange;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(_tileRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_tileRadius),
        child: Center(
          child: Text(
            'Settings',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}

/// Small header cell for column 2 — 250×115 — displays the opened
/// tab's title (e.g. "INVENTORY", "ACTIVE CARTS"). Left-aligned so
/// the layout matches the Figma mock.
class _OpenedTitleCell extends StatelessWidget {
  final String title;
  const _OpenedTitleCell({required this.title});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _tileFill,
        borderRadius: BorderRadius.circular(_tileRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            title,
            style: const TextStyle(
              color: Color(0xFF2E2E2E),
              fontSize: 26,
              fontWeight: FontWeight.w500,
              letterSpacing: 3,
            ),
          ),
        ),
      ),
    );
  }
}

/// Empty gray rounded cell — matches the mockup's placeholder tiles
/// in the middle and bottom of column 2. Non-interactive.
class _OpenedPlaceholderCell extends StatelessWidget {
  const _OpenedPlaceholderCell();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _tileFill,
        borderRadius: BorderRadius.circular(_tileRadius),
      ),
    );
  }
}

/// 70×70 white `<` glyph at bottom-right of an opened tab. Sits below
/// the L-hook rail (no visual overlap) and pops one navigation level.
class _OpenedChevronBack extends StatelessWidget {
  final VoidCallback onTap;
  const _OpenedChevronBack({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_oChevronSize / 2),
        child: const Center(
          child: Icon(
            Icons.chevron_left,
            size: 56,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
