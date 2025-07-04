import 'dart:io' show File;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:google_places_autocomplete_text_field/google_places_autocomplete_text_field.dart';
import '../themes/app_theme.dart';
import 'package:image_picker/image_picker.dart';
import '../models/user_model.dart';


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
  final addressController = TextEditingController();
  final cityController = TextEditingController();
  bool _isSubmitting = false;


  final ImagePicker _picker = ImagePicker();
  XFile? _selectedImage;

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  File? profileImage;
  Uint8List? profileImageBytes;
  XFile? _identityCardImage;



  @override
  void initState() {
    super.initState();
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
  if (!_formKey.currentState!.validate()) return;

  if (_identityCardImage == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Merci de joindre une pièce d'identité pour finaliser votre inscription."),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
      ),
    );
    return;
  }

  if (_isSubmitting) return;
  setState(() => _isSubmitting = true);

  try {
    print("🟡 Création de compte Firebase Auth...");
    final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: emailController.text.trim(),
      password: passwordController.text.trim(),
    );

    final uid = cred.user!.uid;
    print("✅ Compte créé. UID : $uid");

    // Envoi de l'e-mail de vérification
    await cred.user?.sendEmailVerification();
    print("📧 Email de vérification envoyé");

      // Upload photo de profil
    String? photoUrl;
    if (_selectedImage != null) {
      print("📤 Upload photo de profil...");

      final ext = _selectedImage!.name.split('.').last; // 📦 récupère l’extension
      final profileRef = FirebaseStorage.instance.ref().child("users_data/$uid/profile.$ext");

      try {
        if (kIsWeb) {
          final bytes = await _selectedImage!.readAsBytes();
          await profileRef.putData(bytes, SettableMetadata(contentType: 'image/$ext'));
        } else {
          await profileRef.putFile(
            File(_selectedImage!.path),
            SettableMetadata(contentType: 'image/$ext'),
          );
        }

        photoUrl = await profileRef.getDownloadURL();
        print("✅ Photo de profil uploadée : $photoUrl");
      } catch (e) {
        print("❌ Erreur upload photo profil : $e");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur photo de profil : $e"), backgroundColor: Colors.redAccent),
        );
      }
    }




  // Upload pièce d'identité
      String? idCardUrl;
      if (_identityCardImage != null) {
        print("📤 Upload carte d'identité...");

        final ext = _identityCardImage!.name.split('.').last;
        final idCardRef = FirebaseStorage.instance.ref().child("users_data/$uid/id_card.$ext");

        try {
          if (kIsWeb) {
            final bytes = await _identityCardImage!.readAsBytes();
            await idCardRef.putData(bytes, SettableMetadata(contentType: 'image/$ext'));
          } else {
            await idCardRef.putFile(
              File(_identityCardImage!.path),
              SettableMetadata(contentType: 'image/$ext'),
            );
          }

          idCardUrl = await idCardRef.getDownloadURL();
          print("✅ Carte d'identité uploadée : $idCardUrl");
        } catch (e) {
          print("❌ Erreur upload carte identité : $e");
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erreur carte d'identité : $e"), backgroundColor: Colors.redAccent),
          );
        }
      }



    // Création du modèle utilisateur
    final userModel = UserModel(
      uid: uid,
      firstName: firstNameController.text.trim(),
      lastName: lastNameController.text.trim(),
      email: emailController.text.trim(),
      phone: phoneController.text.trim(),
      address: addressController.text.trim(),
      birthdate: Timestamp.fromDate(
        DateFormat('dd/MM/yyyy').parse(birthdateController.text.trim()),
      ),
      photoUrl: photoUrl,
      identityCardUrl: idCardUrl,
      role: 'passenger', // ou 'driver' si écran conducteur
      createdAt: Timestamp.now(),
    );

    // Enregistrement Firestore
    print("📄 Enregistrement Firestore...");
    await FirebaseFirestore.instance.collection('users').doc(uid).set(userModel.toMap());
    print("✅ Document Firestore créé");

    // Dialogue de vérification email
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0A0A0A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titlePadding: const EdgeInsets.only(top: 24, left: 24, right: 24),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        actionsPadding: const EdgeInsets.only(bottom: 16, right: 12),
        title: const Text(
          "Vérification de l'email",
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.deepGold,
            fontFamily: 'PlayfairDisplay',
          ),
        ),
        content: const Text(
          "Un lien a été envoyé à votre adresse email. Cliquez sur ce lien avant de continuer.",
          style: TextStyle(
            fontSize: 16,
            color: Colors.white70,
            fontFamily: 'PlayfairDisplay',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => const Center(
                  child: CircularProgressIndicator(color: AppColors.deepGold),
                ),
              );
              await FirebaseAuth.instance.currentUser?.reload();
              final refreshedUser = FirebaseAuth.instance.currentUser;
              Navigator.of(context).pop();

              if (refreshedUser != null && refreshedUser.emailVerified) {
                Navigator.of(context).pop();
                if (context.mounted) context.go('/login');
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Votre adresse email n’est pas encore vérifiée."),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            },
            child: const Text("J'ai vérifié", style: TextStyle(color: AppColors.deepGold, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () async {
              try {
                await FirebaseAuth.instance.currentUser?.sendEmailVerification();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Lien de vérification renvoyé."),
                    backgroundColor: AppColors.deepGold,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Erreur lors de l'envoi : $e"),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            },
            child: const Text("Renvoyer le lien", style: TextStyle(color: AppColors.deepGold, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  } catch (e) {
    print("❌ Erreur pendant l'inscription : $e");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Erreur : $e"), backgroundColor: Colors.redAccent),
    );
  } finally {
    if (mounted) setState(() => _isSubmitting = false);
  }
}



  Future<void> _showVerificationDialog() async {
    bool emailVerified = false;
    final user = FirebaseAuth.instance.currentUser;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: AppColors.black,
          title: const Text("Vérifiez votre e-mail", style: TextStyle(color: AppColors.gold)),
          content: const Text("Cliquez sur le lien dans l'e-mail reçu pour vérifier votre compte.",
              style: TextStyle(color: Colors.white)),
          actions: [
            TextButton(
              onPressed: () async {
                await user?.reload();
                if (user?.emailVerified ?? false) {
                  emailVerified = true;
                  if (context.mounted) context.go('/login');
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text("L'e-mail n'a pas encore été vérifié."),
                    backgroundColor: Colors.redAccent,
                  ));
                }
              },
              child: const Text("J’ai vérifié", style: TextStyle(color: AppColors.gold)),
            ),
            TextButton(
              onPressed: () async {
                await user?.sendEmailVerification();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text("Lien de vérification renvoyé."),
                  backgroundColor: AppColors.gold,
                ));
              },
              child: const Text("Renvoyer le lien", style: TextStyle(color: AppColors.gold)),
            ),
          ],
        ),
      ),
    );
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
    resizeToAvoidBottomInset: true,
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return CustomScrollView(
            slivers: [
              SliverAppBar(
              pinned: true,
              backgroundColor: AppColors.black,
              automaticallyImplyLeading: false,
              expandedHeight: 140,
              collapsedHeight: 80,
              flexibleSpace: LayoutBuilder(
                builder: (context, constraints) {
                  final isCollapsed = constraints.maxHeight <= 80;
                  return FlexibleSpaceBar(
                    centerTitle: false, // désactive le centrage
                    titlePadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16), // marge à gauche
                    title: isCollapsed
                        ? const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              "Votre trajet de prestige commence ici",
                              style: TextStyle(
                                color: AppColors.gold,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'PlayfairDisplay',
                              ),
                            ),
                          )
                        : null,
                    background: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const SizedBox(height: 16),
                        Image.asset('assets/images/logo_transparent.png', height: 60),
                        const SizedBox(height: 16),
                        const Text(
                          "Créer un compte",
                          style: TextStyle(
                            color: AppColors.gold,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'PlayfairDisplay',
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

              SliverFillRemaining(
              hasScrollBody: true,
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  top: 24,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 80, 
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                        const SizedBox(height: 16),
                        _buildField(firstNameController, "Prénom", validator: (v) {
                          if (v == null || v.trim().isEmpty) return "Merci d’indiquer votre prénom.";
                          return null;
                        }),

                        const SizedBox(height: 16),
                        _buildField(lastNameController, "Nom", validator: (v) {
                            if (v == null || v.trim().isEmpty) return "Merci d’indiquer votre nom.";
                            return null;
                          }),

                        const SizedBox(height: 16),
                        _buildField(emailController, "Email",
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return "L’email est requis.";
                          if (!_isValidEmail(v)) return "Email invalide.";
                          return null;
                        }),

                        const SizedBox(height: 16),
                        _buildPasswordField(
                        passwordController,
                        "Mot de passe",
                        obscure: _obscurePassword,
                        toggle: () => setState(() => _obscurePassword = !_obscurePassword),
                        validator: (v) {
                          if (v == null || v.isEmpty) return "Le mot de passe est requis.";
                          if (!_isPasswordStrong(v)) return "8+ caractères, majuscule, chiffre, spécial.";
                          return null;
                        },
                      ),

                        const SizedBox(height: 16),
                       _buildPasswordField(
                        confirmPasswordController,
                        "Confirmer le mot de passe",
                        obscure: _obscureConfirm,
                        toggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
                        validator: (v) {
                          if (v != passwordController.text) return "Les mots de passe ne correspondent pas.";
                          return null;
                        },
                      ),

                        const SizedBox(height: 24),
                        TextFormField(
                          controller: phoneController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [_FixedPrefixPhoneFormatter(prefix: '+33 ')],
                          style: const TextStyle(color: Colors.white),
                          cursorColor: AppColors.gold,
                          decoration: _inputDecoration("Téléphone"),
                          validator: (value) {
                            final digits = value?.replaceAll(RegExp(r'[^0-9]'), '');
                            if (digits == null || digits.length != 11 || !digits.startsWith('33')) {
                              return 'Numéro invalide (ex : +33 612345678)';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        GooglePlacesAutoCompleteTextFormField(
                          textEditingController: addressController,
                          googleAPIKey: "AIzaSyA_-00rdj9W8AMt-ybpDpvJbnPhMHt2MVI",
                          debounceTime: 800,
                          countries: ["fr"],
                          fetchCoordinates: true,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration("Adresse"),
                          onSuggestionClicked: (prediction) {
                            addressController.text = prediction.description!;
                            FocusScope.of(context).unfocus(); // Pour fermer le clavier
                          },
                          onChanged: (value) => addressController.text = value,
                          onPlaceDetailsWithCoordinatesReceived: (_) {},
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? "Merci d’indiquer une adresse."
                              : null,
                          overlayContainerBuilder: (child) => Material(
                            elevation: 2.0,
                            color: Colors.grey[900],
                            borderRadius: BorderRadius.circular(12),
                            child: child,
                          ),
                        ),

                        const SizedBox(height: 16),
                        GestureDetector(
                        onTap: _selectBirthDate,
                        child: AbsorbPointer(
                          child: TextFormField(
                            controller: birthdateController,
                            style: const TextStyle(color: Colors.white),
                            cursorColor: AppColors.gold,
                            decoration: _inputDecoration("Date de naissance"),
                            validator: (v) => (v == null || v.trim().isEmpty) ? "Merci de sélectionner votre date de naissance." : null,
                          ),
                        ),
                      ),
                        const SizedBox(height: 16),
                                              Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          _buildPhotoPicker(),
                          const SizedBox(height: 20), // espace bien visible
                          _buildIdentityCardPicker(),
                          const SizedBox(height: 24), // un peu plus avant l'adresse
                        ],
                      ),
                          const SizedBox(height: 24),

                        
                        const SizedBox(height: 32),
                        ElevatedButton(
                          onPressed: _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.gold,
                            foregroundColor: AppColors.black,
                            minimumSize: const Size.fromHeight(56),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
                            textStyle: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'PlayfairDisplay',
                            ),
                          ),
                          child: const Text("S’inscrire"),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
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

  Widget _buildField(TextEditingController controller, String label,
      {TextInputType keyboardType = TextInputType.text, String? Function(String?)? validator}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      cursorColor: AppColors.gold,
      decoration: _inputDecoration(label),
      validator: validator ?? (v) => (v == null || v.isEmpty) ? "Champ requis" : null,
    );
  }

    Widget _buildPasswordField(
      TextEditingController controller,
      String label, {
      required bool obscure,
      required VoidCallback toggle,
      required String? Function(String?) validator,
    }) {
      return TextFormField(
        controller: controller,
        obscureText: obscure,
        style: const TextStyle(color: Colors.white),
        cursorColor: AppColors.gold,
        decoration: _inputDecoration(label).copyWith(
          suffixIcon: IconButton(
            icon: Icon(
              obscure ? Icons.visibility_off : Icons.visibility,
              color: Colors.grey[500],
            ),
            onPressed: toggle,
          ),
        ),
        validator: validator,
      );
    }


    Widget _buildPhotoPicker() => GestureDetector(
      onTap: () => _showImagePickerOptions(target: 'profile'),
      child: Row(
        children: [
          const Icon(Icons.add_a_photo_outlined, color: AppColors.gold),
          const SizedBox(width: 8),
          const Text("Ajouter une photo", style: TextStyle(color: AppColors.gold)),
          if (_selectedImage != null) ...[
            const Spacer(),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: kIsWeb
                  ? Image.network(_selectedImage!.path, width: 48, height: 48, fit: BoxFit.cover)
                  : Image.file(File(_selectedImage!.path), width: 48, height: 48, fit: BoxFit.cover),
            ),
          ]
        ],
      ),
    );


  Widget _buildIdentityCardPicker() => GestureDetector(
      onTap: () => _showImagePickerOptions(target: 'id'),
      child: Row(
        children: [
          const Icon(Icons.credit_card, color: AppColors.gold),
          const SizedBox(width: 8),
          const Text("Ajouter carte d'identité", style: TextStyle(color: AppColors.gold)),
          if (_identityCardImage != null) ...[
            const Spacer(),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: kIsWeb
                  ? Image.network(_identityCardImage!.path, width: 48, height: 48, fit: BoxFit.cover)
                  : Image.file(File(_identityCardImage!.path), width: 48, height: 48, fit: BoxFit.cover),
            ),
          ]
        ],
      ),
    );

    void _showImagePickerOptions({required String target}) {
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
              onTap: () => _pickImageWithTarget(target),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.gold),
              title: const Text('Choisir depuis la galerie', style: TextStyle(color: Colors.white)),
              onTap: () => _pickImageWithTarget(target),
            ),
          ],
        ),
      ),
    );
  }


    Future<void> _pickImageWithTarget(String target) async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (pickedFile != null) {
      setState(() {
        if (target == 'profile') {
          _selectedImage = pickedFile;
        } else if (target == 'id') {
          _identityCardImage = pickedFile;
        }
      });
    }
    if (context.mounted) Navigator.pop(context);
  }


  Future<void> _selectBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.subtract(const Duration(days: 365 * 18)), // par défaut 18 ans
      firstDate: DateTime(1900),
      lastDate: now,
      locale: const Locale('fr', 'FR'),
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
          content: Text("L’âge minimum requis est de 18 ans pour rejoindre Ride My Way."),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
        ),
      );
        return;
      }
      setState(() {
        birthdateController.text = DateFormat('dd/MM/yyyy').format(picked);
      });
    }
  }

}

class _FixedPrefixPhoneFormatter extends TextInputFormatter {
  final String prefix;
  _FixedPrefixPhoneFormatter({required this.prefix});

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    String raw = newValue.text;

    // Supprime le préfixe temporairement pour traiter le reste
    if (raw.startsWith(prefix)) {
      raw = raw.substring(prefix.length);
    }

    // Supprime tous les caractères non numériques
    raw = raw.replaceAll(RegExp(r'[^0-9]'), '');

    // Si le premier chiffre est un 0, on l’enlève (cas courant en France)
    if (raw.startsWith('0')) {
      raw = raw.substring(1);
    }

    // Limite à 9 chiffres max (06XXXXXXXX)
    if (raw.length > 9) {
      raw = raw.substring(0, 9);
    }

    // Construit le texte final avec l’indicatif fixe
    final newText = '$prefix$raw';

    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}


