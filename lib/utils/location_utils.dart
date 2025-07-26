import 'package:google_maps_webservice/geocoding.dart';

final _geocoding = GoogleMapsGeocoding(apiKey: 'AIzaSyA_-00rdj9W8AMt-ybpDpvJbnPhMHt2MVI'); // ← remplace avec ta vraie clé

class LatLng {
  final double lat;
  final double lng;

  LatLng(this.lat, this.lng);
}

Future<LatLng?> getCoordinatesFromAddress(String address) async {
  try {
    final response = await _geocoding.searchByAddress(address);

    if (response.status == 'OK' && response.results.isNotEmpty) {
      final location = response.results.first.geometry.location;
      return LatLng(location.lat, location.lng);
    } else {
      print('⛔ Erreur API Google : ${response.errorMessage}');
      return null;
    }
  } catch (e) {
    print('❌ Exception lors du géocodage : $e');
    return null;
  }
}
