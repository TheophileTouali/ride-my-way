import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../themes/app_theme.dart';
import 'package:firebase_auth/firebase_auth.dart';


class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();

  final oldPasswordController = TextEditingController();
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  final RegExp passwordRegex = RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)[A-Za-z\d@$!%*?&]{8,}$');

  Future<void> _submitPasswordChange() async {
  if (!_formKey.currentState!.validate()) return;

  try {
    final user = FirebaseAuth.instance.currentUser;
    final cred = EmailAuthProvider.credential(
      email: user!.email!,
      password: oldPasswordController.text.trim(),
    );

    // Re-authentifie d'abord (obligatoire pour changer le mot de passe)
    await user.reauthenticateWithCredential(cred);

    // Met à jour le mot de passe
    await user.updatePassword(newPasswordController.text.trim());

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Mot de passe modifié avec succès ✅"),
          backgroundColor: AppColors.gold,
        ),
      );
      context.go('/profile');
    }
  } on FirebaseAuthException catch (e) {
    String errorMessage = "Une erreur est survenue.";
    if (e.code == 'wrong-password') {
      errorMessage = "Ancien mot de passe incorrect ❌";
    } else if (e.code == 'requires-recent-login') {
      errorMessage = "Reconnectez-vous pour modifier votre mot de passe.";
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(errorMessage),
        backgroundColor: Colors.redAccent,
      ),
    );
  }
}


  InputDecoration _inputDecoration(String label, bool isObscured, VoidCallback toggle) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.grey),
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
      suffixIcon: IconButton(
        icon: Icon(isObscured ? Icons.visibility_off : Icons.visibility, color: Colors.grey[500]),
        onPressed: toggle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        foregroundColor: AppColors.gold,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.gold),
          onPressed: () => context.go('/profile'),
        ),
        title: const Text("Modifier le mot de passe"),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    const Text(
                      "Changer votre mot de passe",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.gold,
                        fontSize: 24,
                        fontFamily: 'PlayfairDisplay',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 32),

                    TextFormField(
                      controller: oldPasswordController,
                      obscureText: _obscureOld,
                      style: const TextStyle(color: Colors.white),
                      cursorColor: AppColors.gold,
                      decoration: _inputDecoration("Ancien mot de passe", _obscureOld, () {
                        setState(() => _obscureOld = !_obscureOld);
                      }),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return "Veuillez entrer votre ancien mot de passe";
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 20),

                    TextFormField(
                      controller: newPasswordController,
                      obscureText: _obscureNew,
                      style: const TextStyle(color: Colors.white),
                      cursorColor: AppColors.gold,
                      decoration: _inputDecoration("Nouveau mot de passe", _obscureNew, () {
                        setState(() => _obscureNew = !_obscureNew);
                      }),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return "Veuillez saisir un mot de passe";
                        }
                        if (!passwordRegex.hasMatch(value)) {
                          return "8+ caractères, 1 maj, 1 min, 1 chiffre requis";
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 20),

                    TextFormField(
                      controller: confirmPasswordController,
                      obscureText: _obscureConfirm,
                      style: const TextStyle(color: Colors.white),
                      cursorColor: AppColors.gold,
                      decoration: _inputDecoration("Confirmer le mot de passe", _obscureConfirm, () {
                        setState(() => _obscureConfirm = !_obscureConfirm);
                      }),
                      validator: (value) {
                        if (value != newPasswordController.text) {
                          return "Les mots de passe ne correspondent pas";
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 32),

                    ElevatedButton(
                      onPressed: _submitPasswordChange,
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
                      child: const Text("Valider"),
                    ),

                    const SizedBox(height: 16),

                    TextButton(
                      onPressed: () => context.go('/profile'),
                      child: const Text(
                        "Annuler",
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
