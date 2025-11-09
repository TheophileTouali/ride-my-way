// lib/services/chat_service.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

/// ===============================
/// Modèles légers
/// ===============================

class Chat {
  final String id;
  final List<String> members; // [driverUid, passengerUid] (triés)
  final String? rideId; // reservationId optionnel
  final String lastMessage;
  final Timestamp? lastAt;
  final Map<String, int> unread; // { uid: count }
  final Map<String, dynamic> data; // payload brut si besoin

  Chat({
    required this.id,
    required this.members,
    required this.rideId,
    required this.lastMessage,
    required this.lastAt,
    required this.unread,
    required this.data,
  });

  String otherOf(String me) =>
      members.firstWhere((u) => u != me, orElse: () => me);

  factory Chat.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    return Chat(
      id: doc.id,
      members: List<String>.from(d['members'] ?? const <String>[]),
      rideId: d['rideId']?.toString(),
      lastMessage: (d['lastMessage'] ?? '').toString(),
      lastAt: d['lastAt'] as Timestamp?,
      unread: Map<String, int>.from(d['unread'] ?? const <String, int>{}),
      data: d,
    );
  }
}

class Message {
  final String id;
  final String senderId;
  final String text;
  final String type; // "text" | "image" (future-proof)
  final Timestamp? createdAt;

  Message({
    required this.id,
    required this.senderId,
    required this.text,
    required this.type,
    required this.createdAt,
  });

  factory Message.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    return Message(
      id: doc.id,
      senderId: (d['senderId'] ?? '').toString(),
      text: (d['text'] ?? '').toString(),
      type: (d['type'] ?? 'text').toString(),
      createdAt: d['createdAt'] as Timestamp?,
    );
  }
}

/// ===============================
/// Service de chat (singleton)
/// ===============================

class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();

  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _chats =>
      _db.collection('chats');

  /// Crée ou récupère le chat entre driverId et passengerId (idempotent).
  /// Si rideId est fourni, on associe la conversation au trajet.
  Future<String> openChat({
    required String driverId,
    required String passengerId,
    String? rideId,
  }) async {
    // On trie pour garantir un ordre stable des membres
    final members = [driverId, passengerId]..sort();

    // 1) Cherche un chat existant avec ces 2 membres (+ même rideId si fourni)
    final query = await _chats
        .where('members', arrayContains: driverId)
        .orderBy('lastAt', descending: true)
        .limit(25)
        .get();

    for (final d in query.docs) {
      final m = List<String>.from(d.data()['members'] ?? const <String>[])
        ..sort();
      final sameRide = (rideId == null) || (d.data()['rideId'] == rideId);
      if (m.length == 2 &&
          m[0] == members[0] &&
          m[1] == members[1] &&
          sameRide) {
        return d.id;
      }
    }

    // 2) Sinon on crée
    final now = FieldValue.serverTimestamp();
    final doc = await _chats.add({
      'members': members,
      if (rideId != null) 'rideId': rideId,
      'createdAt': now,
      'lastAt': now,
      'lastMessage': '',
      'unread': {driverId: 0, passengerId: 0},
    });
    return doc.id;
  }

  /// Helper : ouvre/assure un chat lié à une réservation
  Future<String> openChatFromReservation({
    required String reservationId,
    required String driverId,
    required String passengerId,
  }) {
    return openChat(
      driverId: driverId,
      passengerId: passengerId,
      rideId: reservationId,
    );
  }

  /// Liste des conversations d’un utilisateur, triées par lastAt desc.
  /// ⚠️ Nécessite un index composite (array-contains + orderBy lastAt).
  Stream<List<Chat>> myChatsStream(String myUid) {
    return _chats
        .where('members', arrayContains: myUid)
        .orderBy('lastAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(Chat.fromDoc).toList());
  }

  /// Flux des messages d’un chat (ordre ascendant pour l’affichage naturel).
  Stream<List<Message>> messagesStream(String chatId) {
    return _chats
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((s) => s.docs.map(Message.fromDoc).toList());
  }

  /// Envoi d’un message texte (message visible par défaut).
  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required String text,
  }) async {
    final ts = FieldValue.serverTimestamp();
    final msgRef = _chats.doc(chatId).collection('messages').doc();
    final chatRef = _chats.doc(chatId);

    await _db.runTransaction((tx) async {
      // 1) Créer le message
      tx.set(msgRef, {
        'senderId': senderId,
        'text': text.trim(),
        'type': 'text',
        'createdAt': ts,
      });

      // 2) Récupérer le chat pour connaître l’autre membre
      final chatSnap = await tx.get(chatRef);
      if (!chatSnap.exists) return;
      final data = chatSnap.data() as Map<String, dynamic>;
      final members = List<String>.from(data['members'] ?? const <String>[]);
      final other =
          members.firstWhere((u) => u != senderId, orElse: () => senderId);

      final unread = Map<String, dynamic>.from(data['unread'] ?? {});
      final current = (unread[other] ?? 0) as int;

      // 3) Mettre à jour le chat
      tx.update(chatRef, {
        'lastMessage': text.trim(),
        'lastAt': ts,
        'unread.$other': current + 1,
      });
    });
  }

  /// Reset du compteur de non-lus pour l’utilisateur courant (à l’ouverture du chat).
  Future<void> resetUnread({
    required String chatId,
    required String myUid,
  }) async {
    final chatRef = _chats.doc(chatId);
    await _db.runTransaction((tx) async {
      final s = await tx.get(chatRef);
      if (!s.exists) return;
      tx.update(chatRef, {'unread.$myUid': 0});
    });
  }
}
