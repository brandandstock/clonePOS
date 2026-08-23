import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clone_pos_core/models/product.dart';

import '../data/product_store.dart';

/// LAN catalog bridge that lets a clone (Satellite) mirror the master's live
/// Inventory. The control-plane ([CloneLinkService]) only carries small JSON
/// datagrams over UDP — far too small for the full catalog (thousands of SKUs,
/// some with embedded images). So the catalog moves over HTTP instead:
///
/// - **Master:** serves its persisted catalog file over a tiny HTTP server on
///   [port]. `GET /catalog` streams the raw catalog JSON (the exact
///   `[Product.toJson()]` list the master already writes on every edit), and
///   `GET /catalog/version` returns a cheap change token (file size + mtime) so
///   a clone can poll for changes without downloading the whole thing.
/// - **Clone:** [fetchCatalog] pulls `/catalog` from the master's address
///   (learned from [CloneLinkService.masterAddress]) and parses it into
///   products; [fetchVersion] polls the cheap token.
///
/// Cleartext HTTP to a LAN IP is fine here: dart:io's [HttpServer]/[HttpClient]
/// use their own sockets and are not subject to Android's `usesCleartextTraffic`
/// policy (which only gates the Java/OkHttp/WebView stack).
class CatalogSyncService {
  /// Distinct from the walkie (47770) and control-plane (47772) UDP ports.
  static const int port = 47773;

  HttpServer? _server;
  final ProductStore _store = ProductStore();

  // ── Master ──────────────────────────────────────────────────────────

  /// Start serving the catalog on the LAN. Returns false if the port could
  /// not be bound (e.g. another instance already owns it) — best-effort, so a
  /// bind failure just means clones can't sync, never a crash.
  Future<bool> startMaster() async {
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _server!.listen(_handle, onError: (_) {});
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final f = await _store.file();
      final exists = await f.exists();
      if (req.uri.path == '/catalog/version') {
        res.headers.contentType = ContentType.text;
        if (exists) {
          final st = await f.stat();
          res.write('${st.size}:${st.modified.millisecondsSinceEpoch}');
        } else {
          res.write('0');
        }
      } else {
        // /catalog — stream the raw persisted JSON with no re-encode. If the
        // file doesn't exist yet (fresh master), load() seeds+writes it first.
        res.headers.contentType = ContentType.json;
        if (exists) {
          await res.addStream(f.openRead());
        } else {
          final ps = await _store.load();
          res.write(jsonEncode([for (final p in ps) p.toJson()]));
        }
      }
    } catch (_) {
      try {
        res.statusCode = HttpStatus.internalServerError;
      } catch (_) {}
    } finally {
      try {
        await res.close();
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  // ── Clone ───────────────────────────────────────────────────────────

  static Uri _uri(InternetAddress host, String path) =>
      Uri(scheme: 'http', host: host.address, port: port, path: path);

  /// Pull the master's full catalog. Returns null on any failure (offline,
  /// timeout, malformed) so the caller can fall back to its cached/seed data.
  static Future<List<Product>?> fetchCatalog(InternetAddress host) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(_uri(host, '/catalog'));
      final resp = await req.close().timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join();
      final decoded = jsonDecode(body) as List<dynamic>;
      return [
        for (final e in decoded) Product.fromJson(e as Map<String, dynamic>),
      ];
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Poll the master's cheap change token; null on failure.
  static Future<String?> fetchVersion(InternetAddress host) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.getUrl(_uri(host, '/catalog/version'));
      final resp = await req.close().timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return null;
      return (await resp.transform(utf8.decoder).join()).trim();
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
