import 'package:flutter/foundation.dart';

import '../../data/repositories/resource_repository_impl.dart';
import '../../domain/entities/resource_item.dart';
import '../../domain/repositories/resource_repository.dart';

class ResourceLibraryViewModel extends ChangeNotifier {
  ResourceLibraryViewModel({ResourceRepository? repository})
    : _repository = repository ?? ResourceRepositoryImpl();

  final ResourceRepository _repository;

  bool isLoading = false;
  String? errorMessage;
  ResourceCategory? selectedCategory;
  List<ResourceItem> resources = const <ResourceItem>[];

  Future<void> loadResources() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      resources = await _repository.getResources(
        category: selectedCategory,
        includeSpouseGuides: true,
      );
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void selectCategory(ResourceCategory? category) {
    selectedCategory = category;
    loadResources();
  }

  List<ResourceItem> get filteredResources {
    if (selectedCategory == null) {
      return resources;
    }
    return resources
        .where((resource) => resource.category == selectedCategory)
        .toList();
  }
}
