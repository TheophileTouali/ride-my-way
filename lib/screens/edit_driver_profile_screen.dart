// lib/screens/edit_driver_profile_screen.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../providers/driver_provider.dart';
import '../models/driver_user.dart';
import '../themes/app_theme.dart';

class EditDriverProfileScreen extends StatefulWidget {
  const EditDriverProfileScreen({super.key});

  @override
  State<EditDriverProfileScreen> createState() =>
      _EditDriverProfileScreenState();
}

class _EditDriverProfileScreenState extends State<EditDriverProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  late final TextEditingController _firstNameC;
  late final TextEditingController _lastNameC;
  late final TextEditingController _emailC; // lecture seule
  late final TextEditingController _phoneC;
  late final TextEditingController _addressC;
  late final TextEditingController _birthdateC;

  // Véhicule
  late final TextEditingController _vehicleBrandC;
  late final TextEditingController _vehicleModelC;
  late final TextEditingController _vehicleYearC;
  late final TextEditingController _licensePlateC;
  late final TextEditingController _driverLicenseNumberC;

  @override
  void initState() {
    super.initState();
    final user = Provider.of<DriverProvider>(context, listen: false).user;

    _firstNameC = TextEditingController(text: user?.firstName ?? '');
    _lastNameC = TextEditingController(text: user?.lastName ?? '');
    _emailC = TextEditingController(text: user?.email ?? '');
    _phoneC = TextEditingController(text: user?.phone ?? '');
    _addressC = TextEditingController(text: user?.address ?? '');
    _birthdateC = TextEditingController(text: user?.birthdate ?? '');

    _vehicleBrandC = TextEditingController(text: user?.vehicleBrand ?? '');
    _vehicleModelC = TextEditingController(text: user?.vehicleModel ?? '');
    _vehicleYearC = TextEditingController(text: user?.vehicleYear ?? '');
    _licensePlateC = TextEditingController(text: user?.licensePlate ?? '');
    _driverLicenseNumberC =
        TextEditingController(text: user?.driverLicenseNumber ?? '');
  }

  @override
  void dispose() {
    _firstNameC.dispose();
    _lastNameC.dispose();
    _emailC.dispose();
    _phoneC.dispose();
    _addressC.dispose();
    _birthdateC.dispose();
    _vehicleBrandC.dispose();
    _vehicleModelC.dispose();
    _vehicleYearC.dispose();
    _licensePlateC.dispose();
    _driverLicenseNumberC.dispose();
    super.dispose();
  }

  Future<void> _pickBirthdate() async {
    final now = DateTime.now();
    final initial =
        _parseDate(_birthdateC.text) ?? DateTime(now.year - 25, 1, 1);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900, 1, 1),
      lastDate: DateTime(now.year - 16, 12, 31),
      helpText: 'Sélectionner la date de naissance',
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.gold,
              surface: AppColors.black,
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: Colors.black87,
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      _birthdateC.text = _formatDate(picked); // yyyy-MM-dd
      setState(() {});
    }
  }

  DateTime? _parseDate(String s) {
    try {
      if (s.trim().isEmpty) return null;
      return DateTime.parse(s.trim());
    } catch (_) {
      return null;
    }
  }

  String _formatDate(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
    // Si tu préfères DD/MM/YYYY, adapte-le ici et dans la lecture côté app.
  }

  InputDecoration _dec(String label, {Widget? suffix, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: Colors.white70),
      hintStyle: const TextStyle(color: Colors.white38),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.white12),
        borderRadius: BorderRadius.circular(14),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: AppColors.gold),
        borderRadius: BorderRadius.circular(14),
      ),
      filled: true,
      fillColor: Colors.black.withOpacity(0.4),
      suffixIcon: suffix,
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.gold,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          fontFamily: 'PlayfairDisplay',
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Session expirée. Merci de vous reconnecter.')),
      );
      context.go('/login-driver');
      return;
    }

    setState(() => _saving = true);

    try {
      final Map<String, dynamic> payload = {
        'firstName': _firstNameC.text.trim(),
        'lastName': _lastNameC.text.trim(),
        'phone': _phoneC.text.trim(),
        'address': _addressC.text.trim(),
        'birthdate': _birthdateC.text
            .trim(), // stocké en String (aligné avec ton modèle)
        'vehicleBrand': _vehicleBrandC.text.trim(),
        'vehicleModel': _vehicleModelC.text.trim(),
        'vehicleYear': _vehicleYearC.text.trim(),
        'licensePlate': _licensePlateC.text.trim().toUpperCase(),
        'driverLicenseNumber': _driverLicenseNumberC.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // On nettoie les champs vides pour éviter d’écraser par "" si tu préfères.
      payload.removeWhere((key, value) => value is String && value.isEmpty);

      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(uid)
          .set(payload, SetOptions(merge: true));

      // Rafraîchir le modèle local via ton provider existant
      await Provider.of<DriverProvider>(context, listen: false)
          .initializeUser();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Profil mis à jour')),
        );
        context.pop(); // revient à l’écran précédent
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de l’enregistrement : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DriverUser? user = Provider.of<DriverProvider>(context).user;

    if (user == null) {
      Future.microtask(() => context.go('/login-driver'));
      return const Scaffold(
        backgroundColor: AppColors.black,
        body: Center(child: CircularProgressIndicator(color: AppColors.gold)),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.gold),
          onPressed: () => context.pop(),
        ),
        centerTitle: true,
        title: const Text(
          'Modifier mon profil',
          style: TextStyle(
            fontFamily: 'PlayfairDisplay',
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.gold,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.gold),
                  )
                : const Text('Enregistrer',
                    style: TextStyle(color: AppColors.gold)),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _sectionTitle('Identité'),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _firstNameC,
                        decoration: _dec('Prénom'),
                        style: const TextStyle(color: Colors.white),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Prénom requis'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _lastNameC,
                        decoration: _dec('Nom'),
                        style: const TextStyle(color: Colors.white),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Nom requis'
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailC,
                  readOnly: true,
                  decoration: _dec('Email').copyWith(
                    helperText: 'Modifiable depuis l’espace sécurité',
                    helperStyle:
                        const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  style: const TextStyle(color: Colors.white70),
                ),
                _sectionTitle('Contact & Adresse'),
                TextFormField(
                  controller: _phoneC,
                  decoration: _dec('Téléphone', hint: 'Ex: +33 6 12 34 56 78'),
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Téléphone requis'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressC,
                  decoration: _dec('Adresse'),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _birthdateC,
                  readOnly: true,
                  decoration: _dec(
                    'Date de naissance',
                    suffix: IconButton(
                      tooltip: 'Choisir une date',
                      icon: const Icon(Icons.date_range, color: AppColors.gold),
                      onPressed: _pickBirthdate,
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
                _sectionTitle('Véhicule'),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _vehicleBrandC,
                        decoration: _dec('Marque (ex: BMW)'),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _vehicleModelC,
                        decoration: _dec('Modèle (ex: R1250)'),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _vehicleYearC,
                        decoration: _dec('Année (ex: 2023)'),
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _licensePlateC,
                        decoration: _dec('Immatriculation'),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _driverLicenseNumberC,
                  decoration: _dec('N° de permis'),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: AppColors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.black),
                          )
                        : const Text('Enregistrer les modifications',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('Annuler',
                      style: TextStyle(color: Colors.white70)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
