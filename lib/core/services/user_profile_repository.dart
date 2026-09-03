import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:niswah/core/models/user_profile.dart';

class UserProfileRepository {
  final SupabaseClient _supabaseClient;

  UserProfileRepository(this._supabaseClient);

  Future<UserProfile?> fetchUserProfile(String userId) async {
    try {
      final response = await _supabaseClient
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();
      return UserProfile.fromJson(response);
    } on PostgrestException catch (e) {
      print('Error fetching user profile: ${e.message}');
      return null;
    } catch (e) {
      print('An unexpected error occurred: $e');
      return null;
    }
  }

  Future<UserProfile?> insertUserProfile(UserProfile profile) async {
    try {
      final response = await _supabaseClient
          .from('profiles')
          .insert(profile.toJson())
          .select()
          .single();
      return UserProfile.fromJson(response);
    } on PostgrestException catch (e) {
      print('Error inserting user profile: ${e.message}');
      return null;
    } catch (e) {
      print('An unexpected error occurred: $e');
      return null;
    }
  }

  Future<UserProfile?> updateUserProfile(UserProfile profile) async {
    try {
      final response = await _supabaseClient
          .from('profiles')
          .update(profile.toJson())
          .eq('id', profile.id)
          .select()
          .single();
      return UserProfile.fromJson(response);
    } on PostgrestException catch (e) {
      print('Error updating user profile: ${e.message}');
      return null;
    } catch (e) {
      print('An unexpected error occurred: $e');
      return null;
    }
  }
}
