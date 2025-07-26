import 'dart:io' show File;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import '../themes/app_theme.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final firstNameController = TextEditingController();
  final lastNameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final birthdateController = TextEditingController();
  final addressController = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  XFile? _selectedImage;
  XFile? _identityCardImage;

  String? existingPhotoUrl;
  String? existingIdCardUrl;

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data();
    if (data != null) {
      firstNameController.text = data['firstName'] ?? '';
      lastNameController.text = data['lastName'] ?? '';
      emailController.text = data['email'] ?? '';
      phoneController.text = data['phone'] ?? '';
      addressController.text = data['address'] ?? '';
      existingPhotoUrl = data['photoUrl'];
      existingIdCardUrl = data['identityCardUrl'];
      if (data['birthdate'] != null) {
        birthdateController.text = DateFormat('dd/MM/yyyy')
            .format((data['birthdate'] as Timestamp).toDate());
      }
      setState(() {});
    }
  }

    Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);
    print('▶ Début de _submit()');

    try {
        final uid = FirebaseAuth.instance.currentUser!.uid;
        print('✅ UID: $uid');

        String? photoUrl = existingPhotoUrl;
        if (_selectedImage != null) {
        print('📷 Upload nouvelle photo...');
        final ref = FirebaseStorage.instanceFor(
            bucket: 'ride-my-way-7f258.appspot.com',
        ).ref().child("users_data/$uid/profile_${DateTime.now().millisecondsSinceEpoch}.png");

        if (kIsWeb) {
            final bytes = await _selectedImage!.readAsBytes();
            await ref.putData(bytes);
        } else {
            await ref.putFile(File(_selectedImage!.path));
        }

        photoUrl = await ref.getDownloadURL();
        print('✅ Nouvelle photo uploadée');
        }

        String? idCardUrl = existingIdCardUrl;
        if (_identityCardImage != null) {
        print('🪪 Upload nouvelle carte ID...');
        final ref = FirebaseStorage.instanceFor(
            bucket: 'ride-my-way-7f258.appspot.com',
        ).ref().child("users_data/$uid/id_card_${DateTime.now().millisecondsSinceEpoch}.png");

        if (kIsWeb) {
            final bytes = await _identityCardImage!.readAsBytes();
            await ref.putData(bytes);
        } else {
            await ref.putFile(File(_identityCardImage!.path));
        }

        idCardUrl = await ref.getDownloadURL();
        print('✅ Nouvelle carte ID uploadée');
        }

        print('📤 Mise à jour Firestore...');
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'firstName': firstNameController.text.trim(),
        'lastName': lastNameController.text.trim(),
        'phone': phoneController.text.trim(),
        'address': addressController.text.trim(),
        'birthdate': Timestamp.fromDate(
            DateFormat('dd/MM/yyyy').parse(birthdateController.text.trim()),
        ),
        'photoUrl': photoUrl,
        'identityCardUrl': idCardUrl,
        'updatedAt': Timestamp.now(),
        });

        print('✅ Firestore mis à jour');
        if (mounted) {
        context.go('/profile?refresh=true');
        }

        ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Profil mis à jour."),
            backgroundColor: AppColors.deepGold,
        ),
        );
    } catch (e) {
        print('❌ Erreur : $e');
        ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur : $e"), backgroundColor: Colors.redAccent),
        );
    } finally {
        if (mounted) setState(() => _isSubmitting = false);
    }
    }


  Future<void> _selectBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.subtract(const Duration(days: 365 * 18)),
      firstDate: DateTime(1900),
      lastDate: now,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          dialogBackgroundColor: AppColors.black,
          colorScheme: const ColorScheme.dark(primary: AppColors.gold),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      final age = now.difference(picked).inDays ~/ 365;
      if (age < 18) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Vous devez avoir au moins 18 ans."),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
      birthdateController.text = DateFormat('dd/MM/yyyy').format(picked);
    }
  }


    @override
    Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: AppColors.black,
        appBar: AppBar(
        title: const Text("Modifier mon profil", style: TextStyle(color: AppColors.gold)),
        backgroundColor: AppColors.black,
        iconTheme: const IconThemeData(color: AppColors.gold),
        ),
        body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
            key: _formKey,
            child: Column(
            children: [
                // PHOTO DE PROFIL
                FutureBuilder<Widget>(
                future: _buildProfileImage(),
                builder: (context, snapshot) {
                    return Column(
                    children: [
                        if (snapshot.hasData) snapshot.data!,
                        TextButton.icon(
                        onPressed: () async {
                            final picked = await _picker.pickImage(source: ImageSource.gallery);
                            if (picked != null) setState(() => _selectedImage = picked);
                        },
                        icon: const Icon(Icons.photo_camera_outlined, color: AppColors.gold),
                        label: const Text("Changer la photo de profil", style: TextStyle(color: AppColors.gold)),
                        ),
                        const SizedBox(height: 16),
                    ],
                    );
                },
                ),

                // CARTE D'IDENTITÉ
                FutureBuilder<Widget>(
                future: _buildIdCardImage(),
                builder: (context, snapshot) {
                    return Column(
                    children: [
                        if (snapshot.hasData) snapshot.data!,
                        TextButton.icon(
                        onPressed: () async {
                            final picked = await _picker.pickImage(source: ImageSource.gallery);
                            if (picked != null) setState(() => _identityCardImage = picked);
                        },
                        icon: const Icon(Icons.credit_card, color: AppColors.gold),
                        label: const Text("Changer la carte d’identité", style: TextStyle(color: AppColors.gold)),
                        ),
                        const SizedBox(height: 16),
                    ],
                    );
                },
                ),

                _buildTextField(firstNameController, "Prénom"),
                _buildTextField(lastNameController, "Nom"),
                _buildTextField(emailController, "Email", enabled: false),
                _buildTextField(phoneController, "Téléphone"),
                _buildTextField(addressController, "Adresse"),
                GestureDetector(
                onTap: _selectBirthDate,
                child: AbsorbPointer(
                    child: _buildTextField(birthdateController, "Date de naissance"),
                ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.black,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: AppColors.black)
                    : const Text("Enregistrer les modifications"),
                )
            ],
            ),
        ),
        ),
    );
    }

    Future<Widget> _buildProfileImage() async {
  if (_selectedImage != null) {
    if (kIsWeb) {
      final bytes = await _selectedImage!.readAsBytes();
      return ClipOval(child: Image.memory(bytes, width: 100, height: 100, fit: BoxFit.cover));
    } else {
      return ClipOval(child: Image.file(File(_selectedImage!.path), width: 100, height: 100, fit: BoxFit.cover));
    }
  } else if (existingPhotoUrl != null) {
    return ClipOval(child: Image.network(existingPhotoUrl!, width: 100, height: 100, fit: BoxFit.cover));
  } else {
    return const SizedBox.shrink();
  }
}

    Future<Widget> _buildIdCardImage() async {
    if (_identityCardImage != null) {
        if (kIsWeb) {
        final bytes = await _identityCardImage!.readAsBytes();
        return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.memory(bytes, height: 120),
        );
        } else {
        return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(File(_identityCardImage!.path), height: 120),
        );
        }
    } else if (existingIdCardUrl != null) {
        return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.network(existingIdCardUrl!, height: 120),
        );
    } else {
        return const SizedBox.shrink();
    }
    }



  Widget _buildTextField(TextEditingController controller, String label, {bool enabled = true}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.grey),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.gold)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.gold, width: 1.5)),
        ),
        validator: (v) => v == null || v.trim().isEmpty ? "Champ requis" : null,
      ),
    );
  }
}
