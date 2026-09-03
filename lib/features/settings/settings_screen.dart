import 'package:flutter/material.dart';
import 'package:niswah/core/models/madhhab_type.dart';
import 'package:niswah/core/models/user_profile.dart';
import 'package:niswah/core/network/supabase_client.dart';
import 'package:niswah/core/services/user_profile_repository.dart';

class UserProfileNotifier extends ChangeNotifier {
  UserProfileNotifier._();
  static final instance = UserProfileNotifier._();

  UserProfile? _currentProfile;
  UserProfile? get currentProfile => _currentProfile;

  void updateProfile(UserProfile? profile) {
    _currentProfile = profile;
    notifyListeners();
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  MadhhabType _selectedMadhhab = MadhhabType.shafii;
  bool _isLoading = true;
  String? _errorMessage;
  late final UserProfileRepository _profileRepo;

  @override
  void initState() {
    super.initState();
    _profileRepo = UserProfileRepository(NiswahSupabase.client);
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userId =
          NiswahSupabase.client.auth.currentUser?.id ?? 'demo-user-id';
      var profile = await _profileRepo.fetchUserProfile(userId);

      if (profile == null) {
        // Automatically insert a default profile if none exists
        profile = UserProfile(
          id: userId,
          fullName: 'Sister',
          selectedMadhhab: MadhhabType.shafii,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        profile = await _profileRepo.insertUserProfile(profile);
      }

      if (profile != null) {
        _nameController.text = profile.fullName ?? '';
        _selectedMadhhab = profile.selectedMadhhab;
        UserProfileNotifier.instance.updateProfile(profile);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load profile settings: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userId =
          NiswahSupabase.client.auth.currentUser?.id ?? 'demo-user-id';
      final updatedProfile = UserProfile(
        id: userId,
        fullName: _nameController.text.trim(),
        selectedMadhhab: _selectedMadhhab,
        createdAt:
            UserProfileNotifier.instance.currentProfile?.createdAt ??
            DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final result = await _profileRepo.updateUserProfile(updatedProfile);

      if (result != null) {
        UserProfileNotifier.instance.updateProfile(result);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Profile and Madhhab settings updated successfully!',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('Update returned null');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to save settings: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings & Madhhab Switcher'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(0xFF0F291E),
      ),
      body: _isLoading && _nameController.text.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    const Text(
                      'Personal Profile',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F291E),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter your full name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'Fiqh Madhhab Switcher',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F291E),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Select your preferred Islamic school of jurisprudence. The cycle calculation engine will strictly apply its specific rules for menses, purity, and Istihadah limits.',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<MadhhabType>(
                      value: _selectedMadhhab,
                      decoration: const InputDecoration(
                        labelText: 'Selected Madhhab',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.gavel_outlined),
                      ),
                      items: MadhhabType.values.map((MadhhabType type) {
                        return DropdownMenuItem<MadhhabType>(
                          value: type,
                          child: Text(
                            type.name.toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        );
                      }).toList(),
                      onChanged: (MadhhabType? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _selectedMadhhab = newValue;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _saveProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F291E),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : const Text(
                                'Save Settings',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
