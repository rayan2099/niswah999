/// Shared list of countries with dial codes for phone-auth inputs
/// (onboarding's phone sign-in sheet and `SignInScreen`'s phone tab).
class Country {
  const Country(this.flag, this.name, this.nameAr, this.dial);

  final String flag;
  final String name;
  final String nameAr;
  final String dial;

  @override
  bool operator ==(Object other) =>
      other is Country &&
      other.flag == flag &&
      other.name == name &&
      other.nameAr == nameAr &&
      other.dial == dial;

  @override
  int get hashCode => Object.hash(flag, name, nameAr, dial);
}

/// Saudi Arabia first, to match the app's primary market.
const List<Country> kCountries = [
  Country('🇸🇦', 'Saudi Arabia', 'السعودية', '+966'),
  Country('🇦🇪', 'UAE', 'الإمارات', '+971'),
  Country('🇰🇼', 'Kuwait', 'الكويت', '+965'),
  Country('🇶🇦', 'Qatar', 'قطر', '+974'),
  Country('🇧🇭', 'Bahrain', 'البحرين', '+973'),
  Country('🇴🇲', 'Oman', 'عمان', '+968'),
  Country('🇾🇪', 'Yemen', 'اليمن', '+967'),
  Country('🇮🇶', 'Iraq', 'العراق', '+964'),
  Country('🇯🇴', 'Jordan', 'الأردن', '+962'),
  Country('🇱🇧', 'Lebanon', 'لبنان', '+961'),
  Country('🇸🇾', 'Syria', 'سوريا', '+963'),
  Country('🇵🇸', 'Palestine', 'فلسطين', '+970'),
  Country('🇪🇬', 'Egypt', 'مصر', '+20'),
  Country('🇱🇾', 'Libya', 'ليبيا', '+218'),
  Country('🇹🇳', 'Tunisia', 'تونس', '+216'),
  Country('🇩🇿', 'Algeria', 'الجزائر', '+213'),
  Country('🇲🇦', 'Morocco', 'المغرب', '+212'),
  Country('🇸🇩', 'Sudan', 'السودان', '+249'),
  Country('🇲🇷', 'Mauritania', 'موريتانيا', '+222'),
  Country('🇸🇴', 'Somalia', 'الصومال', '+252'),
  Country('🇩🇯', 'Djibouti', 'جيبوتي', '+253'),
  Country('🇰🇲', 'Comoros', 'جزر القمر', '+269'),
  Country('🇹🇷', 'Turkey', 'تركيا', '+90'),
  Country('🇮🇷', 'Iran', 'إيران', '+98'),
  Country('🇵🇰', 'Pakistan', 'باكستان', '+92'),
  Country('🇮🇳', 'India', 'الهند', '+91'),
  Country('🇧🇩', 'Bangladesh', 'بنغلاديش', '+880'),
  Country('🇮🇩', 'Indonesia', 'إندونيسيا', '+62'),
  Country('🇲🇾', 'Malaysia', 'ماليزيا', '+60'),
  Country('🇬🇧', 'United Kingdom', 'المملكة المتحدة', '+44'),
  Country('🇺🇸', 'United States', 'الولايات المتحدة', '+1'),
  Country('🇨🇦', 'Canada', 'كندا', '+1'),
  Country('🇫🇷', 'France', 'فرنسا', '+33'),
  Country('🇩🇪', 'Germany', 'ألمانيا', '+49'),
  Country('🇮🇹', 'Italy', 'إيطاليا', '+39'),
  Country('🇪🇸', 'Spain', 'إسبانيا', '+34'),
  Country('🇳🇱', 'Netherlands', 'هولندا', '+31'),
  Country('🇸🇪', 'Sweden', 'السويد', '+46'),
  Country('🇦🇺', 'Australia', 'أستراليا', '+61'),
];
