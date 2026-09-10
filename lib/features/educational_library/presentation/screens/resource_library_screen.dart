import 'package:flutter/material.dart';

import '../../../../core/localization/app_locale_controller.dart';
import '../../domain/entities/resource_item.dart';
import '../viewmodels/resource_library_view_model.dart';

String _rl(String en, String ar) => AppLocaleController.instance.text(en, ar);

class ResourceLibraryScreen extends StatefulWidget {
  const ResourceLibraryScreen({super.key});

  @override
  State<ResourceLibraryScreen> createState() => _ResourceLibraryScreenState();
}

class _ResourceLibraryScreenState extends State<ResourceLibraryScreen> {
  late final ResourceLibraryViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = ResourceLibraryViewModel();
    _viewModel.loadResources();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _viewModel,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(_rl('Educational library', 'المكتبة التعليمية')),
          ),
          body: SafeArea(
            child: Column(
              children: [
                SizedBox(
                  height: 52,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: [null, ...ResourceCategory.values].length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final category = index == 0
                          ? null
                          : ResourceCategory.values[index - 1];
                      final isSelected =
                          _viewModel.selectedCategory == category;

                      return ChoiceChip(
                        label: Text(
                          category == null
                              ? _rl('All', 'الكل')
                              : _label(category),
                        ),
                        selected: isSelected,
                        onSelected: (_) => _viewModel.selectCategory(category),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _viewModel.isLoading
                      ? Center(
                          child: CircularProgressIndicator(
                            semanticsLabel: _rl('Loading', 'جارٍ التحميل'),
                          ),
                        )
                      : _viewModel.errorMessage != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(_viewModel.errorMessage!),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _viewModel.filteredResources.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final resource =
                                _viewModel.filteredResources[index];
                            return ResourceTile(resource: resource);
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _label(ResourceCategory category) {
    return switch (category) {
      ResourceCategory.health => _rl('Health', 'الصحة'),
      ResourceCategory.fiqh => _rl('Fiqh', 'الفقه'),
      ResourceCategory.family => _rl('Family', 'الأسرة'),
      ResourceCategory.wellness => _rl('Wellness', 'العافية'),
      ResourceCategory.spouse => _rl('For spouse', 'للزوج'),
    };
  }
}

class ResourceTile extends StatelessWidget {
  const ResourceTile({super.key, required this.resource});

  final ResourceItem resource;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        title: Text(resource.title),
        subtitle: Text(
          '${resource.author} • ${resource.readMinutes} ${_rl('min', 'دقيقة')}',
        ),
        trailing: resource.isSpouseGuide
            ? const Icon(Icons.favorite_rounded)
            : const Icon(Icons.menu_book_rounded),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  resource.summary,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: resource.tags
                      .map((tag) => Chip(label: Text(tag)))
                      .toList(),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(resource.content),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
