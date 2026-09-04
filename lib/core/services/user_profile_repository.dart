import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:niswah/core/errors/app_error_reporter.dart';
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
    } on PostgrestException catch (e, stack) {
      AppErrorReporter.report(
        e,
        stack,
        context: 'UserProfileRepository.fetchUserProfile',
      );
      return null;
    } catch (e, stack) {
      AppErrorReporter.report(
        e,
        stack,
        context: 'UserProfileRepository.fetchUserProfile',
      );
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
    } on PostgrestException catch (e, stack) {
      AppErrorReporter.report(
        e,
        stack,
        context: 'UserProfileRepository.insertUserProfile',
      );
      return null;
    } catch (e, stack) {
      AppErrorReporter.report(
        e,
        stack,
        context: 'UserProfileRepository.insertUserProfile',
      );
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
    } on PostgrestException catch (e, stack) {
      AppErrorReporter.report(
        e,
        stack,
        context: 'UserProfileRepository.updateUserProfile',
      );
      return null;
    } catch (e, stack) {
      AppErrorReporter.report(
        e,
        stack,
        context: 'UserProfileRepository.updateUserProfile',
      );
      return null;
    }
  }
}
