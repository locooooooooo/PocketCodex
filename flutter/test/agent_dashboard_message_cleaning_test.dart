import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/models/agent_dashboard_message_cleaning.dart';

void main() {
  group('AgentDashboardMessageCleaningHarness', () {
    final harness = AgentDashboardMessageCleaningHarness.codexSession();

    AgentDashboardMessageCleaningResult clean(
      String text, {
      AgentDashboardMessageRole role = AgentDashboardMessageRole.assistant,
    }) {
      return harness.clean(AgentDashboardMessageCleaningContext(
        text: text,
        source: AgentDashboardMessageSource.sessionDetail,
        role: role,
      ));
    }

    test('removes trailing Codex memory citation metadata', () {
      final result = clean('Visible answer\n\n'
          '<oai-mem-citation>\n'
          '<citation_entries>\n'
          'MEMORY.md:1-2|note=[internal]\n'
          '</citation_entries>\n'
          '<rollout_ids>\n'
          '019e815c-78ce-7553-a264-6310ed2c75e9\n'
          '</rollout_ids>\n'
          '</oai-mem-citation>');

      expect(result.text, 'Visible answer');
      expect(result.changed, isTrue);
      expect(
        result.matches.map((match) => match.ruleId),
        contains('codex.trailing_memory_citation_block'),
      );
    });

    test('removes memory citation metadata with padded output tail', () {
      final result = clean('Visible answer\n\n'
          '<oai-mem-citation>\n'
          '<citation_entries>\n'
          'MEMORY.md:16-24|note=[internal]\n'
          'MEMORY.md:73-80|note=[internal]\n'
          '</citation_entries>\n'
          '<rollout_ids>\n'
          '019e815c-78ce-7553-a264-6310ed2c75e9\n'
          '019e959f-3a43-7eb1-b6fd-f9b8cce77f88\n'
          '</rollout_ids>\n'
          '</oai-mem-citation>\n\n');

      expect(result.text, 'Visible answer');
      expect(
        result.matches.map((match) => match.ruleId),
        contains('codex.trailing_memory_citation_block'),
      );
    });

    test('keeps memory citation text inside fenced code blocks', () {
      final result = clean('```xml\n'
          '<oai-mem-citation>\n'
          '</oai-mem-citation>\n'
          '```');

      expect(result.changed, isFalse);
      expect(result.text, contains('<oai-mem-citation>'));
    });

    test('removes trailing memory citation after unterminated transcript fence',
        () {
      final result = clean('Visible answer\n'
          '```text\n'
          '- focused validation passed\n\n'
          '<oai-mem-citation>\n'
          '<citation_entries>\n'
          'MEMORY.md:55-62|note=[internal]\n'
          '</citation_entries>\n'
          '<rollout_ids>\n'
          '019e815c-78ce-7553-a264-6310ed2c75e9\n'
          '</rollout_ids>\n'
          '</oai-mem-citation>');

      expect(
          result.text,
          'Visible answer\n'
          '```text\n'
          '- focused validation passed');
      expect(
        result.matches.map((match) => match.ruleId),
        contains('codex.trailing_memory_citation_block'),
      );
    });

    test('still removes trailing metadata after fenced citation examples', () {
      final result = clean('The visible answer includes an example:\n'
          '```xml\n'
          '<oai-mem-citation>\n'
          '</oai-mem-citation>\n'
          '```\n\n'
          '<oai-mem-citation>\n'
          '<citation_entries>\n'
          'MEMORY.md:1-2|note=[internal]\n'
          '</citation_entries>\n'
          '<rollout_ids>\n'
          '</rollout_ids>\n'
          '</oai-mem-citation>');

      expect(result.changed, isTrue);
      expect(
          result.text,
          'The visible answer includes an example:\n'
          '```xml\n'
          '<oai-mem-citation>\n'
          '</oai-mem-citation>\n'
          '```');
    });

    test('removes standalone Codex host directives', () {
      final result = clean('Patch landed.\n'
          '::git-stage{cwd="<workspace>"}\n'
          'Continue with verification.');

      expect(result.text, 'Patch landed.\nContinue with verification.');
      expect(
        result.matches.map((match) => match.ruleId),
        contains('codex.standalone_host_directive'),
      );
    });

    test('keeps host directive examples inside fenced code blocks', () {
      final result = clean('```text\n'
          '::git-stage{cwd="<workspace>"}\n'
          '```');

      expect(result.changed, isFalse);
      expect(result.text, contains('::git-stage'));
    });

    test('does not clean user-authored text', () {
      final result = clean(
        'Please explain <oai-mem-citation> literally.',
        role: AgentDashboardMessageRole.user,
      );

      expect(result.changed, isFalse);
      expect(result.text, contains('<oai-mem-citation>'));
    });
  });
}
