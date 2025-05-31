import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../themes/app_theme.dart';
import '../providers/user_provider.dart';
import '../models/passenger_preferences.dart'; // ⚠️ à adapter selon ton arborescence

class EditPreferencesScreen extends StatefulWidget {
  const EditPreferencesScreen({super.key});

  @override
  State<EditPreferencesScreen> createState() => _EditPreferencesScreenState();
}

class _EditPreferencesScreenState extends State<EditPreferencesScreen> {
  bool exclusiveMusic = false;
  bool scentPreference = false;
  bool temperatureControl = false;
  bool wifiPremium = false;
  bool smokeFree = false;
  bool allowsElegantPets = false;

  String ambiance = "Calme & relax";

  @override
  void initState() {
    super.initState();
    final prefs = Provider.of<UserProvider>(context, listen: false).preferences;
    ambiance = prefs.ambiance;
    exclusiveMusic = prefs.music;
    scentPreference = prefs.perfume;
    temperatureControl = prefs.temperature;
    wifiPremium = prefs.wifi;
    smokeFree = prefs.smokeFree;
    allowsElegantPets = prefs.pets;
  }

  void _savePreferences() {
    final updatedPrefs = PassengerPreferences(
      ambiance: ambiance,
      music: exclusiveMusic,
      perfume: scentPreference,
      temperature: temperatureControl,
      wifi: wifiPremium,
      smokeFree: smokeFree,
      pets: allowsElegantPets,
    );

    Provider.of<UserProvider>(context, listen: false).updatePreferences(updatedPrefs);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Préférences enregistrées ✅"),
        backgroundColor: AppColors.gold,
        behavior: SnackBarBehavior.floating,
      ),
    );

    Future.delayed(const Duration(seconds: 2), () {
      context.go('/profile');
    });
  }

  Widget _buildSwitch(String label, bool value, Function(bool) onChanged) {
    return SwitchListTile(
      title: Text(label, style: const TextStyle(color: Colors.white)),
      activeColor: AppColors.gold,
      inactiveTrackColor: Colors.grey.shade800,
      inactiveThumbColor: Colors.grey.shade600,
      value: value,
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        foregroundColor: AppColors.gold,
        title: const Text("Mes préférences"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.go('/profile'),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Ambiance souhaitée",
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(color: AppColors.gold, width: 1.3),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: ambiance,
                    dropdownColor: const Color(0xFF1A1A1A),
                    iconEnabledColor: AppColors.gold,
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 16,
                      fontFamily: 'PlayfairDisplay',
                    ),
                    borderRadius: BorderRadius.circular(16),
                    elevation: 2,
                    onChanged: (value) => setState(() => ambiance = value!),
                    items: const [
                      DropdownMenuItem(value: "Calme & relax", child: Text("Calme & relax")),
                      DropdownMenuItem(value: "Échange raffiné", child: Text("Échange raffiné")),
                      DropdownMenuItem(value: "Sans préférence", child: Text("Sans préférence")),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _buildSwitch("Playlist exclusive à bord", exclusiveMusic, (val) => setState(() => exclusiveMusic = val)),
              _buildSwitch("Parfum d'ambiance discret", scentPreference, (val) => setState(() => scentPreference = val)),
              _buildSwitch("Température réglée selon mes préférences", temperatureControl, (val) => setState(() => temperatureControl = val)),
              _buildSwitch("Accès Wi-Fi premium", wifiPremium, (val) => setState(() => wifiPremium = val)),
              _buildSwitch("Trajet 100% non-fumeur", smokeFree, (val) => setState(() => smokeFree = val)),
              _buildSwitch("J'accepte la présence d'animaux élégants", allowsElegantPets, (val) => setState(() => allowsElegantPets = val)),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _savePreferences,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: AppColors.black,
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(40),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'PlayfairDisplay',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                child: const Text("Enregistrer"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
