import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The animated A-Z index rail that lives in the Secondary display's
/// 240x400 panel. Modeled on the Bitpit Launcher fast-scroller:
///
/// - The A-Z column runs down the right edge of the panel.
/// - As the finger drags the rail, letters near the finger are pushed
///   leftward on a Gaussian curve, forming a **curvy wave / bulge**
///   pointing toward the touch point. The letter directly under the
///   finger travels furthest; the neighbours displace by less; letters
///   far from the finger stay at rest. This is the "curve" the client
///   asked for after seeing the previous no-wave version.
/// - Only the touched letter changes colour (walnut → rust bold). The
///   wave is a **position** effect, not a magnification effect — every
///   letter stays the same size.
/// - A preview bubble sits to the left of the column, snaking up and
///   down with the finger via an [AnimatedAlign] tween. Fades in on
///   touch-down, fades out on release.
/// - Every letter change fires a `selectionClick` haptic pulse.
/// - On first mount the letters fade+slide in on a staggered timeline.
///
/// Performance note: the column rebuilds on every touchY tick (so the
/// wave stays glued to the finger), but the ValueListenableBuilder is
/// scoped to the column subtree — the bubble and the outer scaffolding
/// don't rebuild. Repainting 26 letter widgets per frame is well
/// inside Flutter's budget on the target hardware.
class AlphabetIndexRail extends StatefulWidget {
  final ValueChanged<String>? onLetterSelected;

  /// Optional filter — letters not in this set render dimmed and are
  /// non-interactive. Pass `null` (default) to treat every letter as
  /// available, which is how the rail behaves when it's standalone.
  final Set<String>? availableLetters;

  final Color accentColor;
  final Color primaryColor;
  final Color mutedColor;
  final Color surfaceColor;

  const AlphabetIndexRail({
    super.key,
    this.onLetterSelected,
    this.availableLetters,
    this.accentColor = const Color(0xFFC1551C), // rust
    this.primaryColor = const Color(0xFF4A3728), // walnut
    this.mutedColor = const Color(0x664A3728),
    this.surfaceColor = const Color(0xFFFFFBF2), // cream card
  });

  @override
  State<AlphabetIndexRail> createState() => _AlphabetIndexRailState();
}

class _AlphabetIndexRailState extends State<AlphabetIndexRail>
    with SingleTickerProviderStateMixin {
  static const List<String> _letters = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
  ];

  // The touchable column is a wide strip so the wave has room to
  // displace letters leftward without being clipped.
  static const double _columnWidth = 56;
  static const double _bubbleGap = 4;
  static const double _bubbleSize = 84;

  // Wave shape.
  //
  // _waveMaxOffset — how far the peak letter (the exact one under the
  //     finger) is pushed leftward. Bigger = more dramatic curve.
  // _waveSigma    — Gaussian half-width in pixels. Bigger = wider,
  //     softer wave affecting more letters; smaller = tight bulge
  //     around just one or two letters.
  static const double _waveMaxOffset = 22;
  static const double _waveSigma = 42;

  late final AnimationController _entrance;

  /// Finger Y within the letter column (0..columnHeight), or null when
  /// the finger is not down. The column subtree listens.
  final ValueNotifier<double?> _touchY = ValueNotifier<double?>(null);

  /// Whichever letter is currently under the finger. Bubble listens.
  final ValueNotifier<String?> _activeLetter = ValueNotifier<String?>(null);

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
    _activeLetter.dispose();
    super.dispose();
  }

  bool _isAvailable(String letter) =>
      widget.availableLetters == null ||
      widget.availableLetters!.contains(letter);

  void _handleTouch(double localY, double columnHeight) {
    if (columnHeight <= 0) return;
    final clamped = localY.clamp(0.0, columnHeight);
    _touchY.value = clamped;

    final rowHeight = columnHeight / _letters.length;
    final index = (clamped / rowHeight).floor().clamp(0, _letters.length - 1);
    final letter = _letters[index];
    if (!_isAvailable(letter)) return;
    if (letter != _activeLetter.value) {
      _activeLetter.value = letter;
      HapticFeedback.selectionClick();
      widget.onLetterSelected?.call(letter);
    }
  }

  void _endInteraction() {
    _touchY.value = null;
    _activeLetter.value = null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const verticalPad = 8.0;
        final columnHeight = constraints.maxHeight - verticalPad * 2;
        return Stack(
          // Clip.none — letters may translate leftward past the column
          // strip's own bounds during the wave; we don't want those
          // clipped by the parent Stack.
          clipBehavior: Clip.none,
          children: [
            _buildBubble(constraints.maxHeight, verticalPad),
            Positioned(
              right: 0,
              top: verticalPad,
              width: _columnWidth,
              height: columnHeight,
              child: _buildColumn(columnHeight),
            ),
          ],
        );
      },
    );
  }

  Widget _buildColumn(double columnHeight) {
    final rowHeight = columnHeight / _letters.length;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => _handleTouch(d.localPosition.dy, columnHeight),
      onTapUp: (_) => _endInteraction(),
      onTapCancel: _endInteraction,
      onVerticalDragStart: (d) => _handleTouch(d.localPosition.dy, columnHeight),
      onVerticalDragUpdate: (d) =>
          _handleTouch(d.localPosition.dy, columnHeight),
      onVerticalDragEnd: (_) => _endInteraction(),
      onVerticalDragCancel: _endInteraction,
      // Column-wide ValueListenableBuilder — recomputes every letter's
      // wave displacement on each touchY tick. Cheap: no widget-tree
      // churn beyond Transform matrices and one Text style flip.
      child: ValueListenableBuilder<double?>(
        valueListenable: _touchY,
        builder: (context, touchY, _) {
          return ValueListenableBuilder<String?>(
            valueListenable: _activeLetter,
            builder: (context, activeLetter, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < _letters.length; i++)
                    _LetterCell(
                      letter: _letters[i],
                      rowHeight: rowHeight,
                      index: i,
                      totalRows: _letters.length,
                      entrance: _entrance,
                      waveOffset: _waveOffsetFor(i, rowHeight, touchY),
                      isActive: _letters[i] == activeLetter,
                      available: _isAvailable(_letters[i]),
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

  /// Gaussian-weighted horizontal displacement for the letter at
  /// [index]. Returns a positive number of pixels the letter should
  /// translate **leftward** (i.e. the Transform.translate x should be
  /// the negation of this). Zero when the finger isn't down.
  double _waveOffsetFor(int index, double rowHeight, double? touchY) {
    if (touchY == null) return 0;
    final letterCentreY = rowHeight * (index + 0.5);
    final dy = letterCentreY - touchY;
    final weight = math.exp(-(dy * dy) / (2 * _waveSigma * _waveSigma));
    return _waveMaxOffset * weight;
  }

  Widget _buildBubble(double panelHeight, double verticalPad) {
    // Positioned is a ParentDataWidget — must be a *direct* Stack child.
    // Wrapping AnimatedPositioned inside a ValueListenableBuilder breaks
    // the parent-data chain and the bubble renders 0×0. Instead we take
    // a full-height strip and animate the vertical position with an
    // AnimatedAlign inside, which composes fine with rebuilds.
    return Positioned(
      right: _columnWidth + _bubbleGap,
      top: 0,
      bottom: 0,
      width: _bubbleSize,
      child: IgnorePointer(
        child: ValueListenableBuilder<double?>(
          valueListenable: _touchY,
          builder: (context, touchY, _) {
            final visible = touchY != null;
            final travel = panelHeight - _bubbleSize;
            final centreY = visible
                ? (verticalPad + touchY).clamp(
                    _bubbleSize / 2, panelHeight - _bubbleSize / 2)
                : panelHeight / 2;
            final alignmentY = travel <= 0
                ? 0.0
                : (2 * (centreY - _bubbleSize / 2) / travel - 1)
                    .clamp(-1.0, 1.0);

            return AnimatedAlign(
              duration: const Duration(milliseconds: 55),
              curve: Curves.easeOutCubic,
              alignment: Alignment(0, alignmentY),
              child: SizedBox(
                width: _bubbleSize,
                height: _bubbleSize,
                child: AnimatedOpacity(
                  duration: Duration(milliseconds: visible ? 120 : 220),
                  curve: Curves.easeOutCubic,
                  opacity: visible ? 1 : 0,
                  child: AnimatedScale(
                    duration: Duration(milliseconds: visible ? 140 : 220),
                    curve: visible ? Curves.easeOutBack : Curves.easeIn,
                    scale: visible ? 1.0 : 0.7,
                    child: ValueListenableBuilder<String?>(
                      valueListenable: _activeLetter,
                      builder: (context, letter, _) => _PreviewTile(
                        letter: letter ?? ' ',
                        accent: widget.accentColor,
                        surface: widget.surfaceColor,
                        ink: widget.primaryColor,
                        size: _bubbleSize,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LetterCell extends StatelessWidget {
  final String letter;
  final double rowHeight;
  final int index;
  final int totalRows;
  final AnimationController entrance;
  final double waveOffset;
  final bool isActive;
  final bool available;
  final Color accent;
  final Color primary;
  final Color muted;

  const _LetterCell({
    required this.letter,
    required this.rowHeight,
    required this.index,
    required this.totalRows,
    required this.entrance,
    required this.waveOffset,
    required this.isActive,
    required this.available,
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

    final color = !available
        ? muted
        : isActive
            ? accent
            : primary;

    return SizedBox(
      height: rowHeight,
      child: AnimatedBuilder(
        animation: entranceAnim,
        builder: (context, _) {
          final t = entranceAnim.value;
          return Opacity(
            opacity: t,
            child: Transform.translate(
              // Wave pushes letter leftward; entrance slides in from the
              // right. Combine both offsets on the same axis.
              offset: Offset(-waveOffset + 10 * (1 - t), 0),
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(
                    letter,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          isActive ? FontWeight.w800 : FontWeight.w500,
                      letterSpacing: -0.48,
                      color: color,
                      height: 1.0,
                    ),
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
  final String letter;
  final Color accent;
  final Color surface;
  final Color ink;
  final double size;

  const _PreviewTile({
    required this.letter,
    required this.accent,
    required this.surface,
    required this.ink,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
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
      child: Text(
        letter,
        style: TextStyle(
          fontSize: size * 0.6,
          fontWeight: FontWeight.w800,
          color: accent,
          letterSpacing: -size * 0.024,
          height: 1.0,
        ),
      ),
    );
  }
}
