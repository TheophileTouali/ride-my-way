import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../providers/user_provider.dart';
import '../themes/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool _obscurePassword = true;


  Future<void> _handleLogin() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    try {
      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      await userCredential.user?.reload();
      final refreshedUser = FirebaseAuth.instance.currentUser;

      if (refreshedUser != null) {
        if (!refreshedUser.emailVerified) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("📧 Veuillez vérifier votre adresse e-mail avant de continuer."),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        // 🔍 Récupération du document Firestore
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(refreshedUser.uid)
            .get();

        if (!doc.exists || doc.data()?['role'] != 'passenger') {
          await FirebaseAuth.instance.signOut();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("🚫 Ce compte n'est pas autorisé à se connecter ici."),
              backgroundColor: Colors.red.shade900,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
          return;
        }

        // ✅ Connexion côté Provider
        final firstName = doc.data()?['firstName'] ?? 'Nom inconnu';
        final avatarUrl = doc.data()?['photoUrl'] as String?;
        final userProvider = Provider.of<UserProvider>(context, listen: false);

        userProvider.login(
          firstName,
          email,
          avatarUrl: avatarUrl,
        );

        await userProvider.loadUserData();

        // ✅ Redirection vers la home passager
        context.go('/home');
      }
    } on FirebaseAuthException catch (e) {
      final message = switch (e.code) {
        'user-not-found' => "🚫 Aucun compte ne correspond à cet e-mail. Vérifiez votre saisie.",
        'wrong-password' => "🔐 Le mot de passe est incorrect. Veuillez réessayer.",
        'invalid-email' => "✉️ L'adresse e-mail saisie est invalide.",
        'too-many-requests' => "⏳ Trop de tentatives. Patientez un moment avant de réessayer.",
        'user-disabled' => "❌ Ce compte a été désactivé. Contactez le support.",
        'invalid-credential' => "⚠️ Identifiants invalides ou expirés. Réessayez.",
        'network-request-failed' => "🌐 Problème de connexion. Vérifiez votre réseau.",
        _ => "❗ Une erreur inconnue est survenue. Réessayez plus tard.",
      };

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade900,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e, stack) {
      debugPrint("🔥 Erreur inattendue : $e");
      debugPrintStack(stackTrace: stack);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❗ Une erreur est survenue : ${e.toString()}")),
      );
    }
  }




  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset(
                    'assets/images/logo_transparent.png',
                    height: 180,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 32),

                  // Email
                  TextField(
                    controller: emailController,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: AppColors.gold,
                    decoration: InputDecoration(
                      floatingLabelBehavior: FloatingLabelBehavior.never,
                      labelText: 'Email',
                      labelStyle: TextStyle(color: Colors.grey[400]),
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey),
                      ),
                      focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: AppColors.gold),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Mot de passe
                  TextField(
                    controller: passwordController,
                    obscureText: _obscurePassword,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: AppColors.gold,
                    decoration: InputDecoration(
                      labelText: 'Mot de passe',
                      labelStyle: TextStyle(color: Colors.grey[400]),
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey),
                      ),
                      focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: AppColors.gold),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          color: Colors.grey[500],
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Lien mot de passe oublié
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        context.go('/forgot-password');
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.gold,
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text("Mot de passe oublié ?", style: TextStyle(fontSize: 14)),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Bouton Connexion
                  ElevatedButton(
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
                    onPressed: _handleLogin,
                    child: const Text('Connexion'),
                  ),

                  const SizedBox(height: 32),

                  // Lien vers inscription
                  Center(
                    child: RichText(
                      text: TextSpan(
                        text: "Vous n’avez pas de compte ? ",
                        style: TextStyle(color: Colors.grey[500], fontSize: 14),
                        children: [
                          TextSpan(
                            text: 'Créer un compte',
                            style: const TextStyle(
                              color: AppColors.gold,
                              fontWeight: FontWeight.bold,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () {
                                context.go('/signup');
                              },
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
      ),
    );
  }
}
