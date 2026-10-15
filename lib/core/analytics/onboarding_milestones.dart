import '../errors/app_error_reporter.dart';
import '../network/supabase_client.dart';

/// Workflow milestones only: no answer values, location, health details, or text.
/// Best effort; an analytics failure must never block onboarding.
class OnboardingMilestones {
  static const steps = <int, String>{
    1: 'started',
    2: 'madhhab',
    3: 'marital',
    4: 'location',
    5: 'last_period',
    6: 'period_length',
    7: 'privacy',
    8: 'welcome',
  };

  static Future<void> record(String step) async {
    final client = NiswahSupabase.clientOrNull;
    if (client?.auth.currentUser == null) return;
    try {
      await client!.rpc(
        'record_onboarding_milestone',
        params: {'p_step': step},
      );
    } catch (_, stack) {
      AppErrorReporter.report(
        StateError('Onboarding milestone could not be recorded'),
        stack,
        context: 'OnboardingMilestones.record',
        feature: 'onboarding',
      );
    }
  }
}
