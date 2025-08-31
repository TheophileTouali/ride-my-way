import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../themes/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';

class DriverSearchScreen extends StatefulWidget {
  final String reservationId;

  const DriverSearchScreen({super.key, required this.reservationId});

  @override
  State<DriverSearchScreen> createState() => _DriverSearchScreenState();
}

class _DriverSearchScreenState extends State<DriverSearchScreen> with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;
  late Timer _messageTimer;
  late Timer _timeoutTimer;
  late Timer _autoRetryTimer;

  final List<String> _searchMessages = [
    "Recherche d’un chauffeur en cours...",
    "Un instant, nous contactons nos meilleurs chauffeurs...",
    "Nous sélectionnons les profils les plus adaptés pour vous...",
    "Votre trajet sur mesure est entre de bonnes mains...",
    "Recherche en cours dans notre réseau de chauffeurs d’exception...",
    "Nous préparons votre expérience de trajet premium...",
    "Un moment de patience, nous finalisons votre trajet idéal...",
    "Votre demande est transmise à nos chauffeurs de confiance...",
    "Nous orchestrons votre voyage avec soin et précision...",
    "Sélection en cours parmi nos chauffeurs les plus recommandés...",
  ];

  int _currentMessageIndex = 0;
  bool _searchExpired = false;
  bool _showAutoRetryToast = false;
  bool _showDriverFoundMessage = false;

  final AudioPlayer player = AudioPlayer();

  Future<void> _playDriverFoundSound() async {
    await player.setAsset('assets/sounds/driver_found.mp3');
    player.play();
  }

  @override
  void initState() {
    super.initState();

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    _messageTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      setState(() {
        _currentMessageIndex = (_currentMessageIndex + 1) % _searchMessages.length;
      });
    });

    _timeoutTimer = Timer(const Duration(minutes: 5), () {
      setState(() => _searchExpired = true);
    });

    _autoRetryTimer = Timer(const Duration(minutes: 6), () async {
      if (mounted && _searchExpired) {
        setState(() => _showAutoRetryToast = true);
        await Future.delayed(const Duration(seconds: 2));
        await _retrySearch();
        if (mounted) setState(() => _showAutoRetryToast = false);
      }
    });
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _messageTimer.cancel();
    _timeoutTimer.cancel();
    _autoRetryTimer.cancel();
    player.dispose();
    super.dispose();
  }

  Future<void> _retrySearch() async {
    await FirebaseFirestore.instance
        .collection('reservations')
        .doc(widget.reservationId)
        .update({'createdAt': FieldValue.serverTimestamp()});

    setState(() {
      _searchExpired = false;
      _currentMessageIndex = 0;
    });

    _timeoutTimer.cancel();
    _timeoutTimer = Timer(const Duration(minutes: 5), () {
      setState(() => _searchExpired = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('reservations')
            .doc(widget.reservationId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data!.exists) {
            final data = snapshot.data!.data() as Map<String, dynamic>;
            final status = data['status'];
            final driverId = data['driverId'];

            if (status == 'Confirmée' || (driverId != null && driverId.toString().isNotEmpty)) {
              if (!_showDriverFoundMessage) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() => _showDriverFoundMessage = true);
                  _playDriverFoundSound();
                  Future.delayed(const Duration(seconds: 1), () {
                    if (mounted) context.go('/reservations');
                  });
                });
              }
            }
          }

          return _buildSearchUI();
        },
      ),
    );
  }

  Widget _buildSearchUI() {
    if (_showDriverFoundMessage) {
      return Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 30, end: 0),
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOut,
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, value),
              child: child,
            );
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.95),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.gold.withOpacity(0.4)),
            ),
            child: const Text(
              "✨ Chauffeur trouvé ! Préparation de votre trajet...",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.gold,
                fontWeight: FontWeight.w600,
                fontFamily: 'PlayfairDisplay',
                fontSize: 18,
              ),
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 🌟 Halo + loupe animée
                Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(seconds: 2),
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.gold.withOpacity(0.35),
                            blurRadius: 45,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                    ),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 1.0, end: 1.06),
                      duration: const Duration(seconds: 2),
                      curve: Curves.easeInOut,
                      builder: (context, scale, _) {
                        return Transform.scale(
                          scale: scale,
                          child: RotationTransition(
                            turns: _rotationController,
                            child: const Icon(
                              Icons.search_rounded,
                              size: 76,
                              color: AppColors.gold,
                              shadows: [
                                Shadow(blurRadius: 24, color: Colors.amber),
                                Shadow(blurRadius: 40, color: Colors.deepOrangeAccent),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Texte doré animé
                SizedBox(
                  height: 56,
                  width: double.infinity,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 800),
                      transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                      child: ShaderMask(
                        key: ValueKey(_searchMessages[_currentMessageIndex]),
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ).createShader(bounds),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Text(
                            _searchMessages[_currentMessageIndex],
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'PlayfairDisplay',
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                            softWrap: true,
                            overflow: TextOverflow.fade,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _searchExpired
                      ? "Il arrive parfois que nos chauffeurs soient déjà engagés.\nEssayez de nouveau, nous trouverons le bon profil pour vous."
                      : "Veuillez patienter...",
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    fontFamily: 'PlayfairDisplay',
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_searchExpired)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: ElevatedButton.icon(
                      onPressed: _retrySearch,
                      icon: const Icon(Icons.refresh, color: Colors.black),
                      label: const Text(
                        "Relancer",
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'PlayfairDisplay',
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_showAutoRetryToast)
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: AnimatedOpacity(
              opacity: 1.0,
              duration: const Duration(milliseconds: 500),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.gold.withOpacity(0.3)),
                ),
                child: const Center(
                  child: Text(
                    "Relance automatique en cours...",
                    style: TextStyle(
                      color: AppColors.gold,
                      fontFamily: 'PlayfairDisplay',
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
