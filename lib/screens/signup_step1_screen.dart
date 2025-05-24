import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../themes/app_theme.dart';
// import 'package:firebase_auth/firebase_auth.dart'; // 🔁 Décommenter quand Firebase est prêt

class SignupStep1Screen extends StatefulWidget {
  const SignupStep1Screen({super.key});

  @override
  State<SignupStep1Screen> createState() => _SignupStep1ScreenState();
}

class _SignupStep1ScreenState extends State<SignupStep1Screen> {
  final _formKey = GlobalKey<FormState>();

  final firstNameController = TextEditingController();
  final lastNameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  void _continue() async {
    if (_formKey.currentState!.validate()) {
      // 🔒 Étapes futures avec Firebase (décommenter quand prêt)
      /*
      try {
        final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
        );

        await credential.user?.sendEmailVerification();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Un e-mail de vérification a été envoyé.")),
        );
      } on FirebaseAuthException catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur : ${e.message}")),
        );
        return;
      }
      */

      // 🔁 Simulation en attendant Firebase
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Simulation : e-mail de vérification envoyé.")),
      );

      context.go('/signup-step2');
    }
  }

  bool _isPasswordStrong(String password) {
    final pattern = RegExp(r'^(?=.*[A-Z])(?=.*\d)(?=.*[a-z]).{8,}$');
    return pattern.hasMatch(password);
  }

  bool _isValidEmail(String email) {
    final regex = RegExp(r"^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$");
    return regex.hasMatch(email);
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
                Image.asset(
                  'assets/images/logo_transparent.png',
                  height: 120,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 24),
                const Text(
                  "Inscription",
                  style: TextStyle(
                    color: AppColors.gold,
                    fontSize: 28,
                    fontFamily: 'PlayfairDisplay',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Étape 1 de 3",
                  style: TextStyle(
                    color: AppColors.gold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 32),

                _buildTextField(
                  firstNameController,
                  "Prénom",
                  validator: (value) => (value == null || value.isEmpty)
                      ? "Veuillez renseigner votre prénom"
                      : null,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  lastNameController,
                  "Nom",
                  validator: (value) => (value == null || value.isEmpty)
                      ? "Veuillez renseigner votre nom"
                      : null,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  emailController,
                  "Adresse e-mail",
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return "Veuillez entrer une adresse e-mail";
                    }
                    if (!_isValidEmail(value)) {
                      return "Adresse e-mail invalide";
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _buildPasswordField(
                  passwordController,
                  "Mot de passe",
                  obscure: _obscurePassword,
                  toggle: () => setState(() => _obscurePassword = !_obscurePassword),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return "Veuillez définir un mot de passe";
                    }
                    if (!_isPasswordStrong(value)) {
                      return "8+ caractères, 1 majuscule, 1 chiffre";
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _buildPasswordField(
                  confirmPasswordController,
                  "Confirmer le mot de passe",
                  obscure: _obscureConfirm,
                  toggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return "Veuillez confirmer le mot de passe";
                    }
                    if (value != passwordController.text) {
                      return "Les mots de passe ne correspondent pas";
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 32),

                ElevatedButton(
                  onPressed: _continue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.black,
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(40),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'PlayfairDisplay',
                    ),
                  ),
                  child: const Text("Continuer"),
                ),

                const SizedBox(height: 24),

                GestureDetector(
                  onTap: () => context.go('/login'),
                  child: RichText(
                    text: TextSpan(
                      text: "Vous avez déjà un compte ? ",
                      style: TextStyle(color: Colors.grey[500], fontSize: 14),
                      children: const [
                        TextSpan(
                          text: 'Se connecter',
                          style: TextStyle(
                            color: AppColors.gold,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
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

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    bool obscureText = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
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
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off : Icons.visibility,
            color: Colors.grey[500],
          ),
          onPressed: toggle,
        ),
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
