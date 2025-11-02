// lib/guards/require_auth_profile.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Garde d'accès : impose connexion + profil complet + rôle.
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

    final hasAll = notEmpty('firstName') &&
        notEmpty('lastName') &&
        notEmpty('address') &&
        notEmpty('phone') &&
        d['birthdate'] != null &&
        notEmpty('photoUrl') &&
        notEmpty('role');

    final roleOk = (d['role']?.toString() ?? '') == widget.requiredRole;

    // (optionnel) email vérifié :
    // final emailVerified = user.emailVerified == true;

    return hasAll && roleOk; // && emailVerified;
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
          // Profil incomplet ou mauvais rôle → forcer l’édition
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
