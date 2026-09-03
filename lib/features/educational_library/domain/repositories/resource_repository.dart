import '../entities/resource_item.dart';

abstract class ResourceRepository {
  Future<List<ResourceItem>> getResources({
    ResourceCategory? category,
    bool includeSpouseGuides = true,
  });

  Future<ResourceItem?> getResourceById({required String id});
}
