import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_places_autocomplete_text_field/google_places_autocomplete_text_field.dart';
import '../themes/app_theme.dart';
import 'package:flutter/foundation.dart'; // pour kIsWeb


class SignupDriverScreen extends StatefulWidget {
  const SignupDriverScreen({super.key});

  @override
  State<SignupDriverScreen> createState() => _SignupDriverScreenState();
}

class _SignupDriverScreenState extends State<SignupDriverScreen> {
  final _formKey = GlobalKey<FormState>();
  final picker = ImagePicker();

  final firstName = TextEditingController();
  final lastName = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController(text: '+33 ');
  final password = TextEditingController();
  final confirmPassword = TextEditingController();
  final birthdate = TextEditingController();
  final addressController = TextEditingController();

  final carBrand = TextEditingController();
  final licensePlate = TextEditingController();
  final driverLicenseNumber = TextEditingController();

  File? driverLicense;
  File? registration;
  File? insurance;
File? profileImage;
Uint8List? profileImageBytes;

File? vehiclePhoto;
Uint8List? vehiclePhotoBytes;



  bool obscure1 = true;
  bool obscure2 = true;

  String? selectedVehicleType;
  String? selectedVehicleYear;

  final vehicleTypes = [
    'Voitures électriques',
    'Berlines',
    'Vans Standing',
    'Classe S',
    'Classe E',
    'Motos',
  ];

  late final List<String> anneesVoiture;
late final List<String> anneesMoto;

final List<String> marquesVoitures = [
  'Audi', 'BMW', 'Mercedes-Benz', 'Tesla', 'Lexus',
  'Peugeot', 'Renault', 'Citroën', 'Volkswagen', 'Toyota'
];

final List<String> marquesMotos = [
  'Honda Goldwing 1800',
  'BMW R1250 RT',
  'Yamaha TMAX 560',
  'Suzuki Burgman 650',
  'Harley-Davidson Touring'
];

List<String> get marquesSelonType {
  if (selectedVehicleType?.toLowerCase().contains('moto') == true) {
    return marquesMotos;
  }
  return marquesVoitures;
}

List<String> get anneesSelonType {
  if (selectedVehicleType?.toLowerCase().contains('moto') == true) {
    return anneesMoto;
  }
  return anneesVoiture;
}


@override
void initState() {
  super.initState();
  final currentYear = DateTime.now().year;
  anneesVoiture = List.generate(DateTime.now().year - 1999, (i) => (DateTime.now().year - i).toString());
anneesMoto = List.generate(DateTime.now().year - 2004, (i) => (DateTime.now().year - i).toString());


  // Ajout : on initialise à null pour éviter l’affichage "Ajouté" par défaut
  driverLicense = null;
  registration = null;
  insurance = null;
}


  InputDecoration _inputDecoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        filled: true,
        fillColor: const Color(0xFF121212),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.deepGold, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.deepGold, width: 1.5),
        ),
      );

  Widget _buildTextField(TextEditingController controller, String label, {TextInputType type = TextInputType.text}) {
    return TextFormField(
      controller: controller,
      keyboardType: type,
      style: const TextStyle(color: Colors.white),
      cursorColor: AppColors.deepGold,
      decoration: _inputDecoration(label),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          switch (label) {
            case "Prénom":
              return "Veuillez saisir votre prénom pour poursuivre l’inscription.";
            case "Nom":
              return "Merci d’indiquer votre nom afin de compléter votre profil.";
            case "Email":
              return "Une adresse email est nécessaire pour créer votre compte.";
            case "Adresse":
              return "L’adresse est indispensable pour une prise en charge personnalisée.";
            default:
              return "Ce champ est requis pour continuer.";
          }
        }
        return null;
      }
    );
  }


  Widget _buildPassword(TextEditingController controller, String label, bool obscure, VoidCallback toggle) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      cursorColor: AppColors.deepGold,
      decoration: _inputDecoration(label).copyWith(
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, color: Colors.grey[500]),
          onPressed: toggle,
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return "Veuillez définir un mot de passe confidentiel.";
        }
        if (label.contains('Confirmer') && value != password.text) {
          return "La confirmation ne correspond pas au mot de passe saisi.";
        }
        if (!_isPasswordStrong(value)) {
          return "Votre mot de passe doit contenir au minimum 8 caractères, dont une majuscule, un chiffre et un symbole.";
        }
        return null;
      },
    );
  }

  bool _isPasswordStrong(String password) {
    final pattern = RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[!@#\$&*~.,;:\-_]).{8,}$');
    return pattern.hasMatch(password);
  }



Future<void> _pickBirthDate() async {
  final now = DateTime.now();
  final maxDate = DateTime(now.year - 21, now.month, now.day); // 21 ans révolus

  final picked = await showDatePicker(
    context: context,
    initialDate: DateTime(now.year - 25), // Suggestion : par défaut 25 ans
    firstDate: DateTime(1900),
    lastDate: maxDate,
    locale: const Locale('fr', 'FR'),
  );

  if (picked != null) {
    setState(() => birthdate.text = DateFormat('dd/MM/yyyy').format(picked));
  }
}


Widget _uploadTileAligned(String label, File? file, VoidCallback onPressed) {
  final isAdded = file != null;

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'PlayfairDisplay',
              fontSize: 18,
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(
            isAdded ? Icons.check_box : Icons.upload_file,
            color: isAdded ? Colors.lightGreen : Colors.grey,
          ),
          label: Text(
            isAdded ? "Ajouté" : "Uploader",
            style: const TextStyle(color: AppColors.deepGold),
          ),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.deepGold),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
      ],
    ),
  );
}




Widget _uploadPhotoRowAligned(String label, Uint8List? imageBytes, VoidCallback onPressed) {
  final hasImage = imageBytes != null;

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'PlayfairDisplay',
              fontSize: 18,
            ),
          ),
        ),
        Row(
          children: [
            if (hasImage)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.memory(imageBytes!, width: 48, height: 48, fit: BoxFit.cover),
              ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(
                hasImage ? Icons.check_circle : Icons.camera_alt,
                color: hasImage ? Colors.lightGreen : Colors.grey,
              ),
              label: Text(
                hasImage ? "Modifier" : "Ajouter photo",
                style: const TextStyle(color: AppColors.deepGold),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.deepGold),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}





  Future<void> _submit() async {
  if (!_formKey.currentState!.validate()) return;

  try {
    final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email.text.trim(),
      password: password.text.trim(),
    );

    await cred.user?.sendEmailVerification();

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
          // Loader circulaire sombre
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const Center(
              child: CircularProgressIndicator(
                color: AppColors.deepGold,
              ),
            ),
          );

          await FirebaseAuth.instance.currentUser?.reload();
          final refreshedUser = FirebaseAuth.instance.currentUser;

          Navigator.of(context).pop(); // ferme loader

          if (refreshedUser != null && refreshedUser.emailVerified) {
            Navigator.of(context).pop(); // ferme dialog principal
            if (context.mounted) context.go('/login');
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
              content: const Text(
                "Votre adresse email n’a pas encore été confirmée. Veuillez cliquer sur le lien reçu.",
                style: TextStyle(fontFamily: 'PlayfairDisplay'),
              ),
              backgroundColor: Colors.redAccent,
            ),
            );
          }
        },
        child: const Text(
          "J'ai vérifié",
          style: TextStyle(
            color: AppColors.deepGold,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      TextButton(
        onPressed: () async {
          try {
            await FirebaseAuth.instance.currentUser?.sendEmailVerification();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  "Un nouveau lien de vérification vous a été envoyé avec succès.",
                  style: TextStyle(fontFamily: 'PlayfairDisplay'),
                ),
                backgroundColor: AppColors.deepGold,
              ),

            );
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Un nouveau lien de vérification vous a été envoyé avec succès.",
                style: TextStyle(fontFamily: 'PlayfairDisplay'),
              ),
              backgroundColor: AppColors.deepGold,
              behavior: SnackBarBehavior.floating,
              margin: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
            ),
          );
          }
        },
        child: const Text(
          "Renvoyer le lien",
          style: TextStyle(
            color: AppColors.deepGold,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  ),
);


      final uid = cred.user!.uid;
      String? photoUrl;
      if (profileImageBytes != null) {
  final ref = FirebaseStorage.instance.ref().child("profile_images/$uid.jpg");
  if (kIsWeb) {
    await ref.putData(profileImageBytes!);
  } else {
    await ref.putFile(profileImage!);
  }
  photoUrl = await ref.getDownloadURL();
}


      String? vehicleUrl;

if (vehiclePhotoBytes != null) {
  final ref = FirebaseStorage.instance.ref().child("vehicle_images/$uid.jpg");
  if (kIsWeb) {
    await ref.putData(vehiclePhotoBytes!);
  } else {
    await ref.putFile(vehiclePhoto!);
  }
  vehicleUrl = await ref.getDownloadURL();
}


      Future<String?> uploadDoc(File? doc, String name) async {
        if (doc == null) return null;
        final ext = doc.path.split('.').last.toLowerCase();
        final ref = FirebaseStorage.instance.ref().child('documents/$uid/$name.$ext');
        await ref.putFile(doc);
        return await ref.getDownloadURL();
      }

      final driverLicenseUrl = await uploadDoc(driverLicense, 'driver_license');
      final registrationUrl = await uploadDoc(registration, 'registration');
      final insuranceUrl = await uploadDoc(insurance, 'insurance');

      await FirebaseFirestore.instance.collection('drivers').doc(uid).set({
        'firstName': firstName.text.trim(),
        'lastName': lastName.text.trim(),
        'email': email.text.trim(),
        'vehiclePhotoUrl': vehicleUrl,
        'phone': phone.text.trim(),
        'birthdate': birthdate.text.trim(),
        'address': addressController.text.trim(),
        'vehicleType': selectedVehicleType,
        'carBrand': carBrand.text.trim(),
        'licensePlate': licensePlate.text.trim(),
        'vehicleYear': selectedVehicleYear,
        'driverLicenseNumber': driverLicenseNumber.text.trim(),
        'photoUrl': photoUrl,
        'documents': {
          'driverLicense': driverLicenseUrl,
          'registration': registrationUrl,
          'insurance': insuranceUrl,
        },
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (context.mounted) context.go('/login');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur : $e")),
      );
    }
  }


Future<void> _pickImage(Function(File, Uint8List) onPicked) async {
  final picker = ImagePicker();
  final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
  if (picked != null) {
    final file = File(picked.path);
    final bytes = await picked.readAsBytes(); // important pour Web
    onPicked(file, bytes);
  }
}

@override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: const Color(0xFF0A0A0A),
    body: SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
  backgroundColor: const Color(0xFF0A0A0A),
  pinned: true,
  expandedHeight: 160,
  collapsedHeight: 60,
  flexibleSpace: Container(
    color: const Color(0xFF0A0A0A),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final shrink = constraints.maxHeight < 100;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24), // <-- AJOUTÉ ICI
          child: Align(
            alignment: shrink ? Alignment.bottomLeft : Alignment.center,
            child: shrink
                ? const Padding(
                    padding: EdgeInsets.only(bottom: 12), // <-- marge en bas
                    child: Text(
                      "Conducteur",
                      style: TextStyle(
                        color: AppColors.deepGold,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'PlayfairDisplay',
                      ),
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset('assets/images/logo_transparent.png', height: 60),
                      const SizedBox(height: 12),
                      const Text(
                        "Créer un compte conducteur",
                        style: TextStyle(
                          color: AppColors.deepGold,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'PlayfairDisplay',
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    ),
  ),
),


          // === Formulaire scrollable ===
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTextField(firstName, "Prénom"),
                    const SizedBox(height: 16),
                    _buildTextField(lastName, "Nom"),
                    const SizedBox(height: 16),
                    _buildTextField(email, "Email", type: TextInputType.emailAddress),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [_FixedPrefixPhoneFormatter(prefix: '+33 ')],
                      style: const TextStyle(color: Colors.white),
                      cursorColor: AppColors.deepGold,
                      decoration: _inputDecoration("Téléphone").copyWith(
                        hintText: "+33 612345678",
                        hintStyle: const TextStyle(color: Colors.white38, fontStyle: FontStyle.italic),
                      ),
                      onChanged: (value) {
                        final clean = value.replaceAll(' ', '');
                        if (clean.startsWith('+330')) {
                          final corrected = '+33 ' + clean.substring(4);
                          phone.text = corrected;
                          phone.selection = TextSelection.collapsed(offset: corrected.length);
                        }
                      },
                      validator: (value) {
                        final digits = value?.replaceAll(RegExp(r'[^0-9]'), '');
                        if (digits == null || digits.length != 11 || !digits.startsWith('33') || digits[2] == '0') {
                          return 'Merci de saisir un numéro de téléphone valide.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: _pickBirthDate,
                      child: AbsorbPointer(
                        child: TextFormField(
                          controller: birthdate,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: AppColors.deepGold,
                          decoration: _inputDecoration("Date de naissance").copyWith(
                            hintText: "Sélectionnez votre date de naissance",
                            hintStyle: const TextStyle(color: Colors.white38, fontStyle: FontStyle.italic),
                          ),
                          validator: (value) => value == null || value.trim().isEmpty
                          ? "Merci d’indiquer votre date de naissance pour valider votre inscription."
                          : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildPassword(password, "Mot de passe", obscure1, () => setState(() => obscure1 = !obscure1)),
                    const SizedBox(height: 16),
                    _buildPassword(confirmPassword, "Confirmer le mot de passe", obscure2, () => setState(() => obscure2 = !obscure2)),
                    const SizedBox(height: 16),

                    // Ajoute ici le reste du formulaire (adresse, dropdowns, etc.)
                    // ...

                    const Divider(height: 40, color: AppColors.deepGold),

                    _uploadTileAligned("Permis de conduire", driverLicense, () async {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
                      );
                      if (result != null && result.files.single.path != null) {
                        setState(() => driverLicense = File(result.files.single.path!));
                      }
                    }),
                    _uploadTileAligned("Carte grise", registration, () async {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
                      );
                      if (result != null && result.files.single.path != null) {
                        setState(() => registration = File(result.files.single.path!));
                      }
                    }),
                    _uploadTileAligned("Assurance", insurance, () async {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
                      );
                      if (result != null && result.files.single.path != null) {
                        setState(() => insurance = File(result.files.single.path!));
                      }
                    }),
                    _uploadPhotoRowAligned("Photo de profil", profileImageBytes, () {
                      _pickImage((f, bytes) {
                        setState(() {
                          profileImage = f;
                          profileImageBytes = bytes;
                        });
                      });
                    }),
                    _uploadPhotoRowAligned("Photo du véhicule", vehiclePhotoBytes, () {
                      _pickImage((f, bytes) {
                        setState(() {
                          vehiclePhoto = f;
                          vehiclePhotoBytes = bytes;
                        });
                      });
                    }),

                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.deepGold,
                        foregroundColor: AppColors.black,
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
                        textStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'PlayfairDisplay',
                        ),
                      ),
                      child: const Text("S'inscrire"),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

}

class _FixedPrefixPhoneFormatter extends TextInputFormatter {
  final String prefix;

  _FixedPrefixPhoneFormatter({required this.prefix});

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (!newValue.text.startsWith(prefix) || newValue.selection.start < prefix.length) {
      return oldValue;
    }
    final digitsOnly = newValue.text.replaceFirst(prefix, '').replaceAll(RegExp(r'[^0-9]'), '');
    final newText = prefix + digitsOnly;
    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}
