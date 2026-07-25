import 'package:clone_pos_core/models/product.dart';

/// Prototype-only seed inventory. Used as the data source for the
/// Inventory list screen and the A-Z rail's first real test bed. Real
/// products come from the InventoryRepository once persistence is wired.
List<Product> seedProducts() {
  const rows = <List<String>>[
    ['p-001', 'Alpaca Wool Scarf', 'Apparel', '48.00'],
    ['p-002', 'Anchor Keyring', 'Accessories', '12.50'],
    ['p-003', 'Bamboo Cutting Board', 'Kitchen', '24.00'],
    ['p-004', 'Beeswax Candle Set', 'Home', '18.00'],
    ['p-005', 'Black Denim Apron', 'Apparel', '38.00'],
    ['p-006', 'Ceramic Espresso Cup', 'Kitchen', '9.00'],
    ['p-007', 'Copper Coffee Filter', 'Kitchen', '22.00'],
    ['p-008', 'Cotton Tote Bag', 'Accessories', '14.00'],
    ['p-009', 'Denim Field Jacket', 'Apparel', '128.00'],
    ['p-010', 'Enamel Kettle', 'Kitchen', '54.00'],
    ['p-011', 'Field Notes Journal', 'Stationery', '11.00'],
    ['p-012', 'Flint Striker', 'Outdoor', '8.50'],
    ['p-013', 'Glass Milk Bottle', 'Kitchen', '6.50'],
    ['p-014', 'Green Wool Beanie', 'Apparel', '26.00'],
    ['p-015', 'Hemp Bar Soap', 'Bath', '7.50'],
    ['p-016', 'Iron Skillet', 'Kitchen', '42.00'],
    ['p-017', 'Ivory Playing Cards', 'Games', '13.00'],
    ['p-018', 'Jute Doormat', 'Home', '32.00'],
    ['p-019', 'Kraft Gift Box', 'Stationery', '4.00'],
    ['p-020', 'Leather Card Wallet', 'Accessories', '58.00'],
    ['p-021', 'Linen Napkin Set', 'Kitchen', '28.00'],
    ['p-022', 'Marbled Notebook', 'Stationery', '16.00'],
    ['p-023', 'Merino Wool Socks', 'Apparel', '22.00'],
    ['p-024', 'Natural Bristle Brush', 'Bath', '13.00'],
    ['p-025', 'Oak Salt Cellar', 'Kitchen', '19.00'],
    ['p-026', 'Olive Wood Spoon', 'Kitchen', '11.00'],
    ['p-027', 'Pewter Shot Glass', 'Bar', '14.00'],
    ['p-028', 'Pine Tar Soap', 'Bath', '8.50'],
    ['p-029', 'Porcelain Teapot', 'Kitchen', '46.00'],
    ['p-030', 'Rattan Bread Basket', 'Kitchen', '24.00'],
    ['p-031', 'Rope Trivet', 'Kitchen', '16.00'],
    ['p-032', 'Sandalwood Comb', 'Bath', '11.00'],
    ['p-033', 'Silk Pocket Square', 'Apparel', '32.00'],
    ['p-034', 'Slate Cheese Board', 'Kitchen', '22.00'],
    ['p-035', 'Stoneware Mug', 'Kitchen', '14.00'],
    ['p-036', 'Suede Notebook Cover', 'Stationery', '38.00'],
    ['p-037', 'Terracotta Planter', 'Home', '18.00'],
    ['p-038', 'Tin Storage Box', 'Home', '9.50'],
    ['p-039', 'Umbrella (Waxed Canvas)', 'Accessories', '68.00'],
    ['p-040', 'Vegetable Tanned Belt', 'Apparel', '72.00'],
    ['p-041', 'Waxed Canvas Rucksack', 'Bags', '158.00'],
    ['p-042', 'Whittled Whistle', 'Outdoor', '5.00'],
    ['p-043', 'Wool Blanket', 'Home', '96.00'],
    ['p-044', 'Xylitol Mints', 'Sundries', '3.50'],
    ['p-045', 'Yak Wool Sweater', 'Apparel', '178.00'],
    ['p-046', 'Yellow Rain Cape', 'Apparel', '84.00'],
    ['p-047', 'Zebrawood Bottle Opener', 'Bar', '19.00'],
    ['p-048', 'Zinc Water Bottle', 'Outdoor', '22.00'],
  ];
  return [
    for (final r in rows)
      Product(id: r[0], name: r[1], category: r[2], price: double.parse(r[3])),
  ];
}
