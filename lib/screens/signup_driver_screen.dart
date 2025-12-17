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

  File? driverLicenseFile, registrationFile, insuranceFile;
  Uint8List? driverLicenseBytes, registrationBytes, insuranceBytes;
  bool driverLicenseSelected = false,
      registrationSelected = false,
      insuranceSelected = false;

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
    'Véhicules premiums',
    'Motos',
  ];

  late final List<String> anneesVoiture;
  late final List<String> anneesMoto;

  final List<String> marquesVoitures = [
    'Audi',
    'BMW',
    'Mercedes-Benz',
    'Tesla',
    'Lexus',
    'Peugeot',
    'Renault',
    'Citroën',
    'Volkswagen',
    'Toyota'
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
    anneesVoiture = List.generate(
      DateTime.now().year - 1999,
      (i) => (DateTime.now().year - i).toString(),
    );
    anneesMoto = List.generate(
      DateTime.now().year - 2004,
      (i) => (DateTime.now().year - i).toString(),
    );

    driverLicenseFile = null;
    driverLicenseBytes = null;

    registrationFile = null;
    registrationBytes = null;

    insuranceFile = null;
    insuranceBytes = null;
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

  Widget _buildTextField(TextEditingController controller, String label,
      {TextInputType type = TextInputType.text}) {
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
            // ✅ Adresse n’est plus requise (Apple 5.1.1) -> donc pas de message bloquant
            default:
              return "Ce champ est requis pour continuer.";
          }
        }
        return null;
      },
    );
  }

  Widget _buildPassword(TextEditingController controller, String label,
      bool obscure, VoidCallback toggle) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      cursorColor: AppColors.deepGold,
      decoration: _inputDecoration(label).copyWith(
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_off : Icons.visibility,
              color: Colors.grey[500]),
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
    final pattern =
        RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[!@#\$&*~.,;:\-_]).{8,}$');
    return pattern.hasMatch(password);
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final maxDate =
        DateTime(now.year - 21, now.month, now.day); // 21 ans révolus

    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 25),
      firstDate: DateTime(1900),
      lastDate: maxDate,
      locale: const Locale('fr', 'FR'),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(
              primary: AppColors.deepGold,
              surface: const Color(0xFF121212),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF0A0A0A),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => birthdate.text = DateFormat('dd/MM/yyyy').format(picked));
    }
  }

  Widget _uploadTileAligned(String label, File? file, VoidCallback onPressed,
      {bool showCheck = false}) {
    final isAdded = file != null || showCheck;

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
              isAdded ? Icons.check_circle : Icons.upload_file,
              color: isAdded ? Colors.lightGreen : Colors.grey,
            ),
            label: Text(
              isAdded ? "Ajouté" : "Uploader",
              style: const TextStyle(color: AppColors.deepGold),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.deepGold),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _uploadPhotoRowAligned(
      String label, Uint8List? imageBytes, VoidCallback onPressed) {
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
                  child: Image.memory(imageBytes!,
                      width: 48, height: 48, fit: BoxFit.cover),
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
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
      print("🔐 Création du compte Firebase Auth...");
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email.text.trim(),
        password: password.text.trim(),
      );
      final uid = cred.user!.uid;
      print("✅ Compte créé : $uid");

      print("📧 Envoi de l'email de vérification...");
      await cred.user?.sendEmailVerification();

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF0A0A0A),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text(
            "Vérification de l'email",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.deepGold,
            ),
          ),
          content: const Text(
            "Un lien a été envoyé à votre adresse email. Cliquez sur ce lien avant de continuer.",
            style: TextStyle(fontSize: 16, color: Colors.white70),
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
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          "Email non vérifié. Veuillez cliquer sur le lien."),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              },
              child: const Text(
                "J'ai vérifié",
                style: TextStyle(
                    color: AppColors.deepGold, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: () async {
                try {
                  final user = FirebaseAuth.instance.currentUser;
                  if (user != null && !user.emailVerified) {
                    await user.sendEmailVerification();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Nouveau lien envoyé."),
                        backgroundColor: AppColors.deepGold,
                      ),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text("Erreur : $e")));
                }
              },
              child: const Text(
                "Renvoyer le lien",
                style: TextStyle(
                    color: AppColors.deepGold, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );

      // ✅ Upload doc optionnel (web + mobile) : retourne null si absent
      Future<String?> uploadDocIfProvided({
        required String name,
        File? file,
        Uint8List? bytes,
      }) async {
        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        if (currentUid == null) throw Exception("Utilisateur non connecté.");

        if (file == null && bytes == null) return null;

        final ref = FirebaseStorage.instance
            .ref()
            .child('drivers_data/$currentUid/$name');

        if (bytes != null) {
          await ref.putData(bytes);
        } else {
          await ref.putFile(file!);
        }

        return ref.getDownloadURL();
      }

      // Upload photo de profil (optionnelle)
      String? photoUrl;
      if (profileImageBytes != null) {
        final ref = FirebaseStorage.instance
            .ref()
            .child("drivers_data/$uid/profile.jpg");
        if (kIsWeb) {
          await ref.putData(profileImageBytes!);
        } else if (profileImage != null) {
          await ref.putFile(profileImage!);
        }
        photoUrl = await ref.getDownloadURL();
      }

      // Upload photo véhicule (optionnelle)
      String? vehicleUrl;
      if (vehiclePhotoBytes != null) {
        final ref = FirebaseStorage.instance
            .ref()
            .child("drivers_data/$uid/vehicle.jpg");
        if (kIsWeb) {
          await ref.putData(vehiclePhotoBytes!);
        } else if (vehiclePhoto != null) {
          await ref.putFile(vehiclePhoto!);
        }
        vehicleUrl = await ref.getDownloadURL();
      }

      // ✅ Upload des documents (optionnels)
      final driverLicenseUrl = await uploadDocIfProvided(
        name: "driver_license.pdf",
        file: driverLicenseFile,
        bytes: driverLicenseBytes,
      );
      final registrationUrl = await uploadDocIfProvided(
        name: "registration.pdf",
        file: registrationFile,
        bytes: registrationBytes,
      );
      final insuranceUrl = await uploadDocIfProvided(
        name: "insurance.pdf",
        file: insuranceFile,
        bytes: insuranceBytes,
      );

      final documents = <String, dynamic>{};
      if (driverLicenseUrl != null)
        documents['driverLicense'] = driverLicenseUrl;
      if (registrationUrl != null) documents['registration'] = registrationUrl;
      if (insuranceUrl != null) documents['insurance'] = insuranceUrl;

      // ✅ Firestore : champs Apple seulement si renseignés + documents seulement si présents
      final driverData = <String, dynamic>{
        'firstName': firstName.text.trim(),
        'lastName': lastName.text.trim(),
        'email': email.text.trim(),
        'vehicleType': selectedVehicleType,
        'carBrand': carBrand.text.trim(),
        'licensePlate': licensePlate.text.trim(),
        'vehicleYear': selectedVehicleYear,
        'driverLicenseNumber': driverLicenseNumber.text.trim(),
        'photoUrl': photoUrl,
        'vehiclePhotoUrl': vehicleUrl,
        if (documents.isNotEmpty) 'documents': documents,
        'role': 'driver',
        'createdAt': FieldValue.serverTimestamp(),
        'isVisible': false,
        // ✅ AJOUT ICI (valeurs par défaut)
        'verificationStatus': documents.isNotEmpty ? 'pending' : 'unverified',
        'canAcceptRides': false,
        // (optionnel) pour audit
        'reviewedAt': null,
        'reviewedBy': null,
        'rejectedReason': null,
      };

      final phoneValue = phone.text.trim();
      if (phoneValue.isNotEmpty &&
          phoneValue != '+33' &&
          phoneValue != '+33 ') {
        driverData['phone'] = phoneValue;
      }

      final birthValue = birthdate.text.trim();
      if (birthValue.isNotEmpty) {
        final dt = DateFormat('dd/MM/yyyy').parse(birthValue);
        driverData['birthdate'] = Timestamp.fromDate(dt); // ✅ Timestamp
      }

      final addressValue = addressController.text.trim();
      if (addressValue.isNotEmpty) {
        driverData['address'] = addressValue;
      }

      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(uid)
          .set(driverData);

      print("✅ Données Firestore enregistrées avec succès !");
      if (context.mounted) context.go('/login');
    } catch (e) {
      print("❌ Erreur générale : $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text("Erreur : $e"), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _pickImage(Function(File, Uint8List) onPicked) async {
    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) {
      final file = File(picked.path);
      final bytes = await picked.readAsBytes();
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
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Align(
                        alignment:
                            shrink ? Alignment.bottomLeft : Alignment.center,
                        child: shrink
                            ? const Padding(
                                padding: EdgeInsets.only(bottom: 12),
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
                                  Image.asset(
                                      'assets/images/logo_transparent.png',
                                      height: 60),
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
                      _buildTextField(email, "Email",
                          type: TextInputType.emailAddress),
                      const SizedBox(height: 16),

                      // ✅ Téléphone optionnel (validé seulement si rempli)
                      TextFormField(
                        controller: phone,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          _FixedPrefixPhoneFormatter(prefix: '+33 ')
                        ],
                        style: const TextStyle(color: Colors.white),
                        cursorColor: AppColors.deepGold,
                        decoration: _inputDecoration("Téléphone").copyWith(
                          hintText: "+33 612345678",
                          hintStyle: const TextStyle(
                              color: Colors.white38,
                              fontStyle: FontStyle.italic),
                        ),
                        onChanged: (value) {
                          final clean = value.replaceAll(' ', '');
                          if (clean.startsWith('+330')) {
                            final corrected = '+33 ' + clean.substring(4);
                            phone.text = corrected;
                            phone.selection = TextSelection.collapsed(
                                offset: corrected.length);
                          }
                        },
                        validator: (value) {
                          final v = (value ?? '').trim();
                          if (v.isEmpty || v == '+33' || v == '+33 ')
                            return null;

                          final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
                          if (digits.isEmpty) return null;

                          if (digits.length != 11 ||
                              !digits.startsWith('33') ||
                              digits[2] == '0') {
                            return 'Merci de saisir un numéro de téléphone valide.';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      // ✅ Birthdate optionnelle
                      GestureDetector(
                        onTap: _pickBirthDate,
                        child: AbsorbPointer(
                          child: TextFormField(
                            controller: birthdate,
                            style: const TextStyle(color: Colors.white),
                            cursorColor: AppColors.deepGold,
                            decoration:
                                _inputDecoration("Date de naissance").copyWith(
                              hintText: "Sélectionnez votre date de naissance",
                              hintStyle: const TextStyle(
                                  color: Colors.white38,
                                  fontStyle: FontStyle.italic),
                            ),
                            validator: (_) => null,
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),
                      _buildPassword(password, "Mot de passe", obscure1,
                          () => setState(() => obscure1 = !obscure1)),
                      const SizedBox(height: 16),
                      _buildPassword(
                          confirmPassword,
                          "Confirmer le mot de passe",
                          obscure2,
                          () => setState(() => obscure2 = !obscure2)),
                      const SizedBox(height: 24),

                      // ✅ Adresse optionnelle
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
                          FocusScope.of(context).unfocus();
                        },
                        onChanged: (value) => addressController.text = value,
                        onPlaceDetailsWithCoordinatesReceived: (_) {},
                        validator: (_) => null,
                        overlayContainerBuilder: (child) => Material(
                          elevation: 2.0,
                          color: Colors.grey[900],
                          borderRadius: BorderRadius.circular(12),
                          child: child,
                        ),
                      ),

                      const SizedBox(height: 16),

                      // 🔻 Le reste inchangé (véhicule + docs UI)
                      DropdownButtonFormField<String>(
                        value: selectedVehicleType,
                        items: vehicleTypes
                            .map((type) => DropdownMenuItem(
                                  value: type,
                                  child: Text(type,
                                      style:
                                          const TextStyle(color: Colors.white)),
                                ))
                            .toList(),
                        onChanged: (val) {
                          setState(() {
                            selectedVehicleType = val;
                            carBrand.text = '';
                            selectedVehicleYear = null;
                          });
                        },
                        decoration: _inputDecoration("Type de véhicule"),
                        dropdownColor: Colors.black,
                        iconEnabledColor: AppColors.deepGold,
                        validator: (v) => (v == null || v.isEmpty)
                            ? "Veuillez choisir le type de véhicule utilisé."
                            : null,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: marquesSelonType.contains(carBrand.text)
                            ? carBrand.text
                            : null,
                        items: marquesSelonType
                            .map((brand) => DropdownMenuItem(
                                  value: brand,
                                  child: Text(brand,
                                      style:
                                          const TextStyle(color: Colors.white)),
                                ))
                            .toList(),
                        onChanged: (value) =>
                            setState(() => carBrand.text = value!),
                        decoration: _inputDecoration("Marque du véhicule"),
                        dropdownColor: Colors.black,
                        iconEnabledColor: AppColors.deepGold,
                        validator: (v) => v == null
                            ? "Merci d’indiquer la marque de votre véhicule."
                            : null,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: selectedVehicleYear,
                        items: anneesSelonType
                            .map((year) => DropdownMenuItem(
                                  value: year,
                                  child: Text(year,
                                      style:
                                          const TextStyle(color: Colors.white)),
                                ))
                            .toList(),
                        onChanged: (val) =>
                            setState(() => selectedVehicleYear = val),
                        decoration: _inputDecoration("Année du véhicule"),
                        dropdownColor: Colors.black,
                        iconEnabledColor: AppColors.deepGold,
                        validator: (v) => v == null
                            ? "Merci de sélectionner l’année de mise en circulation."
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: licensePlate,
                        style: const TextStyle(color: Colors.white),
                        cursorColor: AppColors.deepGold,
                        decoration:
                            _inputDecoration("Immatriculation").copyWith(
                          hintText: "Ex : AB-123-CD",
                          hintStyle: const TextStyle(
                              color: Colors.white38,
                              fontStyle: FontStyle.italic),
                        ),
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[A-Za-z0-9]')),
                          _LicensePlateFormatter(),
                        ],
                        validator: (value) {
                          if (value == null || value.trim().isEmpty)
                            return 'Merci d’indiquer l’immatriculation.';
                          final reg =
                              RegExp(r'^[A-HJ-NP-Z]{2}-\d{3}-[A-HJ-NP-Z]{2}$');
                          if (!reg.hasMatch(value.toUpperCase()))
                            return 'Format invalide (ex : AB-123-CD)';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: driverLicenseNumber,
                        style: const TextStyle(color: Colors.white),
                        cursorColor: AppColors.deepGold,
                        decoration:
                            _inputDecoration("N° Permis de conduire").copyWith(
                          hintText: "Ex : 20AB12345",
                          hintStyle: const TextStyle(
                              color: Colors.white38,
                              fontStyle: FontStyle.italic),
                        ),
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9]'))
                        ],
                        validator: (value) {
                          if (value == null || value.trim().isEmpty)
                            return 'Champ requis';
                          final clean = value.trim().toUpperCase();
                          final reg = RegExp(r'^[0-9]{2}[A-Z]{2}[0-9]{5}$');
                          if (!reg.hasMatch(clean)) {
                            return 'Format attendu : 2 chiffres + 2 lettres + 5 chiffres (ex : 20AB12345)';
                          }
                          return null;
                        },
                      ),
                      const Divider(height: 40, color: AppColors.deepGold),

                      // ✅ UI docs inchangée (non bloquante)
                      _uploadTileAligned(
                          "Permis de conduire", driverLicenseFile, () async {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
                          withData: true,
                        );
                        if (result != null) {
                          if (kIsWeb && result.files.single.bytes != null) {
                            setState(() {
                              driverLicenseBytes = result.files.single.bytes!;
                              driverLicenseFile = null;
                              driverLicenseSelected = true;
                            });
                          } else if (result.files.single.path != null) {
                            setState(() {
                              driverLicenseFile =
                                  File(result.files.single.path!);
                              driverLicenseBytes = null;
                              driverLicenseSelected = true;
                            });
                          }
                        }
                      }, showCheck: driverLicenseSelected),

                      _uploadTileAligned("Assurance", insuranceFile, () async {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
                          withData: true,
                        );
                        if (result != null) {
                          if (kIsWeb && result.files.single.bytes != null) {
                            setState(() {
                              insuranceBytes = result.files.single.bytes!;
                              insuranceFile = null;
                              insuranceSelected = true;
                            });
                          } else if (result.files.single.path != null) {
                            setState(() {
                              insuranceFile = File(result.files.single.path!);
                              insuranceBytes = null;
                              insuranceSelected = true;
                            });
                          }
                        }
                      }, showCheck: insuranceSelected),

                      _uploadTileAligned("Carte grise", registrationFile,
                          () async {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
                          withData: true,
                        );
                        if (result != null) {
                          if (kIsWeb && result.files.single.bytes != null) {
                            setState(() {
                              registrationBytes = result.files.single.bytes!;
                              registrationFile = null;
                              registrationSelected = true;
                            });
                          } else if (result.files.single.path != null) {
                            setState(() {
                              registrationFile =
                                  File(result.files.single.path!);
                              registrationBytes = null;
                              registrationSelected = true;
                            });
                          }
                        }
                      }, showCheck: registrationSelected),

                      _uploadPhotoRowAligned(
                          "Photo de profil", profileImageBytes, () {
                        _pickImage((f, bytes) {
                          setState(() {
                            profileImage = f;
                            profileImageBytes = bytes;
                          });
                        });
                      }),
                      _uploadPhotoRowAligned(
                          "Photo du véhicule", vehiclePhotoBytes, () {
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
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(40)),
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
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (!newValue.text.startsWith(prefix) ||
        newValue.selection.start < prefix.length) {
      return oldValue;
    }
    final digitsOnly = newValue.text
        .replaceFirst(prefix, '')
        .replaceAll(RegExp(r'[^0-9]'), '');
    final newText = prefix + digitsOnly;
    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}

class _LicensePlateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final rawText =
        newValue.text.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();

    String formatted = '';
    for (int i = 0; i < rawText.length && i < 7; i++) {
      if (i == 2 || i == 5) formatted += '-';
      formatted += rawText[i];
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
