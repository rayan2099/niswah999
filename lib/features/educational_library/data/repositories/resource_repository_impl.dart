import 'package:collection/collection.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/network/supabase_client.dart';
import '../../domain/entities/resource_item.dart';
import '../../domain/repositories/resource_repository.dart';

class ResourceRepositoryImpl implements ResourceRepository {
  ResourceRepositoryImpl({SupabaseClient? client})
    : _client = client ?? NiswahSupabase.clientOrNull;

  final SupabaseClient? _client;

  static const String _tableName = 'educational_resources';

  @override
  Future<List<ResourceItem>> getResources({
    ResourceCategory? category,
    bool includeSpouseGuides = true,
  }) async {
    final client = _client;
    if (client == null) {
      return _defaultResources().where((resource) {
        if (category != null && resource.category != category) {
          return false;
        }
        if (!includeSpouseGuides && resource.isSpouseGuide) {
          return false;
        }
        return true;
      }).toList();
    }

    try {
      var query = client.from(_tableName).select();
      if (category != null) {
        query = query.eq('category', category.name);
      }
      if (!includeSpouseGuides) {
        query = query.eq('is_spouse_guide', false);
      }

      final response = await query.order('created_at', ascending: false);
      final resources = (response as List<dynamic>)
          .map((item) => ResourceItem.fromJson(Map<String, dynamic>.from(item)))
          .toList();

      return resources;
    } on PostgrestException {
      return _defaultResources().where((resource) {
        if (category != null && resource.category != category) {
          return false;
        }
        if (!includeSpouseGuides && resource.isSpouseGuide) {
          return false;
        }
        return true;
      }).toList();
    }
  }

  @override
  Future<ResourceItem?> getResourceById({required String id}) async {
    final resources = await getResources();
    return resources.where((item) => item.id == id).firstOrNull;
  }

  List<ResourceItem> _defaultResources() {
    return [
      ResourceItem(
        id: 'res-1',
        category: ResourceCategory.health,
        title: 'Cycle health essentials',
        summary: 'Simple ways to support your health during different phases of the cycle.',
        content: 'During the follicular phase, focus on light movement, hydration, and consistent routines. In the luteal phase, prioritize rest, sleep quality, and balanced meals. Recognize your patterns and adapt gently to the changes in your body.',
        author: 'Niswah Team',
        readMinutes: 6,
        tags: const ['wellness', 'cycle'],
        isSpouseGuide: false,
        createdAt: DateTime(2026, 8, 10),
      ),
      ResourceItem(
        id: 'res-2',
        category: ResourceCategory.spouse,
        title: 'Supporting your spouse through cycle changes',
        summary: 'A compassionate guide for partners to understand emotional and physical needs.',
        content: 'A spouse can offer meaningful support by listening without pressure, offering practical help, and respecting changing energy levels. Gentle communication, thoughtful planning, and patience create safety during difficult days.',
        author: 'Niswah Care Team',
        readMinutes: 8,
        tags: const ['partner', 'support'],
        isSpouseGuide: true,
        createdAt: DateTime(2026, 8, 12),
      ),
      ResourceItem(
        id: 'res-3',
        category: ResourceCategory.fiqh,
        title: 'Daily worship and practical guidance',
        summary: 'Balanced insight on worship routines and flexibility when health needs shift.',
        content: 'When your routine changes due to health, the goal is to return to the next right step with intention. A realistic plan is better than perfection. Re-assess, make space for rest, and keep your worship consistent in a sustainable way.',
        author: 'Niswah Team',
        readMinutes: 5,
        tags: const ['fiqh', 'worship'],
        isSpouseGuide: false,
        createdAt: DateTime(2026, 8, 14),
      ),
      ResourceItem(
        id: 'res-4',
        category: ResourceCategory.family,
        title: 'Healthy conversations in marriage',
        summary: 'Frameworks for honest, respectful communication about wellbeing and expectations.',
        content: 'Health conversations work best when both partners feel heard. Focus on what is happening, what is needed, and what can be adjusted together. Calm clarity is more effective than pressure or guilt.',
        author: 'Niswah Family Guidance',
        readMinutes: 7,
        tags: const ['communication', 'family'],
        isSpouseGuide: true,
        createdAt: DateTime(2026, 8, 16),
      ),
    ];
  }
}
