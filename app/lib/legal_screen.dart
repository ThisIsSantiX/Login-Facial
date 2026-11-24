import 'package:flutter/material.dart';

import 'design.dart';
import 'legal_documents.dart';

enum LegalDocument { privacy, terms }

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.document});

  final LegalDocument document;

  static Future<void> openPrivacy(BuildContext context) =>
      open(context, LegalDocument.privacy);

  static Future<void> openTerms(BuildContext context) =>
      open(context, LegalDocument.terms);

  static Future<void> open(BuildContext context, LegalDocument document) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => LegalScreen(document: document)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isPrivacy = document == LegalDocument.privacy;
    final title = isPrivacy ? privacyTitle : termsTitle;
    final sections = isPrivacy ? privacySections : termsSections;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: BezierBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            children: [
              BezierCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Versión $legalVersion',
                      style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Vigente desde $legalEffectiveDate',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Responsable: $legalOwner · $legalLocation',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              for (final section in sections)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: BezierCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          section.title,
                          style: TextStyle(
                            color: scheme.primary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          section.body,
                          style: const TextStyle(fontSize: 13.5, height: 1.45),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  'Contacto: $legalEmail',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
