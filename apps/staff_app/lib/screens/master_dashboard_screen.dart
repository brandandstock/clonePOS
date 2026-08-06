import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:clone_pos_widgets/clone_pos_widgets.dart';
import '../data/active_cart.dart';
import 'inventory_opened_view.dart';
import 'sales_kit_opened_view.dart';

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

// Landing tile geometry — Figma node 411:485 revision. Landing now
// uses the SAME 4×2 canvas as the opened template: 250×350 tiles at
// cols 137/389/641/893, rows y=34/386, white cells with plain text
// labels for each tab name.
const double _tileW = 250;
const double _tileH = 350;
const double _tileGap = 2;
const double _gridLeft = 137;
const double _gridTop = 34;
const double _tileRadius = 10;

// Selection border on the highlighted tile (rail-driven selection).
const Color _selectionBlue = Color(0xFF3AA0FF);
const double _selectionBorderWidth = 3;

// Rail geometry — 30 × 300, shared between landing and opened states
// so the flanks look identical across both.
const double _railLeftX = 82;
const double _railRightX = 1196;
const double _railW = 30;
const double _railH = 300;
const double _railTouchPad = 8;

// ============================================================================
// OPENED-STATE GEOMETRY — Figma node 411:530 (Version-ONE, revised).
// A uniform 4×2 grid of 250×350 tiles spans the full central rectangle;
// flank badges sit on both sides and a chevron_back drops below the
// right rail. The prior summary-column + settings-swap template has
// been retired — all opened tabs render the same 8-tile canvas.
//
//   [L flank] [tile 1] [tile 2] [tile 3] [tile 4]  [R flank]
//              ..                                    ..
//             [tile 5] [tile 6] [tile 7] [tile 8]
//                                          [chevron_back]
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
// flank's left edge. The 4×2 tile grid fills this rectangle exactly.
const double _oCentralStartX = 137;
const double _oCentralEndX = 1143; // 893 (col 4) + 250

// Tile geometry — 4 cols × 250w at 137/389/641/893, 2 rows × 350h at
// y=34/386, uniform 2px gutter.
const double _oTileW = 250;
const double _oTileH = 350;
const double _oGridGap = 2;
const double _oGridStartX = _oCentralStartX;
const double _oGridStartY = _oFlankTopY;

// Rails in opened state — bar height unchanged (300), y=344.
const double _oRailTop = 344;

// Chevron_back in opened state (70×70 white glyph, bottom-right area).
const double _oChevronX = 1176;
const double _oChevronY = 683;
const double _oChevronSize = 70;

// Fill colors used by the flank badges.
const Color _oCartsOrange = Color(0xFFE87722);
const Color _oClonesGreen = Color(0xFF2ECC71);

class MenuTile {
  final String label;
  final IconData icon;
  const MenuTile({required this.label, required this.icon});
}

// ── Animation kit (client spec: 250 ms) ─────────────────────────────
// Entrance/transition system distilled from the reference site
// (styles.refero.design ORYZO extraction). Every animation runs at
// the instructed 250 ms; staggers are 40 ms per element.

/// Editorial reveal — fades a child in while rising 14 px. 250 ms,
/// easeOutCubic, with a caller-supplied stagger delay. Plays once per
/// insertion into the tree, so grids replay it naturally whenever a
/// tab or sub-detail (re)opens.
class _Reveal extends StatefulWidget {
  final Widget child;
  final int delayMs;
  const _Reveal({required this.child, this.delayMs = 0});

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );
  late final CurvedAnimation _a =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    if (widget.delayMs <= 0) {
      _c.forward();
    } else {
      _delay = Timer(Duration(milliseconds: widget.delayMs), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _a.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      // child is built once; only the transform/opacity update per frame.
      child: widget.child,
      builder: (_, child) => Opacity(
        opacity: _a.value,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - _a.value)),
          child: child,
        ),
      ),
    );
  }
}

/// Masked headline reveal — the text rises out of an invisible clip,
/// the editorial signature entrance for display type. Nothing fades;
/// the letterforms slide up from behind the mask. 250 ms.
class _MaskedReveal extends StatefulWidget {
  final Widget child;
  final int delayMs;
  const _MaskedReveal({required this.child, this.delayMs = 0});

  @override
  State<_MaskedReveal> createState() => _MaskedRevealState();
}

class _MaskedRevealState extends State<_MaskedReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );
  late final CurvedAnimation _a =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    if (widget.delayMs <= 0) {
      _c.forward();
    } else {
      _delay = Timer(Duration(milliseconds: widget.delayMs), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _a.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: _a,
        child: widget.child,
        builder: (_, child) => FractionalTranslation(
          translation: Offset(0, 1 - _a.value),
          child: child,
        ),
      ),
    );
  }
}

/// The "lone object floating" idle loop from the reference site — a
/// slow ±5 px sine drift on the product image, ~3.6 s per cycle.
class _VoidFloat extends StatefulWidget {
  final Widget child;
  const _VoidFloat({required this.child});

  @override
  State<_VoidFloat> createState() => _VoidFloatState();
}

class _VoidFloatState extends State<_VoidFloat>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, 5 * math.sin(_c.value * 2 * math.pi)),
        child: child,
      ),
    );
  }
}

class MasterDashboardScreen extends StatefulWidget {
  const MasterDashboardScreen({super.key});

  @override
  State<MasterDashboardScreen> createState() => _MasterDashboardScreenState();
}

class _MasterDashboardScreenState extends State<MasterDashboardScreen> {
  int _selectedIndex = 0;
  int? _openedIndex;

  /// One of the 8 right-tile slots the user tapped inside the opened
  /// tab (1..8). null = the tab is on its landing grid; non-null = the
  /// in-place sub-detail panel is shown covering the whole tile grid.
  int? _openSubIndex;

  /// Which clone card (0..5) is currently selected on the Clones
  /// overview — draws the blue focus border. null = none selected.
  int? _selectedClone;

  /// Settings panel — theme / chime / language / logout, rendered
  /// inline as the tall right-column panel (250×702). Toggled by the
  /// Settings flank badge on both the landing screen and any opened
  /// feature page. When false on landing → full 4×2 grid; when false
  /// on an opened tab → right panel shows title + filter for that tab.
  bool _settingsPanelOn = false;
  bool _darkMode = true;

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

  // Sales Kit owns its own drill (gallery → player). Chevron pops
  // player back to gallery before collapsing the tab.
  final GlobalKey<SalesKitOpenedViewState> _salesKitKey =
      GlobalKey<SalesKitOpenedViewState>();

  @override
  void dispose() {
    _leftRailHorizontalCtrl.dispose();
    _rightRailVerticalCtrl.dispose();
    _cloneTicker?.cancel();
    for (final n in _cloneElapsed) {
      n.dispose();
    }
    super.dispose();
  }

  // ── Clone fleet call state ─────────────────────────────────────────
  // Shared source of truth so the SESSIONS master control and each
  // individual clone card drive the SAME live/timer state:
  //   - master CALL  → every clone connects (all cards go live)
  //   - master END   → every clone disconnects
  //   - a card's CALL/CUT toggles just that one clone, independently
  // A single ticker advances every live clone's clock once a second.
  static const int _cloneCount = 6;
  final List<bool> _cloneLive = List<bool>.filled(_cloneCount, false);
  // Each clone's running-call seconds. A ValueNotifier per clone so the
  // once-a-second tick rebuilds ONLY the two timer labels that read it
  // (the card clock + the SESSIONS row) via ValueListenableBuilder —
  // never the whole dashboard. A blanket setState here re-composited the
  // full-screen mesh backdrop and all 500 inventory tiles every second,
  // even from other tabs, which was the app-wide lag.
  final List<ValueNotifier<int>> _cloneElapsed = List<ValueNotifier<int>>
      .generate(_cloneCount, (_) => ValueNotifier<int>(0));
  Timer? _cloneTicker;

  bool get _anyCloneLive => _cloneLive.any((e) => e);

  void _syncCloneTicker() {
    if (_anyCloneLive && _cloneTicker == null) {
      _cloneTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        // Bump each live clone's notifier — no setState. Only the bound
        // ValueListenableBuilder timer labels rebuild; if the Clones tab
        // isn't open, nothing is listening and nothing rebuilds.
        for (var i = 0; i < _cloneCount; i++) {
          if (_cloneLive[i]) _cloneElapsed[i].value++;
        }
      });
    } else if (!_anyCloneLive && _cloneTicker != null) {
      _cloneTicker!.cancel();
      _cloneTicker = null;
    }
  }

  void _toggleClone(int i) {
    setState(() {
      _cloneLive[i] = !_cloneLive[i];
      _cloneElapsed[i].value = 0;
      _selectedClone = i; // calling/cutting a clone focuses its card
    });
    _syncCloneTicker();
  }

  void _callAllClones() {
    setState(() {
      for (var i = 0; i < _cloneCount; i++) {
        _cloneLive[i] = true;
        _cloneElapsed[i].value = 0;
      }
    });
    _syncCloneTicker();
  }

  void _cutAllClones() {
    setState(() {
      for (var i = 0; i < _cloneCount; i++) {
        _cloneLive[i] = false;
        _cloneElapsed[i].value = 0;
      }
    });
    _syncCloneTicker();
  }

  // Placeholder metrics — wire to real repositories later.
  int activeCarts = 26;
  int activeClones = 4;
  int totalClones = 6;

  // Ordered per client brief:
  //   row 1: [0][1][2][3], row 2: [4][5][6][7].
  // Icons kept on the model for future use; landing renders text
  // labels only per Version-ONE landing revision.
  static const List<MenuTile> _tiles = [
    MenuTile(label: 'Carts', icon: Symbols.shopping_cart),
    MenuTile(label: 'Clones', icon: Symbols.devices_other),
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
    });
  }

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
    final openedLabel = _tiles[_openedIndex!].label;
    if (openedLabel == 'Inventory' &&
        (_inventoryKey.currentState?.maybePop() ?? false)) {
      return;
    }
    // Sales Kit runs gallery → player internally; pop player first.
    if (openedLabel == 'Sales Kit' &&
        (_salesKitKey.currentState?.maybePop() ?? false)) {
      return;
    }
    setState(() => _openedIndex = null);
  }

  void _closeOpened() {
    if (_openedIndex != null) {
      setState(() {
        _openedIndex = null;
        _openSubIndex = null;
      });
    }
  }

  void _toggleSettingsPanel() =>
      setState(() => _settingsPanelOn = !_settingsPanelOn);

  @override
  Widget build(BuildContext context) {
    // Responsive shell: the design lives inside a fixed 1280×800
    // canvas scaled to fit the device via FittedBox (preserves the
    // design aspect — no distortion). The mesh backdrop sits OUTSIDE
    // that canvas so it fills the entire device on any aspect ratio;
    // on iPad Pro 13" (~4:3) the extra space above/below the design
    // canvas is now the gradient continuing rather than a black bar.
    //
    // AppTheme wraps everything so cards, panels and the backdrop
    // pick up the current light/dark palette from a single source.
    return AppTheme(
      dark: _darkMode,
      child: Scaffold(
        backgroundColor: _darkMode ? Colors.black : const Color(0xFFEDEDED),
        body: Stack(
          children: [
            Positioned.fill(child: _MeshBackdrop(dark: _darkMode)),
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

                    // Central content — landing (4×2 tab tiles + landing
                    // flank chrome), or the opened-tab template.
                    if (_isOpened)
                      ..._buildOpenedLayout()
                    else ...[
                      ..._buildTiles(),
                      ..._buildLandingChrome(),
                    ],

                    // Visible L-hook rails — same position across landing
                    // and opened states.
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
                      top: _oRailTop,
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
                      top: _oRailTop,
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
                    // Vertical drag → step selection. Swipe-to-open
                    // was removed: it fired too easily on partial
                    // horizontal drift during a scroll gesture, so
                    // the rail is now scroll-only on landing. Tiles
                    // are still tap-to-open.
                    if (!_isOpened) ...[
                      Positioned(
                        left: _railLeftX - _railTouchPad,
                        top: _oRailTop - _railTouchPad,
                        width: _railW + _railTouchPad * 2,
                        height: _railH + _railTouchPad * 2,
                        child: FlankRail(
                          itemCount: _tiles.length,
                          side: RailSide.left,
                          selectedIndex: _selectedIndex,
                          showVisual: false,
                          onSelected: _selectTile,
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
                          selectedIndex: _selectedIndex,
                          showVisual: false,
                          onSelected: _selectTile,
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

                    // In-place sub-detail panel — fills the entire central
                    // rectangle when the user tapped one of the tab's
                    // sub-detail tiles. Carts gets a bespoke 3-region
                    // detail view (filter / cart items / summary +
                    // checkout); every other tab falls back to the
                    // simple titled placeholder.
                    if (_isOpened && _openSubIndex != null)
                      Positioned(
                        left: _oCentralStartX,
                        top: _oFlankTopY,
                        width: _oCentralEndX - _oCentralStartX,
                        height: _oTileH * 2 + _oGridGap,
                        child: _tiles[_openedIndex!].label == 'Carts'
                            ? _CartDetailPanel(
                                cartName: _subDetailTitle(),
                                cartIndex: _openSubIndex!,
                              )
                            : _SubDetailPanel(title: _subDetailTitle()),
                      ),

                  ],
                ),
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }

  /// Build the entire opened-tab layout — Figma node 411:530 revision.
  ///
  /// LEFT: Carts + Clones flank badges.
  /// CENTRE: 3×2 grid of 250×350 sub-detail tiles at cols 137/389/641.
  /// RIGHT COL 4 (x=893): merged 250×702 tall panel. Default mode
  /// shows page-opening title + sub-categories + filter; when the
  /// Settings badge is toggled it swaps to the Settings body.
  /// RIGHT FLANK: Settings toggle + menu_open close.
  /// CHEVRON: bottom-right back button.
  ///
  /// Inventory is special-cased: its InventoryOpenedView owns the
  /// whole central rectangle and overrides both the tile grid and
  /// the right panel with its own browser.
  List<Widget> _buildOpenedLayout() {
    final openedLabel = _tiles[_openedIndex!].label;
    final isInventory = openedLabel == 'Inventory';
    final isSalesKit = openedLabel == 'Sales Kit';
    final ownsCentralRect = isInventory || isSalesKit;

    const centralW = _oCentralEndX - _oCentralStartX;
    const centralH = _oTileH * 2 + _oGridGap;

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

      // ─── CENTRAL CONTENT ───
      //   Inventory / Sales Kit own the central rect with their own
      //   browsers; when Settings is toggled on they shrink to cols
      //   1-3 (750 wide) to make room for the Settings panel in col 4.
      //   Other tabs render a filter column + 3×2 tile grid + optional
      //   Settings panel in col 4.
      if (ownsCentralRect) ...[
        Positioned(
          left: _oCentralStartX,
          top: _oFlankTopY,
          width: _settingsPanelOn
              ? (_oTileW * 3 + _oGridGap * 2) // 750 = cols 1-3
              : centralW,
          height: centralH,
          child: isInventory
              ? InventoryOpenedView(
                  key: _inventoryKey,
                  scrollController: _rightRailVerticalCtrl,
                  filterScrollController: _leftRailHorizontalCtrl,
                )
              : SalesKitOpenedView(
                  key: _salesKitKey,
                  scrollController: _rightRailVerticalCtrl,
                  filterScrollController: _leftRailHorizontalCtrl,
                ),
        ),
        if (_settingsPanelOn)
          Positioned(
            left: _oGridStartX + 3 * (_oTileW + _oGridGap), // col 4 (x=893)
            top: _oGridStartY,
            width: _oTileW,
            height: _oTileH * 2 + _oGridGap,
            child: _RightColumnPanel(
              child: _SettingsPanelBody(
                darkMode: _darkMode,
                onToggleTheme: () => setState(() => _darkMode = !_darkMode),
                onNoop: () {},
              ),
            ),
          ),
      ] else if (_openSubIndex == null) ...[
        // Col 1 — filter column, same 250×702 chrome as Inventory's
        // summary column. Static placeholder for now; each tab can
        // wire its own fields later.
        Positioned(
          left: _oGridStartX,
          top: _oGridStartY,
          width: _oTileW,
          height: _oTileH * 2 + _oGridGap,
          // Clones docks a live SESSIONS console under its filters —
          // the fleet-wide CALL/END control lives on the overview, not
          // on each clone's detail page.
          child: openedLabel == 'Clones'
              ? _ClonesFilterColumn(
                  live: _cloneLive,
                  elapsed: _cloneElapsed,
                  anyLive: _anyCloneLive,
                  onCallAll: _callAllClones,
                  onCutAll: _cutAllClones,
                )
              : _FeatureFilterColumn(title: openedLabel),
        ),
        // Cols 2-4 — 3×2 sub-detail tile grid, or 2×2 when Settings
        // is on to leave col 4 for the panel.
        //
        // Skipped when a sub-detail panel is up: the sub-detail's
        // Stack children would otherwise composite on top of the
        // labelled tiles (visible bleed under empty cells in the
        // Cart bento — session-10 fix).
        ..._buildOpenedTileGrid(openedLabel),
        if (_settingsPanelOn)
          Positioned(
            left: _oGridStartX + 3 * (_oTileW + _oGridGap), // col 4 (x=893)
            top: _oGridStartY,
            width: _oTileW,
            height: _oTileH * 2 + _oGridGap,
            child: _RightColumnPanel(
              child: _SettingsPanelBody(
                darkMode: _darkMode,
                onToggleTheme: () => setState(() => _darkMode = !_darkMode),
                onNoop: () {},
              ),
            ),
          ),
      ],

      // ─── RIGHT FLANK ─── Top badge toggles the Settings panel;
      // bottom = menu_open to close the tab.
      Positioned(
        left: _oRightColX,
        top: _oFlankTopY,
        width: _oFlankW,
        height: _oFlankH,
        child: _SettingsBadge(onTap: _toggleSettingsPanel),
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

  /// Sub-detail tile grid for opened tabs — sits to the RIGHT of the
  /// filter column at grid cols 2-4 (x=389/641/893).
  ///
  ///   Settings off → 3 cols × 2 rows = 6 labelled tiles.
  ///   Settings on  → 2 cols × 2 rows = 4 labelled tiles (labels at
  ///                  positions 2 and 5 are the col-4 pair that gets
  ///                  covered by the Settings panel).
  List<Widget> _buildOpenedTileGrid(String openedLabel) {
    final labels = _rightTileLabelsFor(openedLabel);
    final widgets = <Widget>[];
    // Logical inner cols 0..2 → grid cols 1..3 (skipping col 0 = filter).
    for (var row = 0; row < 2; row++) {
      for (var innerCol = 0; innerCol < 3; innerCol++) {
        if (_settingsPanelOn && innerCol == 2) continue;
        final gridCol = innerCol + 1;
        final x = _oGridStartX + gridCol * (_oTileW + _oGridGap);
        final y = _oGridStartY + row * (_oTileH + _oGridGap);
        final labelIdx = row * 3 + innerCol;
        final Widget cell;
        if (openedLabel == 'Clones') {
          // Clone tiles are live call cards, not drill-in tiles. Their
          // live/timer state is owned by the parent so the SESSIONS
          // master control and the card share one source of truth.
          final id = _cloneIdentities[labelIdx % _cloneIdentities.length];
          cell = _CloneCard(
            number: labelIdx + 1,
            name: id.$1,
            subtitle: id.$2,
            live: _cloneLive[labelIdx],
            elapsed: _cloneElapsed[labelIdx],
            onToggle: () => _toggleClone(labelIdx),
            selected: _selectedClone == labelIdx,
            onSelect: () => setState(() => _selectedClone = labelIdx),
          );
        } else if (labels != null) {
          cell = _LabelledTile(
            label: labels[labelIdx],
            onTap: () => setState(() => _openSubIndex = labelIdx + 1),
          );
        } else {
          cell = const _BlankTile();
        }
        widgets.add(Positioned(
          left: x,
          top: y,
          width: _oTileW,
          height: _oTileH,
          child: _Reveal(delayMs: labelIdx * 40, child: cell),
        ));
      }
    }
    return widgets;
  }

  /// Build the LANDING tile grid — 4×2 of white text-labelled tab
  /// tiles. When the Settings panel is on, the RIGHT COLUMN tiles
  /// (indices 3 and 7) are suppressed to make room for the merged
  /// tall Settings panel rendered from _buildLandingChrome.
  List<Widget> _buildTiles() {
    final widgets = <Widget>[];
    for (var i = 0; i < _tiles.length; i++) {
      final col = i % 4;
      if (_settingsPanelOn && col == 3) continue;
      final row = i ~/ 4;
      final x = _gridLeft + col * (_tileW + _tileGap);
      final y = _gridTop + row * (_tileH + _tileGap);
      widgets.add(Positioned(
        left: x,
        top: y,
        width: _tileW,
        height: _tileH,
        // 40 ms stagger left-to-right, top-to-bottom. Plays on first
        // build and whenever landing remounts.
        child: _Reveal(
          delayMs: i * 40,
          child: _MenuTileCell(
            tile: _tiles[i],
            selected: i == _selectedIndex,
            onTap: () => _openTile(i),
          ),
        ),
      ));
    }
    return widgets;
  }

  /// Landing chrome — 4 flank badges (Carts + Clones on the left,
  /// Settings + Full Screen on the right) plus the bottom-right
  /// chevron. When Settings is toggled on, also renders the merged
  /// tall Settings panel at column 4. Rails render separately in
  /// build().
  List<Widget> _buildLandingChrome() {
    return [
      // Left flank is a display (Active Carts / Active Clones counts)
      // on every page — landing and every opened tab. Not tappable.
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
      Positioned(
        left: _oRightColX,
        top: _oFlankTopY,
        width: _oFlankW,
        height: _oFlankH,
        child: _LandingFlankBadge(
          label: 'Settings',
          onTap: _toggleSettingsPanel,
        ),
      ),
      const Positioned(
        left: _oRightColX,
        top: _oFlankSecondY,
        width: _oFlankW,
        height: _oFlankH,
        child: _LandingFlankBadge(label: 'Full\nScreen'),
      ),
      if (_settingsPanelOn)
        Positioned(
          left: _gridLeft + 3 * (_tileW + _tileGap), // col 4 (x=893)
          top: _gridTop,
          width: _tileW,
          height: _tileH * 2 + _tileGap,
          child: _RightColumnPanel(
            child: _SettingsPanelBody(
              darkMode: _darkMode,
              onToggleTheme: () => setState(() => _darkMode = !_darkMode),
              onNoop: () {},
            ),
          ),
        ),
      Positioned(
        left: _oChevronX,
        top: _oChevronY,
        width: _oChevronSize,
        height: _oChevronSize,
        child: _OpenedChevronBack(onTap: () {}),
      ),
    ];
  }

  /// Returns the 6 sub-detail tile labels for a given opened tab, or
  /// null when the tab renders empty gray placeholders. Order is
  /// row-major over the 3×2 grid (row 1 left→right, then row 2).
  /// Column 4 is reserved for the right-column info panel.
  List<String>? _rightTileLabelsFor(String openedLabel) {
    switch (openedLabel) {
      case 'Carts':
        return const [
          'Cart 1', 'Cart 2', 'Cart 3',
          'Cart 4', 'Cart 5', 'Cart 6',
        ];
      case 'Clones':
        return const [
          'Clone 1', 'Clone 2', 'Clone 3',
          'Clone 4', 'Clone 5', 'Clone 6',
        ];
      case 'Logistics':
        return const [
          'Inbound', 'Outbound', 'In Transit',
          'Returns', 'Fleet', 'Suppliers',
        ];
      case 'Analytics':
        return const [
          'Sales', 'Top Sellers', 'Slow Movers',
          'Customers', 'Staff', 'Peak Hours',
        ];
      case 'Accounts':
        return const [
          'Invoices', 'Payments', 'Refunds',
          'Taxes', 'Expenses', 'Ledger',
        ];
      case 'Data':
        return const [
          'Customers', 'Employees', 'Suppliers',
          'Documents', 'Exports', 'Backups',
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
    final t = AppTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.cardBg,
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
    final t = AppTheme.of(context);
    return Material(
      color: t.cardBg,
      borderRadius: BorderRadius.circular(_tileRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_tileRadius),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: t.cardText,
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
// Cart detail panel — fills the central rectangle when the user taps
// a Cart tile (Cart 1..6) inside the Carts tab. Three regions:
//
//   col 1 (250×702)          — filter column: customer / discount /
//                               coupon / payment / notes.
//   cols 2-3 merged (500×702) — the cart's line items.
//   col 4 (250, split 350/350) — summary tile (subtotal, tax, total)
//                                stacked over checkout action tile.
//
// Text-only placeholders for now — wire real state per section later.
// ---------------------------------------------------------------------------

/// Session-10 rewrite: the middle two columns of the cart detail now
/// render a **bento** — one tall "selected item" cell on the left and a
/// vertical stack of item rows filling the rest. Col-1 also grows a small
/// header pill above the tall cell showing customer/id at a glance.
/// The right-most column (summary + checkout) is untouched per client.
class _CartDetailPanel extends StatefulWidget {
  final String cartName;
  final int cartIndex; // 1..6 — maps to seedActiveCarts()[cartIndex-1]
  const _CartDetailPanel({
    required this.cartName,
    required this.cartIndex,
  });

  @override
  State<_CartDetailPanel> createState() => _CartDetailPanelState();
}

class _CartDetailPanelState extends State<_CartDetailPanel> {
  // Cache the deterministic seed once. seedActiveCarts() runs an RNG
  // pass over 300 seed products — keep it out of the build.
  static final List<ActiveCart> _cartsCache = seedActiveCarts();

  int _selectedLine = 0;

  ActiveCart get _cart {
    // cartIndex 1..6 → clamp into seed range so we never crash if the
    // sub-index model grows past the seed length.
    final i = (widget.cartIndex - 1).clamp(0, _cartsCache.length - 1);
    return _cartsCache[i];
  }

  @override
  Widget build(BuildContext context) {
    const w = _oTileW; // 250
    const h = _oTileH; // 350
    const g = _oGridGap; // 2

    // Column-1 split: a short header pill at the top, then the tall
    // selected-item cell fills the remainder. 90 lines up with the
    // header strip inside cols 2-3 so the two columns share a baseline.
    const headerH = 90.0;
    const detailH = h * 2 + g - headerH - g;

    return Stack(
      children: [
        // Col 1 top: customer header pill. Staggered 250 ms reveals
        // sweep the bento left-to-right on open.
        Positioned(
          left: 0,
          top: 0,
          width: w,
          height: headerH,
          child: _Reveal(child: _CustomerHeaderPill(cart: _cart)),
        ),
        // Col 1 bottom: selected item detail (blue border when a row
        // is picked from the stack).
        Positioned(
          left: 0,
          top: headerH + g,
          width: w,
          height: detailH,
          child: _Reveal(
            delayMs: 40,
            child: _SelectedItemCell(line: _cart.lines[_selectedLine]),
          ),
        ),

        // Cols 2-3: item-list bento (top header strip + vertical stack).
        Positioned(
          left: w + g,
          top: 0,
          width: w * 2 + g,
          height: h * 2 + g,
          child: _Reveal(
            delayMs: 80,
            child: _ItemListBento(
              cart: _cart,
              selectedIndex: _selectedLine,
              onSelect: (i) => setState(() => _selectedLine = i),
            ),
          ),
        ),

        // Col 4: summary + checkout — UNCHANGED per client sign-off.
        Positioned(
          left: (w + g) * 3,
          top: 0,
          width: w,
          height: h,
          child: _Reveal(delayMs: 120, child: _summaryTile()),
        ),
        Positioned(
          left: (w + g) * 3,
          top: h + g,
          width: w,
          height: h,
          child: _Reveal(delayMs: 160, child: _checkoutTile()),
        ),
      ],
    );
  }

  Widget _summaryTile() {
    return Builder(builder: (context) {
      final t = AppTheme.of(context);
      return DecoratedBox(
        decoration: BoxDecoration(
          color: t.cardBg,
          borderRadius: BorderRadius.circular(_tileRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'SUMMARY',
                style: TextStyle(
                  color: t.cardText,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 18),
              _summaryRow(t, 'Subtotal', '₹0.00'),
              _summaryRow(t, 'Discount', '₹0.00'),
              _summaryRow(t, 'Tax (GST)', '₹0.00'),
              const Spacer(),
              Divider(color: t.divider, height: 1),
              const SizedBox(height: 10),
              _summaryRow(t, 'Total', '₹0.00', emphasise: true),
            ],
          ),
        ),
      );
    });
  }

  static Widget _summaryRow(AppTheme t, String label, String value,
      {bool emphasise = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: t.cardText,
              fontSize: emphasise ? 16 : 13,
              fontWeight: emphasise ? FontWeight.w800 : FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: t.cardText,
              fontSize: emphasise ? 18 : 14,
              fontWeight: emphasise ? FontWeight.w800 : FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _checkoutTile() {
    return Material(
      color: _oCartsOrange,
      borderRadius: BorderRadius.circular(_tileRadius),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(_tileRadius),
        child: const Padding(
          padding: EdgeInsets.fromLTRB(20, 22, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'CHECKOUT',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
              Spacer(),
              Text(
                'Charge',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  height: 1,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Confirm payment and close this cart.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  height: 1.35,
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
// Cart-detail bento pieces (session 10).
//   [_CustomerHeaderPill] — small panel above the tall selected-item cell.
//   [_SelectedItemCell]   — tall left cell showing the currently focused
//                           line item; blue border while a row is picked.
//   [_ItemListBento]      — cols 2-3: header strip + vertical stack of
//                           bento rows, one per cart line.
// ---------------------------------------------------------------------------

const Color _kSelectionBlue = Color(0xFF3AA0FF);

class _CustomerHeaderPill extends StatelessWidget {
  final ActiveCart cart;
  const _CustomerHeaderPill({required this.cart});

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.panelBg,
        borderRadius: BorderRadius.circular(_tileRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _MaskedReveal(
              // Rises just after the pill's own reveal settles.
              delayMs: 80,
              child: Text(
                cart.customerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.panelText,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  height: 1.1,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${cart.id}  ·  Sat ${cart.satelliteNumber}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.cardSubtleText,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedItemCell extends StatelessWidget {
  final CartLine line;
  const _SelectedItemCell({required this.line});

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final p = line.product;
    return Container(
      decoration: BoxDecoration(
        color: t.cardBg,
        borderRadius: BorderRadius.circular(_tileRadius),
        border: Border.all(color: _kSelectionBlue, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Big product image — takes ~half the cell height. The
            // museum-artifact treatment from the reference site: a
            // slow float loop plus a 250 ms fade+scale swap when a
            // different row is selected.
            AspectRatio(
              aspectRatio: 1,
              child: _VoidFloat(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.96, end: 1)
                          .animate(anim),
                      child: child,
                    ),
                  ),
                  child: ClipRRect(
                    key: ValueKey(p.id),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      color: t.chipBg,
                      alignment: Alignment.center,
                      child: (p.imageUrl ?? '').isNotEmpty
                          ? Image.network(
                              p.imageUrl!,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Icon(
                                Symbols.image_not_supported,
                                color: t.cardSubtleText,
                                size: 36,
                              ),
                            )
                          : Icon(
                              Symbols.image_not_supported,
                              color: t.cardSubtleText,
                              size: 36,
                            ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              p.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.cardText,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              p.brand ?? '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.cardSubtleText,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            // Qty + unit price.
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: t.chipBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Qty ${line.quantity}',
                    style: TextStyle(
                      color: t.cardText,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '₹${_formatMoney(p.price)}',
                  style: TextStyle(
                    color: t.cardSubtleText,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '₹${_formatMoney(line.subtotal)}',
              style: TextStyle(
                color: t.cardText,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemListBento extends StatelessWidget {
  final ActiveCart cart;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  const _ItemListBento({
    required this.cart,
    required this.selectedIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    const headerH = 90.0;
    const gap = 2.0;

    return Column(
      children: [
        // Header strip — item count + total items pill. Baseline
        // matches the customer header on col 1.
        SizedBox(
          height: headerH,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: t.cardBg,
              borderRadius: BorderRadius.circular(_tileRadius),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'ITEMS',
                        style: TextStyle(
                          color: t.cardSubtleText,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.6,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${cart.lines.length} lines · '
                        '${cart.itemCount} qty',
                        style: TextStyle(
                          color: t.cardText,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: t.chipBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Symbols.add,
                            size: 16,
                            color: t.cardText,
                            weight: 500),
                        const SizedBox(width: 4),
                        Text(
                          'Add product',
                          style: TextStyle(
                            color: t.cardText,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: gap),
        // Vertical stack of item rows. ListView so long carts scroll —
        // eventually attaches to the right rail's vertical controller.
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: cart.lines.length,
            separatorBuilder: (_, __) => const SizedBox(height: gap),
            itemBuilder: (ctx, i) => _Reveal(
              delayMs: i * 40,
              child: _ItemRow(
                line: cart.lines[i],
                selected: i == selectedIndex,
                onTap: () => onSelect(i),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  final CartLine line;
  final bool selected;
  final VoidCallback onTap;
  const _ItemRow({
    required this.line,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final p = line.product;
    return Material(
      color: t.cardBg,
      borderRadius: BorderRadius.circular(_tileRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_tileRadius),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_tileRadius),
            border: Border.all(
              color: selected ? _kSelectionBlue : Colors.transparent,
              width: 2,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 18, 12),
          child: Row(
            children: [
              // Thumbnail.
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: 56,
                  height: 56,
                  color: t.chipBg,
                  alignment: Alignment.center,
                  child: (p.imageUrl ?? '').isNotEmpty
                      ? Image.network(
                          p.imageUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Icon(
                            Symbols.image_not_supported,
                            color: t.cardSubtleText,
                            size: 22,
                          ),
                        )
                      : Icon(
                          Symbols.image_not_supported,
                          color: t.cardSubtleText,
                          size: 22,
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.cardText,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${p.brand ?? '—'} · ₹${_formatMoney(p.price)} × '
                      '${line.quantity}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.cardSubtleText,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '₹${_formatMoney(line.subtotal)}',
                style: TextStyle(
                  color: t.cardText,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Local Indian-grouping money formatter — matches the format used in
// active_carts_view.dart's cart tiles.
String _formatMoney(double n) {
  final s = n.toStringAsFixed(0);
  final b = StringBuffer();
  final chars = s.split('').reversed.toList();
  for (var i = 0; i < chars.length; i++) {
    b.write(chars[i]);
    final atGroup = i == 2 || (i > 2 && (i - 2) % 2 == 0);
    if (atGroup && i != chars.length - 1) b.write(',');
  }
  return b.toString().split('').reversed.join();
}

// ---------------------------------------------------------------------------
// In-place sub-detail panel — fills the tile-grid rectangle when the
// user drills into one of an opened tab's 6 right-tiles (non-Carts).
//
// No close button here: the right-flank chevron already pops sub-detail
// → tile grid → landing one step at a time.
// ---------------------------------------------------------------------------

class _SubDetailPanel extends StatelessWidget {
  final String title;
  const _SubDetailPanel({required this.title});

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Material(
      color: t.cardBg,
      borderRadius: BorderRadius.circular(_tileRadius),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
            color: t.chipBg,
            child: Text(
              title,
              style: TextStyle(
                color: t.cardText,
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
// Clones filter column — the Clones tab replaces the generic feature
// filter column with this one: the same CLONES / SEARCH / SORT / STATUS
// / DATE chrome, plus a live SESSIONS console docked beneath the filters.
//
// SESSIONS is the fleet-wide call console (it lives on the Clones
// overview, not on each clone's detail page):
//   - Idle  → every session reads 00:00, all dots grey, green CALL.
//   - Tap CALL → the fleet is dialled: connected clones' clocks start
//     ticking and their dots light green; the button flips to a red END.
//     Tap END → everything resets back to idle.
// Figma: SESSIONS component on the Clone feature page (Version-ONE).
// ---------------------------------------------------------------------------

// Clone-feature palette — sampled straight from the Version-ONE Figma.
const Color _oCallGreen = Color(0xFF00C700); // CALL button / live clocks
const Color _oCallRed = Color(0xFFA80B0B); // SESSIONS master END — deep red
const Color _oCloneLiveBg = Color(0xFFF4C75D); // live card — mustard yellow
const Color _oCloneOrange = Color(0xFFFB8F00); // badge numeral
const Color _oCutRed = Color(0xFFF64900); // card CUT button — orange-red
const Color _oCloneCardBg = Color(0xFFD9D9D9); // idle card — fixed light grey
const Color _oCloneCardText = Color(0xFF63605B); // card name/sub/time (both states)

// Placeholder clone identities — name + posting. Wire to real fleet
// records later; cycles if the grid ever grows past six.
const List<(String, String)> _cloneIdentities = [
  ('Staff', 'Department'),
  ('Ronaldo', 'Soccer Isle'),
  ('Mia', 'Cosmetics'),
  ('Dev', 'Electronics'),
  ('Aisha', 'Grocery'),
  ('Leo', 'Home & Living'),
];

// ---------------------------------------------------------------------------
// Clone call card — one per clone tile on the Clones overview grid.
//   Idle → grey card, green CALL, clock parked at 00:00.
//   Live → mustard-yellow card, red CUT, clock ticking.
// Stateless: its live/timer state is owned by the parent so the SESSIONS
// master control ("call all") and this card stay in lockstep. Tap CALL/
// CUT toggles just this clone; tapping the body selects it (blue border).
// The badge is a fixed "1" on every card per client.
// ---------------------------------------------------------------------------

class _CloneCard extends StatelessWidget {
  final int number; // badge numeral — the clone's sequence (1, 2, 3 …)
  final String name;
  final String subtitle;
  final bool live;
  final ValueListenable<int> elapsed;
  final VoidCallback onToggle; // CALL/CUT for this one clone
  final bool selected;
  final VoidCallback onSelect;
  const _CloneCard({
    required this.number,
    required this.name,
    required this.subtitle,
    required this.live,
    required this.elapsed,
    required this.onToggle,
    required this.selected,
    required this.onSelect,
  });

  String _fmt(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    // Fixed Figma colours (the card is a client-locked design element, so
    // it stays light grey / mustard in both app themes to match the mock).
    // Absolute-positioned to the exact Figma offsets on the 250×350 tile.
    return GestureDetector(
      onTap: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: live ? _oCloneLiveBg : _oCloneCardBg,
          borderRadius: BorderRadius.circular(10),
          border: selected
              ? Border.all(
                  color: _selectionBlue, width: _selectionBorderWidth)
              : null,
        ),
        child: Stack(
          children: [
            // Badge — the clone's sequence number, 96px Bold, centred near
            // the top.
            Positioned(
              top: -2,
              left: 0,
              right: 0,
              child: Text(
                '$number',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _oCloneOrange,
                  fontSize: 96,
                  fontWeight: FontWeight.w700,
                  height: 1.0042,
                  letterSpacing: -3.84,
                ),
              ),
            ),
            // Name — 36px Light.
            Positioned(
              top: 94,
              left: 8,
              right: 8,
              child: Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _oCloneCardText,
                  fontSize: 36,
                  fontWeight: FontWeight.w300,
                  height: 1.0042,
                  letterSpacing: -1.44,
                ),
              ),
            ),
            // Subtitle — 20px Regular.
            Positioned(
              top: 128,
              left: 8,
              right: 8,
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _oCloneCardText,
                  fontSize: 20,
                  fontWeight: FontWeight.w400,
                  height: 1.0042,
                  letterSpacing: -1.2,
                ),
              ),
            ),
            // CALL / CUT button — 60×60, centred at y≈238.
            Positioned(
              top: 208,
              left: 0,
              right: 0,
              child: Center(child: _callButton()),
            ),
            // Clock — 13px Regular. Only this label rebuilds on the tick.
            Positioned(
              top: 285,
              left: 8,
              right: 8,
              child: ValueListenableBuilder<int>(
                valueListenable: elapsed,
                builder: (_, seconds, __) => Text(
                  live ? _fmt(seconds) : '00:00',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _oCloneCardText,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    height: 1.0042,
                    letterSpacing: 0.91,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _callButton() {
    final color = live ? _oCutRed : _oCallGreen;
    return Material(
      color: color,
      shape: const CircleBorder(),
      elevation: 3,
      shadowColor: color.withValues(alpha: 0.5),
      child: InkWell(
        onTap: onToggle,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 60,
          height: 60,
          child: Center(
            child: Text(
              live ? 'CUT' : 'CALL',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w400,
                letterSpacing: 4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClonesFilterColumn extends StatelessWidget {
  final List<bool> live;
  final List<ValueListenable<int>> elapsed;
  final bool anyLive;
  final VoidCallback onCallAll;
  final VoidCallback onCutAll;
  const _ClonesFilterColumn({
    required this.live,
    required this.elapsed,
    required this.anyLive,
    required this.onCallAll,
    required this.onCutAll,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 115, child: _titleCell(t)),
        const SizedBox(height: 2),
        Expanded(child: _bodyCell(t)),
      ],
    );
  }

  Widget _titleCell(AppTheme t) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.panelBg,
        borderRadius: BorderRadius.circular(_tileRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Align(
          // Centred per client design update — the CLONES title above
          // the SESSIONS tab is centred, not left-aligned.
          alignment: Alignment.center,
          child: _MaskedReveal(
            child: Text(
              'CLONES',
              style: TextStyle(
                color: t.panelText,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: 4.48,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // The SESSIONS console owns the whole cell — filters removed per
  // client. FittedBox scales the console to the panel height so the
  // CALL button is always on-screen: it must fit in one view, no scroll.
  Widget _bodyCell(AppTheme t) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.panelBg,
        borderRadius: BorderRadius.circular(_tileRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: 210,
            child: _CloneSessionsConsole(
              live: live,
              elapsed: elapsed,
              anyLive: anyLive,
              onCallAll: onCallAll,
              onCutAll: onCutAll,
            ),
          ),
        ),
      ),
    );
  }
}

// Compact SESSIONS console tuned for the ~210px-wide filter column:
// heading, a live clock per clone, connection dots, and the fleet
// master CALL/END control. Stateless — the parent owns the shared
// live/elapsed state; the master button dials or cuts EVERY clone at
// once, and each row mirrors whatever state its clone is currently in
// (whether that came from the master or the card's own CALL/CUT).
class _CloneSessionsConsole extends StatelessWidget {
  final List<bool> live;
  final List<ValueListenable<int>> elapsed;
  final bool anyLive;
  final VoidCallback onCallAll;
  final VoidCallback onCutAll;
  const _CloneSessionsConsole({
    required this.live,
    required this.elapsed,
    required this.anyLive,
    required this.onCallAll,
    required this.onCutAll,
  });

  String _fmt(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Text(
            'SESSIONS',
            style: TextStyle(
              color: t.panelText,
              fontSize: 24,
              fontWeight: FontWeight.w500,
              letterSpacing: 3.84,
            ),
          ),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < live.length; i++) _sessionRow(t, i),
        const SizedBox(height: 14),
        // Connection dots — one per clone; green while that clone is live.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < live.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _dot(t, on: live[i]),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Center(child: _callButton()),
        const SizedBox(height: 8),
        Text(
          'ALL\nCLONES',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: t.cardSubtleText,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 3,
            height: 1.3,
          ),
        ),
      ],
    );
  }

  // Stacked clock — clone label above its running time, centred, like
  // the Figma mock. The whole column belongs to SESSIONS now that the
  // filters are gone, so the rows can breathe.
  Widget _sessionRow(AppTheme t, int i) {
    final on = live[i];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          Text(
            'CLONE :0${i + 1}',
            style: TextStyle(
              color: t.panelText,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 2.4,
            ),
          ),
          // Only this clock rebuilds on the per-second tick.
          ValueListenableBuilder<int>(
            valueListenable: elapsed[i],
            builder: (_, value, __) => Text(
              _fmt(on ? value : 0),
              style: TextStyle(
                // Live clocks read in the fleet green; parked clocks stay
                // in Figma's black-80% so the row still reads when idle.
                color: on ? _oCallGreen : t.panelText,
                fontSize: 24,
                fontWeight: FontWeight.w300,
                letterSpacing: 0.48,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(AppTheme t, {required bool on}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      width: 11,
      height: 11,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? _oCallGreen : t.divider,
      ),
    );
  }

  Widget _callButton() {
    final color = anyLive ? _oCallRed : _oCallGreen;
    return Material(
      color: color,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: color.withValues(alpha: 0.5),
      child: InkWell(
        onTap: anyLive ? onCutAll : onCallAll,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 60,
          height: 60,
          child: Center(
            child: Text(
              anyLive ? 'END' : 'CALL',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w400,
                letterSpacing: 4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// App theme — single source of truth for card / panel / text /
// backdrop colors. Flipped by the Settings → Light/Dark toggle.
// ---------------------------------------------------------------------------

class AppTheme extends InheritedWidget {
  final bool dark;
  const AppTheme({super.key, required this.dark, required super.child});

  static AppTheme of(BuildContext context) {
    final t = context.dependOnInheritedWidgetOfExactType<AppTheme>();
    assert(t != null, 'AppTheme missing above this widget');
    return t!;
  }

  // Cards and tiles — the main visual surface. Kept high-contrast in
  // both modes so labels are legible from across the room.
  Color get cardBg => dark ? const Color(0xFF2A2A2A) : Colors.white;
  Color get cardText => dark ? Colors.white : const Color(0xFF2E2E2E);
  Color get cardSubtleText =>
      dark ? Colors.white70 : const Color(0xFF666666);

  // Gray filter panels (Inventory / Sales Kit / feature-tab left col).
  Color get panelBg =>
      dark ? const Color(0xFF232323) : const Color(0xFFD9D9D9);
  Color get panelText => dark ? Colors.white : const Color(0xFF2E2E2E);
  Color get panelAccent =>
      dark ? Colors.white70 : const Color(0xFF2E2E2E);

  // Inline text fields inside the filter panels.
  Color get fieldBg =>
      dark ? const Color(0xFF3A3A3A) : Colors.white;
  Color get fieldHint =>
      dark ? const Color(0xFFB0B0B0) : const Color(0xFFA0A0A0);

  // Sub-detail placeholder chip / divider.
  Color get chipBg =>
      dark ? const Color(0xFF3A3A3A) : const Color(0xFFF3F3F3);
  Color get divider =>
      dark ? const Color(0xFF3A3A3A) : const Color(0xFFE5E5E5);

  // Scaffold + mesh backdrop base.
  Color get scaffoldBg =>
      dark ? Colors.black : const Color(0xFFEDEDED);

  @override
  bool updateShouldNotify(covariant AppTheme old) => old.dark != dark;
}

// ---------------------------------------------------------------------------
// Mesh backdrop — dark base + heavily-blurred coloured blobs in dark
// mode; soft neutral base + pastel blobs in light mode.
// ---------------------------------------------------------------------------

class _MeshBackdrop extends StatelessWidget {
  final bool dark;
  const _MeshBackdrop({required this.dark});

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary is load-bearing here: the blob blurs are
    // 120-sigma over a 1280×800 canvas, cripplingly expensive to
    // recomposite each frame. Without this, every scroll pixel in
    // the inventory grid re-rasters the entire backdrop. Isolating
    // it lets Flutter cache the layer and re-use it verbatim.
    final base = dark ? const Color(0xFF1A1A1A) : const Color(0xFFEDEDED);
    final blobs = dark
        ? const [
            (-80.0, -60.0, null, null, 620.0, Color(0xFF1E5B3E)),
            (-100.0, null, -80.0, null, 500.0, Color(0xFF0F5555)),
            (null, -60.0, null, -80.0, 520.0, Color(0xFF6E5820)),
            (null, null, -80.0, -100.0, 600.0, Color(0xFF6A2A3A)),
            (300.0, 400.0, null, null, 500.0, Color(0xFF3A2A5A)),
          ]
        : const [
            (-80.0, -60.0, null, null, 620.0, Color(0xFFB9E1CA)),
            (-100.0, null, -80.0, null, 500.0, Color(0xFFB6DADA)),
            (null, -60.0, null, -80.0, 520.0, Color(0xFFF0DFB0)),
            (null, null, -80.0, -100.0, 600.0, Color(0xFFF2C3CE)),
            (300.0, 400.0, null, null, 500.0, Color(0xFFD5C9F0)),
          ];
    return RepaintBoundary(
      child: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: base)),
          for (final b in blobs)
            _blob(
              top: b.$1,
              left: b.$2,
              right: b.$3,
              bottom: b.$4,
              size: b.$5,
              color: b.$6,
            ),
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
// Landing tile — white cell with the tab name centred as plain text.
// Blue border indicates rail-driven selection.
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

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Material(
      color: t.cardBg,
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
            child: Text(
              tile.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: t.cardText,
                fontSize: 22,
                fontWeight: FontWeight.w400,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Landing flank badge — 115×115 white rounded cell with a small text
// label centred (Carts / Clones / Settings / Full Screen). Inert stub
// for now; will wire tap handlers once each destination is designed.
// ---------------------------------------------------------------------------

class _LandingFlankBadge extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _LandingFlankBadge({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Material(
      color: t.cardBg,
      borderRadius: BorderRadius.circular(_tileRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_tileRadius),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t.cardText,
              fontSize: 12,
              fontWeight: FontWeight.w400,
              letterSpacing: 1.5,
              height: 1.25,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Feature filter column — 250×702 gray filter panel that sits in
// col 1 of every non-Inventory opened tab. Mirrors the visual style
// of Inventory's summary column (title cell 250×115 + filter cell
// 250×585 with a 2px gap). Fields are placeholders for now; each
// tab can wire its own filter controls later.
// ---------------------------------------------------------------------------

class _FeatureFilterColumn extends StatelessWidget {
  final String title;
  const _FeatureFilterColumn({required this.title});

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 115, child: _titleCell(t)),
        const SizedBox(height: 2),
        Expanded(child: _filterCell(t)),
      ],
    );
  }

  Widget _titleCell(AppTheme t) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.panelBg,
        borderRadius: BorderRadius.circular(_tileRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Align(
          alignment: Alignment.centerLeft,
          // Display headline rises out of its clip on tab open — the
          // masked editorial entrance.
          child: _MaskedReveal(
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                color: t.panelText,
                fontSize: 24,
                fontWeight: FontWeight.w500,
                letterSpacing: 3,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterCell(AppTheme t) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.panelBg,
        borderRadius: BorderRadius.circular(_tileRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: TextStyle(
                color: t.panelText,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 6),
            Container(height: 2, width: 100, color: t.panelAccent),
            const SizedBox(height: 20),
            _filterLabel(t, 'SEARCH'),
            const _FilterField(hint: 'Name, keyword'),
            const SizedBox(height: 16),
            _filterLabel(t, 'SORT'),
            const _FilterField(hint: 'Default'),
            const SizedBox(height: 16),
            _filterLabel(t, 'STATUS'),
            const _FilterField(hint: 'All'),
            const SizedBox(height: 16),
            _filterLabel(t, 'DATE'),
            const _FilterField(hint: 'Any'),
          ],
        ),
      ),
    );
  }

  static Widget _filterLabel(AppTheme t, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          color: t.cardSubtleText,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

class _FilterField extends StatelessWidget {
  final String hint;
  const _FilterField({required this.hint});

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Container(
      height: 34,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: t.fieldBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        hint,
        style: TextStyle(
          color: t.fieldHint,
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tall right-column panel — 250×702 white rounded rect that occupies
// the merged right column of the 4×2 grid. Two content modes:
//
//   Settings mode  — Light/Dark, Chime, Language, Logout list.
//   Feature mode   — page-opening title (e.g. "ANALYTICS") + filter /
//                    sub-category placeholder for the opened tab.
//
// The Settings badge on the right flank toggles between the two
// modes on a feature page, or between panel-shown / hidden on the
// landing screen.
// ---------------------------------------------------------------------------

class _RightColumnPanel extends StatelessWidget {
  final Widget child;
  const _RightColumnPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.cardBg,
        borderRadius: BorderRadius.circular(_tileRadius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_tileRadius),
        child: child,
      ),
    );
  }
}

class _SettingsPanelBody extends StatelessWidget {
  final bool darkMode;
  final VoidCallback onToggleTheme;
  final VoidCallback onNoop;
  const _SettingsPanelBody({
    required this.darkMode,
    required this.onToggleTheme,
    required this.onNoop,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'SETTINGS',
            style: TextStyle(
              color: t.cardText,
              fontSize: 20,
              fontWeight: FontWeight.w500,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 22),
          _PanelRow(
            icon: darkMode
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined,
            label: darkMode ? 'Light mode' : 'Dark mode',
            onTap: onToggleTheme,
          ),
          _PanelRow(
            icon: Icons.notifications_active_outlined,
            label: 'Chime',
            onTap: onNoop,
          ),
          _PanelRow(
            icon: Icons.translate_outlined,
            label: 'Language',
            onTap: onNoop,
          ),
          const Spacer(),
          Divider(color: t.divider, height: 1),
          _PanelRow(
            icon: Icons.logout_outlined,
            label: 'Logout',
            onTap: onNoop,
          ),
        ],
      ),
    );
  }
}

class _PanelRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PanelRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: t.cardText),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                color: t.cardText,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.4,
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

/// Right-flank TOP badge — 115×115 rounded orange square labelled
/// "Settings". Opens the shared settings popover.
class _SettingsBadge extends StatelessWidget {
  final VoidCallback onTap;
  const _SettingsBadge({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _oCartsOrange,
      borderRadius: BorderRadius.circular(_tileRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_tileRadius),
        child: const Center(
          child: Text(
            'Settings',
            style: TextStyle(
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
