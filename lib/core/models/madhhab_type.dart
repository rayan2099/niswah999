enum MadhhabType {
  hanafi,
  maliki,
  shafii,
  hanbali;

  /// Strict parser: invalid/unknown persisted values must never become a real
  /// school by fallback. Callers that legitimately accept absence should use
  /// [tryFromValue] and preserve null/UNKNOWN explicitly.
  factory MadhhabType.fromValue(String value) {
    final parsed = tryFromValue(value);
    if (parsed == null) {
      throw FormatException('Unknown Madhhab value: $value');
    }
    return parsed;
  }

  static MadhhabType? tryFromValue(String? value) {
    if (value == null) return null;
    final normalized = value.trim().toLowerCase();
    for (final madhhab in MadhhabType.values) {
      if (madhhab.name == normalized) return madhhab;
    }
    return null;
  }
}
