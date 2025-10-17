import 'package:flutter/material.dart';
import '../themes/app_theme.dart';

class DriverReviewsCarousel extends StatelessWidget {
  final List<Map<String, dynamic>> reviews;
  const DriverReviewsCarousel({super.key, required this.reviews});

  @override
  Widget build(BuildContext context) {
    if (reviews.isEmpty) {
      return const Text("Aucun avis de chauffeur pour le moment.",
          style: TextStyle(color: Colors.white38));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("📝 Avis des chauffeurs",
            style: TextStyle(
                color: AppColors.gold,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        SizedBox(
          height: 160,
          child: PageView.builder(
            controller: PageController(viewportFraction: 0.9),
            itemCount: reviews.length,
            itemBuilder: (_, i) {
              final r = reviews[i];
              final stars = "⭐️" * ((r['rating'] ?? 0) as int);
              final comment = (r['comment'] ?? '') as String;
              final ts = r['timestamp'];
              final date = ts != null ? (ts.toDate() as DateTime) : null;
              final dateStr = date != null ? "• ${date.day}/${date.month}" : "";
              return Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.gold.withOpacity(0.3)),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(stars, style: const TextStyle(color: Colors.amber)),
                      const SizedBox(height: 8),
                      Expanded(
                          child: Text(comment,
                              style: const TextStyle(color: Colors.white70))),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Text(dateStr,
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12)),
                      )
                    ]),
              );
            },
          ),
        ),
      ],
    );
  }
}
