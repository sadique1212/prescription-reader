class Medicine {
  final String name;
  final String manufacturer;
  final String type;
  final String composition1;
  final String composition2;

  Medicine({
    required this.name,
    required this.manufacturer,
    required this.type,
    required this.composition1,
    required this.composition2,
  });

  factory Medicine.fromMap(Map<String, dynamic> map) {
    return Medicine(
      name: map['name'] ?? '',
      manufacturer: map['manufacturer_name'] ?? '',
      type: map['type'] ?? '',
      composition1: map['short_composition1'] ?? '',
      composition2: map['short_composition2'] ?? '',
    );
  }
}