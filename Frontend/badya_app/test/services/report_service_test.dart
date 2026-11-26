import 'package:Badya/services/report_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReportService', () {
    late FakeFirebaseFirestore fakeFirestore;
    late ReportService service;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      service = ReportService(firestore: fakeFirestore);
      // Simulate the `submitReport` Cloud Function: it re-checks server-side
      // and writes the report with the reporter derived from the verified ID
      // token (the payload carries no identity).
      service.submitRemoteOverride = (payload) async {
        await fakeFirestore.collection('reports').add({
          'reporter_uid': 'me',
          'reported_uid': payload['reportedUid'],
          'content_type': 'user',
          'content_id': payload['reportedUid'],
          'reason': payload['reason'],
          'details': payload['details'],
          'status': 'pending',
          'created_at': FieldValue.serverTimestamp(),
        });
      };
    });

    test('submitUserReport writes a pending report doc', () async {
      final ok = await service.submitUserReport(
        reporterUid: 'me',
        reportedUid: 'them',
        reason: 'violence',
        details: '  They posted violent content  ',
      );

      expect(ok, true);
      final snap = await fakeFirestore.collection('reports').get();
      expect(snap.docs.length, 1);
      final data = snap.docs.first.data();
      expect(data['reporter_uid'], 'me');
      expect(data['reported_uid'], 'them');
      expect(data['content_type'], 'user');
      expect(data['reason'], 'violence');
      expect(data['details'], 'They posted violent content');
      expect(data['status'], 'pending');
    });

    test('submitUserReport ignores unauthenticated or self-reporting users',
        () async {
      expect(
        await service.submitUserReport(
          reporterUid: '',
          reportedUid: 'them',
          reason: 'spam',
        ),
        false,
      );
      expect(
        await service.submitUserReport(
          reporterUid: 'me',
          reportedUid: 'me',
          reason: 'spam',
        ),
        false,
      );
      final snap = await fakeFirestore.collection('reports').get();
      expect(snap.docs, isEmpty);
    });

    test('submitUserReport rejects an invalid reason', () async {
      expect(
        () => service.submitUserReport(
          reporterUid: 'me',
          reportedUid: 'them',
          reason: 'not-a-valid-reason',
        ),
        throwsA(isA<ReportSubmissionException>()),
      );
    });

    test('submitUserReport blocks duplicate pending reports', () async {
      await service.submitUserReport(
        reporterUid: 'me',
        reportedUid: 'them',
        reason: 'harassment',
      );

      expect(
        () => service.submitUserReport(
          reporterUid: 'me',
          reportedUid: 'them',
          reason: 'spam',
        ),
        throwsA(isA<ReportSubmissionException>()),
      );
    });

    test('submitUserReport enforces the daily limit', () async {
      for (var i = 0; i < ReportService.maxDailyReports; i++) {
        final ok = await service.submitUserReport(
          reporterUid: 'me',
          reportedUid: 'target_$i',
          reason: 'spam',
        );
        expect(ok, true);
      }

      expect(
        () => service.submitUserReport(
          reporterUid: 'me',
          reportedUid: 'another_target',
          reason: 'spam',
        ),
        throwsA(isA<ReportSubmissionException>()),
      );
    });

    test('hasPendingReport detects existing open reports', () async {
      expect(
        await service.hasPendingReport(
          reporterUid: 'me',
          reportedUid: 'them',
        ),
        false,
      );

      await service.submitUserReport(
        reporterUid: 'me',
        reportedUid: 'them',
        reason: 'impersonation',
      );

      expect(
        await service.hasPendingReport(
          reporterUid: 'me',
          reportedUid: 'them',
        ),
        true,
      );
    });

    test('submitUserReport maps server-side errors to friendly messages',
        () async {
      // Duplicate-pending rejected by the Cloud Function.
      service.submitRemoteOverride = (payload) async {
        throw FirebaseFunctionsException(
          code: 'already-exists',
          message: 'You already reported this user. Our team will review it.',
        );
      };
      await expectLater(
        service.submitUserReport(
          reporterUid: 'me',
          reportedUid: 'them',
          reason: 'spam',
        ),
        throwsA(
          isA<ReportSubmissionException>().having(
            (e) => e.message,
            'message',
            contains('already reported'),
          ),
        ),
      );

      // Daily cap rejected by the Cloud Function.
      service.submitRemoteOverride = (payload) async {
        throw FirebaseFunctionsException(
          code: 'resource-exhausted',
          message:
              "You've reached the daily report limit. Please try again tomorrow.",
        );
      };
      await expectLater(
        service.submitUserReport(
          reporterUid: 'me',
          reportedUid: 'them',
          reason: 'spam',
        ),
        throwsA(
          isA<ReportSubmissionException>().having(
            (e) => e.message,
            'message',
            contains('daily report limit'),
          ),
        ),
      );
    });

    test('ReportReason.isValid matches the rule allowlist', () {
      for (final reason in ReportReason.all) {
        expect(ReportReason.isValid(reason.value), true);
      }
      expect(ReportReason.isValid('bogus'), false);
    });
  });
}
