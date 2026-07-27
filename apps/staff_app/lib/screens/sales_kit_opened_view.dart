import 'package:flutter/material.dart';
import 'master_dashboard_screen.dart' show AppTheme;

/// Sales Kit — training / marketing YouTube gallery for the POS.
/// Four drill levels, walk the same shape as InventoryOpenedView so
/// the chevron pops one level at a time:
///
///   categories    — 3-col grid of top-level topic cards
///   subCategories — 3-col grid of sub-topics under a category
///   videos        — 5-col grid of video thumbnails under a sub
///   player        — big video-player placeholder + related row
///
/// Content is a curated set of realistic POS training titles. Actual
/// YouTube playback wires in later; for now the player renders the
/// title, a YouTube search URL, and a placeholder frame.
class SalesKitOpenedView extends StatefulWidget {
  final ScrollController? scrollController;
  final ScrollController? filterScrollController;

  const SalesKitOpenedView({
    super.key,
    this.scrollController,
    this.filterScrollController,
  });

  @override
  SalesKitOpenedViewState createState() => SalesKitOpenedViewState();
}

enum _Level { categories, subCategories, videos, player }

class SalesKitOpenedViewState extends State<SalesKitOpenedView> {
  _Level _level = _Level.categories;
  _Category? _category;
  _SubCategory? _sub;
  _Video? _playing;

  /// Chevron-back from the master dashboard. Returns false only when
  /// already at the categories root so the parent can close the tab.
  bool maybePop() {
    switch (_level) {
      case _Level.categories:
        return false;
      case _Level.subCategories:
        setState(() {
          _level = _Level.categories;
          _category = null;
        });
        return true;
      case _Level.videos:
        setState(() {
          _level = _Level.subCategories;
          _sub = null;
        });
        return true;
      case _Level.player:
        setState(() {
          _level = _Level.videos;
          _playing = null;
        });
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = SizedBox(
      width: 250,
      child: RepaintBoundary(child: _filterColumn()),
    );
    final content = Expanded(
      child: RepaintBoundary(child: _buildLevel()),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [filter, const SizedBox(width: 2), content],
    );
  }

  Widget _buildLevel() {
    switch (_level) {
      case _Level.categories:
        return _grid3col(
          items: _catalog.length,
          builder: (i) => _TopicTile(
            title: _catalog[i].title,
            subtitle: '${_catalog[i].subs.length} topics',
            icon: _catalog[i].icon,
            onTap: () => setState(() {
              _category = _catalog[i];
              _level = _Level.subCategories;
            }),
          ),
        );
      case _Level.subCategories:
        final subs = _category!.subs;
        return _grid3col(
          items: subs.length,
          builder: (i) => _TopicTile(
            title: subs[i].title,
            subtitle: '${subs[i].videos.length} videos',
            icon: Icons.playlist_play,
            onTap: () => setState(() {
              _sub = subs[i];
              _level = _Level.videos;
            }),
          ),
        );
      case _Level.videos:
        final videos = _sub!.videos;
        return GridView.builder(
          controller: widget.scrollController,
          padding: const EdgeInsets.symmetric(vertical: 2),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
            childAspectRatio: 149 / 232,
          ),
          itemCount: videos.length,
          itemBuilder: (ctx, i) => _VideoThumb(
            title: videos[i].title,
            onTap: () => setState(() {
              _playing = videos[i];
              _level = _Level.player;
            }),
          ),
        );
      case _Level.player:
        return _playerLayout(_playing!);
    }
  }

  Widget _grid3col({required int items, required Widget Function(int) builder}) {
    return GridView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.symmetric(vertical: 2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        childAspectRatio: 250 / 349,
      ),
      itemCount: items,
      itemBuilder: (ctx, i) => builder(i),
    );
  }

  // ----- Filter column ------------------------------------------------------

  Widget _filterColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 115, child: _titleCell()),
        const SizedBox(height: 2),
        Expanded(child: _filterCell()),
      ],
    );
  }

  Widget _titleCell() {
    return Builder(builder: (context) {
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
              'SALES KIT',
              style: TextStyle(
                color: t.panelText,
                fontSize: 22,
                fontWeight: FontWeight.w500,
                letterSpacing: 3,
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _filterCell() {
    final breadcrumb = <String>[
      'Categories',
      if (_category != null) _category!.title,
      if (_sub != null) _sub!.title,
      if (_playing != null) _playing!.title,
    ].join(' › ');
    return Builder(builder: (context) {
      final t = AppTheme.of(context);
      return DecoratedBox(
        decoration: BoxDecoration(
          color: t.panelBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: SingleChildScrollView(
          controller: widget.filterScrollController,
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'VIDEOS',
                style: TextStyle(
                  color: t.panelText,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 6),
              Container(height: 2, width: 100, color: t.panelAccent),
              const SizedBox(height: 14),
              Text(
                breadcrumb,
                style: TextStyle(
                  color: t.cardSubtleText,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              _label(t, 'SEARCH'),
              const _FilterField(hint: 'Search videos'),
              const SizedBox(height: 16),
              _label(t, 'LANGUAGE'),
              const _FilterField(hint: 'English'),
              const SizedBox(height: 16),
              _label(t, 'LENGTH'),
              const _FilterField(hint: 'Any'),
              const SizedBox(height: 16),
              _label(t, 'SORT'),
              const _FilterField(hint: 'Newest'),
            ],
          ),
        ),
      );
    });
  }

  static Widget _label(AppTheme t, String text) {
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

  // ----- Player layout ------------------------------------------------------

  Widget _playerLayout(_Video video) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 5,
          child: _VideoPlayerPlaceholder(video: video),
        ),
        const SizedBox(height: 2),
        SizedBox(height: 180, child: _relatedRow(video)),
      ],
    );
  }

  Widget _relatedRow(_Video current) {
    // Pull related from the same sub-category, then fall back across
    // the whole catalog. Keep 5 visible, skip the current video.
    final pool = <_Video>[];
    for (final v in _sub!.videos) {
      if (v != current) pool.add(v);
    }
    if (pool.length < 5) {
      for (final cat in _catalog) {
        for (final sub in cat.subs) {
          for (final v in sub.videos) {
            if (v != current && !pool.contains(v)) pool.add(v);
            if (pool.length >= 5) break;
          }
          if (pool.length >= 5) break;
        }
        if (pool.length >= 5) break;
      }
    }
    final related = pool.take(5).toList();
    return Row(
      children: [
        for (var i = 0; i < related.length; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          Expanded(
            child: _VideoThumb(
              title: related[i].title,
              onTap: () => setState(() {
                _playing = related[i];
                // Stay on the player level; just swap the video.
              }),
              compact: true,
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Content model — categories → sub-categories → videos.
// Titles are realistic POS training / marketing topics; each carries
// a YouTube search URL so a real embed can wire in later.
// ---------------------------------------------------------------------------

class _Category {
  final String title;
  final IconData icon;
  final List<_SubCategory> subs;
  const _Category(this.title, this.icon, this.subs);
}

class _SubCategory {
  final String title;
  final List<_Video> videos;
  const _SubCategory(this.title, this.videos);
}

class _Video {
  final String title;
  const _Video(this.title);
  String get searchUrl =>
      'https://www.youtube.com/results?search_query=${Uri.encodeQueryComponent('$title POS tutorial')}';
}

const List<_Category> _catalog = [
  _Category('Getting Started', Icons.rocket_launch, [
    _SubCategory('Onboarding', [
      _Video('Welcome to the POS'),
      _Video('Store setup in 5 minutes'),
      _Video('Adding your first staff'),
      _Video('Choosing your plan'),
    ]),
    _SubCategory('First Sale', [
      _Video('Ring up your first cart'),
      _Video('Accept a UPI payment'),
      _Video('Print a receipt'),
      _Video('Void a mistaken sale'),
    ]),
    _SubCategory('Navigation', [
      _Video('Dashboard tour'),
      _Video('Flank rails and gestures'),
      _Video('Keyboard shortcuts'),
      _Video('Light vs dark mode'),
    ]),
  ]),
  _Category('Cart & Checkout', Icons.point_of_sale, [
    _SubCategory('Cart basics', [
      _Video('Add / remove items'),
      _Video('Quantity and unit price'),
      _Video('Splitting a cart'),
      _Video('Parking a cart'),
    ]),
    _SubCategory('Payments', [
      _Video('Cash tender & change'),
      _Video('Card + tip flow'),
      _Video('UPI / QR checkout'),
      _Video('Split payment methods'),
    ]),
    _SubCategory('Discounts', [
      _Video('Line-level discount'),
      _Video('Cart-level discount'),
      _Video('Manager approval flow'),
    ]),
    _SubCategory('Refunds & returns', [
      _Video('Full refund'),
      _Video('Partial refund'),
      _Video('Exchange without receipt'),
    ]),
  ]),
  _Category('Inventory', Icons.inventory_2, [
    _SubCategory('Products', [
      _Video('Adding a product'),
      _Video('Product variants'),
      _Video('Bulk import via CSV'),
      _Video('Retiring a product'),
    ]),
    _SubCategory('Categories & tags', [
      _Video('Building a category tree'),
      _Video('Sub-category best practice'),
      _Video('Tagging for search'),
    ]),
    _SubCategory('Stock control', [
      _Video('Receive stock'),
      _Video('Stock take & adjustments'),
      _Video('Low-stock alerts'),
      _Video('Transfers between stores'),
    ]),
    _SubCategory('Barcodes', [
      _Video('Generating barcodes'),
      _Video('Scanning at checkout'),
      _Video('Handling unknown scans'),
    ]),
  ]),
  _Category('Analytics', Icons.query_stats, [
    _SubCategory('Sales', [
      _Video('Daily sales at a glance'),
      _Video('Top-seller reports'),
      _Video('Slow-mover cleanup'),
      _Video('Sales forecasting'),
    ]),
    _SubCategory('Customers', [
      _Video('Repeat rate'),
      _Video('Basket size trends'),
      _Video('Customer lifetime value'),
    ]),
    _SubCategory('Staff', [
      _Video('Cashier throughput'),
      _Video('Attach rate by staff'),
      _Video('Shift performance'),
    ]),
    _SubCategory('Peak hours', [
      _Video('Reading the heatmap'),
      _Video('Staffing to demand'),
    ]),
  ]),
  _Category('Customers & Loyalty', Icons.people_alt, [
    _SubCategory('Directory', [
      _Video('Adding a customer'),
      _Video('Merging duplicates'),
      _Video('GDPR export & delete'),
    ]),
    _SubCategory('Loyalty', [
      _Video('Starting a points program'),
      _Video('Redeeming rewards'),
      _Video('Tiered loyalty'),
    ]),
    _SubCategory('Messaging', [
      _Video('SMS receipts'),
      _Video('WhatsApp reorder nudges'),
    ]),
  ]),
  _Category('Marketing', Icons.campaign, [
    _SubCategory('Promotions', [
      _Video('Buy-one-get-one setup'),
      _Video('Time-boxed offers'),
      _Video('Bundle pricing'),
    ]),
    _SubCategory('Coupons', [
      _Video('Single-use codes'),
      _Video('Referral coupons'),
      _Video('Coupon analytics'),
    ]),
    _SubCategory('Campaigns', [
      _Video('Festival playbook'),
      _Video('Local ads that convert'),
    ]),
  ]),
  _Category('Staff & Roles', Icons.badge, [
    _SubCategory('Users', [
      _Video('Inviting staff'),
      _Video('Password resets'),
      _Video('Removing an ex-employee'),
    ]),
    _SubCategory('Permissions', [
      _Video('Role templates'),
      _Video('Custom permissions'),
      _Video('Manager overrides'),
    ]),
    _SubCategory('Shifts', [
      _Video('Clock in / clock out'),
      _Video('Break policies'),
      _Video('Shift handover'),
    ]),
  ]),
  _Category('Advanced', Icons.settings_suggest, [
    _SubCategory('Integrations', [
      _Video('Accounting sync'),
      _Video('Delivery partner APIs'),
      _Video('Marketplace connectors'),
    ]),
    _SubCategory('Data', [
      _Video('Exports to CSV / Excel'),
      _Video('Scheduled backups'),
      _Video('Restore from backup'),
    ]),
    _SubCategory('API & webhooks', [
      _Video('Getting an API key'),
      _Video('Webhook events'),
      _Video('Rate limits and retries'),
    ]),
  ]),
];

// ---------------------------------------------------------------------------
// Topic tile — categories and sub-categories share the same visual.
// ---------------------------------------------------------------------------

class _TopicTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _TopicTile({
    required this.title,
    required this.subtitle,
    required this.icon,
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
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(icon, size: 44, color: t.panelText),
              const Spacer(),
              Text(
                title,
                style: TextStyle(
                  color: t.panelText,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: t.cardSubtleText,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
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
// Video thumbnail — gallery card + related-row card (compact).
// ---------------------------------------------------------------------------

class _VideoThumb extends StatelessWidget {
  final String title;
  final VoidCallback onTap;
  final bool compact;

  const _VideoThumb({
    required this.title,
    required this.onTap,
    this.compact = false,
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
          padding: EdgeInsets.all(compact ? 8 : 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    color: t.chipBg,
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.play_circle_fill,
                      size: compact ? 32 : 48,
                      color: t.cardSubtleText,
                    ),
                  ),
                ),
              ),
              SizedBox(height: compact ? 6 : 10),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.panelText,
                  fontSize: compact ? 11 : 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                  height: 1.2,
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
// Video player placeholder — black frame with title + a searchable
// YouTube URL. When a real player is wired in, swap this widget's
// body for a YoutubePlayer / WebView keyed off `video.searchUrl` or
// a resolved video id.
// ---------------------------------------------------------------------------

class _VideoPlayerPlaceholder extends StatelessWidget {
  final _Video video;
  const _VideoPlayerPlaceholder({required this.video});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(
              Icons.play_circle_fill,
              size: 96,
              color: Colors.white70,
            ),
            const SizedBox(height: 18),
            Text(
              video.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'YouTube playback wires in here',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w400,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                video.searchUrl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
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
