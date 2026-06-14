class ProfileModel {
  final String id;
  final String? email;
  final String? avatarUrl;
  final String userName;
  final String? fullName;
  final String? bio;
  final String? tagline;
  final String? countryCode; // ISO 3166-1 alpha-2
  final String subscriptionTier; // 'free' or 'pro'
  final String verificationStatus; // 'none', 'verified', 'official'
  final String? accountReference;
  final String? userReference;
  final String? phoneNumber;
  final String? accountStatus;
  final String? gender;
  final DateTime? dateOfBirth;

  ProfileModel({
    required this.id,
    this.email,
    this.avatarUrl,
    required this.userName,
    this.fullName,
    this.bio,
    this.tagline,
    this.countryCode,
    required this.subscriptionTier,
    required this.verificationStatus,
    this.accountReference,
    this.userReference,
    this.phoneNumber,
    this.accountStatus,
    this.gender,
    this.dateOfBirth,
  });

  factory ProfileModel.fromMap(
    Map<String, dynamic> map, {
    String? accountReference,
    String? accountStatus,
  }) {
    final info = map['info'] as Map<String, dynamic>? ?? {};
    final dobRaw = map['date_of_birth'] as String?;
    return ProfileModel(
      id: map['id'] as String,
      email: map['email'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      userName: map['user_name'] as String? ?? 'user',
      fullName: map['full_name'] as String?,
      bio: info['bio'] as String?,
      tagline: info['tagline'] as String?,
      countryCode: map['country_code'] as String?,
      subscriptionTier: (map['is_premium'] == true) ? 'pro' : 'free',
      verificationStatus: map['verification_status'] as String? ?? 'none',
      accountReference: accountReference ?? map['account_reference'] as String?,
      userReference: map['reference'] as String?,
      phoneNumber: map['phone_number'] as String?,
      accountStatus: accountStatus ?? map['account_status'] as String?,
      gender: map['gender'] as String?,
      dateOfBirth: dobRaw != null ? DateTime.tryParse(dobRaw) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'full_name': fullName,
      'user_name': userName,
      'avatar_url': avatarUrl,
      'country_code': countryCode,
      'gender': gender,
      'date_of_birth': dateOfBirth?.toIso8601String().split('T')[0],
      'info': {
        'bio': bio,
        'tagline': tagline,
      },
    };
  }

  bool get isIncomplete => 
      fullName == null || 
      fullName!.isEmpty || 
      userName.startsWith('user_') || 
      userName.startsWith('guest_');
  bool get isPremium => subscriptionTier == 'pro';

  ProfileModel copyWith({
    String? fullName,
    String? userName,
    String? bio,
    String? tagline,
    String? avatarUrl,
    String? countryCode,
    bool clearAvatarUrl = false,
    String? accountReference,
    String? userReference,
    String? phoneNumber,
    String? accountStatus,
    String? gender,
    DateTime? dateOfBirth,
  }) {
    return ProfileModel(
      id: id,
      email: email,
      avatarUrl: clearAvatarUrl ? null : (avatarUrl ?? this.avatarUrl),
      userName: userName ?? this.userName,
      fullName: fullName ?? this.fullName,
      bio: bio ?? this.bio,
      tagline: tagline ?? this.tagline,
      countryCode: countryCode ?? this.countryCode,
      subscriptionTier: subscriptionTier,
      verificationStatus: verificationStatus,
      accountReference: accountReference ?? this.accountReference,
      userReference: userReference ?? this.userReference,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      accountStatus: accountStatus ?? this.accountStatus,
      gender: gender ?? this.gender,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
    );
  }
}
