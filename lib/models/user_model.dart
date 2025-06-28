import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

class UserModel extends Equatable {
  final String uid;
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String address;
  final Timestamp birthdate;
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
    required this.birthdate,
    this.photoUrl,
    this.identityCardUrl,
    this.role = 'passenger',
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'phone': phone,
        'address': address,
        'birthdate': birthdate,
        'photoUrl': photoUrl,
        'identityCardUrl': identityCardUrl,
        'role': role,
        'createdAt': createdAt,
      };

  factory UserModel.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel(
      uid: doc.id,
      firstName: data['firstName'] ?? '',
      lastName: data['lastName'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      address: data['address'] ?? '',
      birthdate: data['birthdate'] ?? Timestamp.now(),
      photoUrl: data['photoUrl'],
      identityCardUrl: data['identityCardUrl'],
      role: data['role'] ?? 'passenger',
      createdAt: data['createdAt'] ?? Timestamp.now(),
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
