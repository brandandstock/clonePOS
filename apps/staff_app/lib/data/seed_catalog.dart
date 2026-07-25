import 'package:flutter/material.dart';
import 'package:clone_pos_core/models/product.dart';

/// Prototype seed catalog for the Inventory tab's card view. Values
/// mirror the ten reference product cards the client shared as design
/// direction — SKUs, prices, ratings and copy taken verbatim from
/// those screenshots so the layout can be compared side-by-side.
///
/// [iconFor] gives each product a Material Icon stand-in for the
/// product photo. When real product imagery is added, swap the Icon
/// widget in the card view for an Image and drop this map.
List<Product> seedCatalog() {
  return const [
    Product(
      id: 'CAM-000001',
      name: 'Sony Alpha a7 IV Mirrorless Camera',
      price: 189990,
      category: 'Cameras',
      brand: 'Sony',
      subCategory: 'Mirrorless Cameras',
      description:
          '33MP full-frame Exmor R CMOS sensor with BIONZ XR processor. '
          '4K 60p 10-bit video, 5-axis in-body stabilization, '
          '10 fps continuous shooting.',
      rating: 4.5,
      ratingCount: 128,
      stock: 12,
      warrantyText: '1 Year Official Sony Warranty',
    ),
    Product(
      id: 'AUD-000001',
      name: 'Sony WH-1000XM5 Wireless Headphones',
      price: 29990,
      category: 'Audio',
      brand: 'Sony',
      subCategory: 'Headphones',
      description:
          'Industry-leading noise cancellation with dual processors. '
          'Up to 30-hour battery life with quick charge. Comfortable '
          'design for all-day listening.',
      rating: 4.5,
      ratingCount: 342,
      stock: 18,
      warrantyText: '1 Year Official Sony Warranty',
    ),
    Product(
      id: 'AUD-000002',
      name: 'Anker Soundcore Liberty 4 NC True Wireless Earbuds',
      price: 7999,
      category: 'Audio',
      brand: 'Anker',
      subCategory: 'Earbuds',
      description:
          'Adaptive Active Noise Cancellation reduces noise by up to '
          '98.5%. Hi-Res sound with 11mm drivers, 50H total playtime, '
          'wireless charging and IPX4 water resistance.',
      rating: 4.5,
      ratingCount: 856,
      stock: 34,
      warrantyText: '18 Months Manufacture Warranty',
    ),
    Product(
      id: 'AUD-000003',
      name: 'Bose SoundLink Flex Bluetooth Portable Speaker',
      price: 11990,
      category: 'Audio',
      brand: 'Bose',
      subCategory: 'Portable Speakers',
      description:
          'Deep, powerful sound in a compact size. Waterproof (IP67), '
          'dustproof and built to withstand drops, shocks and rust. '
          'Up to 12 hours of battery life.',
      rating: 4.5,
      ratingCount: 1892,
      stock: 16,
      warrantyText: '1 Year Official Bose Warranty',
    ),
    Product(
      id: 'AUD-000004',
      name: 'Sennheiser Momentum 4 Wireless Headphones',
      price: 24990,
      category: 'Audio',
      brand: 'Sennheiser',
      subCategory: 'Headphones',
      description:
          'Crystal-clear sound with Sennheiser signature tuning. '
          'Adaptive Noise Cancellation, 60-hour battery life, premium '
          'comfort and smart pause. Intuitive controls and foldable '
          'design.',
      rating: 4.5,
      ratingCount: 2765,
      stock: 18,
      warrantyText: '2 Years Official Sennheiser Warranty',
    ),
    Product(
      id: 'AUD-000005',
      name: 'Bang & Olufsen Beosound Explore Portable Bluetooth Speaker',
      price: 21990,
      category: 'Audio',
      brand: 'Bang & Olufsen',
      subCategory: 'Portable Speakers',
      description:
          '360° TrueSound with deep bass in a compact design. Water and '
          'dust resistant (IP67), up to 27 hours of playtime and built '
          'for any adventure. Premium materials and iconic B&O design.',
      rating: 5,
      ratingCount: 1357,
      stock: 14,
      warrantyText: '2 Years Official Bang & Olufsen Warranty',
    ),
    Product(
      id: 'AUD-000006',
      name: 'Genelec 8020D Active Studio Monitor (Each)',
      price: 74990,
      category: 'Audio',
      brand: 'Genelec',
      subCategory: 'Studio Monitors',
      description:
          'Compact active 2-way studio monitor with exceptional accuracy. '
          'Optimized for small control rooms and surround setups. '
          'MDE™ (Minimum Diffraction Enclosure) for neutral sound, '
          'flexible positioning and reliable performance.',
      rating: 5,
      ratingCount: 1246,
      stock: 10,
      warrantyText: '2 Years Official Genelec Warranty',
    ),
    Product(
      id: 'WEA-000001',
      name: 'Apple Watch SE (2nd Gen) GPS, 44mm Midnight Aluminum',
      price: 27900,
      category: 'Wearables',
      brand: 'Apple',
      subCategory: 'Smartwatches',
      description:
          'Stay connected, active and healthy with advanced fitness '
          'tracking, heart rate monitoring, Crash Detection and up to '
          '18 hours of battery life.',
      rating: 4.5,
      ratingCount: 1256,
      stock: 23,
      warrantyText: '1 Year Official Apple Warranty',
    ),
    Product(
      id: 'PRO-000001',
      name: 'XGIMI Horizon Pro 4K Smart Home Projector',
      price: 89990,
      category: 'Home Entertainment',
      brand: 'XGIMI',
      subCategory: 'Projectors',
      description:
          '4K UHD resolution with 1500 ISO lumens brightness. Android '
          'TV 10.0, built-in Harman Kardon speakers, auto keystone '
          'correction and intelligent screen alignment for the perfect '
          'view.',
      rating: 5,
      ratingCount: 1024,
      stock: 12,
      warrantyText: '1 Year Official XGIMI Warranty',
    ),
  ];
}

/// Placeholder Material Icon for a product until real imagery is
/// bundled. Chosen by sub-category first, then category — falls back
/// to a generic box.
IconData iconFor(Product product) {
  switch (product.subCategory) {
    case 'Mirrorless Cameras':
    case 'Cameras':
      return Icons.photo_camera_outlined;
    case 'Headphones':
      return Icons.headphones_outlined;
    case 'Earbuds':
      return Icons.earbuds_outlined;
    case 'Portable Speakers':
    case 'Studio Monitors':
      return Icons.speaker_outlined;
    case 'Smartwatches':
      return Icons.watch_outlined;
    case 'Projectors':
      return Icons.videocam_outlined;
  }
  return Icons.inventory_2_outlined;
}
