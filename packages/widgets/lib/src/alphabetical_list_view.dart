import 'package:flutter/material.dart';
import 'alphabetical_rail.dart';

/// Companion to [AlphabeticalRail] that wires it up to a real
/// scrollable list. Given a flat list of items and a way to derive each
/// item's section key (typically the uppercase first letter of a name),
/// this widget:
///
/// - groups items into A–Z sections,
/// - lays them out as a single scrollable column with section headers,
/// - draws the A–Z rail on the trailing edge,
/// - jumps to the tapped section on rail interaction, and
/// - keeps the rail's highlighted letter in sync as the user scrolls
///   the list manually.
///
/// Reusable: pass any item type in as `T` and the appropriate builders.
/// Used first for the Inventory list in the staff app; will be reused
/// wherever a long alphabetized list appears (Customers, Clones, etc.).
class AlphabeticalListView<T> extends StatefulWidget {
  final List<T> items;

  /// Derive a section key for [item]. Typically
  /// `(item) => item.name[0].toUpperCase()`. Non-letter keys are
  /// bucketed under `#`.
  final String Function(T item) sectionKeyOf;

  final Widget Function(BuildContext context, T item) itemBuilder;

  /// Optional custom section header. Defaults to a small caption row.
  final Widget Function(BuildContext context, String key)? headerBuilder;

  /// Item / header extents. Fixed so the rail can jump precisely without
  /// having to measure — matches the constraint every fast-scroll rail
  /// implementation runs into.
  final double itemExtent;
  final double headerExtent;

  const AlphabeticalListView({
    super.key,
    required this.items,
    required this.sectionKeyOf,
    required this.itemBuilder,
    this.headerBuilder,
    this.itemExtent = 44,
    this.headerExtent = 28,
  });

  @override
  State<AlphabeticalListView<T>> createState() =>
      _AlphabeticalListViewState<T>();
}

class _AlphabeticalListViewState<T> extends State<AlphabeticalListView<T>> {
  late final ScrollController _controller;
  late List<_Section<T>> _sections;
  late Set<String> _availableLetters;
  String? _currentSectionKey;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    _controller.addListener(_onScroll);
    _rebuildSections();
  }

  @override
  void didUpdateWidget(covariant AlphabeticalListView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items) {
      _rebuildSections();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _rebuildSections() {
    final buckets = <String, List<T>>{};
    for (final item in widget.items) {
      final raw = widget.sectionKeyOf(item);
      final key = raw.isEmpty ? '#' : raw[0].toUpperCase();
      final normalized = RegExp(r'^[A-Z]$').hasMatch(key) ? key : '#';
      buckets.putIfAbsent(normalized, () => []).add(item);
    }
    final sortedKeys = buckets.keys.toList()..sort();
    _sections = [
      for (final key in sortedKeys)
        _Section(key: key, items: buckets[key]!),
    ];
    _availableLetters = _sections.map((s) => s.key).toSet();
    _currentSectionKey = _sections.isNotEmpty ? _sections.first.key : null;
  }

  /// Total pixel offset of the section header for [sectionKey], relative
  /// to the top of the scrollable content.
  double _offsetOfSection(String sectionKey) {
    var offset = 0.0;
    for (final section in _sections) {
      if (section.key == sectionKey) return offset;
      offset += widget.headerExtent + section.items.length * widget.itemExtent;
    }
    return offset;
  }

  String? _sectionKeyAtOffset(double offset) {
    var running = 0.0;
    for (final section in _sections) {
      final sectionSize =
          widget.headerExtent + section.items.length * widget.itemExtent;
      if (offset < running + sectionSize) return section.key;
      running += sectionSize;
    }
    return _sections.isEmpty ? null : _sections.last.key;
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final key = _sectionKeyAtOffset(_controller.offset);
    if (key != _currentSectionKey) {
      setState(() => _currentSectionKey = key);
    }
  }

  void _jumpTo(String letter) {
    if (!_availableLetters.contains(letter)) return;
    final offset = _offsetOfSection(letter);
    _controller.jumpTo(
      offset.clamp(
        0.0,
        _controller.position.hasContentDimensions
            ? _controller.position.maxScrollExtent
            : offset,
      ),
    );
    setState(() => _currentSectionKey = letter);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _buildList()),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: SizedBox(
            width: 20,
            child: AlphabeticalRail(
              availableLetters: _availableLetters,
              highlightedLetter: _currentSectionKey,
              onLetterSelected: _jumpTo,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildList() {
    if (_sections.isEmpty) {
      return const Center(
        child: Text(
          'Nothing to show yet.',
          style: TextStyle(letterSpacing: -0.56),
        ),
      );
    }
    // Flatten sections into a single list of (header/item) entries so we
    // can rely on a fixed row height for accurate rail-jumping.
    final rows = <_Row<T>>[];
    for (final section in _sections) {
      rows.add(_Row.header(section.key));
      for (final item in section.items) {
        rows.add(_Row.item(item, section.key));
      }
    }
    return ListView.builder(
      controller: _controller,
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        if (row.isHeader) {
          return SizedBox(
            height: widget.headerExtent,
            child: widget.headerBuilder != null
                ? widget.headerBuilder!(context, row.sectionKey)
                : _DefaultHeader(letter: row.sectionKey),
          );
        }
        return SizedBox(
          height: widget.itemExtent,
          child: widget.itemBuilder(context, row.item as T),
        );
      },
    );
  }
}

class _Section<T> {
  final String key;
  final List<T> items;
  _Section({required this.key, required this.items});
}

class _Row<T> {
  final bool isHeader;
  final Object? item;
  final String sectionKey;
  _Row.header(this.sectionKey)
      : isHeader = true,
        item = null;
  _Row.item(this.item, this.sectionKey) : isHeader = false;
}

class _DefaultHeader extends StatelessWidget {
  final String letter;
  const _DefaultHeader({required this.letter});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      color: const Color(0xFFF2E8D5), // cream
      child: Text(
        letter,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: Color(0xFFC1551C), // rust
          fontSize: 12,
          letterSpacing: -0.48,
        ),
      ),
    );
  }
}
