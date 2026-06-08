enum AgentResponsePresentationStatus {
  completed,
  running,
  needsConfirmation,
  failed,
  informational,
}

class AgentResponsePresentationSection {
  const AgentResponsePresentationSection({
    required this.id,
    required this.title,
    required this.content,
  });

  final String id;
  final String title;
  final String content;
}

class AgentResponsePresentation {
  const AgentResponsePresentation({
    required this.rawText,
    required this.shouldUseCard,
    required this.status,
    required this.statusLabel,
    required this.title,
    required this.summary,
    required this.chips,
    required this.sections,
  });

  final String rawText;
  final bool shouldUseCard;
  final AgentResponsePresentationStatus status;
  final String statusLabel;
  final String title;
  final String summary;
  final List<String> chips;
  final List<AgentResponsePresentationSection> sections;

  bool get hasDetails => sections.isNotEmpty || rawText.trim().isNotEmpty;
}

class AgentDashboardMessagePresentationHarness {
  const AgentDashboardMessagePresentationHarness();

  static const int _cardLengthThreshold = 360;
  static const int _cardLineThreshold = 8;

  AgentResponsePresentation present(String text) {
    final normalized = text.replaceAll('\r\n', '\n').trim();
    final lines = normalized
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.trim().isNotEmpty)
        .toList();
    final sections = _extractSections(normalized);
    final shouldUseCard = normalized.length >= _cardLengthThreshold ||
        lines.length >= _cardLineThreshold ||
        sections.length >= 2 ||
        _hasStructuralMarkers(normalized);
    final status = _inferStatus(normalized);
    final title = _deriveTitle(lines, status);
    final summary = _deriveSummary(normalized, lines, sections);
    final chips = _deriveChips(normalized, status, sections);

    return AgentResponsePresentation(
      rawText: normalized,
      shouldUseCard: shouldUseCard,
      status: status,
      statusLabel: _statusLabel(status),
      title: title,
      summary: summary,
      chips: List.unmodifiable(chips),
      sections: List.unmodifiable(sections),
    );
  }

  List<AgentResponsePresentationSection> _extractSections(String text) {
    final headingMatches = RegExp(
      r'^(?:#{1,3}\s+|\*\*)?'
      r'(Summary|Changes?|Validation|Tests?|Risks?|Notes?|'
      r'Next Actions?|Actions?)'
      r'(?:\*\*)?\s*:?\s*$',
      caseSensitive: false,
      multiLine: true,
    ).allMatches(text).toList();

    if (headingMatches.isEmpty) {
      return _classifiedSections(text);
    }

    final sections = <AgentResponsePresentationSection>[];
    for (var index = 0; index < headingMatches.length; index++) {
      final match = headingMatches[index];
      final title = _normalizeSectionTitle(match.group(1) ?? 'Details');
      final contentStart = match.end;
      final contentEnd = index + 1 < headingMatches.length
          ? headingMatches[index + 1].start
          : text.length;
      final content = text.substring(contentStart, contentEnd).trim();
      if (content.isEmpty) {
        continue;
      }
      sections.add(AgentResponsePresentationSection(
        id: _sectionId(title),
        title: title,
        content: content,
      ));
    }
    return _dedupeSections(sections);
  }

  List<AgentResponsePresentationSection> _classifiedSections(String text) {
    final lines = text.split('\n').map((line) => line.trim()).toList();
    final changes = <String>[];
    final validation = <String>[];
    final risks = <String>[];
    final actions = <String>[];

    for (final line in lines) {
      if (line.isEmpty) {
        continue;
      }
      final lower = line.toLowerCase();
      if (_looksLikeValidation(line, lower)) {
        validation.add(line);
      } else if (_looksLikeRisk(line, lower)) {
        risks.add(line);
      } else if (_looksLikeAction(line, lower)) {
        actions.add(line);
      } else if (_looksLikeChange(line, lower)) {
        changes.add(line);
      }
    }

    final sections = <AgentResponsePresentationSection>[
      if (changes.length >= 2)
        AgentResponsePresentationSection(
          id: 'changes',
          title: 'Changes',
          content: changes.join('\n'),
        ),
      if (validation.isNotEmpty)
        AgentResponsePresentationSection(
          id: 'validation',
          title: 'Validation',
          content: validation.join('\n'),
        ),
      if (risks.isNotEmpty)
        AgentResponsePresentationSection(
          id: 'risks',
          title: 'Risks',
          content: risks.join('\n'),
        ),
      if (actions.isNotEmpty)
        AgentResponsePresentationSection(
          id: 'next-actions',
          title: 'Next Actions',
          content: actions.join('\n'),
        ),
    ];
    return _dedupeSections(sections);
  }

  bool _hasStructuralMarkers(String text) {
    return RegExp(
      r'^(?:[-*]\s+|\d+[.)]\s+|#{1,3}\s+|'
      r'(Summary|Changes?|Validation|Risks?|Next Actions?)\s*:?\s*$)',
      caseSensitive: false,
      multiLine: true,
    ).hasMatch(text);
  }

  AgentResponsePresentationStatus _inferStatus(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('failed') ||
        lower.contains('error') ||
        text.contains('FAIL')) {
      return AgentResponsePresentationStatus.failed;
    }
    if (lower.contains('needs approval') ||
        lower.contains('needs confirmation') ||
        lower.contains('approval required')) {
      return AgentResponsePresentationStatus.needsConfirmation;
    }
    if (lower.contains('running') ||
        lower.contains('in progress') ||
        lower.contains('processing')) {
      return AgentResponsePresentationStatus.running;
    }
    if (lower.contains('passed') ||
        lower.contains('completed') ||
        lower.contains('done') ||
        lower.contains('success')) {
      return AgentResponsePresentationStatus.completed;
    }
    return AgentResponsePresentationStatus.informational;
  }

  String _deriveTitle(
    List<String> lines,
    AgentResponsePresentationStatus status,
  ) {
    for (final line in lines.take(4)) {
      final cleaned = _stripMarkdownMarker(line);
      if (cleaned.length < 8 || _isGenericHeading(cleaned)) {
        continue;
      }
      return _truncate(cleaned, 64);
    }
    switch (status) {
      case AgentResponsePresentationStatus.completed:
        return 'Completed response';
      case AgentResponsePresentationStatus.running:
        return 'In-progress response';
      case AgentResponsePresentationStatus.needsConfirmation:
        return 'Needs confirmation';
      case AgentResponsePresentationStatus.failed:
        return 'Failed response';
      case AgentResponsePresentationStatus.informational:
        return 'Agent response';
    }
  }

  String _deriveSummary(
    String text,
    List<String> lines,
    List<AgentResponsePresentationSection> sections,
  ) {
    final summarySection = _firstSectionContent(sections, 'summary');
    if (summarySection != null && summarySection.trim().isNotEmpty) {
      return _truncate(_compactWhitespace(summarySection), 180);
    }

    final paragraph = _firstReadableBlock(text);
    if (paragraph != null) {
      return _truncate(paragraph, 180);
    }

    final line = _firstReadableLine(lines);
    return line == null
        ? 'No readable summary available.'
        : _truncate(line, 180);
  }

  List<String> _deriveChips(
    String text,
    AgentResponsePresentationStatus status,
    List<AgentResponsePresentationSection> sections,
  ) {
    final chips = <String>[_statusLabel(status)];
    final fileCount = RegExp(
      r'(?:(?:changed|updated|added|removed)\s*)?(\d+)\s*files?',
      caseSensitive: false,
    ).firstMatch(text);
    if (fileCount != null) {
      chips.add('${fileCount.group(1)} files');
    }
    if (RegExp(r'flutter test|tests? passed|validation|analyze|passed',
            caseSensitive: false)
        .hasMatch(text)) {
      chips.add('Validation');
    }
    if (RegExp(r'risk|warning|caution', caseSensitive: false).hasMatch(text)) {
      chips.add('Risks');
    }
    if (sections.isNotEmpty) {
      chips.add('${sections.length} sections');
    }
    return chips.take(4).toList();
  }

  bool _looksLikeValidation(String line, String lower) {
    return lower.contains('flutter test') ||
        lower.contains('analyze') ||
        lower.contains('test passed') ||
        lower.contains('tests passed') ||
        lower.contains('validation') ||
        lower.contains('passed');
  }

  bool _looksLikeRisk(String line, String lower) {
    return lower.contains('risk') ||
        lower.contains('warning') ||
        lower.contains('caution');
  }

  bool _looksLikeAction(String line, String lower) {
    return lower.contains('next') ||
        lower.contains('action') ||
        lower.contains('recommend');
  }

  bool _looksLikeChange(String line, String lower) {
    return lower.contains('changed') ||
        lower.contains('updated') ||
        lower.contains('added') ||
        lower.contains('removed') ||
        lower.contains('.dart');
  }

  List<AgentResponsePresentationSection> _dedupeSections(
    List<AgentResponsePresentationSection> sections,
  ) {
    final seen = <String>{};
    final deduped = <AgentResponsePresentationSection>[];
    for (final section in sections) {
      if (seen.add(section.id)) {
        deduped.add(section);
      }
    }
    return deduped;
  }

  String _normalizeSectionTitle(String title) {
    final lower = title.toLowerCase();
    if (lower == 'summary') {
      return 'Summary';
    }
    if (lower.startsWith('change')) {
      return 'Changes';
    }
    if (lower.startsWith('validation') || lower.startsWith('test')) {
      return 'Validation';
    }
    if (lower.startsWith('risk')) {
      return 'Risks';
    }
    if (lower.contains('action') || lower.startsWith('next')) {
      return 'Next Actions';
    }
    return 'Notes';
  }

  String _sectionId(String title) {
    return title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  }

  String _statusLabel(AgentResponsePresentationStatus status) {
    switch (status) {
      case AgentResponsePresentationStatus.completed:
        return 'Done';
      case AgentResponsePresentationStatus.running:
        return 'Running';
      case AgentResponsePresentationStatus.needsConfirmation:
        return 'Needs approval';
      case AgentResponsePresentationStatus.failed:
        return 'Failed';
      case AgentResponsePresentationStatus.informational:
        return 'Info';
    }
  }

  String? _firstSectionContent(
    List<AgentResponsePresentationSection> sections,
    String id,
  ) {
    for (final section in sections) {
      if (section.id == id) {
        return section.content;
      }
    }
    return null;
  }

  String? _firstReadableBlock(String text) {
    for (final block in text.split(RegExp(r'\n\s*\n'))) {
      final compact = _compactWhitespace(block);
      if (compact.length >= 12 && !_isGenericHeading(compact)) {
        return compact;
      }
    }
    return null;
  }

  String? _firstReadableLine(List<String> lines) {
    for (final line in lines) {
      final value = _stripMarkdownMarker(line);
      if (value.length >= 8 && !_isGenericHeading(value)) {
        return value;
      }
    }
    return null;
  }

  bool _isGenericHeading(String value) {
    final normalized = value.trim().toLowerCase();
    return const {
      'summary',
      'changes',
      'change',
      'validation',
      'tests',
      'test',
      'risks',
      'risk',
      'notes',
      'next actions',
      'actions',
    }.contains(normalized);
  }

  String _stripMarkdownMarker(String value) {
    return value
        .replaceFirst(RegExp(r'^\s*#{1,6}\s+'), '')
        .replaceFirst(RegExp(r'^\s*[-*]\s+'), '')
        .replaceFirst(RegExp(r'^\s*\d+[.)]\s+'), '')
        .replaceAll(RegExp(r'^\*\*|\*\*$'), '')
        .trim();
  }

  String _compactWhitespace(String value) {
    return _stripMarkdownMarker(value).replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _truncate(String value, int maxLength) {
    final compact = _compactWhitespace(value);
    if (compact.length <= maxLength) {
      return compact;
    }
    return '${compact.substring(0, maxLength - 3).trimRight()}...';
  }
}
