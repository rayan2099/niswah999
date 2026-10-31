/// Email address handling for sign-up, confirmation and recovery
/// (journeys NJ-005, NJ-061, NJ-062).
///
/// Normalization is deliberately small and documented: surrounding spaces
/// are removed and the address is lower-cased, which is what Supabase Auth
/// itself does before storing it. Nothing else is rewritten. A likely
/// typing mistake in the domain is only ever *suggested*; the address she
/// typed is never silently changed.
library;

/// Trims surrounding whitespace (including a pasted newline) and
/// lower-cases the address.
String normalizeEmail(String raw) => raw.trim().toLowerCase();

final RegExp _shape = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// Whether [email] (already normalized) has the shape of an address. The
/// email service remains the authority on whether it can be delivered.
bool looksLikeEmail(String email) => _shape.hasMatch(email);

/// Common misspellings of widely used mail domains, mapped to the domain
/// they almost certainly meant. Only exact matches are suggested.
const Map<String, String> _domainFixes = {
  'gmial.com': 'gmail.com',
  'gmai.com': 'gmail.com',
  'gmaill.com': 'gmail.com',
  'gamil.com': 'gmail.com',
  'gmail.co': 'gmail.com',
  'gmail.con': 'gmail.com',
  'gmail.cm': 'gmail.com',
  'gnail.com': 'gmail.com',
  'hotmial.com': 'hotmail.com',
  'hotmai.com': 'hotmail.com',
  'hotmail.co': 'hotmail.com',
  'hotmail.con': 'hotmail.com',
  'hotmal.com': 'hotmail.com',
  'outlok.com': 'outlook.com',
  'outloo.com': 'outlook.com',
  'outlook.co': 'outlook.com',
  'outlook.con': 'outlook.com',
  'yaho.com': 'yahoo.com',
  'yahooo.com': 'yahoo.com',
  'yahoo.co': 'yahoo.com',
  'yahoo.con': 'yahoo.com',
  'icloud.co': 'icloud.com',
  'icloud.con': 'icloud.com',
  'iclod.com': 'icloud.com',
  'icoud.com': 'icloud.com',
};

/// The corrected address when [email]'s domain is a known misspelling,
/// otherwise null. A suggestion for her to accept, never applied for her.
String? suggestEmailCorrection(String email) {
  final normalized = normalizeEmail(email);
  final at = normalized.lastIndexOf('@');
  if (at <= 0 || at == normalized.length - 1) return null;
  final fix = _domainFixes[normalized.substring(at + 1)];
  return fix == null ? null : '${normalized.substring(0, at)}@$fix';
}

/// Seconds to wait before another email may be requested, read from Auth's
/// rate-limit message ("... you can only request this after 37 seconds"),
/// or null when the message carries none.
int? retryAfterSecondsFrom(String message) {
  final match = RegExp(r'after (\d+) seconds?').firstMatch(message);
  return match == null ? null : int.tryParse(match.group(1)!);
}
