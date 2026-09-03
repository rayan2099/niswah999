# Niswah UI/UX parity certification plan

## Source of truth

- Deployed web app: `https://niswah.vercel.app/`
- Reference mobile viewport: 390 × 844 logical pixels
- Required directions: English/LTR and Arabic/RTL
- A screen is certified only when its isolated golden, interaction checks, and supported viewport checks pass.

## Independent suites

| Surface | English golden | Arabic golden | Interaction state | Responsive |
| --- | --- | --- | --- | --- |
| Dashboard | `parity_dashboard_test.dart` | `parity_dashboard_test.dart` | AI overlay in `parity_interactions_test.dart` | `parity_responsive_test.dart` |
| Calendar | `parity_calendar_test.dart` | `parity_calendar_test.dart` | Gregorian/Hijri in `parity_interactions_test.dart` | `parity_responsive_test.dart` |
| Insights | `parity_insights_test.dart` | `parity_insights_test.dart` | Navigation smoke coverage | `parity_responsive_test.dart` |
| Community | `parity_community_test.dart` | `parity_community_test.dart` | Existing community flow tests | `parity_responsive_test.dart` |
| Profile | `parity_profile_test.dart` | `parity_profile_test.dart` | Toggle isolation in `parity_interactions_test.dart` | `parity_responsive_test.dart` |

## Supported viewport matrix

- 320 × 568: compact phone
- 390 × 844: visual-reference phone
- 430 × 932: large phone

Every core screen is opened independently at every size and fails on any Flutter layout exception or overflow.

## Execution order

1. Run `flutter analyze` and require zero issues.
2. Run each `parity_<screen>_test.dart` file as its own process.
3. Run `parity_interactions_test.dart` independently.
4. Run `parity_responsive_test.dart` independently.
5. Run the complete test suite to detect cross-feature regressions.

## Claim boundary

Passing these suites certifies the captured core mobile UI states. Backend-dependent content, native platform dialogs, generated file contents, animation frames, tablets, and desktop layouts require their own references and must not be included in a 100% claim until separately captured and tested.
