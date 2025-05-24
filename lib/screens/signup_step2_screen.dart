import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../themes/app_theme.dart';

class SignupStep2Screen extends StatefulWidget {
  const SignupStep2Screen({super.key});

  @override
  State<SignupStep2Screen> createState() => _SignupStep2ScreenState();
}

class _SignupStep2ScreenState extends State<SignupStep2Screen> {
  final _formKey = GlobalKey<FormState>();
  final phoneController = TextEditingController(text: "+33 ");
  final birthdateController = TextEditingController(
    text: DateFormat('dd/MM/yyyy', 'fr_FR').format(DateTime.now()),
  );

  final ImagePicker _picker = ImagePicker();
  XFile? _selectedImage;

  void _continue() {
    if (_formKey.currentState!.validate()) {
      context.go('/signup-step3');
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final XFile? pickedFile = await _picker.pickImage(source: source, imageQuality: 75);
    if (pickedFile != null) {
      setState(() => _selectedImage = pickedFile);
    }
    if (context.mounted) Navigator.pop(context);
  }

  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: AppColors.gold),
                title: const Text('Prendre une photo', style: TextStyle(color: Colors.white)),
                onTap: () => _pickImage(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: AppColors.gold),
                title: const Text('Choisir depuis la galerie', style: TextStyle(color: Colors.white)),
                onTap: () => _pickImage(ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _selectBirthDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      locale: const Locale('fr', 'FR'),
      initialDate: now,
      firstDate: DateTime(1900),
      lastDate: now,
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: Theme.of(context).copyWith(
            dialogBackgroundColor: AppColors.black,
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: AppColors.gold),
            ),
            colorScheme: const ColorScheme.dark(
              primary: AppColors.gold,
              surface: AppColors.black,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final formatted = DateFormat('dd/MM/yyyy', 'fr_FR').format(picked);
      setState(() => birthdateController.text = formatted);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const SizedBox(height: 48),
                Image.asset('assets/images/logo_transparent.png', height: 120, fit: BoxFit.contain),
                const SizedBox(height: 24),
                const Text(
                  "Création de compte",
                  style: TextStyle(color: AppColors.gold, fontSize: 28, fontFamily: 'PlayfairDisplay', fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text("2/3", style: TextStyle(color: AppColors.gold, fontSize: 16)),
                const SizedBox(height: 24),

                // 📸 Image picker preview
                GestureDetector(
                  onTap: _showImagePickerOptions,
                  child: Row(
                    children: [
                      const Icon(Icons.add_a_photo_outlined, color: AppColors.gold),
                      const SizedBox(width: 8),
                      const Text("Ajouter une photo", style: TextStyle(color: AppColors.gold, fontSize: 16)),
                      if (_selectedImage != null) ...[
                        const Spacer(),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(30),
                          child: kIsWeb
                              ? Image.network(_selectedImage!.path, width: 48, height: 48, fit: BoxFit.cover)
                              : Image.file(File(_selectedImage!.path), width: 48, height: 48, fit: BoxFit.cover),
                        ),
                      ]
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                _buildPhoneField(phoneController),
                const SizedBox(height: 16),

                GestureDetector(
                  onTap: _selectBirthDate,
                  child: AbsorbPointer(child: _buildBirthDateField(birthdateController)),
                ),

                const SizedBox(height: 32),

                ElevatedButton(
                  onPressed: _continue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.black,
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
                    textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'PlayfairDisplay'),
                  ),
                  child: const Text("Suivant"),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneField(TextEditingController controller) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.phone,
      style: const TextStyle(color: Colors.white),
      cursorColor: AppColors.gold,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s]'))],
      decoration: InputDecoration(
        labelText: "Téléphone",
        hintText: "+33 6 12 34 56 78",
        hintStyle: const TextStyle(color: Colors.grey),
        labelStyle: const TextStyle(color: AppColors.gold),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        filled: true,
        fillColor: Colors.black.withOpacity(0.05),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.gold),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.gold, width: 1.5),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return "Veuillez entrer votre numéro de téléphone";
        if (!value.startsWith("+33")) return "Le numéro doit commencer par +33";
        if (value.length < 12) return "Numéro trop court";
        return null;
      },
    );
  }

  Widget _buildBirthDateField(TextEditingController controller) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      cursorColor: AppColors.gold,
      readOnly: true,
      decoration: InputDecoration(
        labelText: "Date de naissance",
        hintText: "JJ/MM/AAAA",
        hintStyle: const TextStyle(color: Colors.grey),
        labelStyle: const TextStyle(color: AppColors.gold),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        suffixIcon: const Icon(Icons.calendar_month_outlined, color: AppColors.gold),
        filled: true,
        fillColor: Colors.black.withOpacity(0.05),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.gold),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.gold, width: 1.5),
        ),
      ),
      validator: (value) => (value == null || value.isEmpty) ? "Veuillez choisir votre date de naissance" : null,
    );
  }
}
