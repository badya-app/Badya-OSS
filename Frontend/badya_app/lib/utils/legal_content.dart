/// Legal document content for Badya — Terms of Service & Privacy Policy.
///
/// These documents are rendered in-app by [LegalDocumentPage] (see
/// `lib/legal_document_page.dart`) and linked from the signup form and the
/// profile's Privacy & Security sheet.
///
/// The text below reflects Badya's actual data practices as implemented in
/// this codebase: Firebase Auth (email/password + Google Sign-In), Firestore
/// `users/{uid}` documents, Cloud Storage uploads (profile photos, imported
/// content images), FCM push notifications, in-app purchases, and issue
/// reports. It is a solid template but **should still be reviewed by a lawyer**
/// before a public launch (especially the governing-law and jurisdiction
/// clauses).
library;


/// A single titled section inside a legal document. Paragraphs that start
/// with a bullet marker (`•`) are rendered as list items.
class LegalSection {
  final String title;
  final List<String> paragraphs;

  const LegalSection(this.title, this.paragraphs);
}

/// A full legal document: title, last-updated date, and ordered sections.
class LegalDocument {
  final String title;
  final String lastUpdated;
  final List<LegalSection> sections;

  const LegalDocument({
    required this.title,
    required this.lastUpdated,
    required this.sections,
  });
}

/// Container for all legal documents and the current version constant.
class LegalContent {
  /// Version of the legal documents. Bumped whenever the terms change so the
  /// app can later prompt users to re-accept the updated terms. Stored on the
  /// `users/{uid}` document at signup (`tos_version`).
  static const String version = 'v1';

  static const String lastUpdated = 'August 2026';

  // ─── Terms of Service ──────────────────────────────────────────────

  static const LegalDocument termsOfService = LegalDocument(
    title: 'Terms of Service',
    lastUpdated: lastUpdated,
    sections: [
      LegalSection('Acceptance of These Terms', [
        "By creating an account, accessing, or using Badya (\"the App\"), you agree to be bound by these Terms of Service (\"Terms\"). If you do not agree with any part of these Terms, you must not use the App. When you create an account, you confirm that you accept these Terms and the Privacy Policy.",
      ]),
      LegalSection('Eligibility', [
        "You must be at least 13 years old to use the App. If you are under the age of majority in your country, you confirm that your parent or legal guardian has reviewed and agreed to these Terms on your behalf.",
        "If you are located in the European Economic Area (EEA), you must be at least 16 years old, or have verifiable parental consent. By creating an account, you confirm that you meet these requirements.",
      ]),
      LegalSection('Your Account', [
        '• You are responsible for keeping your login credentials secure and for all activity that happens under your account. Never share your password.',
        '• You must provide accurate information and keep it up to date.',
        '• You may delete your account at any time from Privacy & Security in the app. This permanently removes your account and all associated data, and cannot be undone.',
      ]),
      LegalSection('Acceptable Use', [
        "You agree not to:",
        '• Use the App for any unlawful purpose or in violation of these Terms.',
        "• Attempt to access another user's account or data.",
        '• Scrape, copy, or redistribute App content without permission.',
        "• Interfere with or disrupt the App's servers, networks, or services.",
        '• Create accounts through automated means or for fraudulent purposes.',
      ]),
      LegalSection('User Content You Provide', [
        "You retain all rights to the content you import into the App, such as documents, texts, and audio you upload for learning purposes.",
        "By importing content, you grant Badya a limited, non-exclusive, worldwide license to store, process, and display that content solely to provide the App's features to you. You confirm that you either own the content or have the right to use and import it.",
      ]),
      LegalSection('Our Intellectual Property', [
        "The App's name, logo, design, and all software and content provided by Badya are owned by Badya or its licensors and are protected by intellectual property laws. You may not copy, modify, or create derivative works from them without permission.",
      ]),
      LegalSection('Purchases and Virtual Currency', [
        "The App may offer in-app purchases such as coins, subscriptions, or premium features. Payments are processed by the platform store (Apple App Store or Google Play) and are subject to that store's terms.",
        "Virtual currency and items are non-refundable except where required by law. Prices and availability may change at any time.",
      ]),
      LegalSection('Termination', [
        "You may stop using the App at any time and delete your account as described in these Terms.",
        "We may suspend or terminate your access if you violate these Terms, misuse the service, or if we are required to do so by law. Upon termination, your right to use the App ends, and we may delete your account data in accordance with our Privacy Policy.",
      ]),
      LegalSection('Disclaimers', [
        "The App is provided \"as is\" and \"as available\" without warranties of any kind, whether express or implied, including merchantability, fitness for a particular purpose, and non-infringement.",
        "We do not guarantee that the App will be uninterrupted, error-free, or that any particular learning outcome will be achieved.",
      ]),
      LegalSection('Limitation of Liability', [
        "To the maximum extent permitted by law, Badya shall not be liable for any indirect, incidental, special, consequential, or punitive damages, or any loss of profits, data, or goodwill, arising from your use of the App.",
        "Our total liability shall not exceed the amount you paid to use the App in the six months preceding the claim.",
      ]),
      LegalSection('Changes to These Terms', [
        "We may update these Terms from time to time. When we do, we will revise the \"Last updated\" date and, for material changes, make reasonable efforts to notify you (for example, with an in-app notice).",
        "Continued use of the App after changes take effect means you accept the updated Terms.",
      ]),
      LegalSection('Governing Law', [
        "These Terms shall be governed by and construed in accordance with the laws applicable in your country of residence, without regard to conflict-of-law principles. Any disputes shall be resolved in the competent courts of your country of residence.",
      ]),
      LegalSection('Contact Us', [
        "Questions about these Terms? Contact us at badyaapp@gmail.com.",
      ]),
    ],
  );

  // ─── Privacy Policy ────────────────────────────────────────────────

  static const LegalDocument privacyPolicy = LegalDocument(
    title: 'Privacy Policy',
    lastUpdated: lastUpdated,
    sections: [
      LegalSection('Introduction', [
        "This Privacy Policy explains what information Badya (\"the App\", \"we\", \"us\") collects, how we use and protect it, and the rights you have over your data. By using the App, you agree to the practices described here.",
      ]),
      LegalSection('Information We Collect', [
        '• Account information: your name, email address, and sign-in method (email/password or Google).',
        '• Profile information: your profile photo, bio, native language, and the languages you are learning.',
        '• Learning data: your progress, XP, streaks, scores, coins, achievements, saved vocabulary, and the content you import for learning.',
        '• Device and usage data: technical information collected by Firebase, such as app version, device type, and crash reports.',
        '• Communications: feedback and issue reports you send us.',
        "If you sign in with Google, we receive the basic profile information Google shares with us (such as your name, email address, and profile picture) in accordance with Google's Privacy Policy.",
      ]),
      LegalSection('How We Use Your Information', [
        '• To create and manage your account and keep you signed in.',
        '• To provide core features: tracking progress, scoring, recommendations, and content import.',
        '• To send you notifications you have opted into (for example, study reminders).',
        '• To respond to your feedback and support requests.',
        '• To improve the App, fix bugs, and keep it secure.',
        'We do not sell your personal information.',
      ]),
      LegalSection('How We Store and Protect Your Data', [
        "Your data is stored securely using Firebase (Google Cloud), including Firestore for your profile and progress and Cloud Storage for uploaded files.",
        "We use industry-standard measures to protect data in transit and at rest. No method of transmission or storage is 100% secure, so we cannot guarantee absolute security.",
      ]),
      LegalSection('Sharing Your Information', [
        '• Service providers: we share data with trusted providers who help operate the App (for example, Google/Firebase infrastructure and push-notification services).',
        '• Google Sign-In: if you sign in with Google, Google shares basic profile data with us according to Google\'s Privacy Policy.',
        '• Legal requirements: we may disclose data if required by law or to protect our rights and safety.',
        'We do not sell or rent your personal information to third parties.',
      ]),
      LegalSection('Your Rights and Choices', [
        '• Access and update: you can edit your profile and preferences at any time in the app.',
        '• Delete your account: you can permanently delete your account and all associated data from Privacy & Security. Deletion is immediate and irreversible.',
        "• Export your data: you may contact us at badyaapp@gmail.com to request a copy of your personal data.",
        '• Withdraw consent: you can turn off notifications and adjust what is visible on your public profile at any time.',
        "Depending on your location (for example, the EEA), you may have additional rights under the GDPR, including access, rectification, erasure, restriction, and portability. You can exercise these rights by contacting us.",
      ]),
      LegalSection('Data Retention', [
        "We keep your data for as long as your account is active, so the App can function. When you delete your account, your personal data is removed from our services.",
        "Some anonymized or aggregated data may be retained for analytics and security purposes.",
      ]),
      LegalSection("Children's Privacy", [
        "The App is not directed at children under 13, and we do not knowingly collect personal information from children under 13. If you believe a child has provided us personal information, please contact us and we will delete it.",
      ]),
      LegalSection('International Transfers', [
        "Your data may be processed and stored on servers outside your country, including the United States, through Firebase/Google Cloud. We take steps to protect your data in accordance with applicable law.",
      ]),
      LegalSection('Changes to This Policy', [
        "We may update this policy from time to time. Material changes will be announced in the app. Continued use of the App after changes take effect constitutes acceptance of the updated policy.",
      ]),
      LegalSection('Contact Us', [
        "Questions about this Privacy Policy or your data? Email us at badyaapp@gmail.com.",
      ]),
    ],
  );
}
