import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../themes/app_theme.dart';

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
  bool _loading = false;

  String? _userRole; // "driver" | "passenger"

  // 8+ chars, 1 upper, 1 lower, 1 digit
  final RegExp passwordRegex =
      RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)[A-Za-z\d@$!%*?&]{8,}$');

  @override
  void initState() {
    super.initState();
    _fetchUserRole();
  }

  Future<void> _fetchUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (snap.exists) {
        setState(
            () => _userRole = (snap.data()?['role'] as String?) ?? 'passenger');
      }
    } catch (e) {
      debugPrint('Erreur récupération rôle utilisateur : $e');
    }
  }

  @override
  void dispose() {
    oldPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  // ----- Navigation sûre -----
  void _safeBack() {
    final router = GoRouter.of(context);

    if (router.canPop()) {
      context.pop();
      return;
    }

    final from = GoRouterState.of(context).uri.queryParameters['from'];
    if (from != null && from.isNotEmpty) {
      try {
        context.go(from);
        return;
      } catch (_) {}
    }

    if (_userRole == 'driver') {
      try {
        context.go('/driver-profile');
        return;
      } catch (_) {}
      try {
        context.go('/driver-home');
        return;
      } catch (_) {}
    } else {
      try {
        context.go('/profile');
        return;
      } catch (_) {}
      try {
        context.go('/home');
        return;
      } catch (_) {}
    }

    try {
      context.go('/');
    } catch (_) {}
  }

  InputDecoration _inputDecoration(
    String label,
    bool isObscured,
    VoidCallback toggle,
  ) {
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
        icon: Icon(
          isObscured ? Icons.visibility_off : Icons.visibility,
          color: Colors.grey[500],
        ),
        onPressed: toggle,
      ),
    );
  }

  Future<void> _submitPasswordChange() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'Utilisateur non connecté',
        );
      }

      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: oldPasswordController.text.trim(),
      );

      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(newPasswordController.text.trim());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mot de passe modifié avec succès ✅'),
          backgroundColor: Colors.green,
        ),
      );

      _safeBack();
    } on FirebaseAuthException catch (e) {
      String msg = 'Une erreur est survenue.';
      switch (e.code) {
        case 'wrong-password':
          msg = 'Ancien mot de passe incorrect ❌';
          break;
        case 'requires-recent-login':
          msg = 'Veuillez vous reconnecter pour modifier votre mot de passe.';
          break;
        case 'too-many-requests':
          msg = 'Trop de tentatives. Réessayez plus tard.';
          break;
        case 'network-request-failed':
          msg = 'Problème réseau. Vérifiez votre connexion.';
          break;
        default:
          msg = e.message ?? msg;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _safeBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.black,
        appBar: AppBar(
          backgroundColor: AppColors.black,
          foregroundColor: AppColors.gold,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.gold),
            onPressed: _safeBack,
          ),
          title: const Text('Modifier le mot de passe'),
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
                        'Changer votre mot de passe',
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
                        enabled: !_loading,
                        style: const TextStyle(color: Colors.white),
                        cursorColor: AppColors.gold,
                        decoration: _inputDecoration(
                          'Ancien mot de passe',
                          _obscureOld,
                          () => setState(() => _obscureOld = !_obscureOld),
                        ),
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'Obligatoire' : null,
                      ),
                      const SizedBox(height: 20),

                      TextFormField(
                        controller: newPasswordController,
                        obscureText: _obscureNew,
                        enabled: !_loading,
                        style: const TextStyle(color: Colors.white),
                        cursorColor: AppColors.gold,
                        decoration: _inputDecoration(
                          'Nouveau mot de passe',
                          _obscureNew,
                          () => setState(() => _obscureNew = !_obscureNew),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Obligatoire';
                          if (!passwordRegex.hasMatch(v)) {
                            return '8+ car., 1 maj, 1 min, 1 chiffre requis';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      TextFormField(
                        controller: confirmPasswordController,
                        obscureText: _obscureConfirm,
                        enabled: !_loading,
                        style: const TextStyle(color: Colors.white),
                        cursorColor: AppColors.gold,
                        decoration: _inputDecoration(
                          'Confirmer le mot de passe',
                          _obscureConfirm,
                          () => setState(
                              () => _obscureConfirm = !_obscureConfirm),
                        ),
                        validator: (v) {
                          if (v != newPasswordController.text) {
                            return 'Les mots de passe ne correspondent pas';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 32),

                      // ---- Bouton Valider (premium) ----
                      ElevatedButton.icon(
                        onPressed: _loading ? null : _submitPasswordChange,
                        icon: _loading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.black,
                                ),
                              )
                            : const Icon(Icons.lock_reset_rounded,
                                size: 20, color: AppColors.black),
                        label: Text(_loading ? ' ' : 'Valider'),
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
                          elevation: 8,
                          shadowColor: AppColors.gold.withOpacity(.35),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // ---- Bouton Annuler (outlined danger) ----
                      SizedBox(
                        width: 220,
                        child: OutlinedButton.icon(
                          onPressed: _loading ? null : _safeBack,
                          icon: const Icon(Icons.close_rounded,
                              size: 18, color: Colors.redAccent),
                          label: const Text('Annuler'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(
                                color: Colors.redAccent, width: 1.4),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(32),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: .2,
                            ),
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
      ),
    );
  }
}
