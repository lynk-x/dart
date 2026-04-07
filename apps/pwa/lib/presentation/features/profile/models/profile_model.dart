class ProfileModel {
  final String id;
  final String? email;
  final String? avatarUrl;
  final String userName;
  final String? fullName;
  final String? bio;
  final String? tagline;
  final String subscriptionTier; // 'free' or 'pro'
  final String verificationStatus; // 'none', 'verified', 'official'

  ProfileModel({
    required this.id,
    this.email,
    this.avatarUrl,
    required this.userName,
    this.fullName,
    this.bio,
    this.tagline,
    required this.subscriptionTier,
    required this.verificationStatus,
  });

  factory ProfileModel.fromMap(Map<String, dynamic> map) {
    final metadata = map['metadata'] as Map<String, dynamic>? ?? {};
    return ProfileModel(
      id: map['id'] as String,
      email: map['email'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      userName: map['user_name'] as String? ?? 'user',
      fullName: map['full_name'] as String?,
      bio: map['bio'] as String?,
      tagline: map['tagline'] as String?,
      subscriptionTier: metadata['subscription_tier'] as String? ?? 'free',
      verificationStatus: (map['is_verified'] == true) ? 'verified' : 'none',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'full_name': fullName,
      'user_name': userName,
      'bio': bio,
      'tagline': tagline,
      'avatar_url': avatarUrl,
    };
  }

  bool get isIncomplete => fullName == null || fullName!.isEmpty;

  ProfileModel copyWith({
    String? fullName,
    String? userName,
    String? bio,
    String? tagline,
    String? avatarUrl,
  }) {
    return ProfileModel(
      id: id,
      email: email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      userName: userName ?? this.userName,
      fullName: fullName ?? this.fullName,
      bio: bio ?? this.bio,
      tagline: tagline ?? this.tagline,
      subscriptionTier: subscriptionTier,
      verificationStatus: verificationStatus,
    );
  }
}
