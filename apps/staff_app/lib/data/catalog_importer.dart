import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:clone_pos_core/models/product.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:xml/xml.dart';

/// Outcome of parsing an uploaded spreadsheet. [products] are ready to merge
/// into the catalog (images already attached where found); [issues] lists
/// per-row problems (skipped rows and why); [imagesMatched] counts embedded
/// XLSX pictures that were successfully tied to a row; [fatal] is set only
/// when the whole file could not be read.
class ImportReport {
  final List<Product> products;
  final List<String> issues;
  final int imagesMatched;
  final String? fatal;
  const ImportReport({
    this.products = const [],
    this.issues = const [],
    this.imagesMatched = 0,
    this.fatal,
  });
}

/// Parses a CSV or XLSX byte buffer into products. Column headers are matched
/// case-insensitively against a set of aliases (see [_HeaderMap]); `name`,
/// `price` and `category` are required per row. XLSX files additionally get a
/// best-effort pass to pull images embedded in cells and attach them to the
/// product on the same row — this is inherently fragile (depends on how the
/// sheet was authored/exported) so any failure just yields no image.
class CatalogImporter {
  /// [extension] is the lowercase file extension without the dot ('csv'/'xlsx').
  static ImportReport parse({
    required Uint8List bytes,
    required String extension,
  }) {
    try {
      if (extension == 'csv') return _parseCsv(bytes);
      if (extension == 'xlsx') return _parseXlsx(bytes);
      return ImportReport(fatal: 'Unsupported file type: .$extension');
    } catch (e) {
      return ImportReport(fatal: 'Could not read the file: $e');
    }
  }

  // ---- CSV ----------------------------------------------------------------

  static ImportReport _parseCsv(Uint8List bytes) {
    // Strip a UTF-8 BOM if present, then let the converter auto-detect EOL.
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
      text = text.substring(1);
    }
    // Normalise line endings: the csv package defaults to \r\n only, so a
    // Unix (\n) or old-Mac (\r) file would otherwise parse as a single row.
    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rows = const CsvToListConverter(eol: '\n', shouldParseNumbers: false)
        .convert(text);
    if (rows.isEmpty) {
      return const ImportReport(fatal: 'The file is empty.');
    }
    final header = _HeaderMap(rows.first.map((c) => '$c').toList());
    if (!header.hasRequired) return ImportReport(fatal: header.missingMsg);

    final products = <Product>[];
    final issues = <String>[];
    for (var r = 1; r < rows.length; r++) {
      final cells = rows[r].map((c) => c == null ? '' : '$c').toList();
      if (cells.every((c) => c.trim().isEmpty)) continue; // skip blank lines
      final res = _rowToProduct(header, cells, r + 1);
      if (res.product != null) {
        products.add(res.product!);
      } else if (res.error != null) {
        issues.add(res.error!);
      }
    }
    return ImportReport(products: products, issues: issues);
  }

  // ---- XLSX ---------------------------------------------------------------

  static ImportReport _parseXlsx(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) {
      return const ImportReport(fatal: 'No sheets found in the workbook.');
    }
    final sheetName = excel.tables.keys.first;
    final sheet = excel.tables[sheetName]!;
    final rows = sheet.rows;
    if (rows.isEmpty) {
      return const ImportReport(fatal: 'The first sheet is empty.');
    }

    final header =
        _HeaderMap(rows.first.map((c) => _cellStr(c) ?? '').toList());
    if (!header.hasRequired) return ImportReport(fatal: header.missingMsg);

    // Best-effort: images embedded in the sheet, keyed by 0-based row index
    // (matching `rows`), so rows[j] pairs with imagesByRow[j].
    final imagesByRow = _extractXlsxImages(bytes);

    final products = <Product>[];
    final issues = <String>[];
    var matched = 0;
    for (var r = 1; r < rows.length; r++) {
      final cells = rows[r].map((c) => _cellStr(c) ?? '').toList();
      // Skip fully-blank rows silently (trailing rows Excel keeps around).
      if (cells.every((c) => c.trim().isEmpty)) continue;
      final res = _rowToProduct(header, cells, r + 1);
      if (res.product != null) {
        var p = res.product!;
        final img = imagesByRow[r];
        if (img != null && (p.imageBytes == null)) {
          p = p.copyWith(imageBytes: img);
          matched++;
        }
        products.add(p);
      } else if (res.error != null) {
        issues.add(res.error!);
      }
    }
    return ImportReport(
      products: products,
      issues: issues,
      imagesMatched: matched,
    );
  }

  /// Unzips the .xlsx (a ZIP) and walks the drawing XML to map each embedded
  /// picture to the 0-based worksheet row it's anchored to. Returns
  /// {rowIndex: pngBytes}. Any structural surprise → empty map (best-effort).
  static Map<int, Uint8List> _extractXlsxImages(Uint8List bytes) {
    final out = <int, Uint8List>{};
    try {
      final zip = ZipDecoder().decodeBytes(bytes);
      ArchiveFile? file(String path) {
        for (final f in zip.files) {
          if (f.name == path) return f;
        }
        return null;
      }

      // Media blobs by their archive path (xl/media/imageN.ext).
      final media = <String, Uint8List>{};
      for (final f in zip.files) {
        if (f.name.startsWith('xl/media/') && f.isFile) {
          media[f.name] = Uint8List.fromList(f.content as List<int>);
        }
      }
      if (media.isEmpty) return out;

      // Each drawing file anchors images to rows; its .rels maps the embed
      // id → a media path. Iterate every drawing we can find.
      for (final f in zip.files) {
        if (!(f.name.startsWith('xl/drawings/') &&
            f.name.endsWith('.xml') &&
            !f.name.contains('_rels'))) {
          continue;
        }
        final relsPath =
            'xl/drawings/_rels/${f.name.split('/').last}.rels';
        final rels = file(relsPath);
        final embedToMedia = <String, String>{};
        if (rels != null) {
          final relDoc =
              XmlDocument.parse(utf8.decode(rels.content as List<int>));
          for (final rel in relDoc.findAllElements('Relationship')) {
            final id = rel.getAttribute('Id');
            final target = rel.getAttribute('Target');
            if (id == null || target == null) continue;
            // Target like ../media/image1.png → normalise to xl/media/...
            final norm = 'xl/${target.replaceFirst('../', '')}';
            embedToMedia[id] = norm;
          }
        }

        final doc =
            XmlDocument.parse(utf8.decode(f.content as List<int>));
        // Both one-cell and two-cell anchors carry an <xdr:from><xdr:row>.
        for (final anchor in [
          ...doc.findAllElements('xdr:twoCellAnchor'),
          ...doc.findAllElements('xdr:oneCellAnchor'),
        ]) {
          final rowEls = anchor.findAllElements('xdr:row');
          if (rowEls.isEmpty) continue;
          final rowIdx = int.tryParse(rowEls.first.innerText.trim());
          if (rowIdx == null) continue;
          final blip = anchor.findAllElements('a:blip').firstOrNull;
          final embed = blip?.getAttribute('r:embed');
          if (embed == null) continue;
          final mediaPath = embedToMedia[embed];
          if (mediaPath == null) continue;
          final blob = media[mediaPath];
          if (blob != null) out.putIfAbsent(rowIdx, () => blob);
        }
      }
    } catch (_) {
      return {};
    }
    return out;
  }

  // ---- Shared row → Product ----------------------------------------------

  static _RowResult _rowToProduct(
    _HeaderMap h,
    List<String> cells,
    int rowNumber,
  ) {
    String? at(int? i) {
      if (i == null || i < 0 || i >= cells.length) return null;
      final v = cells[i].trim();
      return v.isEmpty ? null : v;
    }

    final name = at(h.name);
    final category = at(h.category);
    final priceRaw = at(h.price);
    final price = priceRaw == null
        ? null
        : double.tryParse(priceRaw.replaceAll(RegExp(r'[^0-9.\-]'), ''));

    if (name == null || category == null || price == null) {
      final missing = [
        if (name == null) 'name',
        if (category == null) 'category',
        if (price == null) 'price',
      ].join(', ');
      return _RowResult(error: 'Row $rowNumber skipped — missing/invalid: $missing');
    }

    final id = at(h.id) ?? 'IMP-${DateTime.now().microsecondsSinceEpoch}-$rowNumber';
    final stockRaw = at(h.stock);
    final ratingRaw = at(h.rating);
    final ratingCountRaw = at(h.ratingCount);

    return _RowResult(
      product: Product(
        id: id,
        name: name,
        price: price,
        category: category,
        subCategory: at(h.subCategory),
        brand: at(h.brand),
        description: at(h.description),
        warrantyText: at(h.warranty),
        specifications: at(h.specifications),
        stock: stockRaw == null
            ? null
            : int.tryParse(stockRaw.replaceAll(RegExp(r'[^0-9\-]'), '')),
        rating: ratingRaw == null ? null : double.tryParse(ratingRaw),
        ratingCount:
            ratingCountRaw == null ? null : int.tryParse(ratingCountRaw),
        imageUrl: at(h.imageUrl),
      ),
    );
  }

  static String? _cellStr(Data? c) {
    final v = c?.value;
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }
}

class _RowResult {
  final Product? product;
  final String? error;
  const _RowResult({this.product, this.error});
}

/// Maps normalised header names → column indices, accepting common aliases so
/// staff don't have to match an exact template.
class _HeaderMap {
  int? id, name, price, category, subCategory, brand, stock, description,
      warranty, specifications, rating, ratingCount, imageUrl;

  _HeaderMap(List<String> headers) {
    for (var i = 0; i < headers.length; i++) {
      final key = headers[i].toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      switch (key) {
        case 'id':
        case 'sku':
        case 'productid':
          id = i;
          break;
        case 'name':
        case 'productname':
        case 'title':
          name = i;
          break;
        case 'price':
        case 'sellingprice':
        case 'mrp':
        case 'cost':
          price = i;
          break;
        case 'category':
        case 'cat':
          category = i;
          break;
        case 'subcategory':
        case 'sub':
        case 'subcat':
          subCategory = i;
          break;
        case 'brand':
        case 'make':
          brand = i;
          break;
        case 'stock':
        case 'qty':
        case 'quantity':
        case 'instock':
          stock = i;
          break;
        case 'description':
        case 'desc':
        case 'details':
          description = i;
          break;
        case 'warranty':
        case 'warrantytext':
          warranty = i;
          break;
        case 'specifications':
        case 'specification':
        case 'specs':
        case 'spec':
          specifications = i;
          break;
        case 'rating':
          rating = i;
          break;
        case 'ratingcount':
        case 'reviews':
          ratingCount = i;
          break;
        case 'imageurl':
        case 'image':
        case 'imagelink':
        case 'img':
        case 'photo':
          imageUrl = i;
          break;
      }
    }
  }

  bool get hasRequired => name != null && price != null && category != null;

  String get missingMsg {
    final missing = [
      if (name == null) 'name',
      if (price == null) 'price',
      if (category == null) 'category',
    ].join(', ');
    return 'Missing required column(s): $missing. '
        'The sheet needs at least name, price and category headers.';
  }
}
