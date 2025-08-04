import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;

class DriverMapWidget extends StatefulWidget {
  final LatLng initialPosition;
  final Set<Marker> markers;
  final bool trafficOn;

  const DriverMapWidget({
    super.key,
    required this.initialPosition,
    this.markers = const {},
    this.trafficOn = true,
  });

  @override
  State<DriverMapWidget> createState() => _DriverMapWidgetState();
}

class _DriverMapWidgetState extends State<DriverMapWidget> {
  late GoogleMapController _controller;
  String _mapStyle = '';

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
  }

  Future<void> _loadMapStyle() async {
    _mapStyle = await rootBundle.loadString('assets/map_style_dark.json');
    _controller.setMapStyle(_mapStyle);
  }

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: widget.initialPosition,
        zoom: 14,
      ),
      markers: widget.markers,
      trafficEnabled: widget.trafficOn,
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      buildingsEnabled: true,
      indoorViewEnabled: false,
      onMapCreated: (GoogleMapController controller) {
        _controller = controller;
        _controller.setMapStyle(_mapStyle);
      },
    );
  }
}
