import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

class UserModel extends Equatable {
  final String uid;
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String address;

  // ✅ OPTIONNEL
  final Timestamp? birthdate;

  final String? photoUrl;
  final String? identityCardUrl;
  final String role;
  final Timestamp createdAt;

  const UserModel({
    required this.uid,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.address,
    this.birthdate, // ✅ plus required
    this.photoUrl,
    this.identityCardUrl,
    this.role = 'passenger',
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'phone': phone,
      'address': address,
      'photoUrl': photoUrl,
      'identityCardUrl': identityCardUrl,
      'role': role,
      'createdAt': createdAt,
    };

    // ✅ on n’enregistre birthdate que si elle existe
    if (birthdate != null) {
      map['birthdate'] = birthdate;
    }

    return map;
  }

  factory UserModel.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel(
      uid: doc.id,
      firstName: data['firstName'] ?? '',
      lastName: data['lastName'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      address: data['address'] ?? '',

      // ✅ optionnel : si absent => null (PAS Timestamp.now())
      birthdate: data['birthdate'] as Timestamp?,

      photoUrl: data['photoUrl'],
      identityCardUrl: data['identityCardUrl'],
      role: data['role'] ?? 'passenger',
      createdAt: (data['createdAt'] as Timestamp?) ?? Timestamp.now(),
    );
  }

  @override
  List<Object?> get props => [
        uid,
        firstName,
        lastName,
        email,
        phone,
        address,
        birthdate,
        photoUrl,
        identityCardUrl,
        role,
        createdAt,
      ];
}
