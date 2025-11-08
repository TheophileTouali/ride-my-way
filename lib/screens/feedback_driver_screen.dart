import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../themes/app_theme.dart';

class DriverFeedbackScreen extends StatefulWidget {
  final String reservationId;
  const DriverFeedbackScreen({super.key, required this.reservationId});

  @override
  State<DriverFeedbackScreen> createState() => _DriverFeedbackScreenState();
}

class _DriverFeedbackScreenState extends State<DriverFeedbackScreen>
    with SingleTickerProviderStateMixin {
  double _rating = 0;
  final _commentController = TextEditingController();
  bool _isSubmitting = false;
  bool _recommend = true;

  Map<String, dynamic>? _reservationData;
  Map<String, dynamic>? _passengerData;

  late AnimationController _controller;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _loadReservationData();
  }

  Future<void> _loadReservationData() async {
    try {
      final resSnap = await FirebaseFirestore.instance
          .collection('reservations')
          .doc(widget.reservationId)
          .get();

      if (resSnap.exists) {
        _reservationData = resSnap.data();
        final userId = _reservationData!['userId'];
        if (userId != null) {
          final userSnap = await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .get();
          if (userSnap.exists) _passengerData = userSnap.data();
        }
        if (mounted) setState(() {});
        _controller.forward();
      }
    } catch (e) {
      debugPrint("Erreur chargement : $e");
    }
  }

  Future<void> _submitFeedback() async {
    if (_isSubmitting ||
        _rating == 0 ||
        _reservationData == null ||
        _passengerData == null) return;

    setState(() => _isSubmitting = true);

    final feedbackData = {
      'reservationId': widget.reservationId,
      'driverId': _reservationData!['driverId'],
      'passengerId': _reservationData!['userId'],
      'fromDriver': true,
      'rating': _rating,
      'comment': _commentController.text.trim(),
      'recommend': _recommend,
      'timestamp': FieldValue.serverTimestamp(),
    };

    await FirebaseFirestore.instance.collection('feedbacks').add(feedbackData);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: const [
            Icon(Icons.check_circle_rounded, color: AppColors.gold),
            SizedBox(width: 12),
            Expanded(
              child: Text("Merci pour votre évaluation !",
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        backgroundColor: Colors.black.withOpacity(0.95),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.gold, width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        duration: const Duration(seconds: 3),
        elevation: 12,
      ),
    );
    context.go('/driver-home');
  }

  @override
  Widget build(BuildContext context) {
    if (_reservationData == null || _passengerData == null) {
      return const Scaffold(
        backgroundColor: AppColors.black,
        body: Center(child: CircularProgressIndicator(color: AppColors.gold)),
      );
    }

    final from = _reservationData!['from'] ?? 'Départ inconnu';
    final to = _reservationData!['to'] ?? 'Arrivée inconnue';
    final price = (_reservationData!['price'] ?? 0).toDouble();
    final timestamp = _reservationData!['timestamp'];
    final date = timestamp is Timestamp
        ? DateFormat.yMMMMd('fr_FR').add_Hm().format(timestamp.toDate())
        : 'Date inconnue';

    final passengerName =
        "${_passengerData!['firstName'] ?? ''} ${_passengerData!['lastName'] ?? ''}"
            .trim();
    final passengerPhoto = _passengerData!['photoUrl'];

    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: _PremiumAppBar(title: "Noter le passager"),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Stack(
          children: [
            // Disques doux pour profondeur
            const _AmbientDiscs(),
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HeaderTripCard(
                    date: date,
                    price: "${price.toStringAsFixed(2)} €",
                    from: from,
                    to: to,
                  ),
                  const SizedBox(height: 18),
                  _PassengerCard(name: passengerName, photoUrl: passengerPhoto),

                  const SizedBox(height: 26),
                  const _SectionTitle(text: "Attribuez une note"),
                  const SizedBox(height: 10),

                  // Zone de rating premium avec halo
                  _RatingHalo(
                    child: RatingBar.builder(
                      initialRating: 0,
                      minRating: 1,
                      allowHalfRating: false,
                      itemCount: 5,
                      unratedColor: Colors.white12,
                      itemPadding: const EdgeInsets.symmetric(horizontal: 8),
                      itemBuilder: (context, _) => const Icon(
                        Icons.star_rounded,
                        size: 36,
                        color: AppColors.gold,
                      ),
                      onRatingUpdate: (rating) =>
                          setState(() => _rating = rating),
                    ),
                  ),

                  const SizedBox(height: 22),
                  const _SectionTitle(text: "Préférence"),
                  const SizedBox(height: 10),
                  _RecommendRow(
                    value: _recommend,
                    onChanged: (v) => setState(() => _recommend = v),
                  ),

                  const SizedBox(height: 22),
                  const _SectionTitle(text: "Commentaire (optionnel)"),
                  const SizedBox(height: 10),
                  _PremiumTextField(controller: _commentController),

                  const SizedBox(height: 26),
                  _ShinyCTA(
                    text: _isSubmitting ? "Envoi..." : "Envoyer la note",
                    enabled: _rating != 0 && !_isSubmitting,
                    onPressed:
                        _rating == 0 || _isSubmitting ? null : _submitFeedback,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    _controller.dispose();
    super.dispose();
  }
}

// -------------------- UI Premium widgets --------------------

class _PremiumAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  const _PremiumAppBar({required this.title});

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.black,
      elevation: 0,
      centerTitle: true,
      title: ShaderMask(
        shaderCallback: (rect) => const LinearGradient(
          colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
        ).createShader(rect),
        child: Text(
          "🛎️ $title",
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 20,
            fontFamily: "PlayfairDisplay",
            letterSpacing: .2,
          ),
        ),
      ),
    );
  }
}

class _AmbientDiscs extends StatelessWidget {
  const _AmbientDiscs();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -80,
            left: -60,
            child: _BlurDisc(size: 220, color: AppColors.gold.withOpacity(.10)),
          ),
          Positioned(
            bottom: -60,
            right: -40,
            child: _BlurDisc(size: 180, color: Colors.white.withOpacity(.06)),
          ),
        ],
      ),
    );
  }
}

class _BlurDisc extends StatelessWidget {
  final double size;
  final Color color;
  const _BlurDisc({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(width: size, height: size, color: color),
      ),
    );
  }
}

class _HeaderTripCard extends StatelessWidget {
  final String date;
  final String price;
  final String from;
  final String to;

  const _HeaderTripCard({
    required this.date,
    required this.price,
    required this.from,
    required this.to,
  });

  @override
  Widget build(BuildContext context) {
    return _Glass(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // bandeau or léger
          Container(
            height: 6,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0x33FFD700), Color(0x33A87C00)],
              ),
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  date,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    letterSpacing: .2,
                  ),
                ),
              ),
              _PricePill(text: price),
            ],
          ),
          const SizedBox(height: 12),
          _TripChips(from: from, to: to),
        ],
      ),
    );
  }
}

class _PricePill extends StatelessWidget {
  final String text;
  const _PricePill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
        ),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withOpacity(.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _TripChips extends StatelessWidget {
  final String from;
  final String to;
  const _TripChips({required this.from, required this.to});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Chip(icon: Icons.trip_origin_rounded, label: from),
        const SizedBox(width: 10),
        const Icon(Icons.chevron_right_rounded, color: Colors.white24),
        const SizedBox(width: 10),
        _Chip(icon: Icons.flag_rounded, label: to),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Chip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.gold),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PassengerCard extends StatelessWidget {
  final String name;
  final String? photoUrl;
  const _PassengerCard({required this.name, required this.photoUrl});

  @override
  Widget build(BuildContext context) {
    return _Glass(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundImage: photoUrl != null
                ? NetworkImage(photoUrl!)
                : const AssetImage('assets/images/avatar_placeholder.png')
                    as ImageProvider,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? "Passager" : name,
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    fontFamily: "PlayfairDisplay",
                  ),
                ),
                const SizedBox(height: 4),
                const Text("Votre passager",
                    style: TextStyle(color: Colors.white54, fontSize: 13)),
              ],
            ),
          ),
          const Icon(Icons.verified_rounded, color: AppColors.gold),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
                color: AppColors.gold, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}

class _RatingHalo extends StatefulWidget {
  final Widget child;
  const _RatingHalo({required this.child});

  @override
  State<_RatingHalo> createState() => _RatingHaloState();
}

class _RatingHaloState extends State<_RatingHalo>
    with SingleTickerProviderStateMixin {
  late AnimationController _a;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _a = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: .12, end: .28).animate(
      CurvedAnimation(parent: _a, curve: Curves.easeInOut),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.03),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
          boxShadow: [
            BoxShadow(
              color: AppColors.gold.withOpacity(_pulse.value),
              blurRadius: 24,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Center(child: widget.child),
      ),
    );
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }
}

class _RecommendRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _RecommendRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return _Glass(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.thumb_up_alt_rounded, color: AppColors.gold),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              "Recommander ce passager",
              style: TextStyle(color: Colors.white70, fontSize: 15),
            ),
          ),
          Switch(
            value: value,
            activeColor: AppColors.gold,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _PremiumTextField extends StatelessWidget {
  final TextEditingController controller;
  const _PremiumTextField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return _Glass(
      padding: EdgeInsets.zero,
      child: TextField(
        controller: controller,
        maxLines: 4,
        maxLength: 250,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: "💬 Laisser un commentaire (optionnel)",
          hintStyle: const TextStyle(color: Colors.white54),
          counterStyle: const TextStyle(color: Colors.white38),
          contentPadding: const EdgeInsets.all(14),
          border: OutlineInputBorder(
            borderSide: BorderSide.none,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class _ShinyCTA extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool enabled;
  const _ShinyCTA(
      {required this.text, required this.onPressed, required this.enabled});

  @override
  State<_ShinyCTA> createState() => _ShinyCTAState();
}

class _ShineTransform extends GradientTransform {
  final double dx;
  const _ShineTransform(this.dx);

  @override
  Matrix4? transform(Rect bounds, {ui.TextDirection? textDirection}) {
    return Matrix4.translationValues(dx, 0, 0);
  }
}

class _ShinyCTAState extends State<_ShinyCTA>
    with SingleTickerProviderStateMixin {
  late AnimationController _a;

  @override
  void initState() {
    super.initState();
    _a = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  Widget build(BuildContext context) {
    final base = Container(
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withOpacity(.35),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Text(
        widget.text,
        style: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w900,
          letterSpacing: .2,
        ),
      ),
    );

    final shine = AnimatedBuilder(
      animation: _a,
      builder: (_, __) {
        return ShaderMask(
          shaderCallback: (rect) {
            final t = _a.value;
            final dx = rect.width * (t * 1.3 - 0.15);
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.white.withOpacity(0.0),
                Colors.white.withOpacity(0.6),
                Colors.white.withOpacity(0.0),
              ],
              stops: const [0.45, 0.5, 0.55],
              transform: _ShineTransform(dx),
            ).createShader(rect);
          },
          blendMode: BlendMode.srcATop,
          child: base,
        );
      },
    );

    return Opacity(
      opacity: widget.enabled ? 1 : .5,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onPressed : null,
        child: shine,
      ),
    );
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }
}

class _Glass extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _Glass({required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.045),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.35),
            blurRadius: 30,
            spreadRadius: 0,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}
