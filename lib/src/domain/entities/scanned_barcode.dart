class ScannedBarcode {
  final String value;
  final int count;
  final DateTime lastIncrementTime;

  const ScannedBarcode({
    required this.value,
    this.count = 1,
    required this.lastIncrementTime,
  });

  ScannedBarcode copyWith({
    int? count,
    DateTime? lastIncrementTime,
  }) {
    return ScannedBarcode(
      value: value,
      count: count ?? this.count,
      lastIncrementTime: lastIncrementTime ?? this.lastIncrementTime,
    );
  }
}
