import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../providers/user_provider.dart';
import '../themes/app_theme.dart';
import 'package:flutter/gestures.dart';

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

      // 🔁 Recharge les infos utilisateur pour être à jour
      await userCredential.user?.reload();
      final refreshedUser = FirebaseAuth.instance.currentUser;

      if (refreshedUser != null) {
        if (!refreshedUser.emailVerified) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Veuillez vérifier votre adresse e-mail.")),
          );
          return;
        }

        // ✅ Connexion réussie
        Provider.of<UserProvider>(context, listen: false)
            .login(refreshedUser.displayName ?? '', email);
        context.go('/home');

      }
    } on FirebaseAuthException catch (e) {
      final message = switch (e.code) {
        'user-not-found' => "Aucun compte trouvé pour cet e-mail.",
        'wrong-password' => "Mot de passe incorrect.",
        'invalid-email' => "Adresse e-mail invalide.",
        'too-many-requests' => "Trop de tentatives. Réessayez plus tard.",
        _ => "Erreur : ${e.message ?? 'inconnue.'}"
      };

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e, stack) {
      // 🔍 Affiche l'erreur complète dans la console
      debugPrint("🔥 Erreur inattendue lors de la connexion : $e");
      debugPrintStack(stackTrace: stack);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur inconnue : ${e.toString()}")),
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
