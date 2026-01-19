// lib/admin/widgets/doc_preview.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:url_launcher/url_launcher.dart';

class DocPreview {
  static String cacheBust(String url) {
    final sep = url.contains('?') ? '&' : '?';
    return '$url${sep}ts=${DateTime.now().millisecondsSinceEpoch}';
  }

  static String _extFromUrl(String url) {
    final q = url.split('?').first;
    final i = q.lastIndexOf('.');
    return (i >= 0 ? q.substring(i + 1) : '').toLowerCase();
  }

  static bool isPdfUrl(String url) {
    final ext = _extFromUrl(url);
    return ext == 'pdf' ||
        url.toLowerCase().contains('content-type=application/pdf');
  }

  static bool isImageUrl(String url) {
    if (isPdfUrl(url)) return false;
    final ext = _extFromUrl(url);
    if (const ['png', 'jpg', 'jpeg', 'webp', 'gif'].contains(ext)) return true;

    final lower = url.toLowerCase();
    // Firebase download urls
    return lower.contains('alt=media') || lower.contains('firebasestorage');
  }

  static Future<String> resolveStorageUrl(String url) async {
    final u = url.trim();
    if (u.isEmpty) return '';

    if (u.startsWith('http://') || u.startsWith('https://')) return u;

    if (u.startsWith('gs://')) {
      return FirebaseStorage.instance.refFromURL(u).getDownloadURL();
    }

    // fallback (parfois tu stockes déjà un path custom)
    return u;
  }

  static Future<void> openExternal(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<void> openDocumentPreview(
    BuildContext context,
    String rawUrl, {
    String? title,
  }) async {
    final resolved = await resolveStorageUrl(rawUrl);
    if (resolved.isEmpty) return;

    final isImage = isImageUrl(resolved);
    if (!isImage) {
      // PDF ou autre => externe
      await openExternal(resolved);
      return;
    }

    final bust = cacheBust(resolved);

    // Image => dialog + zoom
    // ignore: use_build_context_synchronously
    await showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(color: Colors.black.withOpacity(.55)),
                ),
              ),
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 6,
                  child: Image.network(
                    bust,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Text(
                        "Impossible d’afficher ce document",
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const Center(
                        child:
                            CircularProgressIndicator(color: Color(0xFFFFD700)),
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                left: 10,
                top: 10,
                right: 10,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title ?? "Prévisualisation",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
