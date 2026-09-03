import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:niswah/core/models/cycle_log.dart';

class CycleLogRepository {
  final SupabaseClient _supabaseClient;

  CycleLogRepository(this._supabaseClient);

  Future<List<CycleLog>> fetchCycleLogs(String userId) async {
    try {
      final response = await _supabaseClient
          .from('cycle_logs')
          .select()
          .eq('user_id', userId)
          .order('start_date', ascending: false);
      return (response as List).map((json) => CycleLog.fromJson(json)).toList();
    } on PostgrestException catch (e) {
      print('Error fetching cycle logs: ${e.message}');
      return [];
    } catch (e) {
      print('An unexpected error occurred: $e');
      return [];
    }
  }

  Future<CycleLog?> insertCycleLog(CycleLog cycleLog) async {
    try {
      final response = await _supabaseClient
          .from('cycle_logs')
          .insert(cycleLog.toJson())
          .select()
          .single();
      return CycleLog.fromJson(response);
    } on PostgrestException catch (e) {
      print('Error inserting cycle log: ${e.message}');
      return null;
    } catch (e) {
      print('An unexpected error occurred: $e');
      return null;
    }
  }

  Future<CycleLog?> updateCycleLog(CycleLog cycleLog) async {
    try {
      final response = await _supabaseClient
          .from('cycle_logs')
          .update(cycleLog.toJson())
          .eq('id', cycleLog.id)
          .select()
          .single();
      return CycleLog.fromJson(response);
    } on PostgrestException catch (e) {
      print('Error updating cycle log: ${e.message}');
      return null;
    } catch (e) {
      print('An unexpected error occurred: $e');
      return null;
    }
  }

  Future<void> deleteCycleLog(String cycleLogId) async {
    try {
      await _supabaseClient.from('cycle_logs').delete().eq('id', cycleLogId);
    } on PostgrestException catch (e) {
      print('Error deleting cycle log: ${e.message}');
    } catch (e) {
      print('An unexpected error occurred: $e');
    }
  }
}
