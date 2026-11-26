import 'package:Badya/config/local_mode.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Report reasons a user can pick from. Stored as the `reason` field on
/// `reports/{reportId}` documents; the Firestore rules only accept these
/// values, so anything else is rejected server-side.
class ReportReason {
  final String value;
  final String label;

  const ReportReason(this.value, this.label);

  static const violence = ReportReason('violence', 'Violence or threats');
  static const sexual = ReportReason('sexual_content', 'Sexual content');
  static const hate = ReportReason('hate_speech', 'Hate speech');
  static const harassment = ReportReason('harassment', 'Harassment or bullying');
  static const spam = ReportReason('spam', 'Spam or scam');
  static const impersonation = ReportReason(
    'impersonation',
    'Impersonation or fake account',
  );
  static const other = ReportReason('other', 'Something else');

  static const List<ReportReason> all = [
    violence,
    sexual,
    hate,
    harassment,
    spam,
    impersonation,
    other,
  ];

  static bool isValid(String value) => all.any((r) => r.value == value);
}

/// Thrown when a report cannot be submitted (duplicate, rate limit, etc.).
class ReportSubmissionException implements Exception {
  final String message;
  const ReportSubmissionException(this.message);

  @override
  String toString() => message;
}

/// Service for reporting users (and, in future, content) to the moderation
/// team.
///
/// Reports are stored in the top-level `reports` collection as
/// `reports/{reportId}` documents, but they are ONLY created by the
/// `submitReport` Cloud Function — the Firestore rules block all direct
/// client writes. The service keeps its duplicate-pending and daily-cap
/// checks as a fast path for good UX, while the function re-checks them
/// server-side (with the Admin SDK) so a modified client can't bypass them.
/// Triage happens via the Firebase Console / Admin SDK (or a future
/// moderation backend).
class ReportService {
  final FirebaseFirestore? _firestore;

  /// Injected remote call for [submitUserReport] — overridable in tests so
  /// the real Cloud Function isn't invoked.
  @visibleForTesting
  Future<void> Function(Map<String, dynamic> payload)? submitRemoteOverride;

  ReportService({FirebaseFirestore? firestore})
    : _firestore = LocalMode.enabled
          ? firestore
          : (firestore ?? FirebaseFirestore.instance);

  /// Maximum number of reports a single user can submit per calendar day
  /// (client-side fast-path guard; the `submitReport` Cloud Function is the
  /// authority and enforces the same cap server-side).
  static const int maxDailyReports = 5;

  CollectionReference<Map<String, dynamic>> get _reportsRef =>
      _firestore.collection('reports');

  /// Whether [reporterUid] has already submitted an open (pending) report
  /// against [reportedUid]. Used to prevent duplicate spam.
  Future<bool> hasPendingReport({
    required String reporterUid,
    required String reportedUid,
  }) async {
    final snapshot = await _reportsRef
        .where('reporter_uid', isEqualTo: reporterUid)
        .where('reported_uid', isEqualTo: reportedUid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();
    return snapshot.docs.isNotEmpty;
  }

  /// How many reports [reporterUid] has submitted in the current UTC calendar
  /// day.
  ///
  /// This is a client-side FAST-PATH heuristic, NOT the authority: the window
  /// is computed from the device clock, so a user who changes their device
  /// clock could skew it. The `submitReport` Cloud Function re-checks the
  /// daily cap on the SERVER clock (`startOfDayUtc`) and is the source of
  /// truth — the client check only exists to give the user an immediate,
  /// offline-friendly error instead of waiting for the function round trip.
  ///
  /// The boundary uses UTC midnight (matching the server's window and the
  /// UTC `created_at` server timestamps) rather than device-local midnight,
  /// so the window definition can't be shifted by the device timezone.
  Future<int> countReportsToday(String reporterUid) async {
    final now = DateTime.now().toUtc();
    final startOfDay = DateTime.utc(now.year, now.month, now.day);
    final snapshot = await _reportsRef
        .where('reporter_uid', isEqualTo: reporterUid)
        .where('created_at', isGreaterThanOrEqualTo: startOfDay)
        .get();
    return snapshot.docs.length;
  }

  /// Submit a user report. Returns `true` when the report was written.
  ///
  /// Guards (client-side fast path — the `submitReport` Cloud Function
  /// re-checks them server-side and is the authority):
  /// - No-op for an unauthenticated or self-reporting user.
  /// - Rejects a duplicate pending report against the same user.
  /// - Rejects submissions beyond [maxDailyReports] per day.
  ///
  /// If a fast-path query fails (rules not deployed yet, missing index, or a
  /// transient network error), the submission falls through to the callable
  /// instead of aborting — the function re-enforces the duplicate and daily
  /// cap checks with the Admin SDK, so a skipped local check can never weaken
  /// moderation.
  ///
  /// The actual write goes through the `submitReport` callable; the Firestore
  /// rules block direct client writes to `reports`.
  Future<bool> submitUserReport({
    required String reporterUid,
    required String reportedUid,
    required String reason,
    String? details,
  }) async {
    if (reporterUid.isEmpty || reportedUid.isEmpty) return false;
    if (reporterUid == reportedUid) return false;
    if (!ReportReason.isValid(reason)) {
      throw const ReportSubmissionException('Invalid report reason.');
    }

    // Fast-path duplicate check (client-side heuristic for instant UX
    // feedback). The Cloud Function re-checks this server-side and is the
    // authority, so a failure here must not block the submission.
    var duplicate = false;
    try {
      duplicate = await hasPendingReport(
        reporterUid: reporterUid,
        reportedUid: reportedUid,
      );
    } on FirebaseException catch (e) {
      debugPrint('ReportService: pending-report check skipped (${e.code})');
    }
    if (duplicate) {
      throw const ReportSubmissionException(
        'You already reported this user. Our team will review it.',
      );
    }

    // Fast-path daily cap check — same rationale as above; the function
    // enforces the real cap on the server clock.
    var todayCount = 0;
    try {
      todayCount = await countReportsToday(reporterUid);
    } on FirebaseException catch (e) {
      debugPrint('ReportService: daily-count check skipped (${e.code})');
    }
    if (todayCount >= maxDailyReports) {
      throw const ReportSubmissionException(
        'You\'ve reached the daily report limit. Please try again tomorrow.',
      );
    }

    final payload = <String, dynamic>{
      'reportedUid': reportedUid,
      'reason': reason,
      'details': details?.trim().isEmpty == true ? '' : (details?.trim() ?? ''),
    };

    final override = submitRemoteOverride;
    try {
      if (override != null) {
        await override(payload);
      } else {
        final callable = FirebaseFunctions.instance.httpsCallable('submitReport');
        await callable.call(payload);
      }
    } on FirebaseFunctionsException catch (e) {
      throw ReportSubmissionException(_messageFor(e));
    }
    return true;
  }

  /// Map a Cloud Function error to a user-facing message.
  String _messageFor(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'already-exists':
        return 'You already reported this user. Our team will review it.';
      case 'resource-exhausted':
        // The function throws this code for BOTH the daily cap and its
        // 10/60s rate limiter, each with its own message — prefer the
        // server's wording so a rate-limited user isn't told they hit the
        // daily cap. Fall back to the daily-cap copy for older deployments.
        return e.message ??
            'You\'ve reached the daily report limit. Please try again tomorrow.';
      case 'invalid-argument':
        return e.message ?? 'Invalid report. Please check your input and try again.';
      case 'unauthenticated':
        return 'You must be signed in to report a user.';
      default:
        return 'Could not submit your report. Please try again.';
    }
  }
}
