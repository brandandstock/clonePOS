import 'dart:convert';
import 'dart:typed_data';

/// SKU-level product. A Product can have many physical Units (see unit.dart) —
/// Clone-POS assigns a unique QR code per physical unit, never per SKU.
///
/// The core identity fields (id/name/price/category) drive the ledger and
/// reservation engine. The extended fields (brand, subCategory, description,
/// rating, ratingCount, stock, warrantyText) drive the product-card view on
/// the Inventory tab and are all optional so the older seed data still works
/// against this class unchanged. IconData is deliberately not stored here —
/// the core package is Flutter-free, so category → icon mapping lives in the
/// app layer.
class Product {
  final String id;
  final String name;
  final double price;
  final String category;

  final String? brand;
  final String? subCategory;
  final String? description;
  final double? rating;
  final int? ratingCount;
  final int? stock;
  final String? warrantyText;

  /// Raw tabular spec block, as pasted from a spreadsheet: newline-separated
  /// rows, tab-separated (or "Key: Value") cells. Rendered as an aligned
  /// table in the product detail view; kept as raw text so the source paste
  /// round-trips through storage untouched.
  final String? specifications;

  final String? imageUrl;

  /// Raw image bytes for products whose photo was uploaded from the device
  /// (Inventory → Add product) rather than referenced by URL. When present it
  /// takes priority over [imageUrl] at render time. In-memory only — not
  /// persisted, so it survives just for the current session.
  final Uint8List? imageBytes;

  const Product({
    required this.id,
    required this.name,
    required this.price,
    required this.category,
    this.brand,
    this.subCategory,
    this.description,
    this.rating,
    this.ratingCount,
    this.stock,
    this.warrantyText,
    this.specifications,
    this.imageUrl,
    this.imageBytes,
  });

  bool get inStock => (stock ?? 0) > 0;

  Product copyWith({
    String? name,
    double? price,
    String? category,
    String? brand,
    String? subCategory,
    String? description,
    double? rating,
    int? ratingCount,
    int? stock,
    String? warrantyText,
    String? specifications,
    String? imageUrl,
    Uint8List? imageBytes,
  }) {
    return Product(
      id: id,
      name: name ?? this.name,
      price: price ?? this.price,
      category: category ?? this.category,
      brand: brand ?? this.brand,
      subCategory: subCategory ?? this.subCategory,
      description: description ?? this.description,
      rating: rating ?? this.rating,
      ratingCount: ratingCount ?? this.ratingCount,
      stock: stock ?? this.stock,
      warrantyText: warrantyText ?? this.warrantyText,
      specifications: specifications ?? this.specifications,
      imageUrl: imageUrl ?? this.imageUrl,
      imageBytes: imageBytes ?? this.imageBytes,
    );
  }

  /// JSON for local catalog persistence. Uploaded [imageBytes] are stored
  /// base64-encoded; URL-backed products just carry [imageUrl]. Null fields
  /// are omitted to keep the file compact.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'price': price,
        'category': category,
        if (brand != null) 'brand': brand,
        if (subCategory != null) 'subCategory': subCategory,
        if (description != null) 'description': description,
        if (rating != null) 'rating': rating,
        if (ratingCount != null) 'ratingCount': ratingCount,
        if (stock != null) 'stock': stock,
        if (warrantyText != null) 'warrantyText': warrantyText,
        if (specifications != null) 'specifications': specifications,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (imageBytes != null) 'imageBytes': base64Encode(imageBytes!),
      };

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'] as String,
        name: j['name'] as String,
        price: (j['price'] as num).toDouble(),
        category: j['category'] as String,
        brand: j['brand'] as String?,
        subCategory: j['subCategory'] as String?,
        description: j['description'] as String?,
        rating: (j['rating'] as num?)?.toDouble(),
        ratingCount: (j['ratingCount'] as num?)?.toInt(),
        stock: (j['stock'] as num?)?.toInt(),
        warrantyText: j['warrantyText'] as String?,
        specifications: j['specifications'] as String?,
        imageUrl: j['imageUrl'] as String?,
        imageBytes: j['imageBytes'] != null
            ? base64Decode(j['imageBytes'] as String)
            : null,
      );

  @override
  String toString() => 'Product($id, $name, \$${price.toStringAsFixed(2)})';
}
