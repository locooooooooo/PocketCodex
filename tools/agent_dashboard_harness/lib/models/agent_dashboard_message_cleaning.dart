enum AgentDashboardMessageSource {
  sessionDetail,
  liveAgentText,
  structuredAgentEvent,
}

enum AgentDashboardMessageRole {
  assistant,
  user,
}

class AgentDashboardMessageCleaningContext {
  const AgentDashboardMessageCleaningContext({
    required this.text,
    required this.source,
    required this.role,
  });

  final String text;
  final AgentDashboardMessageSource source;
  final AgentDashboardMessageRole role;
}

class AgentDashboardMessageCleaningMatch {
  const AgentDashboardMessageCleaningMatch({
    required this.ruleId,
    required this.label,
  });

  final String ruleId;
  final String label;
}

class AgentDashboardMessageCleaningResult {
  const AgentDashboardMessageCleaningResult({
    required this.originalText,
    required this.text,
    required this.matches,
  });

  final String originalText;
  final String text;
  final List<AgentDashboardMessageCleaningMatch> matches;

  bool get changed => originalText != text;
}

abstract class AgentDashboardMessageCleaningRule {
  const AgentDashboardMessageCleaningRule();

  String get id;

  String get label;

  String clean(AgentDashboardMessageCleaningContext context, String text);
}

class AgentDashboardMessageCleaningHarness {
  const AgentDashboardMessageCleaningHarness({
    required this.rules,
  });

  factory AgentDashboardMessageCleaningHarness.codexSession() {
    return const AgentDashboardMessageCleaningHarness(
      rules: [
        _DashboardEnvelopeCurrentRequestRule(),
        _TrailingMemoryCitationBlockRule(),
        _StandaloneCodexDirectiveRule(),
      ],
    );
  }

  final List<AgentDashboardMessageCleaningRule> rules;

  AgentDashboardMessageCleaningResult clean(
    AgentDashboardMessageCleaningContext context,
  ) {
    var current = context.text;
    final matches = <AgentDashboardMessageCleaningMatch>[];
    for (final rule in rules) {
      if (context.role == AgentDashboardMessageRole.user &&
          rule is! _DashboardEnvelopeCurrentRequestRule) {
        continue;
      }
      final before = current;
      current = rule.clean(context, current);
      if (before != current) {
        matches.add(AgentDashboardMessageCleaningMatch(
          ruleId: rule.id,
          label: rule.label,
        ));
      }
    }
    return AgentDashboardMessageCleaningResult(
      originalText: context.text,
      text: current.trimRight(),
      matches: List.unmodifiable(matches),
    );
  }
}

class _DashboardEnvelopeCurrentRequestRule
    extends AgentDashboardMessageCleaningRule {
  const _DashboardEnvelopeCurrentRequestRule();

  static const _currentRequestMarker = '\n\nCurrent request:\n';

  @override
  String get id => 'codex.dashboard_current_request';

  @override
  String get label => 'Dashboard prompt wrapper';

  @override
  String clean(AgentDashboardMessageCleaningContext context, String text) {
    if (context.source != AgentDashboardMessageSource.sessionDetail ||
        context.role != AgentDashboardMessageRole.user) {
      return text;
    }
    final normalized = text.replaceAll('\r\n', '\n');
    final markerIndex = normalized.indexOf(_currentRequestMarker);
    if (markerIndex == -1) {
      return text;
    }
    final prefix = normalized.substring(0, markerIndex);
    if (!_looksLikeDashboardPromptPrefix(prefix)) {
      return text;
    }
    return normalized
        .substring(markerIndex + _currentRequestMarker.length)
        .trimRight();
  }

  bool _looksLikeDashboardPromptPrefix(String prefix) {
    final trimmed = prefix.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    return trimmed.contains('Runtime info: rustdesk-dashboard') ||
        trimmed.contains('Conversation history:\n') ||
        trimmed.contains('Terminal snapshot:\n') ||
        trimmed.contains('Preferred skills:') ||
        trimmed.contains('Recent files:');
  }
}

class _TrailingMemoryCitationBlockRule
    extends AgentDashboardMessageCleaningRule {
  const _TrailingMemoryCitationBlockRule();

  static final RegExp _citationBlockPattern = RegExp(
    r'<oai-mem-citation>[\s\S]*?</oai-mem-citation>[ \t]*(?:\r?\n)?',
  );

  @override
  String get id => 'codex.trailing_memory_citation_block';

  @override
  String get label => 'Codex memory citation metadata';

  @override
  String clean(AgentDashboardMessageCleaningContext context, String text) {
    final matches = _citationBlockPattern.allMatches(text).toList();
    if (matches.isEmpty) {
      return text;
    }
    final cleaned = StringBuffer();
    var cursor = 0;
    var changed = false;
    for (final match in matches) {
      if (_isInsideClosedFencedCodeBlock(text, match.start, match.end)) {
        continue;
      }
      final removeStart = _memoryCitationRemoveStart(text, match.start);
      if (removeStart < cursor) {
        continue;
      }
      cleaned.write(text.substring(cursor, removeStart));
      cursor = match.end;
      changed = true;
    }
    if (!changed) {
      return text;
    }
    cleaned.write(text.substring(cursor));
    return cleaned.toString().trimRight();
  }
}

class _StandaloneCodexDirectiveRule extends AgentDashboardMessageCleaningRule {
  const _StandaloneCodexDirectiveRule();

  static final RegExp _directivePattern = RegExp(
    r'^\s*::(?:archive|code-comment|git-stage|git-commit|git-create-branch|git-push|git-create-pr)\{.*\}\s*$',
  );

  @override
  String get id => 'codex.standalone_host_directive';

  @override
  String get label => 'Codex host directive';

  @override
  String clean(AgentDashboardMessageCleaningContext context, String text) {
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    var insideFence = false;
    var changed = false;
    final kept = <String>[];
    for (final line in lines) {
      final startsFence = line.trimLeft().startsWith('```');
      if (!insideFence && _directivePattern.hasMatch(line)) {
        changed = true;
        continue;
      }
      kept.add(line);
      if (startsFence) {
        insideFence = !insideFence;
      }
    }
    return changed ? kept.join('\n').trimRight() : text;
  }
}

bool _isInsideClosedFencedCodeBlock(String text, int offset, int blockEnd) {
  final before = text.substring(0, offset).replaceAll('\r\n', '\n');
  if (!RegExp(r'(^|\n)```').allMatches(before).length.isOdd) {
    return false;
  }
  final after = text.substring(blockEnd).replaceAll('\r\n', '\n');
  return RegExp(r'(^|\n)```').hasMatch(after);
}

int _memoryCitationRemoveStart(String text, int citationStart) {
  final lineStart = text.lastIndexOf('\n', citationStart) + 1;
  var removeStart = citationStart;
  if (text.substring(lineStart, citationStart).trim().isEmpty) {
    removeStart = lineStart;
  }
  var consumedBreaks = 0;
  while (removeStart > 0 && consumedBreaks < 2) {
    var previous = removeStart - 1;
    if (text.codeUnitAt(previous) != 0x0A) {
      break;
    }
    previous -= previous > 0 && text.codeUnitAt(previous - 1) == 0x0D ? 1 : 0;
    removeStart = previous;
    consumedBreaks += 1;
  }
  return removeStart;
}
