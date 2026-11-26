import 'package:Badya/services/block_service.dart';
import 'package:Badya/utils/ui_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Management page listing everyone the current user has blocked, with the
/// ability to unblock them.
class BlockedUsersPage extends StatefulWidget {
  final FirebaseFirestore? firestore;
  final String? currentUserId;

  const BlockedUsersPage({super.key, this.firestore, this.currentUserId});

  @override
  State<BlockedUsersPage> createState() => _BlockedUsersPageState();
}

class _BlockedUsersPageState extends State<BlockedUsersPage> {
  String? _currentUid;
  late final BlockService _blockService;
  final Set<String> _unblocking = {};

  @override
  void initState() {
    super.initState();
    _currentUid = widget.currentUserId ?? _resolveCurrentUid();
    _blockService = BlockService(firestore: widget.firestore);
  }

  String? _resolveCurrentUid() {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  Future<void> _unblock(String blockedUid) async {
    final uid = _currentUid;
    if (uid == null) return;
    setState(() => _unblocking.add(blockedUid));
    try {
      await _blockService.unblockUser(
        currentUserId: uid,
        blockedUid: blockedUid,
      );
      if (mounted) {
        UiUtils.showTopNotification(context, 'User unblocked', type: NotificationType.success);
      }
    } catch (e) {
      if (mounted) {
        UiUtils.showErrorSnackbar(context, 'Failed to unblock: $e');
      }
    } finally {
      if (mounted) setState(() => _unblocking.remove(blockedUid));
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _currentUid;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF1A1A1A)
          : const Color(0xFFFDF4DD),
      appBar: AppBar(
        title: Text(
          'Blocked Users',
          style: GoogleFonts.nunito(fontWeight: FontWeight.w800),
        ),
      ),
      body: uid == null
          ? const Center(child: Text('Sign in to manage blocked users'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _blockService.getBlockedUsersStream(uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Failed to load blocked users'),
                  );
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.person_off_rounded,
                          size: 64,
                          color: isDark
                              ? Colors.white24
                              : Colors.black26,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No blocked users',
                          style: GoogleFonts.nunito(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Theme.of(
                              context,
                            ).textTheme.bodyLarge?.color,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Users you block won\'t appear in your feed.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.nunito(
                            fontSize: 13,
                            color: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.color
                                ?.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data();
                    final displayName =
                        (data['display_name'] as String?)?.isNotEmpty == true
                        ? data['display_name'] as String
                        : doc.id;
                    final photoUrl = data['photo_url'] as String?;
                    final isUnblocking = _unblocking.contains(doc.id);

                    return Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardTheme.color,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.black.withValues(alpha: 0.06),
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFFFFF9F0),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: photoUrl != null && photoUrl.isNotEmpty
                              ? Image.network(
                                  photoUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.person_rounded,
                                    size: 28,
                                    color: Color(0xFFB2BEC3),
                                  ),
                                )
                              : const Icon(
                                  Icons.person_rounded,
                                  size: 28,
                                  color: Color(0xFFB2BEC3),
                                ),
                        ),
                        title: Text(
                          displayName,
                          style: GoogleFonts.nunito(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(
                              context,
                            ).textTheme.bodyLarge?.color,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          'Blocked',
                          style: GoogleFonts.nunito(
                            fontSize: 12,
                            color: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.color
                                ?.withValues(alpha: 0.6),
                          ),
                        ),
                        trailing: OutlinedButton(
                          onPressed: isUnblocking
                              ? null
                              : () => _unblock(doc.id),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF4ECDC4),
                            side: const BorderSide(
                              color: Color(0xFF4ECDC4),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: isUnblocking
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Unblock'),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
