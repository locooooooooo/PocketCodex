import 'package:flutter_hbb/models/agent_dashboard_message_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentDashboardMessagePresentationHarness', () {
    const harness = AgentDashboardMessagePresentationHarness();

    test('keeps short assistant text as a normal message', () {
      final result = harness.present('Done. The preview has been rebuilt.');

      expect(result.shouldUseCard, isFalse);
      expect(result.status, AgentResponsePresentationStatus.completed);
      expect(result.summary, 'Done. The preview has been rebuilt.');
    });

    test('turns long structured output into response card data', () {
      final result = harness.present('Summary\n'
          'The dashboard now renders long assistant replies as digest cards.\n\n'
          'Changes\n'
          '- Added AgentResponseCard.\n'
          '- Updated 3 files.\n\n'
          'Validation\n'
          '- flutter test passed.\n'
          '- flutter analyze passed.');

      expect(result.shouldUseCard, isTrue);
      expect(result.status, AgentResponsePresentationStatus.completed);
      expect(result.statusLabel, 'Done');
      expect(result.summary,
          'The dashboard now renders long assistant replies as digest cards.');
      expect(result.chips, contains('3 files'));
      expect(result.chips, contains('Validation'));
      expect(result.sections.map((section) => section.id), [
        'summary',
        'changes',
        'validation',
      ]);
    });

    test('classifies unheaded long output into sections', () {
      final result = harness.present('- Added response presentation harness.\n'
          '- Updated agent_dashboard_page.dart.\n'
          '- flutter test passed.\n'
          '- Warning: rebuild the web harness before checking localhost.\n'
          '- Next: validate compact mode on mobile.');

      expect(result.shouldUseCard, isTrue);
      expect(result.sections.map((section) => section.id), contains('changes'));
      expect(
        result.sections.map((section) => section.id),
        contains('validation'),
      );
      expect(result.sections.map((section) => section.id), contains('risks'));
      expect(
        result.sections.map((section) => section.id),
        contains('next-actions'),
      );
    });

    test('does not require section headings for very long prose', () {
      final result = harness.present(List.filled(
        10,
        'This response explains a detailed implementation decision for the floating dashboard.',
      ).join('\n'));

      expect(result.shouldUseCard, isTrue);
      expect(result.title, startsWith('This response explains'));
      expect(result.summary, startsWith('This response explains'));
    });
  });
}
