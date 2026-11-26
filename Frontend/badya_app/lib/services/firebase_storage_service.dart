import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:Badya/config/local_mode.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class FirebaseStorageService {
  final FirebaseStorage _storage;
  final _uuid = const Uuid();

  FirebaseStorageService({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  /// Resolves the storage path prefix for this user's uploads.
  ///
  /// Files are stored as `{folder}/{uid}/{fileName}` (review issue #5,
  /// Option A). The uid in the path is what lets `storage.rules` scope reads
  /// and writes to the owner with `request.auth.uid == userId` — flat
  /// UUID-only paths had no owner marker and allowed cross-user access.
  ///
  /// Returns null when the user isn't signed in (no valid upload target).
  String? _userFolder(String folder) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return '$folder/$uid';
  }

  /// Uploads a file from a path to Firebase Storage.
  Future<String?> uploadFile(String filePath, String folder) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      final userFolder = _userFolder(folder);
      if (userFolder == null) return null;

      final extension = p.extension(filePath);
      final fileName = '${_uuid.v4()}$extension';
      final ref = _storage.ref().child(userFolder).child(fileName);

      final uploadTask = await ref.putFile(file);
      return await uploadTask.ref.getDownloadURL();
    } catch (e) {
      return null;
    }
  }

  /// Uploads raw bytes to Firebase Storage.
  Future<String?> uploadBytes(
    Uint8List bytes,
    String fileName,
    String folder,
  ) async {
    try {
      final userFolder = _userFolder(folder);
      if (userFolder == null) return null;
      final ref = _storage.ref().child(userFolder).child(fileName);
      final uploadTask = await ref.putData(bytes);
      return await uploadTask.ref.getDownloadURL();
    } catch (e) {
      return null;
    }
  }
}
