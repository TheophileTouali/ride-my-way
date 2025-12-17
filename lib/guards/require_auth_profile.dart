// lib/guards/require_auth_profile.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Garde d'accès : impose connexion + rôle.
/// ✅ Ne bloque plus sur phone/address/birthdate/photoUrl (Apple 5.1.1)
class RequireAuthAndCompleteProfile extends StatefulWidget {
  final Widget child;
  final String requiredRole; // "passenger" ou "driver"

  const RequireAuthAndCompleteProfile({
    super.key,
    required this.child,
    required this.requiredRole,
  });

  @override
  State<RequireAuthAndCompleteProfile> createState() =>
      _RequireAuthAndCompleteProfileState();
}

class _RequireAuthAndCompleteProfileState
    extends State<RequireAuthAndCompleteProfile> {
  Future<bool> _check() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (!snap.exists) return false;

    final d = snap.data() ?? {};
    bool notEmpty(String k) => (d[k]?.toString().trim().isNotEmpty ?? false);

    // ✅ Champs CORE uniquement (ne pas bloquer sur champs optionnels)
    final coreOk = notEmpty('firstName') &&
        notEmpty('lastName') &&
        notEmpty('email') && // si tu stockes email dans Firestore (tu le fais)
        notEmpty('role');

    final roleOk = (d['role']?.toString() ?? '') == widget.requiredRole;

    // (optionnel) email vérifié :
    // final emailVerified = user.emailVerified == true;

    return coreOk && roleOk; // && emailVerified;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    // 1) Non connecté → /login
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => context.go('/login'));
      return const SizedBox.shrink();
    }

    // 2) Connecté → vérifier profil/role
    return FutureBuilder<bool>(
      future: _check(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: Color(0xFF0D0D0D),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final ok = snap.data == true;
        if (!ok) {
          // ❗ Ici on garde le comportement: si doc absent / mauvais rôle / champs core manquants
          WidgetsBinding.instance.addPostFrameCallback((_) {
            context.go('/edit-profile');
          });
          return const SizedBox.shrink();
        }

        // 3) Accès autorisé
        return widget.child;
      },
    );
  }
}
