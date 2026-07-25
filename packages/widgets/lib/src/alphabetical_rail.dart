import 'package:flutter/material.dart';

/// Vertical A–Z strip alongside a long alphabetized list. Tap a letter
/// to jump to that section; drag the finger up/down along the strip to
/// scrub continuously through letters, in the same idiom as the iOS
/// Contacts index or Android's [`FastScroller`].
///
/// The rail is intentionally stateless about the list itself — it only
/// knows which letters are available and which one is currently
/// highlighted. Wiring it to a real list is [AlphabeticalListView]'s job
/// (see alphabetical_list_view.dart); the rail on its own is reusable
/// against any scrollable/pageable content, not just lists.
class AlphabeticalRail extends StatefulWidget {
  /// The set of letters that currently correspond to at least one entry
  /// in the underlying content. Letters not in this set are drawn
  /// dimmed and are non-interactive — nothing to jump to.
  final Set<String> availableLetters;

  /// Called every time the user taps or drags onto a new *available*
  /// letter. Callers listen to this and scroll/page their content in
  /// response. Not called for unavailable letters.
  final ValueChanged<String> onLetterSelected;

  /// The letter to render as visually active. Callers typically pass
  /// whatever section the list is currently scrolled to, so the rail
  /// stays in sync when the user scrolls the list itself rather than
  /// using the rail.
  final String? highlightedLetter;

  /// A–Z. Kept as a field only so tests can shorten it if needed.
  final List<String> letters;

  final Color activeColor;
  final Color inactiveColor;
  final Color disabledColor;

  const AlphabeticalRail({
    super.key,
    required this.availableLetters,
    required this.onLetterSelected,
    this.highlightedLetter,
    this.letters = _defaultLetters,
    this.activeColor = const Color(0xFFC1551C), // ClonePos rust
    this.inactiveColor = const Color(0xFF4A3728), // ClonePos walnut
    this.disabledColor = const Color(0x554A3728),
  });

  static const List<String> _defaultLetters = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
  ];

  @override
  State<AlphabeticalRail> createState() => _AlphabeticalRailState();
}

class _AlphabeticalRailState extends State<AlphabeticalRail> {
  String? _lastEmitted;

  void _resolveAt(double localY, double railHeight) {
    if (railHeight <= 0 || widget.letters.isEmpty) return;
    final rowHeight = railHeight / widget.letters.length;
    final index = (localY / rowHeight).floor().clamp(0, widget.letters.length - 1);
    final letter = widget.letters[index];
    if (letter == _lastEmitted) return;
    if (!widget.availableLetters.contains(letter)) return;
    _lastEmitted = letter;
    widget.onLetterSelected(letter);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final railHeight = constraints.maxHeight;
        final rowHeight = railHeight / widget.letters.length;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _resolveAt(d.localPosition.dy, railHeight),
          onVerticalDragStart: (d) => _resolveAt(d.localPosition.dy, railHeight),
          onVerticalDragUpdate: (d) => _resolveAt(d.localPosition.dy, railHeight),
          onVerticalDragEnd: (_) => _lastEmitted = null,
          onVerticalDragCancel: () => _lastEmitted = null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final letter in widget.letters)
                SizedBox(
                  height: rowHeight,
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _RailLetter(
                      letter: letter,
                      available: widget.availableLetters.contains(letter),
                      active: letter == widget.highlightedLetter,
                      activeColor: widget.activeColor,
                      inactiveColor: widget.inactiveColor,
                      disabledColor: widget.disabledColor,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _RailLetter extends StatelessWidget {
  final String letter;
  final bool available;
  final bool active;
  final Color activeColor;
  final Color inactiveColor;
  final Color disabledColor;

  const _RailLetter({
    required this.letter,
    required this.available,
    required this.active,
    required this.activeColor,
    required this.inactiveColor,
    required this.disabledColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = !available
        ? disabledColor
        : active
            ? activeColor
            : inactiveColor;
    return Text(
      letter,
      style: TextStyle(
        fontSize: 11,
        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        letterSpacing: -0.44, // spec's global -4% letter-spacing
        color: color,
      ),
    );
  }
}
