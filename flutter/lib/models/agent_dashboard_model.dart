import 'dart:async';
import 'dart:convert';

import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'agent_dashboard_storage.dart';
import 'agent_dashboard_message_cleaning.dart';
import 'agent_dashboard_storage_factory.dart';
import 'agent_dashboard_runtime_factory.dart';

class AgentConversation {
  final String id;
  final String title;
  final String projectId;
  final String threadMode;
  final String profile;
  final String sessionRef;
  final List<String> selectedSkillIds;
  final bool pinned;
  final bool archived;
  final String draft;
  final bool includeConversationHistory;
  final bool includeTerminalContext;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastReadAt;
  final List<ChatMessage> messages;

  const AgentConversation({
    required this.id,
    required this.title,
    required this.projectId,
    required this.threadMode,
    required this.profile,
    required this.sessionRef,
    required this.selectedSkillIds,
    required this.pinned,
    required this.archived,
    required this.draft,
    required this.includeConversationHistory,
    required this.includeTerminalContext,
    required this.createdAt,
    required this.updatedAt,
    required this.lastReadAt,
    required this.messages,
  });

  AgentConversation copyWith({
    String? id,
    String? title,
    String? projectId,
    String? threadMode,
    String? profile,
    String? sessionRef,
    List<String>? selectedSkillIds,
    bool? pinned,
    bool? archived,
    String? draft,
    bool? includeConversationHistory,
    bool? includeTerminalContext,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastReadAt,
    List<ChatMessage>? messages,
  }) {
    return AgentConversation(
      id: id ?? this.id,
      title: title ?? this.title,
      projectId: projectId ?? this.projectId,
      threadMode: threadMode ?? this.threadMode,
      profile: profile ?? this.profile,
      sessionRef: sessionRef ?? this.sessionRef,
      selectedSkillIds: selectedSkillIds ?? this.selectedSkillIds,
      pinned: pinned ?? this.pinned,
      archived: archived ?? this.archived,
      draft: draft ?? this.draft,
      includeConversationHistory:
          includeConversationHistory ?? this.includeConversationHistory,
      includeTerminalContext:
          includeTerminalContext ?? this.includeTerminalContext,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      messages: messages ?? this.messages,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'projectId': projectId,
      'threadMode': threadMode,
      'profile': profile,
      'sessionRef': sessionRef,
      'selectedSkillIds': selectedSkillIds,
      'pinned': pinned,
      'archived': archived,
      'draft': draft,
      'includeConversationHistory': includeConversationHistory,
      'includeTerminalContext': includeTerminalContext,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'lastReadAt': lastReadAt?.toIso8601String(),
    };
  }

  static AgentConversation fromJson(Map<String, dynamic> json) {
    final rawSessionRef = json['sessionRef']?.toString().trim() ?? '';
    return AgentConversation(
      id: json['id']?.toString() ?? const Uuid().v4(),
      title: json['title']?.toString() ?? 'New conversation',
      projectId: json['projectId']?.toString() ?? 'rustdesk',
      threadMode:
          json['threadMode']?.toString() == 'continue' ? 'continue' : 'new',
      profile: json['profile']?.toString() ?? '',
      sessionRef: rawSessionRef == '@last' ? '' : rawSessionRef,
      selectedSkillIds: (json['selectedSkillIds'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList(),
      pinned: json['pinned'] == true,
      archived: json['archived'] == true,
      draft: json['draft']?.toString() ?? '',
      includeConversationHistory: json['includeConversationHistory'] != false,
      includeTerminalContext: json['includeTerminalContext'] == true,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
      lastReadAt: DateTime.tryParse(json['lastReadAt']?.toString() ?? ''),
      messages: const [],
    );
  }
}

enum AgentConversationStatus {
  idle,
  running,
  needsConfirmation,
  completed,
  failed,
}

enum AgentConversationListFilter {
  active,
  pinned,
  archived,
  all,
}

class AgentTaskStatusBubble {
  const AgentTaskStatusBubble({
    required this.id,
    required this.conversationId,
    required this.projectId,
    required this.status,
    required this.title,
    required this.summary,
    required this.createdAt,
    required this.expiresAt,
    required this.sticky,
    this.requestId,
    this.dedupeKey,
  });

  final String id;
  final String? requestId;
  final String conversationId;
  final String projectId;
  final AgentConversationStatus status;
  final String title;
  final String summary;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final bool sticky;
  final String? dedupeKey;

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
}

abstract class AgentDashboardRuntime {
  String get peerId;

  List<String> loadProjectIds();

  String loadTerminalContext();

  Future<void> dispatchCommand({
    required String requestId,
    required String projectId,
    required String prompt,
    required String mode,
    required bool requireConfirmation,
  });

  Future<void> dispatchEnvelope(Map<String, dynamic> envelope);

  Future<List<Map<String, dynamic>>> loadSessions({String? conversationId});

  Future<Map<String, dynamic>?> loadSessionDetail(String sessionId,
      {int? cursor, int pageSize = 40, String? conversationId});

  Future<List<Map<String, dynamic>>> loadSkills({String? conversationId});

  Future<Map<String, dynamic>> upsertSkill(Map<String, dynamic> payload);

  Future<void> deleteSkill(String skillId);

  Future<Map<String, dynamic>> syncSkills();

  Future<Map<String, dynamic>> transcribeVoice(Map<String, dynamic> payload);

  Future<String> recordVoiceClipBase64({
    Duration duration = const Duration(seconds: 5),
  }) async {
    throw UnsupportedError('Voice recording is not available in this runtime.');
  }

  Future<Map<String, dynamic>?> requestTaskStatus({
    required String requestId,
    required String projectId,
  });

  bool get defersSkillCatalogLoad => false;

  bool hasActiveStatusTracking(String requestId) => false;

  Future<void> onCommandDispatched({
    required AgentDashboardModel model,
    required AgentConversation conversation,
    required String prompt,
    required String requestId,
  }) async {}
}

Map<String, dynamic> buildAgentRunRequestBodyFromEnvelope(
  Map<String, dynamic> envelope,
) {
  final route = Map<String, dynamic>.from(envelope['route'] as Map? ?? {});
  final requestId = envelope['requestId']?.toString().trim().isNotEmpty == true
      ? envelope['requestId'].toString().trim()
      : const Uuid().v4();
  final projectId = route['projectId']?.toString().trim().isNotEmpty == true
      ? route['projectId'].toString().trim()
      : AgentDashboardModel.defaultProjectId;
  final mode = envelope['mode']?.toString().trim().isNotEmpty == true
      ? envelope['mode'].toString().trim()
      : 'read-only';
  final sessionRef =
      route['codexThreadId']?.toString().trim().isNotEmpty == true
          ? route['codexThreadId'].toString().trim()
          : (route['activeThreadId']?.toString().trim().isNotEmpty == true
              ? route['activeThreadId'].toString().trim()
              : '');
  final resumeLast = route['threadMode']?.toString() == 'continue';
  return {
    'request_id': requestId,
    'project': projectId,
    'prompt': jsonEncode(envelope),
    'mode': mode,
    'require_confirmation': envelope['requireConfirmation'] == true,
    if (sessionRef.isNotEmpty) 'session': sessionRef,
    'resume_last': resumeLast,
    if (route['profileId']?.toString().trim().isNotEmpty == true)
      'profile': route['profileId'].toString().trim(),
  };
}

class MockAgentDashboardRuntime implements AgentDashboardRuntime {
  MockAgentDashboardRuntime({
    this.peerId = 'dashboard-dev',
    List<String>? projects,
    String? terminalContext,
  })  : _projects = projects ?? const ['rustdesk', 'minister', 'workflow'],
        _terminalContext = terminalContext ??
            'PS E:\\rustDesk> cargo build -p rustdesk-flutter\n'
                'Finished dev [unoptimized + debuginfo] target(s) in 3.8s\n\n'
                'PS E:\\rustDesk> codex exec --cd E:\\rustDesk --sandbox read-only "analyze Android entry"\n'
                'Summary: mobile startup path resolved through flutter/lib/main.dart -> App.build().';

  @override
  final String peerId;

  final List<String> _projects;
  final String _terminalContext;

  @override
  List<String> loadProjectIds() => List<String>.from(_projects);

  @override
  String loadTerminalContext() => _terminalContext;

  @override
  bool get defersSkillCatalogLoad => false;

  @override
  Future<void> dispatchCommand({
    required String requestId,
    required String projectId,
    required String prompt,
    required String mode,
    required bool requireConfirmation,
  }) async {}

  @override
  Future<void> dispatchEnvelope(Map<String, dynamic> envelope) async {}

  @override
  Future<List<Map<String, dynamic>>> loadSessions(
      {String? conversationId}) async {
    return [
      {
        'id': 'session-rustdesk-latest',
        'title': 'Pocket-Codex latest thread',
        'updatedAt': DateTime.now().toIso8601String(),
      },
      {
        'id': 'session-mobile-route',
        'title': 'Mobile routing review',
        'updatedAt':
            DateTime.now().subtract(const Duration(hours: 3)).toIso8601String(),
      },
    ];
  }

  @override
  Future<Map<String, dynamic>?> loadSessionDetail(String sessionId,
      {int? cursor, int pageSize = 40, String? conversationId}) async {
    return {
      'id': sessionId,
      'title': sessionId == 'session-rustdesk-latest'
          ? 'Pocket-Codex latest thread'
          : 'Mobile routing review',
      'updatedAt': DateTime.now().toIso8601String(),
      'messages': [
        {
          'role': 'assistant',
          'text': 'Mock session detail for $sessionId',
          'timestamp': DateTime.now().toIso8601String(),
        },
      ],
      'timeline': [
        {
          'stage': 'done',
          'summary': 'Mock session detail loaded.',
          'ts': DateTime.now().millisecondsSinceEpoch,
        }
      ],
      'rawEvents': const [],
      'nextCursor': null,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> loadSkills(
      {String? conversationId}) async {
    return [
      {
        'id': 'route-analyzer',
        'title': 'Route Analyzer',
        'group': 'core',
        'description': 'Summarize remote routing paths.',
        'enabled': true,
        'mirrorName': 'route-analyzer',
        'tags': ['routing', 'analysis'],
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      {
        'id': 'write-planner',
        'title': 'Write Planner',
        'group': 'safe-write',
        'description': 'Generate plans before workspace-write.',
        'enabled': true,
        'mirrorName': 'write-planner',
        'tags': ['write', 'planning'],
        'updatedAt': DateTime.now()
            .subtract(const Duration(hours: 1))
            .millisecondsSinceEpoch,
      },
    ];
  }

  @override
  Future<Map<String, dynamic>> upsertSkill(Map<String, dynamic> payload) async {
    return payload;
  }

  @override
  Future<void> deleteSkill(String skillId) async {}

  @override
  Future<Map<String, dynamic>> syncSkills() async {
    return {
      'status': 'ok',
      'synced': 2,
      'errors': const [],
    };
  }

  @override
  Future<Map<String, dynamic>> transcribeVoice(
      Map<String, dynamic> payload) async {
    return {
      'status': 'ok',
      'audioPath': '/mock/audio.wav',
      'transcript': 'Mock voice transcript',
    };
  }

  @override
  Future<String> recordVoiceClipBase64({
    Duration duration = const Duration(seconds: 5),
  }) async {
    return 'UklGRg==';
  }

  @override
  Future<Map<String, dynamic>?> requestTaskStatus({
    required String requestId,
    required String projectId,
  }) async {
    return {
      'request_id': requestId,
      'project':
          projectId.isEmpty ? AgentDashboardModel.defaultProjectId : projectId,
      'status': 'done',
      'text': 'Mock status refresh completed.',
      'token': '',
      'detail_json': '',
    };
  }

  @override
  bool hasActiveStatusTracking(String requestId) => false;

  @override
  Future<void> onCommandDispatched({
    required AgentDashboardModel model,
    required AgentConversation conversation,
    required String prompt,
    required String requestId,
  }) async {
    final project = conversation.projectId.trim().isEmpty
        ? AgentDashboardModel.defaultProjectId
        : conversation.projectId.trim();
    final compactPrompt = prompt.trim().replaceAll(RegExp(r'\s+'), ' ');

    await Future<void>.delayed(const Duration(milliseconds: 240));
    model.tryHandleAgentText(
      '[Agent:$project] started: mock bridge accepted the request.',
    );

    if (_shouldFail(compactPrompt)) {
      await Future<void>.delayed(const Duration(milliseconds: 520));
      model.tryHandleAgentText(
        '[Agent:$project] failed:\n'
        'Mock route injected a failure so the dashboard can preview the error state.',
      );
      return;
    }

    if (_needsConfirmation(compactPrompt)) {
      await Future<void>.delayed(const Duration(milliseconds: 620));
      model.tryHandleAgentText(
        '[Agent:$project] needs confirmation: workspace-write required.\n'
        'Plan:\n'
        '- inspect the target files\n'
        '- patch only the requested surface\n'
        '- rerun focused validation before returning the result',
      );
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 780));
    model.tryHandleAgentText(
      '[Agent:$project] done:\n'
      'Mock read-only analysis for "${_summarizePrompt(compactPrompt)}".\n'
      'Entry: flutter/lib/main.dart -> App.build()\n'
      'Runtime: AgentDashboardModel -> mock bridge\n'
      'Next: replace mock runtime with a real session or keep using hot reload.',
    );
  }

  bool _needsConfirmation(String prompt) {
    const markers = [
      'modify',
      'write',
      'patch',
      'edit',
      'refactor',
      'implement',
      'rename',
      'delete',
      'fix',
      'create',
    ];
    final lower = prompt.toLowerCase();
    return markers.any((marker) => lower.contains(marker));
  }

  bool _shouldFail(String prompt) {
    const markers = ['fail', 'error'];
    final lower = prompt.toLowerCase();
    return markers.any((marker) => lower.contains(marker));
  }

  String _summarizePrompt(String prompt) {
    if (prompt.isEmpty) return 'empty request';
    return prompt.length > 60 ? '${prompt.substring(0, 60)}...' : prompt;
  }
}

class AgentDashboardModel with ChangeNotifier {
  AgentDashboardModel(Object parent)
      : this.fromRuntime(createRustDeskAgentDashboardRuntime(parent));

  AgentDashboardModel.fromRuntime(
    this.runtime, {
    bool seedDemoData = false,
    AgentDashboardStorage? storage,
    AgentDashboardMessageCleaningHarness? messageCleaningHarness,
  })  : _seedDemoData = seedDemoData,
        _storage = storage ?? createAgentDashboardStorage(),
        _messageCleaningHarness = messageCleaningHarness ??
            AgentDashboardMessageCleaningHarness.codexSession() {
    textController.addListener(_handleComposerChanged);
  }

  factory AgentDashboardModel.dev() {
    return AgentDashboardModel.fromRuntime(
      MockAgentDashboardRuntime(),
      seedDemoData: true,
    );
  }

  factory AgentDashboardModel.webBridge() {
    return AgentDashboardModel.fromRuntime(
      createRustDeskAgentDashboardRuntime(Object()),
    );
  }

  static const _storageFileName = 'agent_dashboard_conversations.json';
  static const String defaultProjectId = 'rustdesk';
  static const _bridgeRunTransportFailure =
      'Failed to send /agent/run to codex bridge';
  static const _maxVisibleTaskStatusBubbles = 2;
  static const _backgroundSessionPrefetchDelay = Duration(milliseconds: 200);
  static const _backgroundSessionPrefetchTargetMessages = 8;

  final AgentDashboardRuntime runtime;
  final bool _seedDemoData;
  final AgentDashboardStorage _storage;
  final AgentDashboardMessageCleaningHarness _messageCleaningHarness;
  final ChatUser me = ChatUser(id: const Uuid().v4(), firstName: 'Me');
  final ChatUser assistant = ChatUser(id: 'agent', firstName: 'Agent');
  final TextEditingController textController = TextEditingController();
  final FocusNode inputFocusNode = FocusNode();

  List<AgentConversation> _conversations = [];
  String? _selectedConversationId;
  List<String> _availableProjects = [defaultProjectId];
  bool _loaded = false;
  bool _saving = false;
  bool _saveQueued = false;
  bool _syncingComposer = false;
  bool _voiceRecording = false;
  String _searchQuery = '';
  String? _projectFilter;
  AgentConversationListFilter _listFilter = AgentConversationListFilter.active;
  String? _activeRequestConversationId;
  Timer? _draftSaveTimer;
  final Map<String, AgentConversationStatus> _runtimeStatuses = {};
  final Map<String, String> _runtimeStatusDetails = {};
  final Map<String, List<Map<String, dynamic>>> _timelineByConversation = {};
  final Map<String, List<Map<String, dynamic>>> _rawEventsByConversation = {};
  final Map<String, String> _requestToConversation = {};
  final Map<String, int> _statusRecoveryAttempts = {};
  final Map<String, DateTime> _recentStructuredAgentResults = {};
  final Map<String, int?> _sessionNextCursorByConversation = {};
  final Set<String> _sessionHydrationInFlight = <String>{};
  final List<AgentTaskStatusBubble> _taskStatusBubbles = [];
  final Set<String> _taskStatusBubbleDedupeKeys = <String>{};
  final Map<String, String> _requestStatusBubbleKeys = {};
  Timer? _taskStatusBubbleTimer;
  Timer? _sessionCatalogRetryTimer;
  int _sessionCatalogRetryCount = 0;
  List<Map<String, dynamic>> _sessionSummaries = [];
  List<Map<String, dynamic>> _skillCatalog = [];
  bool _skillsLoaded = false;
  bool _skillsLoading = false;
  bool _sessionsLoaded = false;

  List<AgentConversation> get conversations => _conversations;

  List<AgentConversation> get visibleConversations {
    final normalizedQuery = _searchQuery.trim().toLowerCase();
    final filtered = _conversations.where((conversation) {
      switch (_listFilter) {
        case AgentConversationListFilter.active:
          if (conversation.archived) return false;
          break;
        case AgentConversationListFilter.pinned:
          if (conversation.archived || !conversation.pinned) return false;
          break;
        case AgentConversationListFilter.archived:
          if (!conversation.archived) return false;
          break;
        case AgentConversationListFilter.all:
          break;
      }
      if (_projectFilter != null &&
          !_sameProjectId(_projectFilter!, conversation.projectId)) {
        return false;
      }
      if (normalizedQuery.isEmpty) {
        return true;
      }
      final fields = [
        conversation.title,
        conversation.projectId,
        conversation.profile,
        conversation.sessionRef,
        conversation.draft,
        latestSnippet(conversation),
      ].join(' ').toLowerCase();
      return fields.contains(normalizedQuery);
    }).toList();
    return filtered;
  }

  List<String> get availableProjects => _collectAvailableProjects();
  List<AgentTaskStatusBubble> get visibleTaskStatusBubbles {
    _pruneExpiredTaskStatusBubbles();
    return List<AgentTaskStatusBubble>.unmodifiable(_taskStatusBubbles);
  }

  List<Map<String, dynamic>> get sessionSummaries => _sessionSummaries;
  List<Map<String, dynamic>> get filteredSessionSummaries {
    if (_projectFilter == null) {
      return _sessionSummaries;
    }
    return _sessionSummaries
        .where((session) =>
            _sameProjectId(sessionProjectId(session), _projectFilter!))
        .toList();
  }

  List<Map<String, dynamic>> get skillCatalog => _skillCatalog;
  bool get loaded => _loaded;
  bool get sessionsLoaded => _sessionsLoaded;
  bool get skillsLoaded => _skillsLoaded;
  bool get skillsLoading => _skillsLoading;
  bool get isVoiceRecording => _voiceRecording;
  String get searchQuery => _searchQuery;
  String? get projectFilter => _projectFilter;
  AgentConversationListFilter get listFilter => _listFilter;

  int get unreadConversationCount => _conversations
      .where((conversation) =>
          !conversation.archived && _conversationHasUnread(conversation))
      .length;

  AgentConversation? get selectedConversation {
    final index = _selectedConversationIndex();
    if (index == -1) return null;
    return _conversations[index];
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loadAvailableProjects();
    await _load();
    var createdInitialConversation = false;
    if (_conversations.isEmpty) {
      if (_seedDemoData) {
        _conversations = _buildDemoConversations();
        _sortConversations();
        _applyDemoStatuses(_conversations);
      } else {
        final initial = _newConversation();
        _conversations = [initial];
      }
      createdInitialConversation = true;
      _selectedConversationId = _conversations.first.id;
    } else {
      _sortConversations();
      _selectedConversationId ??= _conversations.first.id;
    }
    final selectedIndex = _selectedConversationIndex();
    _syncSelectedConversationSideEffects(
      selectedIndex,
      notifyRead: false,
      persistRead: false,
    );
    final attachedLatestSession = await _loadRuntimeCatalogs();
    final reconciledProjects =
        !attachedLatestSession && _reconcileConversationProjectsFromSessions();
    if (reconciledProjects) {
      await _save();
    }
    if (createdInitialConversation && !attachedLatestSession) {
      await _save();
    }
    _loaded = true;
    notifyListeners();
    final trailingSelectedIndex = _selectedConversationIndex();
    unawaited(_ensureConversationHydratedAtIndex(trailingSelectedIndex));
    _scheduleDeferredSessionCatalogRetry();
  }

  AgentConversation createConversation({
    String? title,
    String projectId = defaultProjectId,
    String? threadMode,
    String profile = '',
    String sessionRef = '',
    List<String>? selectedSkillIds,
    bool? pinned,
    bool? includeConversationHistory,
    bool includeTerminalContext = true,
  }) {
    final templateIndex = _selectedConversationIndex();
    final template = templateIndex == -1 ? null : _conversations[templateIndex];
    final normalizedSessionRef = sessionRef.trim();
    final normalizedThreadMode = threadMode == 'continue'
        ? 'continue'
        : (normalizedSessionRef.isNotEmpty ? 'continue' : 'new');
    final normalizedSkillIds =
        (selectedSkillIds ?? template?.selectedSkillIds ?? const <String>[])
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList();
    final inheritedProjectId = projectId == defaultProjectId && template != null
        ? template.projectId
        : projectId;
    final normalizedProjectId = _canonicalProjectId(inheritedProjectId);
    final conversation = AgentConversation(
      id: const Uuid().v4(),
      title:
          title?.trim().isNotEmpty == true ? title!.trim() : 'New conversation',
      projectId: normalizedSessionRef.isEmpty
          ? normalizedProjectId
          : (sessionProjectIdForSessionId(normalizedSessionRef) ??
              normalizedProjectId),
      threadMode: normalizedThreadMode,
      profile: profile.isEmpty && template != null ? template.profile : profile,
      sessionRef: normalizedSessionRef,
      selectedSkillIds: normalizedSkillIds,
      pinned: pinned ?? false,
      archived: false,
      draft: '',
      includeConversationHistory: includeConversationHistory ??
          template?.includeConversationHistory ??
          true,
      includeTerminalContext: includeTerminalContext,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      lastReadAt: DateTime.now(),
      messages: const [],
    );
    _conversations = [conversation, ..._conversations];
    _sortConversations();
    _selectedConversationId = conversation.id;
    _syncComposerDraft('');
    unawaited(_save());
    notifyListeners();
    return conversation;
  }

  void selectConversation(String conversationId) {
    if (_selectedConversationId == conversationId) {
      final index = _selectedConversationIndex();
      if (index == -1) {
        return;
      }
      _syncSelectedConversationSideEffects(index, syncComposer: false);
      return;
    }
    final index = _conversationIndexById(conversationId);
    final nextSelectedIndex =
        index == -1 && _conversations.isNotEmpty ? 0 : index;
    final nextSelectedConversation =
        nextSelectedIndex == -1 ? null : _conversations[nextSelectedIndex];
    final nextSelectedConversationId =
        nextSelectedConversation?.id ?? conversationId;
    _selectedConversationId = nextSelectedConversationId;
    if (nextSelectedConversation != null) {
      dismissTaskStatusBubblesForConversation(nextSelectedConversation.id,
          notify: false);
      _syncSelectedConversationSideEffects(
        nextSelectedIndex,
        notifyRead: false,
      );
    } else {
      _syncComposerDraft('');
    }
    notifyListeners();
    if (nextSelectedConversation != null) {
      unawaited(_ensureConversationHydratedAtIndex(nextSelectedIndex));
    }
  }

  void updateConversationSettings({
    required String conversationId,
    String? title,
    String? projectId,
    String? threadMode,
    String? profile,
    String? sessionRef,
    List<String>? selectedSkillIds,
    bool? pinned,
    bool? archived,
    String? draft,
    bool? includeConversationHistory,
    bool? includeTerminalContext,
    DateTime? lastReadAt,
    bool hydrateIfNeeded = true,
    bool persist = true,
  }) {
    _updateConversationSettingsById(
      conversationId: conversationId,
      title: title,
      projectId: projectId,
      threadMode: threadMode,
      profile: profile,
      sessionRef: sessionRef,
      selectedSkillIds: selectedSkillIds,
      pinned: pinned,
      archived: archived,
      draft: draft,
      includeConversationHistory: includeConversationHistory,
      includeTerminalContext: includeTerminalContext,
      lastReadAt: lastReadAt,
      hydrateIfNeeded: hydrateIfNeeded,
      persist: persist,
    );
  }

  void _updateConversationSettingsAtIndex({
    required int index,
    required String conversationId,
    String? title,
    String? projectId,
    String? threadMode,
    String? profile,
    String? sessionRef,
    List<String>? selectedSkillIds,
    bool? pinned,
    bool? archived,
    String? draft,
    bool? includeConversationHistory,
    bool? includeTerminalContext,
    DateTime? lastReadAt,
    bool hydrateIfNeeded = true,
    bool persist = true,
    bool clearMessagesOnSessionReset = true,
  }) {
    final currentConversation = _conversations[index];
    final previousSessionRef = currentConversation.sessionRef.trim();
    final nextThreadMode = threadMode == null
        ? currentConversation.threadMode
        : (threadMode == 'continue' ? 'continue' : 'new');
    final nextSessionRef =
        sessionRef?.trim() ?? currentConversation.sessionRef.trim();
    final nextSelectedSkillIds = selectedSkillIds == null
        ? currentConversation.selectedSkillIds
        : selectedSkillIds
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList();
    final nextTitle = title ?? currentConversation.title;
    final requestedProjectId = _canonicalProjectId(projectId);
    final nextProjectId = requestedProjectId.isNotEmpty
        ? requestedProjectId
        : (nextSessionRef.isEmpty
            ? _canonicalProjectId(currentConversation.projectId)
            : (sessionProjectIdForSessionId(nextSessionRef) ??
                _canonicalProjectId(currentConversation.projectId)));
    final nextProfile = profile ?? currentConversation.profile;
    final nextStoredSessionRef = sessionRef ?? currentConversation.sessionRef;
    final nextPinned = pinned ?? currentConversation.pinned;
    final nextArchived = archived ?? currentConversation.archived;
    final nextDraft = draft ?? currentConversation.draft;
    final nextIncludeConversationHistory = includeConversationHistory ??
        currentConversation.includeConversationHistory;
    final nextIncludeTerminalContext =
        includeTerminalContext ?? currentConversation.includeTerminalContext;
    final nextLastReadAt = lastReadAt ?? currentConversation.lastReadAt;
    final shouldResetSessionState =
        nextThreadMode != 'continue' || nextSessionRef != previousSessionRef;
    final hasMetadataChanges = nextTitle != currentConversation.title ||
        nextProjectId != currentConversation.projectId ||
        nextThreadMode != currentConversation.threadMode ||
        nextProfile != currentConversation.profile ||
        nextStoredSessionRef != currentConversation.sessionRef ||
        !listEquals(
            nextSelectedSkillIds, currentConversation.selectedSkillIds) ||
        nextPinned != currentConversation.pinned ||
        nextArchived != currentConversation.archived ||
        nextDraft != currentConversation.draft ||
        nextIncludeConversationHistory !=
            currentConversation.includeConversationHistory ||
        nextIncludeTerminalContext !=
            currentConversation.includeTerminalContext ||
        nextLastReadAt != currentConversation.lastReadAt;
    if (!hasMetadataChanges && !shouldResetSessionState) {
      return;
    }
    final nextConversations = List<AgentConversation>.from(_conversations);
    final conversation = nextConversations[index];
    nextConversations[index] = conversation.copyWith(
      title: nextTitle,
      projectId: nextProjectId,
      threadMode: nextThreadMode,
      profile: nextProfile,
      sessionRef: nextStoredSessionRef,
      selectedSkillIds: nextSelectedSkillIds,
      pinned: nextPinned,
      archived: nextArchived,
      draft: nextDraft,
      includeConversationHistory: nextIncludeConversationHistory,
      includeTerminalContext: nextIncludeTerminalContext,
      updatedAt: DateTime.now(),
      lastReadAt: nextLastReadAt,
      messages: shouldResetSessionState && clearMessagesOnSessionReset
          ? const []
          : conversation.messages,
    );
    _conversations = nextConversations;
    _sortConversations();
    if (shouldResetSessionState) {
      _timelineByConversation.remove(conversationId);
      _rawEventsByConversation.remove(conversationId);
      _sessionNextCursorByConversation.remove(conversationId);
      _sessionHydrationInFlight.remove(conversationId);
    }
    if (_selectedConversationId == conversationId && draft != null) {
      _syncComposerDraft(nextDraft);
    }
    if (persist) {
      unawaited(_save());
    }
    notifyListeners();
    if (hydrateIfNeeded &&
        shouldResetSessionState &&
        nextThreadMode == 'continue' &&
        nextSessionRef.isNotEmpty) {
      final hydrationIndex = _conversationIndexById(conversationId);
      unawaited(_ensureConversationHydratedAtIndex(hydrationIndex));
    }
  }

  void _updateConversationSettingsById({
    required String conversationId,
    String? title,
    String? projectId,
    String? threadMode,
    String? profile,
    String? sessionRef,
    List<String>? selectedSkillIds,
    bool? pinned,
    bool? archived,
    String? draft,
    bool? includeConversationHistory,
    bool? includeTerminalContext,
    DateTime? lastReadAt,
    bool hydrateIfNeeded = true,
    bool persist = true,
  }) {
    final index = _conversationIndexById(conversationId);
    if (index == -1) return;
    _updateConversationSettingsAtIndex(
      index: index,
      conversationId: conversationId,
      title: title,
      projectId: projectId,
      threadMode: threadMode,
      profile: profile,
      sessionRef: sessionRef,
      selectedSkillIds: selectedSkillIds,
      pinned: pinned,
      archived: archived,
      draft: draft,
      includeConversationHistory: includeConversationHistory,
      includeTerminalContext: includeTerminalContext,
      lastReadAt: lastReadAt,
      hydrateIfNeeded: hydrateIfNeeded,
      persist: persist,
    );
  }

  void renameConversation(String conversationId, String title) {
    final normalized = title.trim();
    if (normalized.isEmpty) return;
    _updateConversationSettingsById(
      conversationId: conversationId,
      title: normalized,
    );
  }

  void toggleConversationPinned(String conversationId) {
    final index = _conversationIndexById(conversationId);
    if (index == -1) return;
    final conversation = _conversations[index];
    _updateConversationSettingsAtIndex(
      index: index,
      conversationId: conversationId,
      pinned: !conversation.pinned,
    );
  }

  void toggleConversationArchived(String conversationId) {
    final index = _conversationIndexById(conversationId);
    if (index == -1) return;
    final conversation = _conversations[index];
    _updateConversationSettingsAtIndex(
      index: index,
      conversationId: conversationId,
      archived: !conversation.archived,
      lastReadAt: DateTime.now(),
    );
  }

  void deleteConversation(String conversationId) {
    if (_conversations.isEmpty) return;
    final index = _conversationIndexById(conversationId);
    if (index == -1) return;
    final nextConversations = List<AgentConversation>.from(_conversations);
    nextConversations.removeAt(index);
    _conversations = nextConversations;
    _runtimeStatuses.remove(conversationId);
    _runtimeStatusDetails.remove(conversationId);
    _timelineByConversation.remove(conversationId);
    _rawEventsByConversation.remove(conversationId);
    _sessionNextCursorByConversation.remove(conversationId);
    _sessionHydrationInFlight.remove(conversationId);
    dismissTaskStatusBubblesForConversation(conversationId, notify: false);
    if (_activeRequestConversationId == conversationId) {
      _activeRequestConversationId = null;
    }
    var replacementIndex = -1;
    if (_conversations.isEmpty) {
      final replacement = _newConversation();
      _conversations = [replacement];
      _selectedConversationId = replacement.id;
      replacementIndex = 0;
    } else if (_selectedConversationId == conversationId) {
      _selectedConversationId = _conversations.first.id;
      replacementIndex = 0;
    } else {
      replacementIndex = _selectedConversationIndex();
    }
    if (replacementIndex != -1) {
      _syncSelectedConversationSideEffects(
        replacementIndex,
        notifyRead: false,
        persistRead: false,
      );
    }
    unawaited(_save());
    notifyListeners();
  }

  void setSearchQuery(String value) {
    if (_searchQuery == value) return;
    _searchQuery = value;
    notifyListeners();
  }

  void setProjectFilter(String? value) {
    final normalized = value?.trim();
    final nextValue = normalized == null || normalized.isEmpty
        ? null
        : _canonicalProjectId(normalized);
    if (_projectFilter == nextValue) return;
    _projectFilter = nextValue;
    notifyListeners();
  }

  void setListFilter(AgentConversationListFilter value) {
    if (_listFilter == value) return;
    _listFilter = value;
    notifyListeners();
  }

  AgentConversationStatus statusForConversation(String conversationId) {
    final index = _conversationIndexById(conversationId);
    if (index == -1) return AgentConversationStatus.idle;
    return statusForConversationObject(_conversations[index]);
  }

  AgentConversationStatus statusForConversationObject(
      AgentConversation conversation) {
    return _runtimeStatuses[conversation.id] ?? AgentConversationStatus.idle;
  }

  String statusLabelForConversation(String conversationId) {
    final index = _conversationIndexById(conversationId);
    if (index == -1) {
      return statusLabelForStatus(AgentConversationStatus.idle);
    }
    return statusLabelForConversationObject(_conversations[index]);
  }

  String statusLabelForConversationObject(AgentConversation conversation) {
    return statusLabelForStatus(statusForConversationObject(conversation));
  }

  String statusLabelForStatus(AgentConversationStatus status) {
    switch (status) {
      case AgentConversationStatus.running:
        return 'Thinking';
      case AgentConversationStatus.needsConfirmation:
        return 'Needs approval';
      case AgentConversationStatus.completed:
        return 'Done';
      case AgentConversationStatus.failed:
        return 'Failed';
      case AgentConversationStatus.idle:
        return 'Ready';
    }
  }

  String statusDetailForConversation(String conversationId) {
    final index = _conversationIndexById(conversationId);
    if (index == -1) return '';
    return statusDetailForConversationObject(_conversations[index]);
  }

  String statusDetailForConversationObject(AgentConversation conversation) {
    return _runtimeStatusDetails[conversation.id] ?? '';
  }

  void dismissTaskStatusBubble(String bubbleId, {bool notify = true}) {
    _removeTaskStatusBubbleWhere((bubble) => bubble.id == bubbleId,
        notify: notify);
  }

  void dismissTaskStatusBubblesForConversation(
    String conversationId, {
    bool notify = true,
  }) {
    _removeTaskStatusBubbleWhere(
      (bubble) => bubble.conversationId == conversationId,
      notify: notify,
    );
  }

  void openTaskStatusBubble(String bubbleId) {
    AgentTaskStatusBubble? target;
    for (final bubble in _taskStatusBubbles) {
      if (bubble.id == bubbleId) {
        target = bubble;
        break;
      }
    }
    if (target == null) {
      return;
    }
    dismissTaskStatusBubblesForConversation(target.conversationId,
        notify: false);
    selectConversation(target.conversationId);
  }

  List<Map<String, dynamic>> timelineForConversation(String conversationId) {
    final index = _conversationIndexById(conversationId);
    if (index == -1) return const [];
    return timelineForConversationObject(_conversations[index]);
  }

  List<Map<String, dynamic>> timelineForConversationObject(
      AgentConversation conversation) {
    return _timelineByConversation[conversation.id] ?? const [];
  }

  List<Map<String, dynamic>> rawEventsForConversation(String conversationId) {
    final index = _conversationIndexById(conversationId);
    if (index == -1) return const [];
    return rawEventsForConversationObject(_conversations[index]);
  }

  List<Map<String, dynamic>> rawEventsForConversationObject(
      AgentConversation conversation) {
    return _rawEventsByConversation[conversation.id] ?? const [];
  }

  bool isConversationBusy(String conversationId) {
    final index = _conversationIndexById(conversationId);
    if (index == -1) return false;
    return isConversationBusyForConversation(_conversations[index]);
  }

  bool isConversationBusyForConversation(AgentConversation conversation) {
    final status = statusForConversationObject(conversation);
    return status == AgentConversationStatus.running ||
        status == AgentConversationStatus.needsConfirmation;
  }

  bool conversationNeedsConfirmation(String conversationId) {
    final index = _conversationIndexById(conversationId);
    if (index == -1) return false;
    return conversationNeedsConfirmationForConversation(_conversations[index]);
  }

  bool conversationNeedsConfirmationForConversation(
      AgentConversation conversation) {
    return statusForConversationObject(conversation) ==
        AgentConversationStatus.needsConfirmation;
  }

  bool shouldStopStatusTracking(String conversationId) {
    final index = _conversationIndexById(conversationId);
    if (index == -1) return false;
    return shouldStopStatusTrackingForConversation(_conversations[index]);
  }

  bool shouldStopStatusTrackingForConversation(AgentConversation conversation) {
    final status = statusForConversationObject(conversation);
    return status == AgentConversationStatus.completed ||
        status == AgentConversationStatus.failed ||
        status == AgentConversationStatus.needsConfirmation;
  }

  bool conversationHasUnreadForConversation(AgentConversation conversation) {
    return _conversationHasUnread(conversation);
  }

  bool conversationHasUnread(String conversationId) {
    final index = _conversationIndexById(conversationId);
    if (index == -1) return false;
    return conversationHasUnreadForConversation(_conversations[index]);
  }

  bool canLoadMoreSessionHistory(String conversationId) {
    final index = _conversationIndexById(conversationId);
    if (index == -1) return false;
    return canLoadMoreSessionHistoryForConversation(_conversations[index]);
  }

  bool canLoadMoreSessionHistoryForConversation(
      AgentConversation conversation) {
    return _sessionNextCursorByConversation[conversation.id] != null;
  }

  bool isSessionHistoryLoading(String conversationId) {
    return _sessionHydrationInFlight.contains(conversationId);
  }

  bool isSessionHistoryLoadingForConversation(AgentConversation conversation) {
    return isSessionHistoryLoading(conversation.id);
  }

  String sessionProjectId(Map<String, dynamic> session) {
    return sessionProjectIdFromMetadata(session) ?? defaultProjectId;
  }

  bool _sameProjectId(String left, String right) {
    return left.trim().toLowerCase() == right.trim().toLowerCase();
  }

  String _canonicalProjectId(String? raw, {Iterable<String>? candidates}) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) {
      return '';
    }
    final pool = <String>[
      ...?candidates,
      ..._availableProjects,
      defaultProjectId,
    ];
    for (final candidate in pool) {
      final normalized = candidate.trim();
      if (normalized.isEmpty) {
        continue;
      }
      if (_sameProjectId(normalized, trimmed)) {
        return normalized;
      }
    }
    return trimmed;
  }

  String? sessionProjectIdFromMetadata(Map<String, dynamic> session) {
    final explicit = _canonicalProjectId(
      session['projectId']?.toString().trim() ??
          session['project_id']?.toString().trim() ??
          '',
    );
    final path = sessionProjectPath(session);
    final derivedFromPath = sessionProjectIdFromPath(path);
    if (derivedFromPath != null &&
        explicit.isNotEmpty &&
        !_sameProjectId(explicit, derivedFromPath) &&
        _isFallbackSessionProjectId(explicit)) {
      return derivedFromPath;
    }
    if (explicit.isNotEmpty) {
      return explicit;
    }
    return derivedFromPath;
  }

  String sessionProjectPath(Map<String, dynamic> session) {
    final payload = session['payload'];
    final payloadMap =
        payload is Map ? Map<String, dynamic>.from(payload) : null;
    return session['projectPath']?.toString().trim() ??
        session['project_path']?.toString().trim() ??
        session['cwd']?.toString().trim() ??
        payloadMap?['projectPath']?.toString().trim() ??
        payloadMap?['project_path']?.toString().trim() ??
        payloadMap?['cwd']?.toString().trim() ??
        '';
  }

  String? sessionProjectIdFromPath(String path) {
    if (path.trim().isEmpty) {
      return null;
    }
    final normalizedPath =
        path.replaceAll('\\', '/').replaceFirst(RegExp(r'^//\?/'), '');
    final parts = normalizedPath
        .split('/')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    return parts.isEmpty ? null : _canonicalProjectId(parts.last);
  }

  bool _isFallbackSessionProjectId(String projectId) {
    final normalized = projectId.trim().toLowerCase();
    return normalized.isEmpty ||
        normalized == defaultProjectId ||
        normalized == 'unknown';
  }

  String? sessionProjectIdForSessionId(String sessionId) {
    final normalizedSessionId = sessionId.trim();
    if (normalizedSessionId.isEmpty) {
      return null;
    }
    for (final session in _sessionSummaries) {
      if ((session['id']?.toString().trim() ?? '') == normalizedSessionId) {
        return sessionProjectIdFromMetadata(session);
      }
    }
    return null;
  }

  String? sessionTitleForSessionId(String sessionId) {
    final normalizedSessionId = sessionId.trim();
    if (normalizedSessionId.isEmpty) {
      return null;
    }
    for (final session in _sessionSummaries) {
      if ((session['id']?.toString().trim() ?? '') == normalizedSessionId) {
        final title = session['title']?.toString().trim() ?? '';
        return title.isEmpty ? null : title;
      }
    }
    return null;
  }

  int? sessionNextCursorForConversationObject(AgentConversation conversation) {
    return _sessionNextCursorByConversation[conversation.id];
  }

  int? sessionNextCursorFromDetail(Map<String, dynamic> detail) {
    return detail['next_cursor'] as int? ?? detail['nextCursor'] as int?;
  }

  String taskSnapshotSessionIdFromDetail(Map<String, dynamic>? detail) {
    return detail?['sessionId']?.toString().trim() ??
        detail?['session_id']?.toString().trim() ??
        '';
  }

  String codexResultErrorText(Map<String, dynamic> detail) {
    return detail['error']?.toString() ?? '';
  }

  String codexResultSessionIdFromDetail(Map<String, dynamic> detail) {
    return detail['sessionId']?.toString().trim() ?? '';
  }

  String detailKindFromEnvelope(Map<String, dynamic> detail) {
    return detail['kind']?.toString() ?? '';
  }

  Map<String, dynamic>? detailItemFromEnvelope(Map<String, dynamic> detail) {
    return detail['item'] is Map
        ? Map<String, dynamic>.from(detail['item'] as Map)
        : null;
  }

  List<Map<String, dynamic>> detailItemsFromEnvelope(
      Map<String, dynamic> detail) {
    final items = detail['items'] as List<dynamic>? ?? const [];
    return items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  bool isStructuredDetailCatalogOrSessionKind(String kind) {
    return kind == 'sessions' ||
        kind == 'session_detail' ||
        kind == 'session_page' ||
        kind == 'skills';
  }

  bool isStructuredSessionDetailOrPageKind(String kind) {
    return kind == 'session_detail' || kind == 'session_page';
  }

  bool shouldSuppressTaskSnapshotHydrationOrPersist({
    required String kind,
    required String status,
  }) {
    return kind == 'task_snapshot' && status == 'done';
  }

  bool shouldBindCodexResultSessionWithoutImmediateRefresh(String status) {
    return status != 'done';
  }

  bool shouldCleanupTaskSnapshotRequestForStatus(String status) {
    return status != 'running' && status != 'started';
  }

  bool shouldRefreshStructuredSessionDetailForStatus(String status) {
    return status == 'done';
  }

  void clearRequestConversationMapping(String requestId) {
    if (requestId.isNotEmpty) {
      _requestToConversation.remove(requestId);
    }
  }

  void clearStatusRecoveryAttempt(String requestId) {
    if (requestId.isNotEmpty) {
      _statusRecoveryAttempts.remove(requestId);
    }
  }

  bool isCurrentStatusRecoveryAttempt({
    required String requestId,
    required int attempt,
  }) {
    return (_statusRecoveryAttempts[requestId] ?? 0) == attempt;
  }

  bool shouldClearActiveRequestConversationForStatus(String status) {
    return status == 'done' || status == 'failed' || status == 'cancelled';
  }

  Duration? _taskStatusBubbleTtlForStatus(AgentConversationStatus status) {
    switch (status) {
      case AgentConversationStatus.completed:
        return const Duration(seconds: 5);
      case AgentConversationStatus.failed:
        return const Duration(seconds: 8);
      case AgentConversationStatus.needsConfirmation:
      case AgentConversationStatus.running:
      case AgentConversationStatus.idle:
        return null;
    }
  }

  bool _shouldEmitTaskStatusBubble(AgentConversationStatus status) {
    return status == AgentConversationStatus.completed ||
        status == AgentConversationStatus.failed ||
        status == AgentConversationStatus.needsConfirmation;
  }

  void _enqueueTaskStatusBubble({
    required String conversationId,
    required String projectId,
    required AgentConversationStatus status,
    required String summary,
    String? requestId,
  }) {
    if (!_shouldEmitTaskStatusBubble(status)) {
      return;
    }
    final conversation = _conversationById(conversationId);
    if (conversation == null) {
      return;
    }
    final normalizedSummary = _normalizeTaskStatusBubbleSummary(summary);
    final normalizedRequestId = requestId?.trim() ?? '';
    final requestKey = normalizedRequestId.isEmpty
        ? null
        : '$normalizedRequestId::${status.name}';
    final fallbackKey =
        '$conversationId::${status.name}::${normalizedSummary.toLowerCase()}';
    final dedupeKey = requestKey ?? fallbackKey;
    if (_taskStatusBubbleDedupeKeys.contains(dedupeKey)) {
      return;
    }
    final now = DateTime.now();
    final ttl = _taskStatusBubbleTtlForStatus(status);
    final bubble = AgentTaskStatusBubble(
      id: requestKey ?? const Uuid().v4(),
      requestId: normalizedRequestId.isEmpty ? null : normalizedRequestId,
      conversationId: conversationId,
      projectId: projectId.trim().isEmpty ? conversation.projectId : projectId,
      status: status,
      title: statusLabelForStatus(status),
      summary: normalizedSummary,
      createdAt: now,
      expiresAt: ttl == null ? null : now.add(ttl),
      sticky: ttl == null,
      dedupeKey: dedupeKey,
    );
    _taskStatusBubbles
        .removeWhere((item) => item.conversationId == conversationId);
    _taskStatusBubbles.insert(0, bubble);
    _taskStatusBubbleDedupeKeys.add(dedupeKey);
    if (normalizedRequestId.isNotEmpty && requestKey != null) {
      _requestStatusBubbleKeys[normalizedRequestId] = requestKey;
    }
    if (_taskStatusBubbles.length > _maxVisibleTaskStatusBubbles) {
      final overflow =
          _taskStatusBubbles.sublist(_maxVisibleTaskStatusBubbles).toList();
      _taskStatusBubbles.removeRange(
        _maxVisibleTaskStatusBubbles,
        _taskStatusBubbles.length,
      );
      for (final item in overflow) {
        _removeTaskStatusBubbleKey(item);
      }
    }
    _scheduleTaskStatusBubblePrune();
  }

  void _removeTaskStatusBubbleWhere(
    bool Function(AgentTaskStatusBubble bubble) predicate, {
    bool notify = true,
  }) {
    final removed = _taskStatusBubbles.where(predicate).toList();
    if (removed.isEmpty) {
      return;
    }
    _taskStatusBubbles.removeWhere(predicate);
    for (final bubble in removed) {
      _removeTaskStatusBubbleKey(bubble);
    }
    _scheduleTaskStatusBubblePrune();
    if (notify) {
      notifyListeners();
    }
  }

  void _removeTaskStatusBubbleKey(AgentTaskStatusBubble bubble) {
    final dedupeKey = bubble.dedupeKey;
    if (dedupeKey != null && dedupeKey.isNotEmpty) {
      _taskStatusBubbleDedupeKeys.remove(dedupeKey);
    }
    final requestId = bubble.requestId;
    if (requestId != null && requestId.isNotEmpty) {
      _requestStatusBubbleKeys.remove(requestId);
    }
  }

  bool _pruneExpiredTaskStatusBubbles() {
    final now = DateTime.now();
    final removed = _taskStatusBubbles
        .where((bubble) =>
            bubble.expiresAt != null && now.isAfter(bubble.expiresAt!))
        .toList();
    if (removed.isEmpty) {
      return false;
    }
    _taskStatusBubbles.removeWhere(
      (bubble) => bubble.expiresAt != null && now.isAfter(bubble.expiresAt!),
    );
    for (final bubble in removed) {
      _removeTaskStatusBubbleKey(bubble);
    }
    return true;
  }

  void _scheduleTaskStatusBubblePrune() {
    _taskStatusBubbleTimer?.cancel();
    DateTime? nextExpiry;
    for (final bubble in _taskStatusBubbles) {
      final expiresAt = bubble.expiresAt;
      if (expiresAt == null) {
        continue;
      }
      if (nextExpiry == null || expiresAt.isBefore(nextExpiry)) {
        nextExpiry = expiresAt;
      }
    }
    if (nextExpiry == null) {
      return;
    }
    final delay = nextExpiry.difference(DateTime.now());
    _taskStatusBubbleTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () {
        if (_pruneExpiredTaskStatusBubbles()) {
          notifyListeners();
        }
        _scheduleTaskStatusBubblePrune();
      },
    );
  }

  String _normalizeTaskStatusBubbleSummary(String summary) {
    final compact = summary.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.isNotEmpty) {
      return compact;
    }
    return 'Open the conversation for the latest task state.';
  }

  AgentConversation? _conversationById(String conversationId) {
    final index = _conversationIndexById(conversationId);
    if (index == -1) {
      return null;
    }
    return _conversations[index];
  }

  String _projectIdFromAgentText(String text) {
    final match = RegExp(r'^\[Agent:([^\]]+)\]').firstMatch(text.trimLeft());
    final project = match?.group(1)?.trim() ?? '';
    return project.isEmpty ? defaultProjectId : project;
  }

  Map<String, dynamic>? taskSnapshotDetailFromEnvelope(
      Map<String, dynamic> detail) {
    return detail['detail'] is Map
        ? Map<String, dynamic>.from(detail['detail'] as Map)
        : null;
  }

  String? detailConversationIdFromEnvelope(Map<String, dynamic>? detail) {
    final id = detail?['conversationId']?.toString().trim() ??
        (detail?['detail'] is Map
            ? (detail?['detail'] as Map)['conversationId']?.toString().trim()
            : '') ??
        '';
    return id.isEmpty ? null : id;
  }

  Future<void> sendCurrentPrompt() async {
    final prompt = textController.text.trim();
    final conversationIndex = _selectedConversationIndex();
    if (conversationIndex == -1 || prompt.isEmpty) {
      return;
    }
    final conversation = _conversations[conversationIndex];

    final requestId = const Uuid().v4();
    final outbound = ChatMessage(
      text: prompt,
      user: me,
      createdAt: DateTime.now(),
    );
    final envelope = await _buildAgentEnvelope(
      conversation: conversation,
      prompt: prompt,
      requestId: requestId,
    );
    textController.clear();
    _activeRequestConversationId = conversation.id;
    _requestToConversation[requestId] = conversation.id;
    _runtimeStatuses[conversation.id] = AgentConversationStatus.running;
    _runtimeStatusDetails[conversation.id] =
        'Assistant is thinking through this request.';
    _requestStatusBubbleKeys.remove(requestId);
    _appendMessageAtIndex(
      index: conversationIndex,
      conversation.id,
      outbound,
      updateTitleFromPrompt: true,
    );
    try {
      await runtime.dispatchEnvelope(envelope);
      unawaited(runtime.onCommandDispatched(
        model: this,
        conversation: conversation,
        prompt: prompt,
        requestId: requestId,
      ));
    } catch (e) {
      _runtimeStatuses[conversation.id] = AgentConversationStatus.failed;
      _runtimeStatusDetails[conversation.id] = 'Dispatch failed: $e';
      _activeRequestConversationId = null;
      _appendMessage(
        conversation.id,
        ChatMessage(
          text: '[Agent:${conversation.projectId}] failed:\n$e',
          user: assistant,
          createdAt: DateTime.now(),
        ),
      );
    }
  }

  Future<void> sendVoiceClip({
    Duration duration = const Duration(seconds: 5),
  }) async {
    if (_voiceRecording) {
      return;
    }
    final conversationIndex = _selectedConversationIndex();
    if (conversationIndex == -1) {
      return;
    }
    final conversation = _conversations[conversationIndex];
    final conversationId = conversation.id;
    final requestId = const Uuid().v4();
    _voiceRecording = true;
    _runtimeStatuses[conversationId] = AgentConversationStatus.running;
    _runtimeStatusDetails[conversationId] = 'Recording voice clip.';
    notifyListeners();
    try {
      final audioBase64 =
          await runtime.recordVoiceClipBase64(duration: duration);
      final currentIndex = _conversationIndexById(conversationId);
      if (currentIndex == -1) {
        return;
      }
      final currentConversation = _conversations[currentIndex];
      final envelope = await _buildVoiceRunEnvelope(
        conversation: currentConversation,
        audioBase64: audioBase64,
        requestId: requestId,
      );
      _activeRequestConversationId = conversationId;
      _requestToConversation[requestId] = conversationId;
      _runtimeStatuses[conversationId] = AgentConversationStatus.running;
      _runtimeStatusDetails[conversationId] =
          'Voice clip sent to desktop agent.';
      _requestStatusBubbleKeys.remove(requestId);
      _appendMessageAtIndex(
        index: currentIndex,
        conversationId,
        ChatMessage(
          text: 'Voice clip sent to desktop agent.',
          user: me,
          createdAt: DateTime.now(),
        ),
        updateTitleFromPrompt: true,
      );
      await runtime.dispatchEnvelope(envelope);
      unawaited(runtime.onCommandDispatched(
        model: this,
        conversation: currentConversation,
        prompt: 'Voice clip',
        requestId: requestId,
      ));
    } catch (e) {
      _runtimeStatuses[conversationId] = AgentConversationStatus.failed;
      _runtimeStatusDetails[conversationId] = 'Voice dispatch failed: $e';
      _activeRequestConversationId = null;
      clearRequestConversationMapping(requestId);
      _appendMessage(
        conversationId,
        ChatMessage(
          text: '[Agent:${conversation.projectId}] voice failed:\n$e',
          user: assistant,
          createdAt: DateTime.now(),
        ),
      );
    } finally {
      _voiceRecording = false;
      notifyListeners();
    }
  }

  bool tryHandleAgentText(String text) {
    final normalized = text.trimLeft();
    if (!normalized.startsWith('[Agent:')) {
      return false;
    }
    final requestId = _extractAgentResultRequestId(normalized);
    if (requestId != null && _wasStructuredResultSeen(requestId)) {
      return true;
    }
    final conversationId = _activeRequestConversationId ??
        _selectedConversationId ??
        _fallbackConversationId();
    if (conversationId == null) return false;
    final status = _parseAgentStatus(normalized);
    final visibleText = _cleanDashboardMessageText(
      text.trim(),
      source: AgentDashboardMessageSource.liveAgentText,
      role: AgentDashboardMessageRole.assistant,
    );
    final visibleNormalized = visibleText.trimLeft();
    if (status != null) {
      _runtimeStatuses[conversationId] = status;
      _runtimeStatusDetails[conversationId] =
          _summarizeAgentStatus(visibleNormalized);
      _enqueueTaskStatusBubble(
        conversationId: conversationId,
        projectId: _projectIdFromAgentText(normalized),
        status: status,
        requestId: requestId,
        summary: _summarizeAgentStatus(visibleNormalized),
      );
      if (status == AgentConversationStatus.completed ||
          status == AgentConversationStatus.failed) {
        if (_activeRequestConversationId == conversationId) {
          _activeRequestConversationId = null;
        }
      } else {
        _activeRequestConversationId = conversationId;
      }
    }
    _appendMessage(
      conversationId,
      ChatMessage(
        text: visibleText,
        user: assistant,
        createdAt: DateTime.now(),
      ),
    );
    return true;
  }

  Future<void> handleAgentResultEvent(Map<String, dynamic> evt) async {
    await ensureLoaded();
    final requestId = evt['request_id']?.toString() ?? '';
    if (requestId.isNotEmpty) {
      _recentStructuredAgentResults[requestId] = DateTime.now();
      _pruneRecentStructuredResults();
    }
    final detail = _tryDecodeJson(evt['detail_json']?.toString() ?? '');
    debugPrint(
      '[AgentDashboardModel] agent_result request=$requestId '
      'status=${evt['status']} kind=${detail == null ? '' : detailKindFromEnvelope(detail)}',
    );
    final detailConversationId = detailConversationIdFromEnvelope(detail);
    final mappedConversationId = _requestToConversation[requestId];
    final conversationId = mappedConversationId ??
        detailConversationId ??
        _activeRequestConversationId ??
        _selectedConversationId;
    if (conversationId == null) {
      return;
    }
    final status = evt['status']?.toString() ?? 'failed';
    final text = evt['text']?.toString() ?? '';
    final visibleText = _cleanDashboardMessageText(
      text,
      source: AgentDashboardMessageSource.structuredAgentEvent,
      role: AgentDashboardMessageRole.assistant,
    );
    final token = evt['token']?.toString() ?? '';
    final project = evt['project']?.toString() ?? defaultProjectId;
    if (_shouldRecoverBridgeRunFailure(
      requestId: requestId,
      status: status,
      text: text,
    )) {
      final deferImmediateQuery = runtime.hasActiveStatusTracking(requestId);
      _runtimeStatuses[conversationId] = AgentConversationStatus.running;
      _runtimeStatusDetails[conversationId] =
          'Recovering task status for $requestId';
      notifyListeners();
      unawaited(_recoverTaskStatus(
        conversationId: conversationId,
        requestId: requestId,
        projectId: project,
        fallbackEvent: Map<String, dynamic>.from(evt),
        deferImmediateQuery: deferImmediateQuery,
      ));
      return;
    }
    _runtimeStatuses[conversationId] = _statusFromRuntime(status);
    _runtimeStatusDetails[conversationId] =
        visibleText.trim().isEmpty ? status : visibleText.trim();
    _enqueueTaskStatusBubble(
      conversationId: conversationId,
      projectId: project,
      status: _runtimeStatuses[conversationId] ?? AgentConversationStatus.idle,
      requestId: requestId,
      summary: visibleText,
    );
    clearStatusRecoveryAttempt(requestId);
    if (shouldClearActiveRequestConversationForStatus(status)) {
      if (_activeRequestConversationId == conversationId) {
        _activeRequestConversationId = null;
      }
    }
    if (detail != null) {
      final kind = detailKindFromEnvelope(detail);
      final suppressTaskSnapshotHydration =
          shouldSuppressTaskSnapshotHydrationOrPersist(
        kind: kind,
        status: status,
      );
      final suppressTaskSnapshotPersist =
          shouldSuppressTaskSnapshotHydrationOrPersist(
        kind: kind,
        status: status,
      );
      _applyDetailJson(
        conversationId,
        detail,
        hydrateTaskSnapshotSession: !suppressTaskSnapshotHydration,
        persistTaskSnapshotSession: !suppressTaskSnapshotPersist,
      );
      if (kind == 'task_snapshot') {
        final nested = taskSnapshotDetailFromEnvelope(detail);
        final sessionId = taskSnapshotSessionIdFromDetail(nested);
        if (sessionId.isNotEmpty) {
          if (shouldRefreshStructuredSessionDetailForStatus(status)) {
            await _finalizeStructuredSessionRefresh(
              conversationId: conversationId,
              sessionId: sessionId,
            );
          }
        }
        if (sessionId.isEmpty &&
            shouldCleanupTaskSnapshotRequestForStatus(status) &&
            visibleText.trim().isNotEmpty) {
          _appendMessage(
            conversationId,
            ChatMessage(
              text: _agentEventText(
                project: project,
                status: status,
                text: visibleText,
              ),
              user: assistant,
              createdAt: DateTime.now(),
            ),
          );
        }
        if (shouldCleanupTaskSnapshotRequestForStatus(status)) {
          clearRequestConversationMapping(requestId);
        }
        notifyListeners();
        return;
      }
      if (kind == 'codexResult') {
        final sessionId = codexResultSessionIdFromDetail(detail);
        if (sessionId.isNotEmpty) {
          if (!_bindSessionRefAtConversation(
            conversationId: conversationId,
            sessionId: sessionId,
            hydrateIfNeeded:
                shouldBindCodexResultSessionWithoutImmediateRefresh(status),
            persist:
                shouldBindCodexResultSessionWithoutImmediateRefresh(status),
            clearMessagesOnSessionReset:
                shouldBindCodexResultSessionWithoutImmediateRefresh(status),
          )) {
            return;
          }
          if (shouldRefreshStructuredSessionDetailForStatus(status)) {
            await _finalizeStructuredSessionRefresh(
              conversationId: conversationId,
              sessionId: sessionId,
              preferLatestAssistantText: visibleText,
            );
            clearRequestConversationMapping(requestId);
            notifyListeners();
            return;
          }
        }
      }
      if (isStructuredDetailCatalogOrSessionKind(kind)) {
        clearRequestConversationMapping(requestId);
        notifyListeners();
        return;
      }
    }
    _appendMessage(
      conversationId,
      ChatMessage(
        text: _agentEventText(
          project: project,
          status: status,
          text: visibleText,
        ),
        user: assistant,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> _finalizeStructuredSessionRefresh({
    required String conversationId,
    required String sessionId,
    String? preferLatestAssistantText,
  }) async {
    await _refreshConversationFromSession(
      conversationId: conversationId,
      sessionId: sessionId,
      cursor: null,
      appendOlder: false,
      persist: false,
      preferLatestAssistantText: preferLatestAssistantText,
    );
    _sortConversations();
    await _save();
  }

  Future<void> _recoverTaskStatus({
    required String conversationId,
    required String requestId,
    required String projectId,
    required Map<String, dynamic> fallbackEvent,
    bool deferImmediateQuery = false,
  }) async {
    final attempt = (_statusRecoveryAttempts[requestId] ?? 0) + 1;
    _statusRecoveryAttempts[requestId] = attempt;
    try {
      if (!deferImmediateQuery) {
        final recovered = await runtime.requestTaskStatus(
          requestId: requestId,
          projectId: projectId,
        );
        if (recovered != null) {
          await handleAgentResultEvent(recovered);
          return;
        }
      }
      await Future<void>.delayed(const Duration(seconds: 4));
      if (!isCurrentStatusRecoveryAttempt(
        requestId: requestId,
        attempt: attempt,
      )) {
        return;
      }
      if (deferImmediateQuery) {
        final recovered = await runtime.requestTaskStatus(
          requestId: requestId,
          projectId: projectId,
        );
        if (recovered != null) {
          await handleAgentResultEvent(recovered);
          return;
        }
        if (!isCurrentStatusRecoveryAttempt(
          requestId: requestId,
          attempt: attempt,
        )) {
          return;
        }
      }
      clearStatusRecoveryAttempt(requestId);
      await handleAgentResultEvent(fallbackEvent);
    } catch (_) {
      if (!isCurrentStatusRecoveryAttempt(
        requestId: requestId,
        attempt: attempt,
      )) {
        return;
      }
      clearStatusRecoveryAttempt(requestId);
      await handleAgentResultEvent(fallbackEvent);
    }
  }

  Future<void> restoreSessionIntoConversation({
    required String conversationId,
    required String sessionId,
  }) async {
    final index = _conversationIndexById(conversationId);
    if (index == -1) {
      return;
    }
    final normalizedSessionId = sessionId.trim();
    if (normalizedSessionId.isEmpty) {
      final conversation = _conversations[index];
      if (_isBlankSessionConversation(conversation)) {
        return;
      }
      _updateConversationSettingsAtIndex(
        index: index,
        conversationId: conversationId,
        sessionRef: '',
        threadMode: 'new',
      );
      return;
    }

    _bindSessionRefAtIndex(
      index: index,
      conversationId: conversationId,
      sessionId: normalizedSessionId,
      projectId: sessionProjectIdForSessionId(normalizedSessionId),
      hydrateIfNeeded: false,
      persist: false,
    );
    await _restoreSessionIntoConversationAfterBinding(
      conversationId: conversationId,
      sessionId: normalizedSessionId,
    );
  }

  Future<void> restoreSessionAsCurrentConversation(String sessionId) async {
    final normalizedSessionId = sessionId.trim();
    final selectedIndex = _selectedConversationIndex();
    if (normalizedSessionId.isEmpty) {
      if (selectedIndex == -1) return;
      await restoreSessionIntoConversation(
        conversationId: _conversations[selectedIndex].id,
        sessionId: '',
      );
      return;
    }

    final existingIndex = _conversations.indexWhere(
      (conversation) =>
          conversation.threadMode == 'continue' &&
          conversation.sessionRef.trim() == normalizedSessionId,
    );
    if (existingIndex != -1) {
      final conversationId = _conversations[existingIndex].id;
      _selectedConversationId = conversationId;
      _syncSelectedConversationSideEffects(existingIndex, notifyRead: false);
      notifyListeners();
      await _restoreSessionIntoConversationAfterBinding(
        conversationId: conversationId,
        sessionId: normalizedSessionId,
      );
      return;
    }

    if (selectedIndex != -1 &&
        _isBlankSessionConversation(_conversations[selectedIndex])) {
      await restoreSessionIntoConversation(
        conversationId: _conversations[selectedIndex].id,
        sessionId: normalizedSessionId,
      );
      return;
    }

    final conversation = createConversation(
      title: sessionTitleForSessionId(normalizedSessionId),
      projectId:
          sessionProjectIdForSessionId(normalizedSessionId) ?? defaultProjectId,
      threadMode: 'continue',
      sessionRef: normalizedSessionId,
    );
    await _restoreSessionIntoConversationAfterBinding(
      conversationId: conversation.id,
      sessionId: normalizedSessionId,
    );
  }

  bool _isBlankSessionConversation(AgentConversation conversation) {
    return conversation.threadMode != 'continue' &&
        conversation.sessionRef.trim().isEmpty &&
        conversation.messages.isEmpty &&
        conversation.draft.trim().isEmpty &&
        timelineForConversationObject(conversation).isEmpty &&
        rawEventsForConversationObject(conversation).isEmpty &&
        !canLoadMoreSessionHistoryForConversation(conversation);
  }

  Future<void> _restoreSessionIntoConversationAfterBinding({
    required String conversationId,
    required String sessionId,
  }) async {
    try {
      final detail = await _refreshConversationFromSession(
        conversationId: conversationId,
        sessionId: sessionId,
        cursor: null,
        appendOlder: false,
        persist: false,
      );
      if (detail == null) return;
      _runtimeStatusDetails[conversationId] =
          'Loaded Codex session ${detail['title']?.toString() ?? sessionId}';
      notifyListeners();
      _sortConversations();
      unawaited(_save());
      unawaited(_prefetchOlderSessionHistoryInBackground(conversationId));
    } catch (e) {
      _runtimeStatuses[conversationId] = AgentConversationStatus.failed;
      _runtimeStatusDetails[conversationId] = 'Load session failed: $e';
      notifyListeners();
    }
  }

  String composeHistoryPreview(AgentConversation conversation) {
    if (!conversation.includeConversationHistory) return '';
    final items = conversation.messages.reversed.take(12).toList().reversed;
    return items
        .map((message) =>
            '${message.user.id == me.id ? 'Me' : 'Agent'}: ${message.text}')
        .join('\n');
  }

  String latestSnippet(AgentConversation conversation) {
    if (conversation.messages.isEmpty) {
      return conversation.draft.trim().isEmpty
          ? 'No messages yet'
          : 'Draft: ${conversation.draft.trim()}';
    }
    final message = conversation.messages.first;
    final speaker = message.user.id == me.id ? 'Me' : 'Agent';
    final compact = _agentEventSnippet(message.text) ??
        message.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final snippet =
        compact.length > 72 ? '${compact.substring(0, 72)}...' : compact;
    return '$speaker: $snippet';
  }

  Future<void> loadMoreSessionHistory(String conversationId) async {
    try {
      final loaded = await _loadOneOlderSessionHistoryPage(
        conversationId: conversationId,
      );
      if (loaded) {
        notifyListeners();
      }
    } catch (e) {
      _runtimeStatuses[conversationId] = AgentConversationStatus.failed;
      _runtimeStatusDetails[conversationId] = 'Load more history failed: $e';
      notifyListeners();
    }
  }

  String composeTerminalContext(AgentConversation conversation) {
    if (!conversation.includeTerminalContext) return '';
    return runtime.loadTerminalContext().trim();
  }

  bool _shouldIncludeHistoryPreviewForDispatch(
    AgentConversation conversation,
    ({String projectId, String threadMode, String sessionRef}) routeTarget,
  ) {
    if (!conversation.includeConversationHistory) {
      return false;
    }
    if (routeTarget.threadMode == 'continue' &&
        routeTarget.sessionRef.isNotEmpty) {
      return false;
    }
    return true;
  }

  Future<Map<String, dynamic>> _buildAgentEnvelope({
    required AgentConversation conversation,
    required String prompt,
    required String requestId,
  }) async {
    final routeTarget = _resolveDispatchRoute(conversation);
    final includeHistory =
        _shouldIncludeHistoryPreviewForDispatch(conversation, routeTarget);
    final historyPreview =
        includeHistory ? composeHistoryPreview(conversation) : '';
    final terminalContext = composeTerminalContext(conversation);
    return {
      'requestId': requestId,
      'conversationId': conversation.id,
      'kind': 'run',
      'action': 'run',
      'mode': 'read-only',
      'requireConfirmation': true,
      'prompt': prompt.replaceAll('\r\n', '\n'),
      'route': {
        'projectId': routeTarget.projectId,
        'threadMode': routeTarget.threadMode,
        'activeThreadId':
            routeTarget.sessionRef.isEmpty ? null : routeTarget.sessionRef,
        'codexThreadId':
            routeTarget.sessionRef.isEmpty ? null : routeTarget.sessionRef,
        'profileId': conversation.profile.trim().isEmpty
            ? null
            : conversation.profile.trim(),
        'selectedSkillIds': conversation.selectedSkillIds,
      },
      'context': {
        'includeHistory': includeHistory,
        'includeTerminal': conversation.includeTerminalContext,
        'historyPreview': historyPreview,
        'terminalSnapshot': terminalContext,
        'recentFiles': const [],
        'runtimeInfo': 'rustdesk-dashboard',
      },
    };
  }

  Future<Map<String, dynamic>> _buildVoiceRunEnvelope({
    required AgentConversation conversation,
    required String audioBase64,
    required String requestId,
  }) async {
    final routeTarget = _resolveDispatchRoute(conversation);
    final includeHistory =
        _shouldIncludeHistoryPreviewForDispatch(conversation, routeTarget);
    final historyPreview =
        includeHistory ? composeHistoryPreview(conversation) : '';
    final terminalContext = composeTerminalContext(conversation);
    return {
      'requestId': requestId,
      'conversationId': conversation.id,
      'kind': 'voice_run',
      'action': 'voice_run',
      'mode': 'read-only',
      'requireConfirmation': true,
      'route': {
        'projectId': routeTarget.projectId,
        'threadMode': routeTarget.threadMode,
        'activeThreadId':
            routeTarget.sessionRef.isEmpty ? null : routeTarget.sessionRef,
        'codexThreadId':
            routeTarget.sessionRef.isEmpty ? null : routeTarget.sessionRef,
        'profileId': conversation.profile.trim().isEmpty
            ? null
            : conversation.profile.trim(),
        'selectedSkillIds': conversation.selectedSkillIds,
      },
      'context': {
        'includeHistory': includeHistory,
        'includeTerminal': conversation.includeTerminalContext,
        'historyPreview': historyPreview,
        'terminalSnapshot': terminalContext,
        'recentFiles': const [],
        'runtimeInfo': 'rustdesk-dashboard',
      },
      'voice': {
        'audioBase64': audioBase64,
      },
    };
  }

  ({String projectId, String threadMode, String sessionRef})
      _resolveDispatchRoute(AgentConversation conversation) {
    final configuredProjects = _availableProjects
        .map((id) => _canonicalProjectId(id))
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final fallbackProject = configuredProjects.isEmpty
        ? defaultProjectId
        : configuredProjects.first;
    final requestedProject = _canonicalProjectId(conversation.projectId);
    final sessionRef = conversation.sessionRef.trim();
    if (sessionRef.isNotEmpty && conversation.threadMode == 'continue') {
      final sessionProject =
          _canonicalProjectId(sessionProjectIdForSessionId(sessionRef));
      final resolvedSessionProject = sessionProject.isNotEmpty
          ? sessionProject
          : (requestedProject.isNotEmpty ? requestedProject : fallbackProject);
      return (
        projectId: resolvedSessionProject,
        threadMode: 'continue',
        sessionRef: sessionRef,
      );
    }
    final resolvedProject = configuredProjects
            .any((candidate) => _sameProjectId(candidate, requestedProject))
        ? requestedProject
        : fallbackProject;
    return (
      projectId: resolvedProject,
      threadMode: 'new',
      sessionRef: '',
    );
  }

  void _appendMessage(
    String conversationId,
    ChatMessage message, {
    bool updateTitleFromPrompt = false,
  }) {
    final index = _conversationIndexById(conversationId);
    if (index == -1) return;
    _appendMessageAtIndex(
      index: index,
      conversationId,
      message,
      updateTitleFromPrompt: updateTitleFromPrompt,
    );
  }

  void _appendMessageAtIndex(
    String conversationId,
    ChatMessage message, {
    required int index,
    bool updateTitleFromPrompt = false,
  }) {
    final nextConversations = List<AgentConversation>.from(_conversations);
    final conversation = nextConversations[index];
    final nextMessages = [message, ...conversation.messages];
    final isSelected = conversation.id == _selectedConversationId;
    nextConversations[index] = conversation.copyWith(
      title: updateTitleFromPrompt
          ? _titleFromPrompt(message.text, conversation.title)
          : conversation.title,
      archived: false,
      draft: isSelected ? textController.text : conversation.draft,
      updatedAt: DateTime.now(),
      lastReadAt: isSelected ? DateTime.now() : conversation.lastReadAt,
      messages: nextMessages,
    );
    _conversations = nextConversations;
    _sortConversations();
    unawaited(_save());
    notifyListeners();
  }

  String _titleFromPrompt(String prompt, String fallback) {
    final value = prompt.trim();
    if (value.isEmpty) return fallback;
    final compact = value.replaceAll(RegExp(r'\s+'), ' ');
    return compact.length > 28 ? compact.substring(0, 28) : compact;
  }

  AgentConversation _newConversation() {
    return AgentConversation(
      id: const Uuid().v4(),
      title: 'New conversation',
      projectId: _availableProjects.isEmpty
          ? defaultProjectId
          : _availableProjects.first,
      threadMode: 'new',
      profile: '',
      sessionRef: '',
      selectedSkillIds: const [],
      pinned: false,
      archived: false,
      draft: '',
      includeConversationHistory: true,
      includeTerminalContext: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      lastReadAt: DateTime.now(),
      messages: const [],
    );
  }

  List<AgentConversation> _buildDemoConversations() {
    final now = DateTime.now();
    final primaryProject = _availableProjects.isEmpty
        ? defaultProjectId
        : _availableProjects.first;
    final secondaryProject =
        _availableProjects.length > 1 ? _availableProjects[1] : primaryProject;
    final tertiaryProject =
        _availableProjects.length > 2 ? _availableProjects[2] : primaryProject;
    return [
      AgentConversation(
        id: const Uuid().v4(),
        title: 'Analyze Android entry',
        projectId: primaryProject,
        threadMode: 'continue',
        profile: 'mobile-debug',
        sessionRef: '',
        selectedSkillIds: const ['android-entry', 'flutter-mobile'],
        pinned: true,
        archived: false,
        draft: '',
        includeConversationHistory: true,
        includeTerminalContext: true,
        createdAt: now.subtract(const Duration(hours: 2)),
        updatedAt: now.subtract(const Duration(minutes: 4)),
        lastReadAt: now.subtract(const Duration(minutes: 3)),
        messages: [
          _demoMessage(
            assistant,
            '[Agent:$primaryProject] done:\n'
            'Remote chat routes through AgentDashboardModel and the local bridge. '
            'The current mobile entry is safe to iterate with flutter run.',
            now.subtract(const Duration(minutes: 4)),
          ),
          _demoMessage(
            me,
            'Analyze the current mobile entry and confirm where the dashboard opens from.',
            now.subtract(const Duration(minutes: 6)),
          ),
        ],
      ),
      AgentConversation(
        id: const Uuid().v4(),
        title: 'Prepare workspace-write change',
        projectId: secondaryProject,
        threadMode: 'new',
        profile: 'agent-main',
        sessionRef: '',
        selectedSkillIds: const ['workspace-write-plan'],
        pinned: false,
        archived: false,
        draft: 'Need to preserve the current draft before switching sessions.',
        includeConversationHistory: true,
        includeTerminalContext: false,
        createdAt: now.subtract(const Duration(hours: 6)),
        updatedAt: now.subtract(const Duration(minutes: 18)),
        lastReadAt: now.subtract(const Duration(minutes: 30)),
        messages: [
          _demoMessage(
            assistant,
            '[Agent:$secondaryProject] needs confirmation: workspace-write required.\n'
            'Plan:\n'
            '- update the dashboard route\n'
            '- keep the mock runtime separate from the real session\n'
            '- validate with flutter analyze',
            now.subtract(const Duration(minutes: 18)),
          ),
          _demoMessage(
            me,
            'Update the dashboard and keep a mock route for local preview.',
            now.subtract(const Duration(minutes: 21)),
          ),
        ],
      ),
      AgentConversation(
        id: const Uuid().v4(),
        title: 'Review terminal context',
        projectId: tertiaryProject,
        threadMode: 'continue',
        profile: '',
        sessionRef: 'terminal:0',
        selectedSkillIds: const ['terminal-context'],
        pinned: false,
        archived: false,
        draft: '',
        includeConversationHistory: false,
        includeTerminalContext: true,
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now.subtract(const Duration(minutes: 42)),
        lastReadAt: now.subtract(const Duration(minutes: 43)),
        messages: [
          _demoMessage(
            assistant,
            '[Agent:$tertiaryProject] started: collecting terminal transcript and project config.',
            now.subtract(const Duration(minutes: 42)),
          ),
          _demoMessage(
            me,
            'Attach the current terminal transcript and show how the prompt is composed.',
            now.subtract(const Duration(minutes: 44)),
          ),
        ],
      ),
    ];
  }

  ChatMessage _demoMessage(ChatUser user, String text, DateTime createdAt) {
    return ChatMessage(
      text: text,
      createdAt: createdAt,
      user: user,
    );
  }

  Future<bool> _loadRuntimeCatalogs() async {
    var attachedLatestSession = false;
    try {
      final sessions = await runtime.loadSessions(
        conversationId: _selectedConversationId,
      );
      if (runtime.defersSkillCatalogLoad) {
        _sessionSummaries = [];
        _sessionsLoaded = false;
      } else {
        _sessionSummaries = sessions;
        _sessionsLoaded = true;
        attachedLatestSession = _maybeAttachLatestSession();
      }
    } catch (_) {
      _sessionSummaries = [];
      _sessionsLoaded = false;
    }
    await _loadSkillCatalogInternal(notify: false);
    return attachedLatestSession;
  }

  Future<void> reloadSkillCatalog() async {
    await ensureLoaded();
    await _loadSkillCatalogInternal(notify: true);
  }

  Future<void> reloadSessionCatalog() async {
    await ensureLoaded();
    await _requestSessionCatalogReload(notify: true);
  }

  Future<void> _requestSessionCatalogReload({required bool notify}) async {
    final preserveExistingSessions = runtime.defersSkillCatalogLoad;
    try {
      final sessions = await runtime.loadSessions(
        conversationId: _selectedConversationId,
      );
      if (runtime.defersSkillCatalogLoad) {
        if (_sessionSummaries.isEmpty) {
          _sessionsLoaded = false;
        } else {
          _sessionsLoaded = true;
        }
      } else {
        _sessionSummaries = sessions;
        _sessionsLoaded = true;
        if (_maybeAttachLatestSession() ||
            _reconcileConversationProjectsFromSessions()) {
          unawaited(_save());
        }
      }
    } catch (e) {
      debugPrint('[AgentDashboardModel] Failed to reload session catalog: $e');
      if (!preserveExistingSessions || _sessionSummaries.isEmpty) {
        _sessionSummaries = [];
        _sessionsLoaded = false;
      }
    } finally {
      if (notify) {
        notifyListeners();
      }
    }
  }

  void _scheduleDeferredSessionCatalogRetry() {
    if (!runtime.defersSkillCatalogLoad ||
        _sessionsLoaded ||
        _sessionCatalogRetryTimer != null) {
      return;
    }
    _sessionCatalogRetryCount = 0;
    _sessionCatalogRetryTimer =
        Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_sessionsLoaded || !runtime.defersSkillCatalogLoad) {
        _stopDeferredSessionCatalogRetry();
        return;
      }
      _sessionCatalogRetryCount += 1;
      if (_sessionCatalogRetryCount > 6) {
        _stopDeferredSessionCatalogRetry();
        return;
      }
      debugPrint(
        '[AgentDashboardModel] retry session catalog attempt=$_sessionCatalogRetryCount',
      );
      unawaited(_requestSessionCatalogReload(notify: true));
    });
  }

  void _stopDeferredSessionCatalogRetry() {
    _sessionCatalogRetryTimer?.cancel();
    _sessionCatalogRetryTimer = null;
  }

  Future<void> _loadSkillCatalogInternal({required bool notify}) async {
    _skillsLoading = true;
    if (notify) {
      notifyListeners();
    }
    try {
      final skills = await runtime.loadSkills(
        conversationId: _selectedConversationId,
      );
      if (runtime.defersSkillCatalogLoad) {
        _skillsLoading = true;
        _skillsLoaded = false;
      } else {
        _skillCatalog = skills;
        _skillsLoaded = true;
        _skillsLoading = false;
      }
    } catch (_) {
      _skillCatalog = [];
      _skillsLoaded = false;
      _skillsLoading = false;
    } finally {
      if (notify) {
        notifyListeners();
      }
    }
  }

  bool _maybeAttachLatestSession() {
    if (_sessionSummaries.isEmpty) return false;
    final index = _selectedConversationIndex();
    final conversation = _conversations[index];
    if (conversation.sessionRef.trim().isNotEmpty ||
        conversation.messages.isNotEmpty ||
        conversation.draft.trim().isNotEmpty) {
      return false;
    }
    final first = _sessionSummaries.first;
    final sessionId = first['id']?.toString().trim() ?? '';
    if (sessionId.isEmpty) return false;
    _bindSessionRefAtIndex(
      index: index,
      conversationId: conversation.id,
      sessionId: sessionId,
      projectId: sessionProjectIdForSessionId(sessionId),
      hydrateIfNeeded: false,
      persist: false,
    );
    unawaited(
      _restoreSessionIntoConversationAfterBinding(
        conversationId: conversation.id,
        sessionId: sessionId,
      ),
    );
    return true;
  }

  bool _bindSessionRefAtConversation({
    required String conversationId,
    required String sessionId,
    String? projectId,
    bool hydrateIfNeeded = true,
    bool persist = true,
    bool clearMessagesOnSessionReset = true,
  }) {
    final index = _conversationIndexById(conversationId);
    if (index == -1) {
      return false;
    }
    _bindSessionRefAtIndex(
      index: index,
      conversationId: conversationId,
      sessionId: sessionId,
      projectId: projectId,
      hydrateIfNeeded: hydrateIfNeeded,
      persist: persist,
      clearMessagesOnSessionReset: clearMessagesOnSessionReset,
    );
    return true;
  }

  void _bindSessionRefAtIndex({
    required int index,
    required String conversationId,
    required String sessionId,
    String? projectId,
    bool hydrateIfNeeded = true,
    bool persist = true,
    bool clearMessagesOnSessionReset = true,
  }) {
    final resolvedProjectId = projectId?.trim().isNotEmpty == true
        ? _canonicalProjectId(projectId)
        : sessionProjectIdForSessionId(sessionId);
    _updateConversationSettingsAtIndex(
      index: index,
      conversationId: conversationId,
      projectId: resolvedProjectId,
      sessionRef: sessionId,
      threadMode: 'continue',
      hydrateIfNeeded: hydrateIfNeeded,
      persist: persist,
      clearMessagesOnSessionReset: clearMessagesOnSessionReset,
    );
  }

  Map<String, dynamic>? _tryDecodeJson(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }

  void _applyDetailJson(
    String conversationId,
    Map<String, dynamic> detail, {
    bool hydrateTaskSnapshotSession = true,
    bool persistTaskSnapshotSession = true,
  }) {
    final kind = detailKindFromEnvelope(detail);
    if (kind == 'sessions') {
      _sessionSummaries = detailItemsFromEnvelope(detail);
      _sessionsLoaded = true;
      _stopDeferredSessionCatalogRetry();
      if (_reconcileConversationProjectsFromSessions()) {
        unawaited(_save());
      }
    } else if (kind == 'skills') {
      _skillCatalog = detailItemsFromEnvelope(detail);
      _skillsLoaded = true;
      _skillsLoading = false;
    } else if (isStructuredSessionDetailOrPageKind(kind)) {
      final item = detailItemFromEnvelope(detail);
      if (item != null) {
        _applySessionDetail(
          conversationId,
          item,
          appendOlder: kind == 'session_page',
        );
      }
    } else if (kind == 'task_snapshot') {
      final item = detailItemFromEnvelope(detail);
      if (item != null) {
        _applyTaskSnapshot(
          conversationId,
          item,
          taskSnapshotDetailFromEnvelope(detail),
          hydrateIfNeeded: hydrateTaskSnapshotSession,
          persist: persistTaskSnapshotSession,
        );
      }
    } else if (kind == 'codexResult') {
      final error = codexResultErrorText(detail);
      final timeline = List<Map<String, dynamic>>.from(
          timelineForConversation(conversationId));
      timeline.add({
        'stage': error.isNotEmpty ? 'failed' : 'done',
        'summary': error.isNotEmpty ? error : 'Codex result received',
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
      final rawEvents = List<Map<String, dynamic>>.from(
          rawEventsForConversation(conversationId));
      rawEvents.add(detail);
      _storeTimelineAndRawEvents(
        conversationId: conversationId,
        timeline: timeline,
        rawEvents: rawEvents,
      );
    }
  }

  void _applyTaskSnapshot(
    String conversationId,
    Map<String, dynamic> item,
    Map<String, dynamic>? detail, {
    bool hydrateIfNeeded = true,
    bool persist = true,
  }) {
    final timeline = (item['timeline'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final rawEvents = (item['raw_events'] as List<dynamic>? ??
            item['rawEvents'] as List<dynamic>? ??
            const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    _storeTimelineAndRawEvents(
      conversationId: conversationId,
      timeline: timeline,
      rawEvents: rawEvents,
    );

    final sessionId = taskSnapshotSessionIdFromDetail(detail);
    if (sessionId.isNotEmpty) {
      _bindSessionRefAtConversation(
        conversationId: conversationId,
        sessionId: sessionId,
        hydrateIfNeeded: hydrateIfNeeded,
        persist: persist,
        clearMessagesOnSessionReset: hydrateIfNeeded || persist,
      );
    }
  }

  void _applySessionDetail(
    String conversationId,
    Map<String, dynamic> typed, {
    required bool appendOlder,
    bool persist = true,
    bool sort = true,
    String? preferLatestAssistantText,
  }) {
    final sessionMessages = (typed['messages'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final timeline = (typed['timeline'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final rawEvents = (typed['raw_events'] as List<dynamic>? ??
            typed['rawEvents'] as List<dynamic>? ??
            const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    _storeTimelineAndRawEvents(
      conversationId: conversationId,
      timeline: timeline,
      rawEvents: rawEvents,
    );

    final restoredMessages = sessionMessages
        .map((item) {
          final role = item['role']?.toString().toLowerCase() ?? 'assistant';
          final user = role == 'user' ? me : assistant;
          final cleaningRole = role == 'user'
              ? AgentDashboardMessageRole.user
              : AgentDashboardMessageRole.assistant;
          final text = _cleanDashboardMessageText(
            item['text']?.toString() ?? '',
            source: AgentDashboardMessageSource.sessionDetail,
            role: cleaningRole,
          );
          return ChatMessage(
            text: text,
            createdAt: DateTime.tryParse(item['timestamp']?.toString() ?? '') ??
                DateTime.now(),
            user: user,
          );
        })
        .where((msg) => msg.text.trim().isNotEmpty)
        .toList()
        .reversed
        .toList();
    final preferredAssistantText = preferLatestAssistantText?.trim() ?? '';
    if (preferredAssistantText.isNotEmpty) {
      final hasPreferredText = restoredMessages.any(
        (message) =>
            message.user.id == assistant.id &&
            message.text.trim() == preferredAssistantText,
      );
      if (!hasPreferredText) {
        restoredMessages.insert(
          0,
          ChatMessage(
            text: preferredAssistantText,
            createdAt: DateTime.now(),
            user: assistant,
          ),
        );
      }
    }
    _sessionNextCursorByConversation[conversationId] =
        sessionNextCursorFromDetail(typed);

    final index = _conversationIndexById(conversationId);
    if (index == -1) {
      return;
    }
    final nextConversations = List<AgentConversation>.from(_conversations);
    final conversation = nextConversations[index];
    final mergedMessages = appendOlder
        ? _mergeOlderMessages(conversation.messages, restoredMessages)
        : restoredMessages;
    nextConversations[index] = conversation.copyWith(
      title: typed['title']?.toString().trim().isNotEmpty == true
          ? typed['title']!.toString().trim()
          : conversation.title,
      projectId: sessionProjectIdFromMetadata(typed) ?? conversation.projectId,
      sessionRef: typed['id']?.toString().trim().isNotEmpty == true
          ? typed['id']!.toString().trim()
          : conversation.sessionRef,
      threadMode: 'continue',
      messages: mergedMessages.isEmpty ? conversation.messages : mergedMessages,
      updatedAt: DateTime.now(),
    );
    _conversations = nextConversations;
    if (sort) {
      _sortConversations();
    }
    if (persist) {
      unawaited(_save());
    }
  }

  void _storeTimelineAndRawEvents({
    required String conversationId,
    required List<Map<String, dynamic>> timeline,
    required List<Map<String, dynamic>> rawEvents,
  }) {
    _timelineByConversation[conversationId] = timeline;
    _rawEventsByConversation[conversationId] = rawEvents;
  }

  List<ChatMessage> _mergeOlderMessages(
    List<ChatMessage> currentMessages,
    List<ChatMessage> olderMessages,
  ) {
    if (olderMessages.isEmpty) return currentMessages;
    if (currentMessages.isEmpty) return olderMessages;
    final seen =
        currentMessages.map((message) => _messageFingerprint(message)).toSet();
    final merged = List<ChatMessage>.from(currentMessages);
    for (final message in olderMessages) {
      final fingerprint = _messageFingerprint(message);
      if (seen.add(fingerprint)) {
        merged.add(message);
      }
    }
    return merged;
  }

  String _messageFingerprint(ChatMessage message) {
    return '${message.user.id}|${message.createdAt.toIso8601String()}|${message.text}';
  }

  String _cleanDashboardMessageText(
    String text, {
    required AgentDashboardMessageSource source,
    required AgentDashboardMessageRole role,
  }) {
    return _messageCleaningHarness
        .clean(AgentDashboardMessageCleaningContext(
          text: text,
          source: source,
          role: role,
        ))
        .text;
  }

  Future<void> _ensureConversationHydratedAtIndex(int index) async {
    final conversation = _conversations[index];
    final conversationId = conversation.id;
    final sessionId = conversation.sessionRef.trim();
    if (sessionId.isEmpty || conversation.messages.isNotEmpty) return;
    if (_sessionHydrationInFlight.contains(conversationId)) return;
    final detail = await _refreshConversationFromSession(
      conversationId: conversationId,
      sessionId: sessionId,
      cursor: null,
      appendOlder: false,
      persist: false,
    );
    if (detail == null) {
      return;
    }
    notifyListeners();
    _sortConversations();
    unawaited(_save());
    unawaited(_prefetchOlderSessionHistoryInBackground(conversationId));
  }

  Future<bool> _loadOneOlderSessionHistoryPage({
    required String conversationId,
    bool persist = true,
    bool notifyOnStart = true,
  }) async {
    if (_sessionHydrationInFlight.contains(conversationId)) {
      return false;
    }
    final index = _conversationIndexById(conversationId);
    if (index == -1) {
      return false;
    }
    final conversation = _conversations[index];
    final sessionId = conversation.sessionRef.trim();
    final cursor = sessionNextCursorForConversationObject(conversation);
    if (sessionId.isEmpty || cursor == null) {
      return false;
    }
    final detail = await _refreshConversationFromSession(
      conversationId: conversationId,
      sessionId: sessionId,
      cursor: cursor,
      appendOlder: true,
      persist: persist,
      notifyOnStart: notifyOnStart,
    );
    if (detail == null) {
      return false;
    }
    if (!persist) {
      _sortConversations();
      unawaited(_save());
    }
    return true;
  }

  Future<void> _prefetchOlderSessionHistoryInBackground(
      String conversationId) async {
    await Future<void>.delayed(_backgroundSessionPrefetchDelay);
    final index = _conversationIndexById(conversationId);
    if (index == -1) {
      return;
    }
    final conversation = _conversations[index];
    if (conversation.messages.length >=
        _backgroundSessionPrefetchTargetMessages) {
      return;
    }
    if (!canLoadMoreSessionHistoryForConversation(conversation)) {
      return;
    }
    try {
      final loaded = await _loadOneOlderSessionHistoryPage(
        conversationId: conversationId,
        persist: false,
      );
      if (loaded) {
        notifyListeners();
      }
    } catch (e) {
      debugPrint(
        '[AgentDashboardModel] Background history prefetch failed for '
        '$conversationId: $e',
      );
    }
  }

  Future<Map<String, dynamic>?> _refreshConversationFromSession({
    required String conversationId,
    required String sessionId,
    required int? cursor,
    required bool appendOlder,
    bool persist = true,
    bool notifyOnStart = false,
    String? preferLatestAssistantText,
  }) async {
    _sessionHydrationInFlight.add(conversationId);
    if (notifyOnStart) {
      notifyListeners();
    }
    try {
      final detail = await runtime.loadSessionDetail(
        sessionId,
        cursor: cursor,
        conversationId: conversationId,
      );
      if (detail == null) {
        return null;
      }
      _applySessionDetail(
        conversationId,
        detail,
        appendOlder: appendOlder,
        persist: persist,
        sort: persist,
        preferLatestAssistantText: preferLatestAssistantText,
      );
      return detail;
    } finally {
      _sessionHydrationInFlight.remove(conversationId);
    }
  }

  AgentConversationStatus _statusFromRuntime(String status) {
    switch (status) {
      case 'started':
      case 'running':
        return AgentConversationStatus.running;
      case 'needs_confirmation':
        return AgentConversationStatus.needsConfirmation;
      case 'done':
      case 'cancelled':
        return AgentConversationStatus.completed;
      default:
        return AgentConversationStatus.failed;
    }
  }

  String _agentEventText({
    required String project,
    required String status,
    required String text,
  }) {
    final label =
        status == 'needs_confirmation' ? 'needs confirmation' : status;
    final buffer = StringBuffer('[Agent:$project] $label');
    if (text.trim().isNotEmpty) {
      buffer.write(':\n${text.trim()}');
    }
    return buffer.toString();
  }

  bool _shouldRecoverBridgeRunFailure({
    required String requestId,
    required String status,
    required String text,
  }) {
    if (requestId.trim().isEmpty || status != 'failed') {
      return false;
    }
    if (!text.contains(_bridgeRunTransportFailure)) {
      return false;
    }
    return (_statusRecoveryAttempts[requestId] ?? 0) == 0;
  }

  String? _extractAgentResultRequestId(String text) {
    final match = RegExp(
      r'^\[Agent:[^\]]+\]\s+[A-Za-z ]+:\s*([0-9a-fA-F-]{36})(?:\s|$)',
    ).firstMatch(text.trimLeft());
    return match?.group(1);
  }

  bool _wasStructuredResultSeen(String requestId) {
    final seenAt = _recentStructuredAgentResults[requestId];
    if (seenAt == null) {
      return false;
    }
    if (DateTime.now().difference(seenAt) > const Duration(seconds: 15)) {
      _recentStructuredAgentResults.remove(requestId);
      return false;
    }
    return true;
  }

  void _pruneRecentStructuredResults() {
    final now = DateTime.now();
    _recentStructuredAgentResults.removeWhere(
      (_, seenAt) => now.difference(seenAt) > const Duration(seconds: 15),
    );
  }

  Future<void> _load() async {
    try {
      final raw = await _storage.read(
        runtime.peerId,
        _storageFileName,
      );
      if (raw.trim().isEmpty) {
        _conversations = [];
        return;
      }
      final data = jsonDecode(raw) as List<dynamic>;
      _conversations = data
          .whereType<Map>()
          .map((e) => AgentConversation.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      _sortConversations();
    } catch (e) {
      debugPrint('[AgentDashboardModel] Failed to load conversations: $e');
      _conversations = [];
    }
  }

  void _loadAvailableProjects() {
    try {
      final ids = runtime
          .loadProjectIds()
          .map((id) => _canonicalProjectId(id))
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      _availableProjects = ids.isEmpty ? [defaultProjectId] : ids;
    } catch (e) {
      debugPrint('[AgentDashboardModel] Failed to parse project list: $e');
      _availableProjects = [defaultProjectId];
    }
  }

  List<String> _collectAvailableProjects() {
    final merged = <String>[];

    void appendProjectId(String? raw) {
      final value = _canonicalProjectId(raw);
      if (value.isEmpty || merged.contains(value)) {
        return;
      }
      merged.add(value);
    }

    for (final projectId in _availableProjects) {
      appendProjectId(projectId);
    }
    for (final conversation in _conversations) {
      appendProjectId(conversation.projectId);
    }
    for (final session in _sessionSummaries) {
      appendProjectId(sessionProjectIdFromMetadata(session));
    }
    if (merged.isEmpty) {
      merged.add(defaultProjectId);
    }
    return merged;
  }

  bool _reconcileConversationProjectsFromSessions() {
    var changed = false;
    final nextConversations = List<AgentConversation>.from(_conversations);
    for (var index = 0; index < nextConversations.length; index++) {
      final conversation = nextConversations[index];
      final sessionRef = conversation.sessionRef.trim();
      if (sessionRef.isEmpty) {
        continue;
      }
      final projectId = sessionProjectIdForSessionId(sessionRef);
      if (projectId == null ||
          _sameProjectId(projectId, conversation.projectId)) {
        continue;
      }
      nextConversations[index] = conversation.copyWith(
        projectId: projectId,
        updatedAt: conversation.updatedAt,
      );
      changed = true;
    }
    if (changed) {
      _conversations = nextConversations;
    }
    return changed;
  }

  Future<void> _save() async {
    if (_saving) {
      _saveQueued = true;
      return;
    }
    _saving = true;
    try {
      await _storage.write(
        runtime.peerId,
        _storageFileName,
        jsonEncode(_conversations.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('[AgentDashboardModel] Failed to save conversations: $e');
    } finally {
      _saving = false;
      if (_saveQueued) {
        _saveQueued = false;
        unawaited(_save());
      }
    }
  }

  Future<void> resetDemoState() async {
    await ensureLoaded();
    _conversations = _buildDemoConversations();
    _sortConversations();
    _activeRequestConversationId = null;
    _taskStatusBubbles.clear();
    _taskStatusBubbleDedupeKeys.clear();
    _requestStatusBubbleKeys.clear();
    _taskStatusBubbleTimer?.cancel();
    _stopDeferredSessionCatalogRetry();
    _sessionCatalogRetryCount = 0;
    _selectedConversationId = _conversations.first.id;
    _applyDemoStatuses(_conversations);
    final selectedIndex = _selectedConversationIndex();
    _syncComposerDraft(_conversations[selectedIndex].draft);
    await _save();
    notifyListeners();
  }

  @override
  void dispose() {
    _draftSaveTimer?.cancel();
    _taskStatusBubbleTimer?.cancel();
    _stopDeferredSessionCatalogRetry();
    textController.dispose();
    inputFocusNode.dispose();
    super.dispose();
  }

  String? _fallbackConversationId() {
    if (_conversations.isEmpty) return null;
    return _conversations.first.id;
  }

  void _sortConversations() {
    _conversations.sort(_compareConversations);
  }

  void _applyDemoStatuses(List<AgentConversation> conversations) {
    _runtimeStatuses.clear();
    _runtimeStatusDetails.clear();
    if (conversations.isEmpty) return;
    _runtimeStatuses[conversations[0].id] = AgentConversationStatus.completed;
    _runtimeStatusDetails[conversations[0].id] =
        'Mock analysis finished and returned a read-only summary.';
    if (conversations.length > 1) {
      _runtimeStatuses[conversations[1].id] =
          AgentConversationStatus.needsConfirmation;
      _runtimeStatusDetails[conversations[1].id] =
          'Mock bridge is waiting for workspace-write confirmation.';
    }
    if (conversations.length > 2) {
      _runtimeStatuses[conversations[2].id] = AgentConversationStatus.running;
      _runtimeStatusDetails[conversations[2].id] =
          'Mock bridge is collecting terminal transcript context.';
    }
  }

  int _compareConversations(AgentConversation a, AgentConversation b) {
    if (a.archived != b.archived) {
      return a.archived ? 1 : -1;
    }
    if (a.pinned != b.pinned) {
      return a.pinned ? -1 : 1;
    }
    return b.updatedAt.compareTo(a.updatedAt);
  }

  AgentConversationStatus? _parseAgentStatus(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('] started:')) {
      return AgentConversationStatus.running;
    }
    if (lower.contains('] needs confirmation:')) {
      return AgentConversationStatus.needsConfirmation;
    }
    if (lower.contains('] done:')) {
      return AgentConversationStatus.completed;
    }
    if (lower.contains('] failed:')) {
      return AgentConversationStatus.failed;
    }
    return null;
  }

  String _summarizeAgentStatus(String text) {
    final normalized = text.replaceAll('\r\n', '\n').trim();
    final firstLine = normalized.split('\n').first.trim();
    final suffix = firstLine.split(':');
    final summary =
        suffix.length > 1 ? suffix.sublist(1).join(':').trim() : firstLine;
    return summary.isEmpty ? firstLine : summary;
  }

  String? _agentEventSnippet(String text) {
    final normalized = text.replaceAll('\r\n', '\n').trimLeft();
    if (!normalized.startsWith('[Agent:')) return null;
    final firstBreak = normalized.indexOf('\n');
    final firstLine =
        (firstBreak == -1 ? normalized : normalized.substring(0, firstBreak))
            .trimRight();
    final body =
        firstBreak == -1 ? '' : normalized.substring(firstBreak + 1).trim();
    final match = RegExp(r'^\[Agent:([^\]]+)\]\s+([^:]+):?\s*(.*)$')
        .firstMatch(firstLine);
    if (match == null) return null;
    final project = match.group(1)?.trim() ?? defaultProjectId;
    final rawStatus = (match.group(2) ?? '').trim();
    final inlineBody = (match.group(3) ?? '').trim();
    final detail = inlineBody.isNotEmpty
        ? inlineBody
        : body.replaceAll(RegExp(r'\s+'), ' ').trim();
    final status = rawStatus
        .toLowerCase()
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    final label = switch (status) {
      'started' || 'running' => 'Thinking',
      'needs confirmation' => 'Needs approval',
      'done' || 'completed' || 'cancelled' => 'Done',
      'failed' || 'error' => 'Failed',
      _ => rawStatus.isEmpty ? 'Update' : rawStatus,
    };
    return detail.isEmpty ? '$label in $project' : '$label: $detail';
  }

  void _handleComposerChanged() {
    if (_syncingComposer) return;
    final index = _selectedConversationIndex();
    if (index == -1) return;
    final conversation = _conversations[index];
    if (conversation.draft == textController.text) {
      return;
    }
    final nextConversations = List<AgentConversation>.from(_conversations);
    nextConversations[index] = nextConversations[index].copyWith(
      draft: textController.text,
    );
    _conversations = nextConversations;
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(
      const Duration(milliseconds: 220),
      () => unawaited(_save()),
    );
  }

  void _syncComposerDraft(String draft) {
    if (textController.text == draft) return;
    _syncingComposer = true;
    textController.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
    _syncingComposer = false;
  }

  void _syncSelectedConversationSideEffects(
    int index, {
    bool notifyRead = true,
    bool syncComposer = true,
    bool persistRead = true,
  }) {
    if (syncComposer) {
      _syncComposerDraft(_conversations[index].draft);
    }
    _markConversationReadAtIndex(
      index: index,
      notify: notifyRead,
      persist: persistRead,
    );
  }

  int _selectedConversationIndex() {
    final selectedId = _selectedConversationId;
    if (selectedId == null) return -1;
    final index = _conversationIndexById(selectedId);
    if (index != -1) return index;
    return _conversations.isEmpty ? -1 : 0;
  }

  int _conversationIndexById(String conversationId) {
    if (_conversations.isNotEmpty &&
        _conversations.first.id == conversationId) {
      return 0;
    }
    return _conversations.indexWhere((item) => item.id == conversationId);
  }

  void _markConversationReadAtIndex({
    required int index,
    bool notify = true,
    bool persist = true,
  }) {
    final conversation = _conversations[index];
    if (!_conversationHasUnread(conversation)) {
      return;
    }
    final nextConversations = List<AgentConversation>.from(_conversations);
    nextConversations[index] = nextConversations[index].copyWith(
      lastReadAt: DateTime.now(),
    );
    _conversations = nextConversations;
    if (persist) {
      unawaited(_save());
    }
    if (notify) {
      notifyListeners();
    }
  }

  bool _conversationHasUnread(AgentConversation conversation) {
    if (conversation.messages.isEmpty) {
      return false;
    }
    final lastReadAt = conversation.lastReadAt;
    if (lastReadAt == null) {
      return true;
    }
    return conversation.messages.first.createdAt.isAfter(lastReadAt);
  }
}
