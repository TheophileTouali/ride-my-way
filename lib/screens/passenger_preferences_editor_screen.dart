import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/passenger_preferences.dart';
import '../providers/user_provider.dart';
import '../themes/app_theme.dart';
import 'package:go_router/go_router.dart';

class PassengerPreferencesEditorScreen extends StatefulWidget {
  const PassengerPreferencesEditorScreen({super.key});

  @override
  State<PassengerPreferencesEditorScreen> createState() => _PassengerPreferencesEditorScreenState();
}

class _PassengerPreferencesEditorScreenState extends State<PassengerPreferencesEditorScreen> {
  late PassengerPreferences prefs;

  @override
  void initState() {
    super.initState();
    final original = Provider.of<UserProvider>(context, listen: false).preferences;
    prefs = original.copyWith(); // Pour éviter de modifier directement le modèle
  }

  void savePreferences() {
  final userProvider = Provider.of<UserProvider>(context, listen: false);

  userProvider.updatePreferences(prefs);

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Row(
        children: [
          Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              "Préférences mises à jour avec succès.",
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
      backgroundColor: Colors.grey[900],
      behavior: SnackBarBehavior.floating,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 3),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.gold),
        title: const Text(
          "Modifier mes préférences",
          style: TextStyle(
            color: AppColors.gold,
            fontFamily: 'PlayfairDisplay',
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _buildDropdownAmbiance(),
            const SizedBox(height: 16),
            _buildSwitch("Playlist exclusive", prefs.music, (val) => setState(() => prefs.music = val)),
            _buildSwitch("Parfum d’ambiance", prefs.perfume, (val) => setState(() => prefs.perfume = val)),
            _buildSwitch("Température réglée", prefs.temperature, (val) => setState(() => prefs.temperature = val)),
            _buildSwitch("Wi-Fi premium", prefs.wifi, (val) => setState(() => prefs.wifi = val)),
            _buildSwitch("Trajet non-fumeur", prefs.smokeFree, (val) => setState(() => prefs.smokeFree = val)),
            _buildSwitch("Animaux élégants acceptés", prefs.pets, (val) => setState(() => prefs.pets = val)),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: savePreferences,
              icon: const Icon(Icons.check),
              label: const Text("Enregistrer"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.black,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownAmbiance() {
    const ambianceOptions = [
      "Calme & relax",
      "Discussion conviviale",
      "Ambiance musicale",
      "Silence total",
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Ambiance",
          style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.gold.withOpacity(0.3)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: prefs.ambiance,
              dropdownColor: Colors.grey[900],
              iconEnabledColor: AppColors.gold,
              style: const TextStyle(color: Colors.white),
              items: ambianceOptions.map((option) {
                return DropdownMenuItem<String>(
                  value: option,
                  child: Text(option, style: const TextStyle(color: Colors.white)),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => prefs.ambiance = val);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSwitch(String title, bool value, ValueChanged<bool> onChanged) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(title, style: const TextStyle(color: Colors.white))),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.gold,
            inactiveTrackColor: Colors.white30,
          ),
        ],
      ),
    );
  }
}
