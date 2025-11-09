import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/chat_service.dart';
import '../themes/app_theme.dart';

/// Chat in-app (drivers ↔ passengers)
/// - messages visibles par défaut
/// - reset du compteur unread à l’ouverture
/// - auto-scroll en bas à chaque nouveau message
class ChatScreen extends StatefulWidget {
  final String chatId;
  final String? peerName; // optionnel (nom du destinataire)
  final String? peerPhotoUrl; // optionnel (avatar)
  const ChatScreen({
    super.key,
    required this.chatId,
    this.peerName,
    this.peerPhotoUrl,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _c = TextEditingController();
  final _focus = FocusNode();
  final _listCtl = ScrollController();
  final _service = ChatService.instance;

  late final String _me;
  StreamSubscription<List<Message>>? _sub;

  @override
  void initState() {
    super.initState();
    _me = FirebaseAuth.instance.currentUser?.uid ?? '';
    // Remise à zéro des unread immédiatement
    _service.resetUnread(chatId: widget.chatId, myUid: _me);
    // Suivre le flux pour auto-scroll et maintenir unread à 0
    _sub = _service.messagesStream(widget.chatId).listen((_) {
      _scrollToBottom();
      _service.resetUnread(chatId: widget.chatId, myUid: _me);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _c.dispose();
    _focus.dispose();
    _listCtl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_listCtl.hasClients) return;
      _listCtl.animateTo(
        _listCtl.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _c.text.trim();
    if (text.isEmpty) return;
    _c.clear();
    await _service.sendMessage(
      chatId: widget.chatId,
      senderId: _me,
      text: text,
    );
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.peerName ?? 'Chat';
    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.gold),
          onPressed: () => context.pop(),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.gold,
              backgroundImage: (widget.peerPhotoUrl != null &&
                      widget.peerPhotoUrl!.isNotEmpty)
                  ? NetworkImage(widget.peerPhotoUrl!)
                  : null,
              child: (widget.peerPhotoUrl == null)
                  ? const Icon(Icons.person, size: 18, color: Colors.black)
                  : null,
            ),
            const SizedBox(width: 10),
            ShaderMask(
              shaderCallback: (r) => const LinearGradient(
                colors: [Color(0xFFFFD700), Color(0xFFA87C00)],
              ).createShader(r),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontFamily: 'PlayfairDisplay',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Message>>(
              stream: _service.messagesStream(widget.chatId),
              builder: (context, snap) {
                final items = snap.data ?? const <Message>[];
                if (items.isEmpty) {
                  return const _EmptyState();
                }
                return ListView.builder(
                  key: ValueKey(items.length),
                  controller: _listCtl,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final m = items[i];
                    final mine = m.senderId == _me;
                    final prev = i > 0 ? items[i - 1] : null;
                    final showAvatar =
                        !mine && (prev == null || prev.senderId != m.senderId);
                    return _Bubble(
                      text: m.text,
                      mine: mine,
                      showAvatar: showAvatar,
                      peerPhotoUrl: widget.peerPhotoUrl,
                      time: m.createdAt?.toDate(),
                    );
                  },
                );
              },
            ),
          ),
          _Composer(
            controller: _c,
            focusNode: _focus,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

/// =================== UI widgets ===================

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Opacity(
        opacity: .8,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.chat_bubble_outline, color: AppColors.gold, size: 48),
            SizedBox(height: 10),
            Text(
              "Démarre la conversation ✨",
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final String text;
  final bool mine;
  final bool showAvatar;
  final String? peerPhotoUrl;
  final DateTime? time;

  const _Bubble({
    required this.text,
    required this.mine,
    required this.showAvatar,
    required this.peerPhotoUrl,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    final bg = mine ? null : Colors.white.withOpacity(.06);
    final gradient = mine
        ? const LinearGradient(
            colors: [AppColors.gold, AppColors.deepGold],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : null;

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(mine ? 16 : 4),
      bottomRight: Radius.circular(mine ? 4 : 16),
    );

    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        gradient: gradient,
        borderRadius: radius,
        border: Border.all(
          color: mine ? Colors.transparent : Colors.white12,
          width: 1,
        ),
        boxShadow: mine
            ? [
                BoxShadow(
                  color: AppColors.gold.withOpacity(.18),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                )
              ]
            : null,
      ),
      child: Text(
        text,
        style: TextStyle(
          color: mine ? Colors.black : Colors.white,
          fontWeight: FontWeight.w600,
          height: 1.25,
        ),
      ),
    );

    final timeStr = (time == null)
        ? ''
        : "${time!.hour.toString().padLeft(2, '0')}:${time!.minute.toString().padLeft(2, '0')}";

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!mine) ...[
            if (showAvatar)
              CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.gold,
                backgroundImage:
                    (peerPhotoUrl != null && peerPhotoUrl!.isNotEmpty)
                        ? NetworkImage(peerPhotoUrl!)
                        : null,
                child: (peerPhotoUrl == null)
                    ? const Icon(Icons.person, size: 16, color: Colors.black)
                    : null,
              )
            else
              const SizedBox(width: 28),
            const SizedBox(width: 8),
          ],
          Flexible(child: bubble),
          const SizedBox(width: 8),
          Opacity(
            opacity: .6,
            child: Text(
              timeStr,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final Future<void> Function() onSend;

  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.onSend,
  });

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final v = widget.controller.text.trim().isNotEmpty;
    if (v != _canSend) setState(() => _canSend = v);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0E0E0E),
          border: const Border(top: BorderSide(color: Colors.white12)),
          boxShadow: [
            BoxShadow(
              color: AppColors.gold.withOpacity(.06),
              blurRadius: 12,
              offset: const Offset(0, -4),
            )
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                minLines: 1,
                maxLines: 5,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Écrire un message…",
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF121214),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide:
                        const BorderSide(color: AppColors.gold, width: 1.2),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: _canSend ? widget.onSend : null,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    colors: _canSend
                        ? const [AppColors.gold, AppColors.deepGold]
                        : [Colors.black, Colors.black.withOpacity(.85)],
                  ),
                  border: Border.all(
                    color: _canSend
                        ? AppColors.gold.withOpacity(.55)
                        : Colors.white12,
                  ),
                ),
                child: Icon(
                  Icons.send_rounded,
                  size: 20,
                  color: _canSend ? Colors.black : Colors.white54,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
