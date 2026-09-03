class AppClock {
  AppClock._();

  static DateTime Function() now = DateTime.now;

  static void reset() {
    now = DateTime.now;
  }
}
