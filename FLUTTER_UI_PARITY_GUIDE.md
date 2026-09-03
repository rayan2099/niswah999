# Flutter Niswah - UI/UX Parity Implementation Guide

## ✅ COMPLETED FOUNDATIONS

### 1. Design System (Theme)
**File:** `lib/core/theme/app_theme.dart`
- ✅ Color tokens matching web app (#FDFCFB background, #BE123C primary, #FB7185 secondary)
- ✅ Semantic colors (tahara, haid, istihadah, nifas)
- ✅ Typography theme with proper hierarchy
- ✅ Component themes (cards, buttons, inputs)

### 2. Reusable Components
**File:** `lib/core/widgets/common_widgets.dart`
- ✅ `NiswahCard` - Styled card component (32px radius, shadows, borders)
- ✅ `ScreenHeader` - Branded screen headers
- ✅ `MobileCanvas` - Centered mobile layout wrapper
- ✅ `StatCard` - Stats display component
- ✅ `NiswahListTile` - Custom list items

### 3. Navigation
**File:** `lib/core/widgets/floating_nav_bar.dart`
- ✅ Floating bottom navigation bar
- ✅ Centered FAB (pink, sparkles icon)
- ✅ 5-item tab structure (Prayer, Cycle, Pregnancy, Community, Profile)

### 4. Main App Structure
**File:** `lib/main.dart`
- ✅ Custom theme integration
- ✅ AppTheme.lightTheme applied globally
- ✅ FloatingNavBar implementation
- ✅ IndexedStack for tab navigation
- ✅ FAB opens Dr. Niswah chat

---

## ✅ COMPLETED SCREEN

### Prayer Tracking Screen  
**File:** `lib/features/prayer_tracking/presentation/screens/prayer_tracking_screen.dart`

**Status:** Complete ✅

**What's Done:**
- Main build method refactored to use AppColors.brandBackground
- ScreenHeader integration
- NiswahCard imports added
- Layout updated for floating nav (120px bottom spacing)

**Completed Components:**
- ✅ `NiswahCard`-based prayer summary and daily prayer tiles
- ✅ Horizontally scrolling, styled prayer-time chips
- ✅ Semantic status badges and action buttons using `AppColors`
- ✅ Floating-navigation-safe bottom spacing

**Reference Structure:**
```dart
class _PrayerSummaryCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return NiswahCard(
      backgroundColor: AppColors.surface,
      child: Column(
        children: [
          // Header with icon in colored container
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.mosque_rounded, color: AppColors.success),
              ),
              // Title and subtitle
            ],
          ),
          // Horizontal scroll of prayer time chips
          SizedBox(
            height: 120,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [...prayer chips...]
            ),
          ),
        ],
      ),
    );
  }
}
```

---

## ⏭️ TODO SCREENS

### Calendar Screen (Cycle Tracking)
**File:** `lib/features/cycle_tracking/presentation/screens/cycle_tracking_screen.dart`

**Changes Needed:**
1. Remove AppBar, add ScreenHeader (emerald color for Calendar)
2. Replace generic Cards with NiswahCard components
3. Use AppColors throughout
4. Add 120px bottom padding for floating nav
5. Update colors: 
   - Calendar grid: Use AppColors
   - Days: State-based colors (HAID=rose, TAHARA=emerald, etc.)
6. Round corners to 32px on main containers

**Key Components:**
- Calendar grid with proper color coding
- Stats cards using StatCard component
- Legend with colored dots

---

### Insights Screen  
**File:** `lib/features/educational_library/presentation/screens/resource_library_screen.dart`
*(or similar insights screen)*

**Changes Needed:**
1. Remove AppBar, add ScreenHeader (rose color)
2. Grid layout for stat cards using StatCard
3. Charts/trends in NiswahCard containers
4. Symptom list with proper spacing
5. Use AppColors for all colors
6. Add 120px bottom padding

**Key Components:**
- 2-column stat grid (avg cycle length, regularity %)
- Trend bars with progress indicators
- History list with NiswahListTile

---

### Profile Screen
**File:** `lib/features/auth/presentation/screens/profile_screen.dart` or similar

**Changes Needed:**
1. Remove AppBar, add ScreenHeader (rose color)
2. User card at top with avatar
3. Settings sections with NiswahListTile
4. Toggles and inputs with proper styling
5. Use AppColors for all colors
6. Add 120px bottom padding

**Key Components:**
- User avatar card
- Fiqh school selection (grid of cards)
- Health profile toggles
- Export PDF buttons
- Language selector

---

## 🎨 DESIGN SYSTEM REFERENCE

### Colors (Import from AppColors)
```dart
AppColors.brandPrimary          // #BE123C (soft pink)
AppColors.brandSecondary        // #FB7185 (pink)
AppColors.brandBackground       // #FDFCFB (warm off-white)
AppColors.surface               // #FFFFFF (white)
AppColors.surfaceHover          // #F9FAFB (gray-50)
AppColors.textPrimary           // #1F2937 (gray-900)
AppColors.textSecondary         // #6B7280 (gray-500)
AppColors.textTertiary          // #9CA3AF (gray-400)
AppColors.success               // #10B981 (emerald-500)
AppColors.warning               // #F59E0B (amber-500)
AppColors.error                 // #EF4444 (red-500)
```

### Card Styling Pattern
```dart
NiswahCard(
  backgroundColor: AppColors.surface,
  padding: const EdgeInsets.all(24), // or custom
  borderRadius: 32,
  onTap: () {}, // optional
  child: ...
)
```

### List Item Pattern
```dart
NiswahListTile(
  title: 'Label',
  subtitle: 'Optional description',
  icon: Icons.icon_name,
  trailing: optional_widget,
  onTap: () {},
)
```

### Stat Card Pattern
```dart
StatCard(
  label: 'Avg Cycle Length',
  value: '28',
  unit: 'days',
  accentColor: AppColors.brandPrimary,
)
```

### Screen Header Pattern
```dart
ScreenHeader(
  title: 'Screen Title',
  subtitle: 'Optional subtitle',
  titleColor: AppColors.success, // or other color
)
```

---

## 📋 IMPLEMENTATION CHECKLIST

- [x] Complete Prayer Tracking screen component replacements
- [ ] Update Calendar screen
- [ ] Update Insights screen
- [ ] Update Profile screen  
- [ ] Test all screens render properly
- [ ] Verify floating nav bar works on all screens
- [ ] Check spacing and padding (120px bottom margin)
- [ ] Verify colors match web app (#FDFCFB, #BE123C, etc.)
- [ ] Test on both iOS and Android emulators
- [ ] Verify RTL support if applicable
- [ ] Review shadows and border styling

---

## 🔧 COMMON PATTERNS

### Bottom Padding for Floating Nav
Add this to your SingleChildScrollView's last child:
```dart
const SizedBox(height: 120),
```

### Update Imports
Add to screen files:
```dart
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';
```

### Replace Scaffold Background
```dart
Scaffold(
  backgroundColor: AppColors.brandBackground,
  // remove appBar
  body: ...
)
```

---

## ✨ NEXT STEPS

1. **Complete Prayer Tracking**: Replace all component classes with styled versions
2. **Build & Test**: `flutter run` to verify changes compile and display correctly
3. **Iterate Through Screens**: Follow the same pattern for Calendar, Insights, Profile
4. **Visual Polish**: Fine-tune spacing, shadows, and color usage to match web exactly
5. **Final Testing**: Verify 100% parity with web design
