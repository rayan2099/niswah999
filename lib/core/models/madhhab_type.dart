enum MadhhabType {
  hanafi,
  maliki,
  shafii,
  hanbali;

  factory MadhhabType.fromValue(String value) {
    return MadhhabType.values.firstWhere(
      (e) => e.toString().split(".").last == value,
      orElse: () => MadhhabType.shafii, // Default to Shafii if not found
    );
  }
}
