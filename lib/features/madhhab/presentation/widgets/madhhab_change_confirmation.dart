import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../../../core/preferences/madhhab_controller.dart';
import '../../../cycle_tracking/domain/services/madhhab_rule_evaluator.dart';

/// Requirement 2's warning dialog — shown when an existing SELECTED
/// madhhab is being replaced (by a different madhhab, or by "I don't
/// know"), withdrawing or changing an interpretation that already
/// existed. Returns true only on an explicit "Confirm change" tap —
/// Cancel (or dismissing the barrier) leaves everything unchanged.
Future<bool> confirmMadhhabChange(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) => AlertDialog(
      title: Text(
        AppLocaleController.instance.text(
          'Change your Fiqh Madhhab?',
          'تغيير مذهبك الفقهي؟',
        ),
      ),
      content: Text(
        AppLocaleController.instance.text(
          'Changing your Madhhab may change the Fiqh interpretation of '
              'some previously recorded days. Your original records will '
              'not be changed. Niswah will recalculate the relevant Fiqh '
              'results according to your new Madhhab.',
          'تغيير المذهب قد يغيّر التفسير الفقهي لبعض الأيام المسجلة '
              'سابقاً، لكنه لن يغيّر البيانات التي أدخلتِها. بعد التغيير، '
              'ستُعاد الحسابات الفقهية وفق المذهب الجديد.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(AppLocaleController.instance.text('Cancel', 'إلغاء')),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            AppLocaleController.instance.text(
              'Confirm change',
              'تأكيد التغيير',
            ),
          ),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// A lighter, informational notice — shown specifically for unknown ->
/// selected: no prior Madhhab interpretation existed to "change," but
/// adopting one for the first time means her already-logged historical
/// observations will now receive a real Fiqh interpretation for the
/// first time, which deserves a heads-up even though nothing is being
/// overwritten. Never shown during initial onboarding (callers there
/// bypass this file entirely and call MadhhabController directly), since
/// no historical data exists yet at that point for there to be anything
/// newly interpreted.
Future<bool> confirmFirstFiqhInterpretation(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) => AlertDialog(
      content: Text(
        AppLocaleController.instance.text(
          'Niswah will now interpret your previous records according to '
              'the Madhhab you selected. Your original entries will not '
              'be changed.',
          'سيبدأ نسوة الآن بتفسير سجلاتك السابقة وفق المذهب الذي اخترتِه. '
              'لن تتغير البيانات التي سجلتِها بنفسك.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(AppLocaleController.instance.text('Cancel', 'إلغاء')),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(AppLocaleController.instance.text('Continue', 'متابعة')),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// The one shared save path every Madhhab picker (onboarding, Settings,
/// the resolution screen) must call through — this is what makes
/// "saving logic, validation" identical everywhere per Requirement 1.
/// Decision table (Requirement 2, refined after adversarial review):
///
///   unset     -> selected   : no dialog — nothing was ever interpreted.
///   unset     -> unknown    : no dialog.
///   unknown   -> selected   : LIGHT notice (confirmFirstFiqhInterpretation)
///                             — no prior interpretation existed, but her
///                             historical observations are about to receive
///                             a real one for the first time.
///   selected  -> unknown    : FULL warning — withdraws an existing
///                             interpretation.
///   selected A -> selected B (B != A) : FULL warning — replaces an
///                             existing interpretation with a different one.
///   selected A -> selected A (same value) : no-op — returns immediately,
///                             no dialog, no history row, no
///                             notifyListeners, no recomputation trigger.
///                             See MadhhabController.selectMadhhab's own
///                             no-op guard for the second half of this.
///
/// Onboarding never calls this function at all (it calls
/// MadhhabController directly) — by design, so that no dialog of either
/// kind can ever appear before any historical data exists to be
/// reinterpreted.
Future<void> setMadhhabWithConfirmation(
  BuildContext context, {
  required Madhhab? newMadhhab,
  String source = 'unspecified',
}) async {
  final controller = MadhhabController.instance;

  if (controller.state == MadhhabSelectionState.selected &&
      controller.selectedOrNull == newMadhhab) {
    // Selecting the currently-selected madhhab again is a genuine no-op —
    // never persisted, never dialogued, never recorded.
    return;
  }

  final isFullWarning = controller.state == MadhhabSelectionState.selected;
  final isLightNotice =
      !isFullWarning &&
      controller.state == MadhhabSelectionState.unknown &&
      newMadhhab != null;

  if (isFullWarning) {
    if (!await confirmMadhhabChange(context)) return;
  } else if (isLightNotice) {
    if (!await confirmFirstFiqhInterpretation(context)) return;
  }

  if (newMadhhab == null) {
    await controller.selectUnknown(source: source);
  } else {
    await controller.selectMadhhab(newMadhhab, source: source);
  }
}
