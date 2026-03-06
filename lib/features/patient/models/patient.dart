import 'package:equatable/equatable.dart';

/// Core Patient domain model.
///
/// Stored encrypted in the local SQLCipher database and synced
/// to the NHA backend when connectivity is available.
class Patient extends Equatable {
  const Patient({
    required this.id,
    required this.fullName,
    required this.age,
    required this.gender,
    this.aadhaarLast4,
    this.village,
    this.district,
    this.state,
    this.phone,
    this.photoPath,
    required this.createdAt,
    required this.updatedAt,
    this.isSynced = false,
    this.abhaNumber,
  });

  final String id;
  final String fullName;
  final int age;
  final String gender;
  final String? aadhaarLast4;
  final String? village;
  final String? district;
  final String? state;
  final String? phone;
  final String? photoPath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isSynced;
  final String? abhaNumber;

  // ── Serialization ──────────────────────────────────────────

  Map<String, dynamic> toMap() => {
        'id': id,
        'full_name': fullName,
        'age': age,
        'gender': gender,
        'aadhaar_last4': aadhaarLast4,
        'village': village,
        'district': district,
        'state': state,
        'phone': phone,
        'photo_path': photoPath,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'is_synced': isSynced ? 1 : 0,
      };

  factory Patient.fromMap(Map<String, dynamic> map) => Patient(
        id: map['id'] as String,
        fullName: map['full_name'] as String,
        age: map['age'] as int,
        gender: map['gender'] as String,
        aadhaarLast4: map['aadhaar_last4'] as String?,
        village: map['village'] as String?,
        district: map['district'] as String?,
        state: map['state'] as String?,
        phone: map['phone'] as String?,
        photoPath: map['photo_path'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
        isSynced: (map['is_synced'] as int? ?? 0) == 1,
      );

  Patient copyWith({
    String? fullName,
    int? age,
    String? gender,
    String? aadhaarLast4,
    String? village,
    String? district,
    String? state,
    String? phone,
    String? photoPath,
    DateTime? updatedAt,
    bool? isSynced,
    String? abhaNumber,
  }) =>
      Patient(
        id: id,
        fullName: fullName ?? this.fullName,
        age: age ?? this.age,
        gender: gender ?? this.gender,
        aadhaarLast4: aadhaarLast4 ?? this.aadhaarLast4,
        village: village ?? this.village,
        district: district ?? this.district,
        state: state ?? this.state,
        phone: phone ?? this.phone,
        photoPath: photoPath ?? this.photoPath,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        isSynced: isSynced ?? this.isSynced,
        abhaNumber: abhaNumber ?? this.abhaNumber,
      );

  @override
  List<Object?> get props => [
        id,
        fullName,
        age,
        gender,
        aadhaarLast4,
        village,
        district,
        state,
        phone,
        photoPath,
        createdAt,
        updatedAt,
        isSynced,
        abhaNumber,
      ];

  @override
  String toString() => 'Patient(id=$id, name=$fullName, age=$age)';
}
