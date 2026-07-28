import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Painter that draws the L-hook rail from Figma: a short vertical
/// hairline whose TOP end curves outward into a hook, terminated by a
/// small dot. `hookLeft: true` produces the LEFT-flank rail (hook
/// curves off to the left); false makes the RIGHT-flank mirror image.
class _RailHookPainter extends CustomPainter {
  final Color color;
  final bool hookLeft;
  const _RailHookPainter({required this.color, required this.hookLeft});

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Vertical bar sits on the "inner" edge (i.e. the edge facing the
    // tile grid). For the left flank that's the right side of the
    // rail's box; for the right flank it's the left side.
    final barX = hookLeft ? size.width : 0.0;
    final hookRadius = size.width;

    final path = Path()
      ..moveTo(barX, size.height)
      ..lineTo(barX, hookRadius);

    if (hookLeft) {
      path.arcToPoint(
        const Offset(0, 0),
        radius: Radius.circular(hookRadius),
        clockwise: false,
      );
    } else {
      path.arcToPoint(
        Offset(size.width, 0),
        radius: Radius.circular(hookRadius),
        clockwise: true,
      );
    }
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _RailHookPainter old) =>
      old.color != color || old.hookLeft != hookLeft;
}

/// Which flank a [FlankRail] hangs off. The "open" swipe direction
/// depends on this: a right-side rail opens on swipe-left (finger
/// pushes the tile away from the rail into the canvas), a left-side
/// rail opens on swipe-right.
enum RailSide { left, right }

/// Fixed L-hook flank rail — visually static, purely a gesture surface.
///
/// The Figma treats these rails as decorative guides that also happen
/// to be the primary scroll+open input. The visual (hook + dot at tip)
/// never moves regardless of selection — selection is shown by the
/// consumer highlighting the currently-active card. This widget only
/// emits [onSelected] and [onSwipeOpen] events.
///
/// Gesture model:
///   - vertical pan → walks through [itemCount] rows; each row change
///     fires haptics + [onSelected].
///   - horizontal pan in the "open" direction past [_swipeDistanceOpen]
///     or flick velocity [_swipeVelocityOpen] fires [onSwipeOpen] with
///     the currently-selected index. First horizontal motion latches
///     that target so vertical drift afterward doesn't move which tile
///     opens.
class FlankRail extends StatefulWidget {
  final int itemCount;
  final int? selectedIndex;
  final RailSide side;

  /// Called when the finger scrubs to a new row.
  /// Ignored when [scrollController] is provided (rail becomes a
  /// scroll surface instead of a selection surface).
  final ValueChanged<int>? onSelected;

  /// Called when the finger swipes toward the canvas (opens the tile).
  /// Ignored when [scrollController] is provided.
  final ValueChanged<int>? onSwipeOpen;

  /// When set, vertical drag on the rail scrolls this controller
  /// instead of stepping selection. Horizontal drag is ignored in
  /// scroll mode. Use this to make the rail control an inner
  /// ScrollView (Inventory grid, product list, etc.).
  final ScrollController? scrollController;

  /// Draw the visual hook+dot when true. Set to false for wide invisible
  /// gesture strips that overlay the flank edges.
  final bool showVisual;
  final Color railColor;

  const FlankRail({
    super.key,
    required this.itemCount,
    required this.side,
    this.selectedIndex,
    this.onSelected,
    this.onSwipeOpen,
    this.scrollController,
    this.showVisual = true,
    this.railColor = const Color(0xCCCFCFCF),
  });

  @override
  State<FlankRail> createState() => _FlankRailState();
}

class _FlankRailState extends State<FlankRail> {
  static const double _dotSize = 8;
  static const double _swipeDistanceOpen = 40;
  static const double _swipeVelocityOpen = 260;

  /// Horizontal drift under this threshold is treated as noise (not
  /// an "open" attempt). Prevents accidental scroll freezes when the
  /// finger wobbles a few pixels sideways during a vertical scroll.
  static const double _horizontalArmThresholdPx = 12;

  /// Pixels of vertical travel needed for the selection to step by
  /// one row. Delta-based, not positional. Larger = calmer scroll.
  static const double _scrollStepPx = 90;

  double _openTravel = 0;
  double _horizontalDrift = 0;
  double _yAccum = 0;
  int? _lockedTarget;
  // Rail height captured at pan start so _handlePanEnd can compute
  // the drag→scroll ratio for its fling without re-invoking LayoutBuilder.
  double _panelHeight = 0;

  @override
  void initState() {
    super.initState();
    if (widget.showVisual) widget.scrollController?.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant FlankRail old) {
    super.didUpdateWidget(old);
    final oldListen = old.showVisual && old.scrollController != null;
    final newListen = widget.showVisual && widget.scrollController != null;
    if (oldListen != newListen || old.scrollController != widget.scrollController) {
      if (oldListen) old.scrollController?.removeListener(_onScroll);
      if (newListen) widget.scrollController?.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    if (widget.showVisual) widget.scrollController?.removeListener(_onScroll);
    super.dispose();
  }

  /// Fires on every scroll pixel; drives the marker dot's proportional
  /// position. Only registered when this rail actually renders the dot
  /// (showVisual == true). Invisible gesture-only rails skip the
  /// listener so scroll doesn't trigger 60 rebuilds/sec for nothing.
  void _onScroll() {
    if (mounted) setState(() {});
  }

  /// Marker position along the rail as a 0..1 fraction. Landing mode
  /// keeps the marker at the top of the hook (0.0). Scroll mode
  /// reflects the current scroll offset / max scroll extent, so as
  /// products get added and the scroll extent grows, the dot's
  /// position adjusts automatically like a scrollbar thumb.
  double get _markerT {
    final ctrl = widget.scrollController;
    if (ctrl != null && ctrl.hasClients) {
      final max = ctrl.position.maxScrollExtent;
      if (max <= 0) return 0;
      return (ctrl.position.pixels / max).clamp(0.0, 1.0);
    }
    return 0.0;
  }

  double get _openSign =>
      widget.side == RailSide.right ? -1 : 1;

  void _stepSelection(int delta) {
    if (delta == 0 || widget.itemCount <= 0) return;
    final current = widget.selectedIndex ?? 0;
    final next = (current + delta).clamp(0, widget.itemCount - 1);
    if (next != current) {
      HapticFeedback.selectionClick();
      widget.onSelected?.call(next);
    }
  }

  void _handlePanStart(DragStartDetails d, double panelHeight) {
    _openTravel = 0;
    _horizontalDrift = 0;
    _yAccum = 0;
    _lockedTarget = null;
    _panelHeight = panelHeight;
  }

  /// Drag-to-scroll multiplier. The rail is short (~300 dp tall) but
  /// drives lists that can be tens of thousands of dp long, so a raw
  /// 1:1 mapping barely moves the list. Instead we treat the rail as
  /// a scrollbar thumb: dragging the rail's full height covers the
  /// full scrollable extent — CAPPED so ultra-long lists don't
  /// translate 1 dp of finger to 60+ dp of content, which reads as
  /// jumpy on the tablet. The cap keeps browsing calm; a flick still
  /// covers ground because the fling uses the unclamped ratio.
  static const double _dragRatioMax = 12;
  static const double _dragRatioMin = 1;
  double _railScrollRatio(ScrollPosition pos, {bool clamp = false}) {
    if (_panelHeight <= 0) return 1;
    final max = pos.maxScrollExtent;
    if (max <= 0) return 1;
    final raw = max / _panelHeight;
    return clamp ? raw.clamp(_dragRatioMin, _dragRatioMax) : raw;
  }

  void _handlePanUpdate(DragUpdateDetails d, double panelHeight) {
    // Scroll-controller mode — rail acts as a scroll surface for an
    // inner ScrollView. Vertical drag pumps the controller offset;
    // horizontal drag is ignored so the rail doesn't fight with
    // scrollable content on the canvas.
    final controller = widget.scrollController;
    if (controller != null) {
      if (!controller.hasClients) return;
      final pos = controller.position;
      final ratio = _railScrollRatio(pos, clamp: true);
      // Finger UP (dy < 0)  → offset increases (reveal more below).
      // Finger DOWN (dy > 0) → offset decreases (return to top).
      // Clamped ratio keeps deliberate drag calm on long lists;
      // fling on release still uses the raw scrollbar-thumb ratio.
      final next = (pos.pixels - d.delta.dy * ratio)
          .clamp(pos.minScrollExtent, pos.maxScrollExtent);
      controller.jumpTo(next);
      return;
    }

    // Selection mode — accumulate horizontal drift in the "open"
    // direction. Small wobbles under [_horizontalArmThresholdPx]
    // don't lock scroll.
    final opening = d.delta.dx * _openSign;
    if (opening > 0) _horizontalDrift += opening;

    if (_horizontalDrift >= _horizontalArmThresholdPx) {
      _lockedTarget ??= widget.selectedIndex;
      if (opening > 0) _openTravel += opening;
    } else {
      _yAccum += d.delta.dy;
      while (_yAccum <= -_scrollStepPx) {
        _yAccum += _scrollStepPx;
        _stepSelection(1);
      }
      while (_yAccum >= _scrollStepPx) {
        _yAccum -= _scrollStepPx;
        _stepSelection(-1);
      }
    }
  }

  void _handlePanEnd(DragEndDetails d) {
    // Scroll-controller mode — apply a fling from the finger's exit
    // velocity. Uses the raw (unclamped) rail:content ratio so a
    // hard flick covers real distance even on the longest lists.
    // Duration scales with target distance so a light flick decays
    // quickly and a big throw stays smooth to the end.
    final controller = widget.scrollController;
    if (controller != null) {
      if (controller.hasClients) {
        final vy = d.velocity.pixelsPerSecond.dy;
        // Ignore weak lifts — under this it's a stationary release,
        // not a flick, and shouldn't spin the list.
        if (vy.abs() > 80) {
          final pos = controller.position;
          final ratio = _railScrollRatio(pos);
          // 0.22 = seconds of continued motion a flick "buys" before
          // deceleration. Slightly longer than a straight physics
          // integral so releases feel unhurried and elegant.
          final flingDist = -vy * ratio * 0.22;
          final target = (pos.pixels + flingDist)
              .clamp(pos.minScrollExtent, pos.maxScrollExtent);
          final travel = (target - pos.pixels).abs();
          if (travel > 1) {
            // 0.6 ms per dp, clamped to a sane range: a 100 dp
            // nudge lands in ~250 ms; a 3000 dp throw takes ~900 ms
            // and stays smooth all the way down.
            final ms = (travel * 0.6).clamp(220.0, 900.0).round();
            pos.animateTo(
              target,
              duration: Duration(milliseconds: ms),
              curve: Curves.easeOutQuint,
            );
          }
        }
      }
      _openTravel = 0;
      _horizontalDrift = 0;
      _yAccum = 0;
      _lockedTarget = null;
      return;
    }

    // Selection mode — swipe-open on horizontal fling or displacement.
    final vx = d.velocity.pixelsPerSecond.dx * _openSign;
    final dragged = _openTravel >= _swipeDistanceOpen;
    final flicked = vx >= _swipeVelocityOpen;
    if ((dragged || flicked) && _lockedTarget != null) {
      widget.onSwipeOpen?.call(_lockedTarget!);
    }
    _openTravel = 0;
    _horizontalDrift = 0;
    _yAccum = 0;
    _lockedTarget = null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => _handlePanStart(d, h),
          onPanUpdate: (d) => _handlePanUpdate(d, h),
          onPanEnd: _handlePanEnd,
          child: widget.showVisual
              ? _RailVisual(
                  side: widget.side,
                  color: widget.railColor,
                  dotSize: _dotSize,
                  markerT: _markerT,
                )
              : const SizedBox.expand(),
        );
      },
    );
  }
}

/// Purely visual layer: the L-hook line and the fixed dot at the tip
/// of the hook. Never repaints on selection changes because it doesn't
/// depend on them.
class _RailVisual extends StatelessWidget {
  final RailSide side;
  final Color color;
  final double dotSize;

  /// 0..1 position of the marker dot along the rail. 0 = at the hook
  /// tip (top), 1 = at the bottom of the vertical bar. In selection
  /// mode this stays 0 (dot lives at the hook); in scroll mode it
  /// tracks the proportional scroll offset.
  final double markerT;

  const _RailVisual({
    required this.side,
    required this.color,
    required this.dotSize,
    this.markerT = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    // Hooks curve INWARD toward the tile grid (per client). For the
    // left flank rail, the bar sits on the outer (screen-edge) side
    // and the arc + dot land on the inner side facing the tiles.
    // Right flank rail is the mirror image.
    final hookInward = side == RailSide.right;
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        // Dot travels from the hook tip (top, y = -dotSize/2) down to
        // near the bottom of the visible bar. Slight padding at each
        // end so it never clips.
        final travel = (h - dotSize).clamp(0.0, double.infinity);
        final dotTop = -dotSize / 2 + travel * markerT;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _RailHookPainter(
                  color: color,
                  hookLeft: hookInward,
                ),
              ),
            ),
            Positioned(
              top: dotTop,
              right: side == RailSide.left ? -dotSize / 2 : null,
              left: side == RailSide.right ? -dotSize / 2 : null,
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
