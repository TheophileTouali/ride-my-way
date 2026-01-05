import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../themes/app_theme.dart';
import '../providers/driver_provider.dart';
import '../models/driver_user.dart';

// 👇 Couleur d’accent conducteur (or premium)
const Color kDriverAccent = Color(0xFF8C6A2C);

class DriverLoginScreen extends StatefulWidget {
  const DriverLoginScreen({super.key});

  @override
  State<DriverLoginScreen> createState() => _DriverLoginScreenState();
}

class _DriverLoginScreenState extends State<DriverLoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  void _showPremiumError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.grey.shade900,
        behavior: SnackBarBehavior.floating,
        elevation: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        duration: const Duration(seconds: 4),
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ Libère le verrou si une erreur survient après lock (évite "déjà connecté" fantôme)
  Future<void> _releaseDriverSession(String uid) async {
    try {
      await FirebaseFirestore.instance.collection('drivers').doc(uid).set(
        {
          'isLoggedIn': false,
          'lastActive': FieldValue.serverTimestamp(),
          'sessionId': FieldValue.delete(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      // Ne jamais casser l'UX si Firestore échoue ici.
    }
  }

  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showPremiumError(
          "Merci de renseigner votre email et votre mot de passe.");
      return;
    }

    String? uid;
    bool sessionLocked = false;

    try {
      setState(() => _isLoading = true);

      final userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      final user = userCredential.user;
      await user?.reload();
      final refreshedUser = FirebaseAuth.instance.currentUser;

      if (refreshedUser == null) {
        _showPremiumError("Connexion impossible. Veuillez réessayer.");
        return;
      }

      uid = refreshedUser.uid;

      // ✅ Important : si email non vérifié, on sort ET on signOut (pas de session résiduelle)
      if (!refreshedUser.emailVerified) {
        _showPremiumError(
            "Veuillez confirmer votre adresse e-mail avant de vous connecter.");
        try {
          await FirebaseAuth.instance.signOut();
        } catch (_) {}
        return;
      }

      final doc =
          await FirebaseFirestore.instance.collection('drivers').doc(uid).get();

      if (!doc.exists) {
        _showPremiumError("Aucun profil conducteur associé à ce compte.");
        try {
          await FirebaseAuth.instance.signOut();
        } catch (_) {}
        return;
      }

      final driverData = doc.data()!;
      final role = driverData['role'];
      if (role != 'driver') {
        _showPremiumError(
            "Ce compte n'est pas autorisé à accéder à l'espace conducteur.");
        await FirebaseAuth.instance.signOut();
        return;
      }

      // ✅ 1) Crée le modèle AVANT le lock (évite lock fantôme si un champ manque / crash ailleurs)
      late final DriverUser driver;
      try {
        driver = DriverUser.fromMap(driverData, uid: doc.id);
      } catch (e) {
        debugPrint("❌ DriverUser.fromMap error: $e");
        _showPremiumError(
          "Votre profil conducteur est incomplet.\n"
          "Veuillez compléter votre profil.",
        );
        try {
          await FirebaseAuth.instance.signOut();
        } catch (_) {}
        return;
      }

      // 🔒 2) Vérification de session unique (inchangée côté UX, sécurisée côté flux)
      final driverRef =
          FirebaseFirestore.instance.collection('drivers').doc(uid);

      const sessionGrace = Duration(minutes: 10);
      final now = DateTime.now();

      final allowed =
          await FirebaseFirestore.instance.runTransaction<bool>((tx) async {
        final snap = await tx.get(driverRef);
        final data = snap.data() ?? {};

        final isLoggedIn = (data['isLoggedIn'] as bool?) ?? false;
        final lastActiveTs = data['lastActive'] as Timestamp?;
        final lastActive = lastActiveTs?.toDate();

        final hasRecentSession = isLoggedIn &&
            lastActive != null &&
            now.difference(lastActive) < sessionGrace;

        if (hasRecentSession) {
          return false; // session déjà active
        }

        final sessionId = now.millisecondsSinceEpoch.toString();
        tx.set(
          driverRef,
          {
            'isLoggedIn': true,
            'lastActive': FieldValue.serverTimestamp(),
            'sessionId': sessionId,
          },
          SetOptions(merge: true),
        );

        return true;
      });

      if (!allowed) {
        _showPremiumError(
          "Ce compte chauffeur est déjà connecté sur un autre appareil.\n"
          "Réessaie dans quelques minutes ou déconnecte l’autre session.",
        );
        try {
          await FirebaseAuth.instance.signOut();
        } catch (_) {}
        return;
      }

      sessionLocked = true;

      // ✅ Stockage du conducteur en mémoire locale (Provider)
      Provider.of<DriverProvider>(context, listen: false).setUser(driver);

      // ✅ Navigation
      context.go('/driver-home');
    } on FirebaseAuthException catch (e) {
      final message = switch (e.code) {
        'user-not-found' => "Aucun compte trouvé avec cet e-mail.",
        'wrong-password' => "Le mot de passe saisi est incorrect.",
        'invalid-email' => "Adresse e-mail invalide.",
        'too-many-requests' =>
          "Trop de tentatives : veuillez patienter un instant.",
        'invalid-credential' =>
          "Les identifiants fournis sont invalides ou ont expiré.",
        _ => "Une erreur inconnue est survenue. Veuillez réessayer.",
      };
      _showPremiumError(message);
    } on PlatformException catch (e) {
      _showPremiumError(
          "Erreur système (${e.code}). Veuillez réessayer plus tard.");
    } on FirebaseException catch (e) {
      _showPremiumError("Erreur Firebase (${e.code}). Veuillez réessayer.");
    } catch (e, stack) {
      debugPrint("🔥 Type: ${e.runtimeType} | Erreur: $e");
      debugPrintStack(stackTrace: stack);

      // ✅ Rollback : si on a locké la session puis crash, on libère le verrou
      if (uid != null && sessionLocked) {
        await _releaseDriverSession(uid!);
      }

      _showPremiumError(
          "Une erreur inattendue s’est produite. Veuillez réessayer.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
                  // --- Logo ---
                  Image.asset(
                    'assets/images/logo_transparent.png',
                    height: 180,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 12),

                  // --- Badge "Espace Conducteur" ---
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: kDriverAccent.withOpacity(.12),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                            color: kDriverAccent.withOpacity(.5), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.local_taxi_rounded,
                              size: 16, color: kDriverAccent),
                          SizedBox(width: 8),
                          Text(
                            "Espace Conducteur",
                            style: TextStyle(
                              color: kDriverAccent,
                              fontWeight: FontWeight.w700,
                              letterSpacing: .3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // --- Email ---
                  TextField(
                    controller: emailController,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: kDriverAccent,
                    decoration: InputDecoration(
                      floatingLabelBehavior: FloatingLabelBehavior.never,
                      labelText: 'Email',
                      labelStyle: TextStyle(color: Colors.grey[400]),
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey),
                      ),
                      focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: kDriverAccent),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // --- Mot de passe ---
                  TextField(
                    controller: passwordController,
                    obscureText: _obscurePassword,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: kDriverAccent,
                    decoration: InputDecoration(
                      labelText: 'Mot de passe',
                      labelStyle: TextStyle(color: Colors.grey[400]),
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey),
                      ),
                      focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: kDriverAccent),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.grey[500],
                        ),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // --- Mot de passe oublié ---
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => context.go('/forgot-password'),
                      style: TextButton.styleFrom(
                        foregroundColor: kDriverAccent,
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        "Mot de passe oublié ?",
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // --- Bouton Connexion ---
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kDriverAccent,
                      foregroundColor: AppColors.black,
                      minimumSize: const Size.fromHeight(56),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(40)),
                      textStyle: const TextStyle(
                        fontFamily: 'PlayfairDisplay',
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: _isLoading ? null : _handleLogin,
                    child: _isLoading
                        ? const CircularProgressIndicator(
                            color: AppColors.black)
                        : const Text('Connexion'),
                  ),

                  const SizedBox(height: 32),

                  // --- Lien vers inscription conducteur ---
                  Center(
                    child: RichText(
                      text: TextSpan(
                        text: "Pas encore de compte conducteur ? ",
                        style: TextStyle(color: Colors.grey[500], fontSize: 14),
                        children: [
                          TextSpan(
                            text: 'Créer un compte',
                            style: const TextStyle(
                              color: kDriverAccent,
                              fontWeight: FontWeight.bold,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () => context.go('/signup-driver'),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // --- Lien inverse : Passager ---
                  Center(
                    child: TextButton.icon(
                      onPressed: () => context.go('/login'),
                      icon: const Icon(Icons.vpn_key_rounded,
                          size: 16, color: AppColors.gold),
                      label: const Text("Se connecter en tant que passager"),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.gold,
                        textStyle: const TextStyle(fontWeight: FontWeight.w700),
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 12),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
