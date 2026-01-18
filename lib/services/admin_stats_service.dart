import 'package:cloud_functions/cloud_functions.dart';

class AdminStatsService {
  static Future<Map<String, dynamic>> getDashboardStats({
    int days = 180,
    String? driverId,
  }) async {
    final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
        .httpsCallable('adminGetDashboardStats');

    final res = await callable.call({
      "days": days,
      if (driverId != null) "driverId": driverId,
    });

    return Map<String, dynamic>.from(res.data as Map);
  }
}
