import 'dart:ui';
import 'package:flutter/material.dart';
import 'master_dashboard_screen.dart' show MenuCategory;

/// New Master-display content per the Figma at node 35-219: a purple
/// canvas with a stack of glassmorphism cards. The front card names
/// the currently-selected category (driven by the icon rail on the
/// Secondary panel); two more strips peek from beneath it.
///
/// When [openedIndex] is set, the whole 980×740 region cross-fades to
/// that category's fullscreen content — that's the "swipe-left to open
/// the feature" transition. The back FAB in the dashboard button row
/// clears [openedIndex] to return.
class MasterStackView extends StatelessWidget {
  final List<MenuCategory> categories;

  /// Index of the category shown as the front glass card in stacked
  /// mode. Ignored when [openedIndex] is non-null.
  final int selectedIndex;

  /// If non-null, that category's content fills the whole region and
  /// the stacked cards are hidden.
  final int? openedIndex;

  const MasterStackView({
    super.key,
    required this.categories,
    required this.selectedIndex,
    this.openedIndex,
  });

  @override
  Widget build(BuildContext context) {
    // Keys deliberately do NOT include selectedIndex — the stack must
    // stay identity-stable while the rail is scrubbed, so its front
    // card just re-renders in place. Otherwise AnimatedSwitcher
    // treats every rail tick as a different child and cross-fades
    // between them, which is the flicker the client called out.
    // Only the stack↔opened boundary crosses the AnimatedSwitcher.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        // Opened feature slides in from the right (mirroring the
        // swipe-left gesture that summoned it); stack fades out.
        final slide = Tween<Offset>(
          begin: const Offset(0.10, 0),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: openedIndex != null
          ? _OpenedFeature(
              key: const ValueKey('opened'),
              category: categories[openedIndex!],
            )
          : _GlassStack(
              key: const ValueKey('stack'),
              categories: categories,
              frontIndex: selectedIndex,
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Purple canvas + stacked glass cards.
// ---------------------------------------------------------------------------

const Color _canvasPurple = Color(0xFF4E1A4E);
const Color _canvasPurpleDeep = Color(0xFF2F0F2F);

class _GlassStack extends StatelessWidget {
  final List<MenuCategory> categories;
  final int frontIndex;

  const _GlassStack({
    super.key,
    required this.categories,
    required this.frontIndex,
  });

  @override
  Widget build(BuildContext context) {
    // Front card + two peek strips. We show the next-two categories
    // (cyclic) as the peeks so scrubbing the rail keeps a visible
    // "what's coming" feel.
    final n = categories.length;
    final peekA = categories[(frontIndex + 1) % n];
    final peekB = categories[(frontIndex + 2) % n];

    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.1,
          colors: [_canvasPurple, _canvasPurpleDeep],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 90, vertical: 90),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              flex: 3,
              child: _FrontGlassCard(category: categories[frontIndex]),
            ),
            const SizedBox(height: 10),
            _PeekGlassStrip(category: peekA, insetX: 20),
            const SizedBox(height: 6),
            _PeekGlassStrip(category: peekB, insetX: 42),
          ],
        ),
      ),
    );
  }
}

class _FrontGlassCard extends StatelessWidget {
  final MenuCategory category;
  const _FrontGlassCard({required this.category});

  @override
  Widget build(BuildContext context) {
    return _GlassContainer(
      borderRadius: 28,
      // A soft radial glow behind the title — this is what gives the
      // blur something to bite on and what makes the card read as
      // "lit from within". Colour picks up from the category so the
      // stack still hints at which section you're on.
      innerAccent: Color.lerp(category.color, Colors.white, 0.35),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        child: Center(
          child: Text(
            category.label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFFFF3E4),
              fontSize: 34,
              fontWeight: FontWeight.w600,
              letterSpacing: 3,
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }
}

class _PeekGlassStrip extends StatelessWidget {
  final MenuCategory category;

  /// How far to inset the strip from the horizontal edges of its
  /// parent. Deeper strips inset more so the stack visually recedes.
  final double insetX;

  const _PeekGlassStrip({required this.category, required this.insetX});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: insetX),
      child: SizedBox(
        height: 36,
        child: _GlassContainer(
          borderRadius: 18,
          innerAccent: Color.lerp(category.color, Colors.white, 0.2),
          fill: Colors.white.withValues(alpha: 0.05),
          borderOpacity: 0.14,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// A single glassmorphic surface — backdrop-blur inside a rounded
/// clip, translucent fill on top, subtle white border, plus an
/// optional radial accent glow behind the child.
class _GlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final Color? innerAccent;
  final Color? fill;
  final double borderOpacity;

  const _GlassContainer({
    required this.child,
    this.borderRadius = 24,
    this.innerAccent,
    this.fill,
    this.borderOpacity = 0.22,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: fill ?? Colors.white.withValues(alpha: 0.10),
            borderRadius: radius,
            border: Border.all(
              color: Colors.white.withValues(alpha: borderOpacity),
              width: 1,
            ),
          ),
          child: Stack(
            children: [
              if (innerAccent != null)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      gradient: RadialGradient(
                        center: const Alignment(0, 0.6),
                        radius: 0.9,
                        colors: [
                          innerAccent!.withValues(alpha: 0.35),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Opened-feature view — fills the full 980x740 with the category's
// content behind a lighter glass frame.
// ---------------------------------------------------------------------------

class _OpenedFeature extends StatelessWidget {
  final MenuCategory category;
  const _OpenedFeature({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.1,
          colors: [_canvasPurple, _canvasPurpleDeep],
        ),
      ),
      padding: const EdgeInsets.all(18),
      child: _GlassContainer(
        borderRadius: 24,
        innerAccent: Color.lerp(category.color, Colors.white, 0.2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              child: Text(
                category.label,
                style: const TextStyle(
                  color: Color(0xFFFFF3E4),
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(22),
                ),
                child: category.contentBuilder(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
