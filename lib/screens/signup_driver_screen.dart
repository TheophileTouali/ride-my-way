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
      validator: (value) => value == null || value.trim().isEmpty ? 'Champ requis' : null,
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
        if (value == null || value.isEmpty) return 'Champ requis';
        if (label.contains('Confirmer') && value != password.text) return 'Les mots de passe ne correspondent pas';
        if (!_isPasswordStrong(value)) return '8+ caractères, majuscule, chiffre, caractère spécial';
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

      final uid = cred.user!.uid;
      String? photoUrl;
      if (profileImage != null) {
        final ref = FirebaseStorage.instance.ref().child("profile_images/$uid.jpg");
        await ref.putFile(File(profileImage!.path));
        photoUrl = await ref.getDownloadURL();
      }

      String? vehicleUrl;

if (vehiclePhoto != null) {
  final ref = FirebaseStorage.instance.ref().child("vehicle_images/$uid.jpg");
  await ref.putFile(vehiclePhoto!);
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset('assets/images/logo_transparent.png', height: 100),
                const SizedBox(height: 24),
                const Icon(Icons.verified_user_outlined, size: 48, color: AppColors.deepGold),
                const SizedBox(height: 8),
                const Text("Créer un compte conducteur", style: TextStyle(color: AppColors.deepGold, fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
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
                      return 'Numéro invalide (ex: +33 612345678)';
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
    validator: (value) => value == null || value.trim().isEmpty ? 'Champ requis' : null,
  ),
),

                  
                ),
                const SizedBox(height: 16),
                _buildPassword(password, "Mot de passe", obscure1, () => setState(() => obscure1 = !obscure1)),
                const SizedBox(height: 16),
                _buildPassword(confirmPassword, "Confirmer le mot de passe", obscure2, () => setState(() => obscure2 = !obscure2)),
                const SizedBox(height: 16),
                GooglePlacesAutoCompleteTextFormField(
                  textEditingController: addressController,
                  googleAPIKey: "AIzaSyA_-00rdj9W8AMt-ybpDpvJbnPhMHt2MVI",
                  debounceTime: 800,
                  countries: ["fr"],
                  fetchCoordinates: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration("Adresse complète"),
                  onSuggestionClicked: (prediction) => addressController.text = prediction.description!,
                  onPlaceDetailsWithCoordinatesReceived: (_) {},
                  validator: (v) => v == null || v.isEmpty ? "Champ requis" : null,
                ),
                const SizedBox(height: 16),
DropdownButtonFormField<String>(
  value: selectedVehicleType,
  items: vehicleTypes.map((type) => DropdownMenuItem(
    value: type,
    child: Text(type, style: const TextStyle(color: Colors.white)),
  )).toList(),
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
  validator: (v) => v == null ? "Champ requis" : null,
),
const SizedBox(height: 16),

DropdownButtonFormField<String>(
  value: marquesSelonType.contains(carBrand.text) ? carBrand.text : null,
  items: marquesSelonType.map((brand) {
    return DropdownMenuItem(
      value: brand,
      child: Text(brand, style: const TextStyle(color: Colors.white)),
    );
  }).toList(),
  onChanged: (value) {
    setState(() => carBrand.text = value!);
  },
  decoration: _inputDecoration("Marque du véhicule"),
  dropdownColor: Colors.black,
  iconEnabledColor: AppColors.deepGold,
  validator: (v) => v == null ? "Champ requis" : null,
),
const SizedBox(height: 16),

DropdownButtonFormField<String>(
  value: selectedVehicleYear,
  items: anneesSelonType.map((year) => DropdownMenuItem(
    value: year,
    child: Text(year, style: const TextStyle(color: Colors.white)),
  )).toList(),
  onChanged: (val) => setState(() => selectedVehicleYear = val),
  decoration: _inputDecoration("Année du véhicule"),
  dropdownColor: Colors.black,
  iconEnabledColor: AppColors.deepGold,
  validator: (v) => v == null ? "Champ requis" : null,
),

                const SizedBox(height: 16),
                TextFormField(
  controller: licensePlate,
  style: const TextStyle(color: Colors.white),
  cursorColor: AppColors.deepGold,
  decoration: _inputDecoration("Immatriculation").copyWith(
    hintText: "Ex : AB-123-CD",
    hintStyle: const TextStyle(color: Colors.white38, fontStyle: FontStyle.italic),
  ),
  textCapitalization: TextCapitalization.characters,
  validator: (value) {
    if (value == null || value.trim().isEmpty) return 'Champ requis';
    final reg = RegExp(r'^[A-HJ-NP-Z]{2}-?\d{3}-?[A-HJ-NP-Z]{2}$');
    if (!reg.hasMatch(value.toUpperCase())) return 'Format invalide (ex : AB-123-CD)';
    return null;
  },
),
const SizedBox(height: 16),

TextFormField(
  controller: driverLicenseNumber,
  style: const TextStyle(color: Colors.white),
  cursorColor: AppColors.deepGold,
  decoration: _inputDecoration("N° Permis de conduire").copyWith(
    hintText: "Ex : DUPONTRIC123456",
    hintStyle: const TextStyle(color: Colors.white38, fontStyle: FontStyle.italic),
  ),
  textCapitalization: TextCapitalization.characters,
  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9]'))],
  validator: (value) {
    if (value == null || value.trim().isEmpty) return 'Champ requis';
    final clean = value.trim().toUpperCase();
    if (clean.length < 12 || clean.length > 16) return 'Numéro invalide (12 à 16 caractères)';
    return null;
  },
),

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
                    textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'PlayfairDisplay'),
                  ),
                  child: const Text("S'inscrire"),
                )
              ],
            ),
          ),
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
