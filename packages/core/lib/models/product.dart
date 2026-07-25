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
  final String? imageUrl;

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
    this.imageUrl,
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
    String? imageUrl,
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
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }

  @override
  String toString() => 'Product($id, $name, \$${price.toStringAsFixed(2)})';
}
