import 'dart:io' show File;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:google_places_autocomplete_text_field/google_places_autocomplete_text_field.dart';
import '../themes/app_theme.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();

  final firstNameController = TextEditingController();
  final lastNameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  final phoneController = TextEditingController(text: "+33 ");
  final birthdateController = TextEditingController();
  XFile? _selectedImage;
  final ImagePicker _picker = ImagePicker();

  final addressController = TextEditingController();
  final cityController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    birthdateController.text = DateFormat('dd/MM/yyyy').format(DateTime.now());
  }

  @override
  void dispose() {
    firstNameController.dispose();
    lastNameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    phoneController.dispose();
    birthdateController.dispose();
    addressController.dispose();
    cityController.dispose();
    super.dispose();
  }

Future<void> _submit() async {
  if (_formKey.currentState!.validate()) {
    try {
      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      final uid = credential.user!.uid;

      // ✅ Envoie de l'e-mail de vérification
      await credential.user?.sendEmailVerification();

      // ✅ Message visuel
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Un e-mail de vérification vous a été envoyé."),
            backgroundColor: AppColors.gold,
          ),
        );
      }

      // ✅ Upload photo s'il y en a une
      String? profileImageUrl;
      if (_selectedImage != null) {
        final ref = FirebaseStorage.instance.ref().child("profile_images/$uid.jpg");
        await ref.putFile(File(_selectedImage!.path));
        profileImageUrl = await ref.getDownloadURL();
      }

      // ✅ Enregistrement dans Firestore
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'firstName': firstNameController.text.trim(),
        'lastName': lastNameController.text.trim(),
        'email': emailController.text.trim(),
        'phone': phoneController.text.trim(),
        'birthdate': birthdateController.text.trim(),
        'address': addressController.text.trim(),
        'city': cityController.text.trim(),
        'photoUrl': profileImageUrl,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // ✅ Redirection après inscription
      if (context.mounted) {
        context.go('/login');
      }
    } on FirebaseAuthException catch (e) {
      final message = switch (e.code) {
        'email-already-in-use' => "Cet e-mail est déjà utilisé.",
        'invalid-email' => "Adresse e-mail invalide.",
        'weak-password' => "Mot de passe trop faible.",
        _ => e.message ?? "Erreur inconnue."
      };

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Erreur inattendue.")),
      );
    }
  }
}


  bool _isPasswordStrong(String password) {
  final pattern = RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[!@#\$&*~.,;:\-_]).{8,}$');
    return pattern.hasMatch(password.trim());
  }

  bool _isValidEmail(String email) {
    final regex = RegExp(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$");
    return regex.hasMatch(email.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),
                Image.asset('assets/images/logo_transparent.png', height: 100),
                const SizedBox(height: 24),
                const Text("Créer un compte", style: TextStyle(color: AppColors.gold, fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 32),

                _buildField(firstNameController, "Prénom"),
                const SizedBox(height: 16),
                _buildField(lastNameController, "Nom"),
                const SizedBox(height: 16),
                _buildField(emailController, "Email", keyboardType: TextInputType.emailAddress, validator: (v) {
                  if (v == null || v.isEmpty) return "Champ requis";
                  if (!_isValidEmail(v)) return "Email invalide";
                  return null;
                }),
                const SizedBox(height: 16),
                _buildPasswordField(passwordController, "Mot de passe", obscure: _obscurePassword, toggle: () => setState(() => _obscurePassword = !_obscurePassword), validator: (v) {
                  if (v == null || v.isEmpty) return "Champ requis";
                  if (!_isPasswordStrong(v)) return "8+ caractères, majuscule, chiffre, caractère spécial";
                  return null;
                }),
                const SizedBox(height: 16),
                _buildPasswordField(confirmPasswordController, "Confirmer le mot de passe", obscure: _obscureConfirm, toggle: () => setState(() => _obscureConfirm = !_obscureConfirm), validator: (v) {
                  if (v != passwordController.text) return "Les mots de passe ne correspondent pas";
                  return null;
                }),

                const SizedBox(height: 24),
               TextFormField(
  controller: phoneController,
  keyboardType: TextInputType.number,
  inputFormatters: [
    _FixedPrefixPhoneFormatter(prefix: '+33 '),
  ],
  style: const TextStyle(color: Colors.white),
  cursorColor: AppColors.gold,
  decoration: _inputDecoration("Téléphone"),
  validator: (value) {
    final digits = value?.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits == null || digits.length != 11 || !digits.startsWith('33')) {
      return 'Numéro invalide (ex: +33 612345678)';
    }
    return null;
  },
),



                const SizedBox(height: 16),
                GestureDetector(
                  onTap: _selectBirthDate,
                  child: AbsorbPointer(child: _buildField(birthdateController, "Date de naissance")),
                ),
                const SizedBox(height: 16),
                _buildPhotoPicker(),

                const SizedBox(height: 24),
                GooglePlacesAutoCompleteTextFormField(
                  textEditingController: addressController,
                  googleAPIKey: "AIzaSyA_-00rdj9W8AMt-ybpDpvJbnPhMHt2MVI",
                  debounceTime: 800,
                  countries: ["fr"],
                  fetchCoordinates: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration("Adresse"),
                  onSuggestionClicked: (prediction) => addressController.text = prediction.description!,
                  onPlaceDetailsWithCoordinatesReceived: (_) {},
                  validator: (v) => v == null || v.isEmpty ? "Champ requis" : null,
                ),

                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.black,
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
                    textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'PlayfairDisplay'),
                  ),
                  child: const Text("S’inscrire"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Colors.grey),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.gold)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.gold, width: 1.5)),
  );

  Widget _buildField(TextEditingController controller, String label, {
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) => TextFormField(
    controller: controller,
    keyboardType: keyboardType,
    style: const TextStyle(color: Colors.white),
    cursorColor: AppColors.gold,
    decoration: _inputDecoration(label),
    validator: validator ?? (v) => (v == null || v.isEmpty) ? "Champ requis" : null,
  );

  Widget _buildPasswordField(
    TextEditingController controller,
    String label, {
    required bool obscure,
    required VoidCallback toggle,
    required String? Function(String?) validator,
  }) => TextFormField(
    controller: controller,
    obscureText: obscure,
    style: const TextStyle(color: Colors.white),
    cursorColor: AppColors.gold,
    decoration: _inputDecoration(label).copyWith(
      suffixIcon: IconButton(
        icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, color: Colors.grey[500]),
        onPressed: toggle,
      ),
    ),
    validator: validator,
  );

  Widget _buildPhotoPicker() => GestureDetector(
    onTap: _showImagePickerOptions,
    child: Row(
      children: [
        const Icon(Icons.add_a_photo_outlined, color: AppColors.gold),
        const SizedBox(width: 8),
        const Text("Ajouter une photo", style: TextStyle(color: AppColors.gold)),
        if (_selectedImage != null) ...[
          const Spacer(),
          ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: kIsWeb
                ? Image.network(_selectedImage!.path, width: 48, height: 48, fit: BoxFit.cover)
                : Image.file(File(_selectedImage!.path), width: 48, height: 48, fit: BoxFit.cover),
          )
        ]
      ],
    ),
  );

  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.black,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
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
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(source: source, imageQuality: 75);
    if (pickedFile != null) setState(() => _selectedImage = pickedFile);
    if (context.mounted) Navigator.pop(context);
  }

Future<void> _selectBirthDate() async {
  final now = DateTime.now();
  final picked = await showDatePicker(
    context: context,
    initialDate: now,
    firstDate: DateTime(1900),
    lastDate: now,
    locale: const Locale('fr', 'FR'),
    builder: (context, child) => Theme(
      data: Theme.of(context).copyWith(
        dialogBackgroundColor: AppColors.black,
        colorScheme: const ColorScheme.dark(primary: AppColors.gold),
        textTheme: const TextTheme(
          titleMedium: TextStyle(
            color: AppColors.gold, // Titre "Saisir une date"
            fontFamily: 'PlayfairDisplay',
          ),
          bodyMedium: TextStyle(
            color: AppColors.gold, // <- Texte saisi ici
            fontFamily: 'PlayfairDisplay',
          ),
          labelLarge: TextStyle(
            color: Colors.white, // "Sélectionner une date"
            fontFamily: 'PlayfairDisplay',
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          hintStyle: TextStyle(color: Colors.white54, fontFamily: 'PlayfairDisplay'),
          labelStyle: TextStyle(color: Colors.white, fontFamily: 'PlayfairDisplay'),
          floatingLabelStyle: TextStyle(color: AppColors.gold, fontFamily: 'PlayfairDisplay'),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.gold),
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.gold, width: 1.5),
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      ),
      child: child!,
    ),
  );
  if (picked != null) {
    setState(() {
      birthdateController.text = DateFormat('dd/MM/yyyy').format(picked);
    });
  }
}

}

class _FrenchPhoneFormatter extends TextInputFormatter {
  static const String prefix = '+33 ';
  
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Si l’utilisateur tente d’effacer ou modifier le préfixe, on le restaure
    if (!newValue.text.startsWith(prefix)) {
      return oldValue;
    }

    // Supprime tout sauf chiffres après le préfixe
    final raw = newValue.text.substring(prefix.length);
    final onlyDigits = raw.replaceAll(RegExp(r'[^0-9]'), '');

    // Reconstruit le texte avec le préfixe et les chiffres filtrés
    final finalText = prefix + onlyDigits;

    return TextEditingValue(
      text: finalText,
      selection: TextSelection.collapsed(offset: finalText.length),
    );
  }
}

class _FixedPrefixPhoneFormatter extends TextInputFormatter {
  final String prefix;

  _FixedPrefixPhoneFormatter({required this.prefix});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Si suppression ou déplacement du curseur dans le préfixe : retour à old
    if (!newValue.text.startsWith(prefix) ||
        newValue.selection.start < prefix.length) {
      return oldValue;
    }

    // Récupère uniquement les chiffres tapés après le préfixe
    final digitsOnly = newValue.text
        .replaceFirst(prefix, '')
        .replaceAll(RegExp(r'[^0-9]'), '');

    // Reconstruit le texte complet
    final newText = prefix + digitsOnly;

    // Met le curseur à la fin
    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}




