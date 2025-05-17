import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/user_provider.dart';
import '../themes/app_theme.dart';

class LocationPermissionScreen extends StatefulWidget {
  const LocationPermissionScreen({super.key});

  @override
  State<LocationPermissionScreen> createState() => _LocationPermissionScreenState();
}

class _LocationPermissionScreenState extends State<LocationPermissionScreen> {
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final status = await Permission.location.status;
    if (status.isGranted) {
      _redirectAccordingToLogin();
    } else {
      setState(() => _checking = false);
    }
  }

  Future<void> _requestPermission() async {
    final result = await Permission.location.request();
    if (result.isGranted) {
      _redirectAccordingToLogin();
    } else if (result.isPermanentlyDenied) {
      openAppSettings();
    }
  }

  void _redirectAccordingToLogin() {
    final isLoggedIn = Provider.of<UserProvider>(context, listen: false).isLoggedIn;
    context.go(isLoggedIn ? '/home' : '/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      body: _checking
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.location_on, size: 100, color: AppColors.gold),
                const SizedBox(height: 24),
                const Text(
                  "Activer la géolocalisation en temps réel",
                  style: TextStyle(
                    fontSize: 22,
                    color: AppColors.gold,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'PlayfairDisplay',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  "Autorisez Ride My Way à accéder à votre position",
                  style: TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: _redirectAccordingToLogin,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      child: const Text("Refuser"),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: _requestPermission,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: AppColors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      child: const Text("Autoriser"),
                    ),
                  ],
                )
              ],
            ),
    );
  }
}
