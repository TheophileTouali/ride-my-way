import 'package:cloud_functions/cloud_functions.dart';

class AdminStatsService {
  static final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  static Future<Map<String, dynamic>> getDashboardStats({
    int days = 180,
    String? driverId,
  }) async {
    try {
      final callable = _functions.httpsCallable(
        'adminGetDashboardStats',
        options: HttpsCallableOptions(
          timeout: const Duration(seconds: 60),
        ),
      );

      final res = await callable.call({
        'days': days,
        if (driverId != null) 'driverId': driverId,
      });

      return Map<String, dynamic>.from(res.data as Map);
    } on FirebaseFunctionsException catch (e) {
      // 🔥 Erreur propre Firebase (permission, index manquant, etc.)
      final msg = [
        '[${e.code}] ${e.message ?? 'Erreur Cloud Function'}',
        if (e.details != null) 'details: ${e.details}',
      ].join('\n');

      throw Exception(msg);
    } catch (e) {
      // ❌ Autre erreur (réseau, cast, etc.)
      throw Exception('Erreur stats admin: $e');
    }
  }
}
