import 'package:flutter/material.dart';
import 'package:google_places_autocomplete_text_field/google_places_autocomplete_text_field.dart';

class CustomGooglePlacesAutoComplete extends StatelessWidget {
  final TextEditingController controller;
  final String apiKey;
  final String hintText;
  final IconData icon;
  final void Function(Prediction) onSelected;

  const CustomGooglePlacesAutoComplete({
    super.key,
    required this.controller,
    required this.apiKey,
    required this.hintText,
    required this.icon,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return GooglePlacesAutoCompleteTextFormField(
      textEditingController: controller,
      googleAPIKey: apiKey,
      debounceTime: 800,
      countries: const ['fr'],
      fetchCoordinates: true,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: Colors.white70, fontFamily: 'PlayfairDisplay'),
        filled: true,
        fillColor: Colors.grey[900],
        prefixIcon: Icon(icon, color: const Color(0xFFFFD700)),
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade700),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFFFD700)),
        ),
      ),
      overlayContainerBuilder: (child) => Material(
        elevation: 6,
        color: Colors.grey[900], // FOND SOMBRE
        borderRadius: BorderRadius.circular(12),
        child: child,
      ),
      onSuggestionClicked: (prediction) {
        controller.text = prediction.description!;
        onSelected(prediction);
        FocusScope.of(context).unfocus();
      },
    );
  }
}
