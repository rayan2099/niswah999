import '../../../../core/localization/app_locale_controller.dart';
import 'community_post.dart';

/// Single source of truth for category display labels, used by both the
/// filter chip bar and the composer's category picker so they can never
/// drift out of sync with each other or with the enum's 6 values.
extension CommunityCategoryLabel on CommunityCategory {
  String label() {
    final t = AppLocaleController.instance.text;
    return switch (this) {
      CommunityCategory.general => t('General', 'عام'),
      CommunityCategory.wellness => t('Health', 'صحة'),
      CommunityCategory.prayer => t('Fiqh', 'فقه'),
      CommunityCategory.support => t('Mental', 'نفسية'),
      CommunityCategory.parenting => t('Parenting', 'أمومة'),
      CommunityCategory.fertility => t('Fertility', 'خصوبة'),
    };
  }
}
