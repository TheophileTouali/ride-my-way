import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/gestures.dart';
import 'package:google_places_autocomplete_text_field/google_places_autocomplete_text_field.dart';
import '../themes/app_theme.dart';

class SignupStep3Screen extends StatefulWidget {
  const SignupStep3Screen({super.key});

  @override
  State<SignupStep3Screen> createState() => _SignupStep3ScreenState();
}

class _SignupStep3ScreenState extends State<SignupStep3Screen> {
  final _formKey = GlobalKey<FormState>();

  final addressController = TextEditingController();
  final cityController = TextEditingController();
  late TapGestureRecognizer _tapRecognizer;

  @override
  void initState() {
    super.initState();
    _tapRecognizer = TapGestureRecognizer()
      ..onTap = () => context.go('/login');
  }

  @override
  void dispose() {
    _tapRecognizer.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            "🎉 Bienvenue chez Ride My Way ! Inscription réussie.",
            style: TextStyle(
              fontFamily: 'PlayfairDisplay',
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: AppColors.gold,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      );

      Future.delayed(const Duration(seconds: 3), () {
        context.go('/login');
      });
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
                  style: TextStyle(
                    color: AppColors.gold,
                    fontSize: 28,
                    fontFamily: 'PlayfairDisplay',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text("Étape 3/3", style: TextStyle(color: AppColors.gold, fontSize: 16)),
                const SizedBox(height: 24),

                // Adresse
                GooglePlacesAutoCompleteTextFormField(
                  textEditingController: addressController,
                  googleAPIKey: "VOTRE_CLÉ_API_GOOGLE", // Remplacer
                  debounceTime: 800,
                  countries: ["fr"],
                  fetchCoordinates: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: "Adresse",
                    labelStyle: const TextStyle(color: Colors.grey),
                    filled: false,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.gold),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.gold, width: 1.5),
                    ),
                  ),
                  onSuggestionClicked: (prediction) {
                    addressController.text = prediction.description!;
                    addressController.selection = TextSelection.fromPosition(
                      TextPosition(offset: prediction.description!.length),
                    );
                  },
                  onPlaceDetailsWithCoordinatesReceived: (prediction) {},
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return "Veuillez renseigner votre adresse";
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                _buildTextField(cityController, "Ville", validator: (value) {
                  if (value == null || value.isEmpty) {
                    return "Veuillez indiquer votre ville";
                  }
                  if (!RegExp(r"^[a-zA-ZÀ-ÿ\s\-]{2,}").hasMatch(value)) {
                    return "Nom de ville invalide";
                  }
                  return null;
                }),

                const SizedBox(height: 32),

                ElevatedButton(
                  onPressed: _submit,
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
                  child: const Text("S’inscrire"),
                ),

                const SizedBox(height: 24),

                RichText(
                  text: TextSpan(
                    text: "Vous avez déjà un compte ? ",
                    style: TextStyle(color: Colors.grey[500], fontSize: 14),
                    children: [
                      TextSpan(
                        text: "Se connecter",
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontWeight: FontWeight.bold,
                        ),
                        recognizer: _tapRecognizer,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, {String? Function(String?)? validator}) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      cursorColor: AppColors.gold,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        filled: false,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.gold),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.gold, width: 1.5),
        ),
      ),
      validator: validator,
    );
  }
}
