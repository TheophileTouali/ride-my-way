import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;
import 'package:google_places_autocomplete_text_field/google_places_autocomplete_text_field.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../themes/app_theme.dart';

/// Normalise d’éventuelles URLs `.firebasestorage.app` vers `.appspot.com`
String normalizeStorageUrl(String? url) {
  if (url == null || url.isEmpty) return '';
  return url.replaceAll('.firebasestorage.app', '.appspot.com');
}

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
  XFile? _selectedImage; // preview photo de profil
  XFile? _identityCardImage; // preview doc identité

  String? existingPhotoUrl; // URL photo actuelle
  String? existingIdCardUrl; // URL doc identité actuel

  bool _isSubmitting = false;

  // ✅ Bucket correct et cohérent (Web & mobile)
  final FirebaseStorage storage = FirebaseStorage.instanceFor(
      bucket: 'gs://ride-my-way-7f258.firebasestorage.app');

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data();
    if (data != null) {
      firstNameController.text = data['firstName'] ?? '';
      lastNameController.text = data['lastName'] ?? '';
      emailController.text = data['email'] ?? '';
      phoneController.text = data['phone'] ?? '';
      addressController.text = data['address'] ?? '';

      // ✅ normalise les liens éventuellement anciens
      existingPhotoUrl = normalizeStorageUrl(data['photoUrl']);
      existingIdCardUrl = normalizeStorageUrl(data['identityCardUrl']);

      if (data['birthdate'] != null) {
        birthdateController.text = DateFormat('dd/MM/yyyy')
            .format((data['birthdate'] as Timestamp).toDate());
      }
      setState(() {});
    }
  }

  String _bust(String url) {
    final sep = url.contains('?') ? '&' : '?';
    return '$url${sep}ts=${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<String?> _uploadXFile({
    required XFile file,
    required Reference ref,
  }) async {
    final meta = SettableMetadata(contentType: 'image/png');
    if (kIsWeb) {
      final bytes = await file.readAsBytes();
      await ref.putData(bytes, meta);
    } else {
      await ref.putFile(File(file.path), meta);
    }
    return ref.getDownloadURL();
  }

  // ---------------- SUBMIT ----------------
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser!;
      final uid = user.uid;

      // 1) Upload conditionnel
      String? photoUrl = existingPhotoUrl;
      if (_selectedImage != null) {
        final ref = storage.ref().child(
            'users_data/$uid/profile_${DateTime.now().millisecondsSinceEpoch}.png');
        photoUrl = await _uploadXFile(file: _selectedImage!, ref: ref);
      }

      String? idCardUrl = existingIdCardUrl;
      if (_identityCardImage != null) {
        final ref = storage.ref().child(
            'users_data/$uid/id_card_${DateTime.now().millisecondsSinceEpoch}.png');
        idCardUrl = await _uploadXFile(file: _identityCardImage!, ref: ref);
      }

      // 2) Firestore (merge)
      final payload = <String, dynamic>{
        'firstName': firstNameController.text.trim(),
        'lastName': lastNameController.text.trim(),
        'phone': phoneController.text.trim(),
        'address': addressController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final b = birthdateController.text.trim();
      if (b.isNotEmpty) {
        payload['birthdate'] =
            Timestamp.fromDate(DateFormat('dd/MM/yyyy').parse(b));
      }
      if (photoUrl != null && photoUrl.isNotEmpty)
        payload['photoUrl'] = photoUrl;
      if (idCardUrl != null && idCardUrl.isNotEmpty) {
        payload['identityCardUrl'] = idCardUrl;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(payload, SetOptions(merge: true));

      // 3) Auth.photoURL
      if (photoUrl != null && photoUrl.isNotEmpty) {
        await user.updatePhotoURL(photoUrl);
      }

      // 4) Feedback + retour profil
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      _showPremiumSuccess('Profil mis à jour');
      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      final bust = DateTime.now().millisecondsSinceEpoch;
      context.go('/profile?bust=$bust&saved=1');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur : $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showPremiumSuccess(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        duration: const Duration(milliseconds: 1200),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.gold.withOpacity(.28)),
            gradient: LinearGradient(
              colors: [
                AppColors.gold.withOpacity(.22),
                Colors.white.withOpacity(.06),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.gold.withOpacity(.12),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: AppColors.gold, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------- DATE PICKER --------------
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Vous devez avoir au moins 18 ans.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }
      birthdateController.text = DateFormat('dd/MM/yyyy').format(picked);
    }
  }

  // ------------------- UI -------------------
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0B0B0C), Color(0xFF121215)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.transparent,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.gold),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/profile');
              }
            },
          ),
          title: const Text(
            'Modifier mon profil',
            style: TextStyle(
              color: AppColors.gold,
              fontWeight: FontWeight.w800,
              letterSpacing: .2,
            ),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _premiumHeader(),
                const SizedBox(height: 18),
                _sectionCard(
                  title: 'Identité',
                  children: [
                    _goldField(
                        firstNameController, 'Prénom', Icons.badge_rounded),
                    _goldField(lastNameController, 'Nom', Icons.badge_outlined),
                    GestureDetector(
                      onTap: _selectBirthDate,
                      child: AbsorbPointer(
                        child: _goldField(birthdateController,
                            'Date de naissance', Icons.cake_rounded,
                            requiredField: false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _sectionCard(
                  title: 'Coordonnées',
                  children: [
                    _goldField(emailController, 'Email', Icons.mail_rounded,
                        enabled: false),
                    _goldField(
                        phoneController, 'Téléphone', Icons.phone_rounded),
                    _buildAddressAutoComplete(),
                  ],
                ),
                const SizedBox(height: 14),
                _sectionCard(
                  title: 'Document d’identité',
                  children: [
                    FutureBuilder<Widget>(
                      future: _buildIdCardImage(),
                      builder: (_, s) => s.hasData ? s.data! : _emptyDocTile(),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _secondaryButton(
                            icon: Icons.upload_file_rounded,
                            label: 'Ajouter / remplacer',
                            onPressed: () async {
                              final picked = await _picker.pickImage(
                                  source: ImageSource.gallery);
                              if (picked != null) {
                                setState(() => _identityCardImage = picked);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (existingIdCardUrl != null &&
                            existingIdCardUrl!.isNotEmpty)
                          Expanded(
                            child: _dangerButton(
                              icon: Icons.delete_outline_rounded,
                              label: 'Supprimer',
                              onPressed: () async {
                                try {
                                  final uid =
                                      FirebaseAuth.instance.currentUser!.uid;

                                  // Vérifie d'abord si l'URL existe
                                  if (existingIdCardUrl != null &&
                                      existingIdCardUrl!.isNotEmpty) {
                                    try {
                                      // Essaye de supprimer le fichier du Storage
                                      final ref = FirebaseStorage.instance
                                          .refFromURL(existingIdCardUrl!);
                                      await ref.delete();
                                    } catch (e) {
                                      // Ignore si le fichier n’existe pas (c’est ton cas actuel)
                                      if (e
                                          .toString()
                                          .contains('object-not-found')) {
                                        debugPrint(
                                            '⚠️ Fichier déjà inexistant dans le Storage.');
                                      } else {
                                        rethrow;
                                      }
                                    }
                                  }

                                  // Supprime ensuite le champ Firestore
                                  await FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(uid)
                                      .update({
                                    'identityCardUrl': FieldValue.delete()
                                  });

                                  setState(() {
                                    existingIdCardUrl = null;
                                    _identityCardImage = null;
                                  });

                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('✅ Document supprimé'),
                                      backgroundColor: AppColors.deepGold,
                                    ),
                                  );
                                } catch (e) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'Erreur lors de la suppression : $e'),
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: AppColors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppColors.black,
                            ),
                          )
                        : const Text(
                            'Enregistrer les modifications',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              letterSpacing: .2,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddressAutoComplete() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GooglePlacesAutoCompleteTextFormField(
        textEditingController: addressController,
        googleAPIKey: "AIzaSyA_-00rdj9W8AMt-ybpDpvJbnPhMHt2MVI",
        debounceTime: 800,
        countries: const ["fr"],
        fetchCoordinates: true,
        style: const TextStyle(color: Colors.white),
        decoration: _goldDecoration('Adresse', Icons.location_on_rounded),
        onSuggestionClicked: (prediction) {
          addressController.text = prediction.description ?? '';
          FocusScope.of(context).unfocus();
        },
        onChanged: (value) => addressController.text = value,
        onPlaceDetailsWithCoordinatesReceived: (_) {},
        validator: (_) => null, // ✅ optionnel
        overlayContainerBuilder: (child) => Material(
          elevation: 2.0,
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(12),
          child: child,
        ),
      ),
    );
  }

  // ----------------- PREMIUM UI HELPERS -----------------
  Widget _premiumHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _glass(),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.gold.withOpacity(.22),
                      blurRadius: 18,
                      spreadRadius: 1,
                      offset: const Offset(0, 10),
                    ),
                  ],
                  gradient: LinearGradient(
                    colors: [
                      AppColors.gold.withOpacity(.28),
                      Colors.transparent
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: AppColors.gold.withOpacity(.35), width: 1.4),
                ),
              ),
              ClipOval(
                child: FutureBuilder<Widget>(
                  future: _buildProfileImage(),
                  builder: (_, s) =>
                      s.data ??
                      Image.asset(
                        'assets/images/user_placeholder.png',
                        width: 88,
                        height: 88,
                        fit: BoxFit.cover,
                      ),
                ),
              ),
              Positioned(
                bottom: 6,
                right: 4,
                child: InkWell(
                  onTap: () async {
                    final picked =
                        await _picker.pickImage(source: ImageSource.gallery);
                    if (picked != null) setState(() => _selectedImage = picked);
                  },
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.gold, width: 1),
                    ),
                    child:
                        const Icon(Icons.edit, size: 14, color: AppColors.gold),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Flexible(child: _headerInfo()),
        ],
      ),
    );
  }

  Widget _headerInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${firstNameController.text.isEmpty ? '—' : firstNameController.text} '
          '${lastNameController.text.isEmpty ? '' : lastNameController.text}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.gold,
            fontWeight: FontWeight.w800,
            fontSize: 22,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          emailController.text.isEmpty ? '—' : emailController.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _sectionCard({required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: _glass(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.stars_rounded, color: AppColors.gold, size: 18),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.gold,
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: .2,
              ),
            ),
          ]),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _goldField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool enabled = true,
    bool requiredField = true, // ✅ NEW
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        style: const TextStyle(color: Colors.white),
        validator: requiredField
            ? (v) => v == null || v.trim().isEmpty ? 'Champ requis' : null
            : (_) => null, // ✅ optionnel
        decoration: _goldDecoration(label, icon, enabled: enabled),
      ),
    );
  }

  InputDecoration _goldDecoration(String label, IconData icon,
      {bool enabled = true}) {
    return InputDecoration(
      prefixIcon: Icon(icon, color: AppColors.gold),
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      filled: true,
      fillColor: Colors.white.withOpacity(.03),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withOpacity(.12)),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withOpacity(.08)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: AppColors.gold, width: 1.4),
      ),
    );
  }

  Widget _emptyDocTile() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: const [
          Icon(Icons.picture_as_pdf_rounded, color: AppColors.gold, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text('Aucun document envoyé',
                style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  Widget _secondaryButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 46,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: AppColors.gold, size: 18),
        label: Text(label, style: const TextStyle(color: Colors.white)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.white.withOpacity(.18)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          backgroundColor: Colors.white.withOpacity(.04),
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  Widget _dangerButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 46,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.redAccent, size: 18),
        label: Text(label, style: const TextStyle(color: Colors.redAccent)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.redAccent),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          backgroundColor: Colors.redAccent.withOpacity(.06),
          foregroundColor: Colors.redAccent,
        ),
      ),
    );
  }

  Widget _chip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.03),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withOpacity(.16),
            blurRadius: 10,
            spreadRadius: .3,
          ),
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: AppColors.gold),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            letterSpacing: .2,
          ),
        ),
      ]),
    );
  }

  BoxDecoration _glass() {
    return BoxDecoration(
      color: Colors.white.withOpacity(.04),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white.withOpacity(.08)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(.35),
          blurRadius: 20,
          offset: const Offset(0, 12),
        ),
      ],
    );
  }

  // ----------- Helpers UI/preview -----------
  Future<Widget> _buildProfileImage() async {
    if (_selectedImage != null) {
      if (kIsWeb) {
        final bytes = await _selectedImage!.readAsBytes();
        return ClipOval(
          child:
              Image.memory(bytes, width: 160, height: 160, fit: BoxFit.cover),
        );
      } else {
        return ClipOval(
          child: Image.file(File(_selectedImage!.path),
              width: 160, height: 160, fit: BoxFit.cover),
        );
      }
    } else if (existingPhotoUrl != null && existingPhotoUrl!.isNotEmpty) {
      final bust = _bust(existingPhotoUrl!);
      return ClipOval(
        child: Image.network(
          bust,
          width: 160,
          height: 160,
          fit: BoxFit.cover,
          // ✅ évite l'overflow si l'URL échoue
          errorBuilder: (_, __, ___) => Image.asset(
            'assets/images/user_placeholder.png',
            width: 160,
            height: 160,
            fit: BoxFit.cover,
          ),
        ),
      );
    } else {
      return ClipOval(
        child: Image.asset('assets/images/user_placeholder.png',
            width: 160, height: 160, fit: BoxFit.cover),
      );
    }
  }

  Future<Widget> _buildIdCardImage() async {
    if (_identityCardImage != null) {
      if (kIsWeb) {
        final bytes = await _identityCardImage!.readAsBytes();
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.memory(bytes, height: 120, fit: BoxFit.cover),
        );
      } else {
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.file(File(_identityCardImage!.path),
              height: 120, fit: BoxFit.cover),
        );
      }
    } else if (existingIdCardUrl != null && existingIdCardUrl!.isNotEmpty) {
      final bust = _bust(existingIdCardUrl!);
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.network(
          bust,
          height: 120,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            height: 120,
            alignment: Alignment.center,
            color: Colors.white.withOpacity(.04),
            child: const Icon(Icons.image_not_supported_rounded,
                color: AppColors.gold),
          ),
        ),
      );
    } else {
      return const SizedBox.shrink();
    }
  }
}
