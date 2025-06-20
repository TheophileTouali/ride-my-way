import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/splash_screen.dart';
import '../screens/login_screen.dart';
import '../screens/home_screen.dart';
import '../screens/location_permission_screen.dart';
import '../screens/signup_step1_screen.dart';
import '../screens/signup_step2_screen.dart';
import '../screens/signup_step3_screen.dart';
import '../screens/forgot_password_screen.dart';
import '../screens/reset_password_screen.dart';
import '../screens/passenger_profile_screen.dart';
import '../screens/edit_preferences_screen.dart';
import '../screens/reservations_screen.dart';
import '../screens/favorites_screen.dart';
import '../screens/results_screen.dart';
import '../screens/signup_driver_screen.dart'; // ✅ 
import '../screens/signup_screen.dart'; // ✅ 


class AppRoutes {
  static final router = GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/home',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/permission',
        builder: (context, state) => const LocationPermissionScreen(),
      ),
      GoRoute(
        path: '/signup-step1',
        builder: (context, state) => const SignupStep1Screen(),
      ),
      GoRoute(
        path: '/signup-step2',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is! Map<String, dynamic>) {
            return const Scaffold(
              body: Center(child: Text("Erreur : données manquantes")),
            );
          }

          return SignupStep2Screen(
            firstName: extra['firstName'],
            lastName: extra['lastName'],
            email: extra['email'],
          );
        },
      ),
      GoRoute(
        path: '/signup-step3',
        builder: (context, state) => const SignupStep3Screen(),
      ),
      GoRoute(
        path: '/forgot-password',
        name: 'forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/reset-password',
        name: 'reset-password',
        builder: (context, state) => const ResetPasswordScreen(),
      ),
      GoRoute(
        path: '/profile',
        name: 'profile',
        builder: (context, state) => const PassengerProfileScreen(),
      ),
      GoRoute(
        path: '/preferences',
        name: 'preferences',
        builder: (context, state) => const EditPreferencesScreen(),
      ),
      GoRoute(
        path: '/reservations',
        builder: (context, state) => const ReservationsScreen(),
      ),
      GoRoute(
        path: '/favorites',
        builder: (context, state) => const FavoritesScreen(),
      ),

      GoRoute(
  path: '/signup',
  builder: (context, state) => const SignupScreen(),
),
      GoRoute(
        path: '/results',
        builder: (context, state) {
          final from = state.uri.queryParameters['from'] ?? '';
          final to = state.uri.queryParameters['to'] ?? '';
          return ResultsScreen(from: from, to: to);
        },
      ),
      // ✅ Route pour le formulaire unique conducteur
      GoRoute(
        path: '/signup-driver',
        builder: (context, state) => const SignupDriverScreen(),
      ),
    ],
  );
}
