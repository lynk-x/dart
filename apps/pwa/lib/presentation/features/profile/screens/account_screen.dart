import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lynk_core/core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/delete_account_dialog.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  void _showUpdatePhoneDialog(BuildContext context, String currentPhone) {
    final phoneController = TextEditingController(text: currentPhone == 'No phone number linked' ? '' : currentPhone);
    final codeController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isUpdating = false;
    bool codeSent = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> sendCode() async {
              if (!(formKey.currentState?.validate() ?? false)) return;
              setDialogState(() => isUpdating = true);
              try {
                await Supabase.instance.client.auth.updateUser(
                  UserAttributes(phone: phoneController.text.trim()),
                );
                setDialogState(() {
                  isUpdating = false;
                  codeSent = true;
                });
              } catch (e) {
                if (sheetContext.mounted) {
                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                    SnackBar(
                      content: Text('Error: ${e.toFriendlyMessage()}'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
                setDialogState(() => isUpdating = false);
              }
            }

            Future<void> confirmCode() async {
              final code = codeController.text.trim();
              if (code.isEmpty) return;
              setDialogState(() => isUpdating = true);
              try {
                await Supabase.instance.client.auth.verifyOTP(
                  phone: phoneController.text.trim(),
                  token: code,
                  type: OtpType.phoneChange,
                );
                if (context.mounted) {
                  context.read<ProfileCubit>().loadProfile();
                }
                if (sheetContext.mounted) {
                  Navigator.pop(sheetContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Phone number updated successfully'),
                      backgroundColor: context.accentColor,
                    ),
                  );
                }
              } catch (e) {
                if (sheetContext.mounted) {
                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                    SnackBar(
                      content: Text('Error: ${e.toFriendlyMessage()}'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              } finally {
                setDialogState(() => isUpdating = false);
              }
            }

            return Container(
              padding: EdgeInsets.fromLTRB(
                24, 20, 24,
                MediaQuery.of(context).viewInsets.bottom + 32,
              ),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      codeSent
                          ? 'Enter the code we sent you'
                          : (currentPhone.isEmpty || currentPhone == 'No phone number linked'
                              ? 'Add Phone Number'
                              : 'Change Phone Number'),
                      style: AppTypography.interTight(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      codeSent
                          ? 'We texted a 6-digit code to ${phoneController.text.trim()}.'
                          : 'This number becomes your new sign-in identifier.',
                      style: AppTypography.inter(
                        fontSize: 13,
                        color: Colors.white54,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (!codeSent)
                      TextFormField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'New Phone Number',
                          labelStyle: const TextStyle(color: Colors.white60),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: context.accentColor),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Phone number cannot be empty';
                          }
                          if (val.trim().length < 7) {
                            return 'Please enter a valid phone number';
                          }
                          return null;
                        },
                      )
                    else
                      TextFormField(
                        controller: codeController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: '6-digit code',
                          labelStyle: const TextStyle(color: Colors.white60),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: context.accentColor),
                          ),
                        ),
                      ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.accentColor,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: isUpdating ? null : (codeSent ? confirmCode : sendCode),
                      child: isUpdating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : Text(
                              codeSent ? 'Confirm Code' : 'Send Code',
                              style: AppTypography.inter(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => DeleteAccountDialog(
        onDelete: () => context.read<ProfileCubit>().deleteAccount(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primaryBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Account & Security',
          style: AppTypography.interTight(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: BlocBuilder<ProfileCubit, ProfileState>(
        builder: (context, state) {
          if (state is ProfileLoading || state is ProfileInitial) {
            return Center(
              child: CircularProgressIndicator(color: context.accentColor),
            );
          }

          if (state is ProfileError) {
            return Center(
              child: Text(
                'Error: ${state.message}',
                style: const TextStyle(color: Colors.white),
              ),
            );
          }

          final profile = (state as ProfileLoaded).profile;
          final accountRef = profile.accountReference ?? 'Resolving...';
          final status = profile.accountStatus ?? 'active';
          final phone = profile.phoneNumber ?? 'No phone number linked';

          final isStatusActive = status.toLowerCase() == 'active';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader('Identity & ID'),
                _buildSettingTile(
                  title: 'Account Reference',
                  subtitle: accountRef,
                  icon: Icons.badge_outlined,
                  onTap: () {
                    if (profile.accountReference != null) {
                      Clipboard.setData(ClipboardData(text: profile.accountReference!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Account reference copied to clipboard')),
                      );
                    }
                  },
                  trailing: const Icon(Icons.copy_rounded, color: Colors.white24, size: 20),
                ),
                _buildSettingTile(
                  title: 'Account Status',
                  subtitle: status.toUpperCase(),
                  icon: Icons.info_outline_rounded,
                  onTap: () {},
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isStatusActive
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: AppTypography.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isStatusActive ? Colors.greenAccent : Colors.redAccent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                _buildSectionHeader('Login'),
                _buildSettingTile(
                  title: 'Phone Number',
                  subtitle: phone,
                  icon: Icons.phone_iphone_rounded,
                  onTap: () => _showUpdatePhoneDialog(context, profile.phoneNumber ?? ''),
                  trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white24),
                ),
                const SizedBox(height: 48),
                _buildSectionHeader('Danger Zone'),
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.2)),
                  ),
                  child: ListTile(
                    onTap: () => _showDeleteConfirmation(context),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 22),
                    ),
                    title: Text(
                      'Delete Account',
                      style: AppTypography.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.redAccent,
                      ),
                    ),
                    subtitle: Text(
                      'Permanently remove all your data',
                      style: AppTypography.inter(fontSize: 13, color: Colors.white54),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, color: Colors.redAccent),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: AppTypography.inter(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: context.accentColor,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    required Widget trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        title: Text(
          title,
          style: AppTypography.inter(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.inter(fontSize: 13, color: Colors.white54),
        ),
        trailing: trailing,
      ),
    );
  }
}
