import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminGuard extends StatefulWidget {
  final Widget child;
  const AdminGuard({super.key, required this.child});

  @override
  State<AdminGuard> createState() => _AdminGuardState();
}

class _AdminGuardState extends State<AdminGuard> {
  bool _loading = true;
  bool _allowed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _loading = false;
          _allowed = false;
          _error = "Non connecté";
        });
        return;
      }

      bool isSuperAdmin = false;

      // 🔁 Retry pour laisser le temps au claim de se propager (Flutter Web)
      for (int i = 0; i < 5; i++) {
        final token = await user.getIdTokenResult(true);
        final claims = token.claims ?? {};

        if (claims['super_admin'] == true) {
          isSuperAdmin = true;
          break;
        }

        await Future.delayed(const Duration(milliseconds: 500));
      }

      setState(() {
        _loading = false;
        _allowed = isSuperAdmin;
        _error = isSuperAdmin ? null : "Accès refusé (claim non propagé)";
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _allowed = false;
        _error = "Erreur: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFFFD700)),
        ),
      );
    }

    if (!_allowed) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Accès refusé",
                style: TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'PlayfairDisplay',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _error ?? "",
                style: const TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                  foregroundColor: Colors.black,
                ),
                onPressed: _check,
                child: const Text("Recharger les droits"),
              ),
            ],
          ),
        ),
      );
    }

    return widget.child;
  }
}
