import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/user_provider.dart';
import '../screens/splash_screen.dart';
import '../screens/login_screen.dart';
import '../screens/home_screen.dart';
import '../screens/location_permission_screen.dart';
import '../screens/signup_step1_screen.dart';
import '../screens/signup_step2_screen.dart';
import '../screens/signup_step3_screen.dart';

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
        builder: (context, state) => const SignupStep2Screen(),
      ),
      GoRoute(
        path: '/signup-step3',
        builder: (context, state) => const SignupStep3Screen(),
      ),
    ],
  );
}
