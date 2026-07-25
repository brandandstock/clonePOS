import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One entry on an [IconIndexRail]. The [icon] renders in the column;
/// the [label] appears alongside the icon inside the preview bubble.
class RailItem {
  final IconData icon;
  final String label;
  const RailItem({required this.icon, required this.label});
}

/// Icon-driven fast scroller — the successor to `AlphabetIndexRail` for
/// the Secondary display's 240x400 panel. Client's decision after
/// seeing the A-Z version: an alphabet rail creates letter collisions
/// (three A-categories) and mostly-empty letters. Icons instead —
/// one glyph per Master feature, same wave and bubble mechanics.
///
/// Interactions:
/// - Vertical drag / tap: scrubs through the icon column. Same
///   Gaussian wave that pushes nearby icons leftward, same
///   snake-following bubble, same selection-click haptic on the
///   nearest-icon change.
/// - Horizontal drag leftward past [_swipeThreshold]: fires
///   [onSwipeLeft] with the active index. This is the "open the
///   feature into the full Master display" gesture the client asked
///   for. Flutter's gesture arena disambiguates: the first meaningful
///   direction of the finger's travel wins.
///
/// The rail deliberately does not manage the "which category is the
/// front card" state itself — it just emits selection and open events.
/// The dashboard owns the state so it can also react to the back
/// button, the toggle chip, and future non-rail entry points without
/// coordinating with this widget.
class IconIndexRail extends StatefulWidget {
  final List<RailItem> items;
  final ValueChanged<int>? onSelected;
  final ValueChanged<int>? onSwipeLeft;

  final Color accentColor;
  final Color primaryColor;
  final Color mutedColor;
  final Color surfaceColor;

  const IconIndexRail({
    super.key,
    required this.items,
    this.onSelected,
    this.onSwipeLeft,
    this.accentColor = const Color(0xFFC1551C), // rust
    this.primaryColor = const Color(0xFF4A3728), // walnut
    this.mutedColor = const Color(0x664A3728),
    this.surfaceColor = const Color(0xFFFFFBF2), // cream card
  });

  @override
  State<IconIndexRail> createState() => _IconIndexRailState();
}

class _IconIndexRailState extends State<IconIndexRail>
    with SingleTickerProviderStateMixin {
  static const double _columnWidth = 60;
  static const double _bubbleGap = 4;
  static const double _bubbleSize = 92;
  static const double _iconSize = 22;

  // Wave shape — same idea as the letter rail, tuned for the smaller
  // item count. Fewer, larger items → a wider softer wave feels right.
  static const double _waveMaxOffset = 26;
  static const double _waveSigmaFactor = 1.4; // multiples of rowHeight

  // Swipe-left open thresholds. Either can trigger:
  //   * distance-based — you dragged the icon this far leftward, so
  //     you clearly meant it, regardless of how fast;
  //   * velocity-based — you flicked, so speed alone is enough even
  //     if you didn't travel far.
  // The previous revision only accepted a fast flick, which is why
  // deliberate slow swipes felt unresponsive.
  static const double _swipeDistanceOpen = 30;
  static const double _swipeVelocityOpen = 200;

  late final AnimationController _entrance;

  final ValueNotifier<double?> _touchY = ValueNotifier<double?>(null);
  final ValueNotifier<int?> _activeIndex = ValueNotifier<int?>(null);

  /// Cumulative leftward drag distance during the current pan.
  /// Positive number of pixels; reset at each pan start.
  double _horizontalTravel = 0;

  /// Icon that gets opened if the current pan ends with enough
  /// leftward travel. Set the first time the finger moves leftward and
  /// then held constant — subsequent Y-drift updates the bubble/wave
  /// for visual feedback but never changes what would open. Prevents
  /// the "I aimed at icon 4 but icon 6 opened" complaint.
  int? _lockedTarget;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _touchY.dispose();
    _activeIndex.dispose();
    super.dispose();
  }

  /// Update the finger position and (unless [freezeSelection] is true)
  /// the active icon based on Y. The freeze flag is what stops
  /// Y-drift from changing the target once the user has committed to
  /// a leftward swipe.
  void _handleTouch(
    double localY,
    double columnHeight, {
    bool freezeSelection = false,
  }) {
    if (columnHeight <= 0 || widget.items.isEmpty) return;
    final clamped = localY.clamp(0.0, columnHeight);
    _touchY.value = clamped;

    if (freezeSelection) return;

    final rowHeight = columnHeight / widget.items.length;
    final index = (clamped / rowHeight).floor().clamp(0, widget.items.length - 1);
    if (index != _activeIndex.value) {
      _activeIndex.value = index;
      HapticFeedback.selectionClick();
      widget.onSelected?.call(index);
    }
  }

  void _endInteraction() {
    _touchY.value = null;
    _activeIndex.value = null;
    _horizontalTravel = 0;
    _lockedTarget = null;
  }

  // Unified pan handler — replaces the separate vertical + horizontal
  // drag pair. That pair had a gesture-arena bug: whichever direction
  // the finger moved *first* won the arena, so a scroll-then-swipe-
  // left continuous gesture was locked as vertical and the horizontal
  // callbacks never fired. Pan handles both axes so the user can
  // scroll to an icon and then push left in the same touch.
  void _handlePanStart(DragStartDetails details, double columnHeight) {
    _horizontalTravel = 0;
    _lockedTarget = null;
    _handleTouch(details.localPosition.dy, columnHeight);
  }

  void _handlePanUpdate(DragUpdateDetails details, double columnHeight) {
    // The first leftward motion latches the current active icon as
    // the open target. Any subsequent vertical drift updates the
    // bubble via _touchY but doesn't move _activeIndex or fire
    // onSelected — the front card stays put and the correct icon
    // will open on release.
    if (details.delta.dx < 0) {
      if (_horizontalTravel == 0) {
        _lockedTarget = _activeIndex.value;
      }
      _horizontalTravel += -details.delta.dx;
    }
    _handleTouch(
      details.localPosition.dy,
      columnHeight,
      freezeSelection: _lockedTarget != null,
    );
  }

  void _handlePanEnd(DragEndDetails details) {
    final vx = details.velocity.pixelsPerSecond.dx;
    final draggedFarEnough = _horizontalTravel >= _swipeDistanceOpen;
    final flickedFastEnough = vx <= -_swipeVelocityOpen;
    if ((draggedFarEnough || flickedFastEnough) && _lockedTarget != null) {
      widget.onSwipeLeft?.call(_lockedTarget!);
    }
    _endInteraction();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const verticalPad = 6.0;
        final columnHeight = constraints.maxHeight - verticalPad * 2;
        // RepaintBoundaries around bubble and column so wave frames
        // don't force a repaint of the whole Secondary panel (and,
        // transitively, whatever's behind it in the dashboard Stack).
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // _buildBubble returns a Positioned; wrapping it in a
            // RepaintBoundary here would break the Stack->Positioned
            // parent-data contract, so the RepaintBoundary lives
            // *inside* the Positioned instead (see _buildBubble).
            _buildBubble(constraints.maxHeight, verticalPad),
            Positioned(
              right: 0,
              top: verticalPad,
              width: _columnWidth,
              height: columnHeight,
              child: RepaintBoundary(child: _buildColumn(columnHeight)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildColumn(double columnHeight) {
    final rowHeight = columnHeight / widget.items.length;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => _handleTouch(d.localPosition.dy, columnHeight),
      onTapUp: (_) => _endInteraction(),
      onTapCancel: _endInteraction,
      // Unified pan — no arena split between vertical and horizontal.
      // Scrub down to an icon then push left in the same touch works
      // because pan tracks 2D deltas continuously; the leftward
      // motion latches the target and holds it even if Y drifts.
      onPanStart: (d) => _handlePanStart(d, columnHeight),
      onPanUpdate: (d) => _handlePanUpdate(d, columnHeight),
      onPanEnd: _handlePanEnd,
      onPanCancel: _endInteraction,
      child: ValueListenableBuilder<double?>(
        valueListenable: _touchY,
        builder: (context, touchY, _) {
          // Precompute the Gaussian denominator once per rebuild —
          // sigma depends only on rowHeight so it doesn't change
          // per-cell. Saves 7 multiplications per drag frame,
          // negligible individually but keeps the hot loop tight.
          final sigma = rowHeight * _waveSigmaFactor;
          final twoSigmaSq = 2 * sigma * sigma;
          return ValueListenableBuilder<int?>(
            valueListenable: _activeIndex,
            builder: (context, activeIndex, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < widget.items.length; i++)
                    _IconCell(
                      item: widget.items[i],
                      rowHeight: rowHeight,
                      index: i,
                      totalRows: widget.items.length,
                      entrance: _entrance,
                      waveOffset: _waveOffsetAt(i, rowHeight, touchY, twoSigmaSq),
                      isActive: i == activeIndex,
                      accent: widget.accentColor,
                      primary: widget.primaryColor,
                      muted: widget.mutedColor,
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // Wave offset for cell [index] given the current [touchY] and the
  // per-rebuild-constant [twoSigmaSq]. Kept as a pure static-ish
  // method so the hot loop stays branchless past the null-check.
  double _waveOffsetAt(int index, double rowHeight, double? touchY,
      double twoSigmaSq) {
    if (touchY == null) return 0;
    final dy = rowHeight * (index + 0.5) - touchY;
    return _waveMaxOffset * math.exp(-(dy * dy) / twoSigmaSq);
  }

  Widget _buildBubble(double panelHeight, double verticalPad) {
    return Positioned(
      right: _columnWidth + _bubbleGap,
      top: 0,
      bottom: 0,
      width: _bubbleSize + 60, // extra room for the label to the left
      child: RepaintBoundary(
        child: IgnorePointer(
        child: ValueListenableBuilder<double?>(
          valueListenable: _touchY,
          builder: (context, touchY, _) {
            final visible = touchY != null;
            final travel = panelHeight - _bubbleSize;
            final centreY = visible
                ? (verticalPad + touchY!).clamp(
                    _bubbleSize / 2, panelHeight - _bubbleSize / 2)
                : panelHeight / 2;
            final alignmentY = travel <= 0
                ? 0.0
                : (2 * (centreY - _bubbleSize / 2) / travel - 1)
                    .clamp(-1.0, 1.0);

            // Plain [Align] instead of [AnimatedAlign]: the finger
            // already provides a continuous 60 Hz position stream, so
            // smoothing it with a 55 ms tween just adds perceived lag
            // and produces the "chasing" hitch on fast scrubs. Direct
            // alignment matches the finger tip 1:1 each frame — this
            // is the biggest single win for smoothness.
            //
            // Opacity + scale still use implicit animations because
            // they animate a *state change* (visible → not visible),
            // not a continuous input. Those transitions want a curve.
            return Align(
              alignment: Alignment(1.0, alignmentY),
              child: SizedBox(
                height: _bubbleSize,
                child: AnimatedOpacity(
                  duration: Duration(milliseconds: visible ? 120 : 220),
                  curve: Curves.easeOutCubic,
                  opacity: visible ? 1 : 0,
                  child: AnimatedScale(
                    duration: Duration(milliseconds: visible ? 140 : 220),
                    curve: visible ? Curves.easeOutBack : Curves.easeIn,
                    scale: visible ? 1.0 : 0.75,
                    child: ValueListenableBuilder<int?>(
                      valueListenable: _activeIndex,
                      builder: (context, activeIndex, _) {
                        final item = (activeIndex == null ||
                                activeIndex >= widget.items.length)
                            ? null
                            : widget.items[activeIndex];
                        return _PreviewTile(
                          icon: item?.icon,
                          label: item?.label ?? '',
                          accent: widget.accentColor,
                          surface: widget.surfaceColor,
                          ink: widget.primaryColor,
                          size: _bubbleSize,
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        ),
      ),
    );
  }
}

class _IconCell extends StatelessWidget {
  final RailItem item;
  final double rowHeight;
  final int index;
  final int totalRows;
  final AnimationController entrance;
  final double waveOffset;
  final bool isActive;
  final Color accent;
  final Color primary;
  final Color muted;

  const _IconCell({
    required this.item,
    required this.rowHeight,
    required this.index,
    required this.totalRows,
    required this.entrance,
    required this.waveOffset,
    required this.isActive,
    required this.accent,
    required this.primary,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    final start = (index / totalRows) * 0.55;
    final end = (start + 0.45).clamp(0.0, 1.0);
    final entranceAnim = CurvedAnimation(
      parent: entrance,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );

    final color = isActive ? accent : primary;

    return SizedBox(
      height: rowHeight,
      child: AnimatedBuilder(
        animation: entranceAnim,
        builder: (context, _) {
          final t = entranceAnim.value;
          return Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(-waveOffset + 12 * (1 - t), 0),
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(
                    item.icon,
                    size: isActive ? 26 : 22,
                    color: color,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PreviewTile extends StatelessWidget {
  final IconData? icon;
  final String label;
  final Color accent;
  final Color surface;
  final Color ink;
  final double size;

  const _PreviewTile({
    required this.icon,
    required this.label,
    required this.accent,
    required this.surface,
    required this.ink,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        minWidth: size,
        maxHeight: size,
      ),
      padding: EdgeInsets.symmetric(horizontal: size * 0.18, vertical: 0),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(size * 0.24),
        border: Border.all(color: accent, width: 2),
        boxShadow: [
          BoxShadow(
            color: ink.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: size * 0.44, color: accent),
          if (icon != null) SizedBox(width: size * 0.12),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: size * 0.14,
                fontWeight: FontWeight.w800,
                color: ink,
                letterSpacing: -size * 0.006,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
