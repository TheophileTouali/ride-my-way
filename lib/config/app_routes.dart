import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// Import des écrans
import '../screens/splash_screen.dart';
import '../screens/login_screen.dart';
import '../screens/login_driver_screen.dart';
import '../screens/home_screen.dart';
import '../screens/location_permission_screen.dart';
import '../screens/signup_step1_screen.dart';
import '../screens/signup_step2_screen.dart';
import '../screens/signup_step3_screen.dart';
import '../screens/forgot_password_screen.dart';
import '../screens/reset_password_screen.dart';
import '../screens/passenger_profile_screen.dart';
import '../screens/driver_profile_screen.dart';
import '../screens/edit_preferences_screen.dart';
import '../screens/passenger_preferences_editor_screen.dart';
import '../screens/reservations_screen.dart';
import '../screens/favorites_screen.dart';
import '../screens/results_screen.dart';
import '../screens/signup_driver_screen.dart';
import '../screens/signup_screen.dart';
import '../screens/driver_home_screen.dart';
import '../screens/confirmation_screen.dart'; 
import '../screens/booking_success_screen.dart';
import '../screens/driver_search_screen.dart';
import '../screens/live_tracking_screen.dart';
import '../screens/live_tracking_passenger_screen.dart';
import '../screens/driver_trip_detail_screen.dart';
import '../screens/driver_pickup_tracking_screen.dart';
import '../screens/feedback_screen.dart';
import '../screens/feedback_driver_screen.dart';






// 👈 ajoute ce fichier à ton projet

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
        path: '/login-driver',
        builder: (context, state) => const DriverLoginScreen(),
      ),
      GoRoute(
        path: '/preferences-edit',
        builder: (context, state) => const PassengerPreferencesEditorScreen(),
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
          final extra = state.extra as Map<String, dynamic>?;
          if (extra == null) {
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
        path: '/driver-profile',
        name: 'driver-profile',
        builder: (context, state) => const DriverProfileScreen(),
      ),
      GoRoute(
        path: '/driver-home',
        name: 'driver-home',
        builder: (context, state) => const DriverHomeScreen(),
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
        path: '/signup-driver',
        builder: (context, state) => const SignupDriverScreen(),
      ),
      GoRoute(
        path: '/results',
        builder: (context, state) {
          final from = state.uri.queryParameters['from'] ?? '';
          final to = state.uri.queryParameters['to'] ?? '';
          return ResultsScreen(from: from, to: to);
        },
      ),
      GoRoute(
        path: '/confirmation',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return ConfirmationScreen(
            from: extra['from'],
            to: extra['to'],
            vehicle: extra['vehicle'],
            price: extra['price'],
            distance: extra['distance'],
          );
        },
      ),
            GoRoute(
        path: '/success',
        builder: (context, state) => const BookingSuccessScreen(),
      ),

      GoRoute(
      path: '/driver/live_tracking/:reservationId',
      builder: (context, state) => LiveTrackingScreen(
        reservationId: state.pathParameters['reservationId']!,
      ),
    ),

   GoRoute(
      path: '/tracking/:reservationId',
      name: 'tracking',
      builder: (context, state) {
        final id = state.pathParameters['reservationId']!;
        return LiveTrackingPassengerScreen(reservationId: id);
      },
    ),



    GoRoute(
      path: '/driver/trip/:reservationId',
      builder: (context, state) {
        final reservationId = state.pathParameters['reservationId']!;
        return DriverTripDetailScreen(reservationId: reservationId);
      },
    ),

    GoRoute(
      path: '/driver/pickup_tracking/:id',
      name: 'driver-pickup-tracking',
      builder: (context, state) {
        final reservationId = state.pathParameters['id']!;
        return DriverPickupTrackingScreen(reservationId: reservationId);
      },
    ),


      GoRoute(
      path: '/searching',
      builder: (context, state) {
        final reservationId = state.uri.queryParameters['reservationId']!;
        return DriverSearchScreen(reservationId: reservationId);
      },
    ),

    GoRoute(
      path: '/feedback/:reservationId',
      builder: (context, state) {
        final reservationId = state.pathParameters['reservationId']!;
        return PassengerFeedbackScreen(reservationId: reservationId); // ✅ Corrigé
      },
    ),


    GoRoute(
        path: '/feedback-driver/:reservationId',
        builder: (context, state) => DriverFeedbackScreen(
          reservationId: state.pathParameters['reservationId']!, // ✅ Corrigé
        ),
      ),




    ],
  );
}
