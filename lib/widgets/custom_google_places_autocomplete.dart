import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class CustomGooglePlacesAutoComplete extends StatefulWidget {
  final TextEditingController controller;
  final String apiKey;
  final String hintText;
  final IconData icon;
  final void Function(String)? onSelected;

  const CustomGooglePlacesAutoComplete({
    super.key,
    required this.controller,
    required this.apiKey,
    required this.hintText,
    required this.icon,
    this.onSelected,
  });

  @override
  State<CustomGooglePlacesAutoComplete> createState() => _CustomGooglePlacesAutoCompleteState();
}

class _CustomGooglePlacesAutoCompleteState extends State<CustomGooglePlacesAutoComplete> {
  List<String> _suggestions = [];
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  void _fetchSuggestions(String input) async {
    if (input.length < 3) {
      _removeOverlay();
      return;
    }

    final url =
        'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$input&language=fr&components=country:fr&key=${widget.apiKey}';

    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final predictions = data['predictions'] as List;

      setState(() {
        _suggestions = predictions.map((e) => e['description'] as String).toList();
      });

      _showOverlay();
    }
  }

  void _showOverlay() {
    _removeOverlay();
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 56),
          child: Material(
            elevation: 4,
            color: Colors.black87,
            borderRadius: BorderRadius.circular(8),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _suggestions.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white12),
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(_suggestions[index], style: const TextStyle(color: Colors.white)),
                  onTap: () {
                    widget.controller.text = _suggestions[index];
                    widget.onSelected?.call(_suggestions[index]);
                    _removeOverlay();
                  },
                );
              },
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: widget.controller,
        style: const TextStyle(color: Colors.white),
        cursorColor: Colors.amber,
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: const TextStyle(color: Colors.white70),
          prefixIcon: Icon(widget.icon, color: Colors.amber),
          filled: true,
          fillColor: Colors.grey[900],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey.shade800),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.amber),
          ),
        ),
        onChanged: _fetchSuggestions,
      ),
    );
  }
}
