import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/models/agent_dashboard_model.dart';
import 'package:flutter_hbb/models/agent_dashboard_storage.dart';

class _MemoryAgentDashboardStorage implements AgentDashboardStorage {
  final Map<String, String> _values = <String, String>{};
  int writeCount = 0;

  @override
  Future<String> read(String peerId, String fileName) async {
    return _values['$peerId::$fileName'] ?? '';
  }

  @override
  Future<void> write(String peerId, String fileName, String value) async {
    writeCount += 1;
    _values['$peerId::$fileName'] = value;
  }

  void seed(String peerId, String fileName, String value) {
    _values['$peerId::$fileName'] = value;
  }
}

class _TrackingRuntime implements AgentDashboardRuntime {
  _TrackingRuntime({
    required this.hasActiveTracking,
  });

  final bool hasActiveTracking;
  int requestTaskStatusCalls = 0;
  Map<String, dynamic>? nextTaskStatusResponse;

  @override
  String get peerId => 'test-peer';

  @override
  List<String> loadProjectIds() => const [AgentDashboardModel.defaultProjectId];

  @override
  String loadTerminalContext() => '';

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
  Future<List<Map<String, dynamic>>> loadSessions({
    String? conversationId,
  }) async {
    return const [];
  }

  @override
  Future<Map<String, dynamic>?> loadSessionDetail(
    String sessionId, {
    int? cursor,
    int pageSize = 40,
    String? conversationId,
  }) async {
    return null;
  }

  @override
  Future<List<Map<String, dynamic>>> loadSkills({
    String? conversationId,
  }) async {
    return const [];
  }

  @override
  Future<Map<String, dynamic>> upsertSkill(Map<String, dynamic> payload) async {
    return payload;
  }

  @override
  Future<void> deleteSkill(String skillId) async {}

  @override
  Future<Map<String, dynamic>> syncSkills() async {
    return const <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> transcribeVoice(
    Map<String, dynamic> payload,
  ) async {
    return const <String, dynamic>{};
  }

  @override
  Future<String> recordVoiceClipBase64({
    Duration duration = const Duration(seconds: 5),
  }) async {
    return 'UklGRg==';
  }

  @override
  bool get defersSkillCatalogLoad => false;

  @override
  bool hasActiveStatusTracking(String requestId) => hasActiveTracking;

  @override
  Future<Map<String, dynamic>?> requestTaskStatus({
    required String requestId,
    required String projectId,
  }) async {
    requestTaskStatusCalls += 1;
    if (nextTaskStatusResponse != null) {
      return Map<String, dynamic>.from(nextTaskStatusResponse!);
    }
    return {
      'request_id': requestId,
      'project': projectId,
      'status': 'done',
      'text': 'Recovered.',
      'token': '',
      'detail_json': '',
    };
  }

  @override
  Future<void> onCommandDispatched({
    required AgentDashboardModel model,
    required AgentConversation conversation,
    required String prompt,
    required String requestId,
  }) async {}
}

class _DispatchTrackingRuntime extends _TrackingRuntime {
  _DispatchTrackingRuntime() : super(hasActiveTracking: false);

  int dispatchEnvelopeCalls = 0;
  Map<String, dynamic>? lastEnvelope;

  @override
  Future<void> dispatchEnvelope(Map<String, dynamic> envelope) async {
    dispatchEnvelopeCalls += 1;
    lastEnvelope = Map<String, dynamic>.from(envelope);
  }
}

class _DeferredSkillsRuntime extends _DispatchTrackingRuntime {
  int loadSessionsCalls = 0;
  int loadSkillsCalls = 0;
  String? lastConversationId;

  @override
  bool get defersSkillCatalogLoad => true;

  @override
  Future<List<Map<String, dynamic>>> loadSessions({
    String? conversationId,
  }) async {
    loadSessionsCalls += 1;
    lastConversationId = conversationId;
    await dispatchEnvelope({
      'requestId': 'deferred-sessions-request-$loadSessionsCalls',
      'kind': 'list_sessions',
      'action': 'list_sessions',
      if (conversationId != null) 'conversationId': conversationId,
    });
    return const [];
  }

  @override
  Future<List<Map<String, dynamic>>> loadSkills({
    String? conversationId,
  }) async {
    loadSkillsCalls += 1;
    lastConversationId = conversationId;
    await dispatchEnvelope({
      'requestId': 'deferred-skill-request',
      'kind': 'list_skills',
      'action': 'list_skills',
      if (conversationId != null) 'conversationId': conversationId,
    });
    return const [];
  }
}

class _SessionRestoreTrackingRuntime extends _TrackingRuntime {
  _SessionRestoreTrackingRuntime() : super(hasActiveTracking: false);

  int loadSessionDetailCalls = 0;
  String? lastSessionDetailConversationId;

  @override
  Future<Map<String, dynamic>?> loadSessionDetail(
    String sessionId, {
    int? cursor,
    int pageSize = 40,
    String? conversationId,
  }) async {
    loadSessionDetailCalls += 1;
    lastSessionDetailConversationId = conversationId;
    return {
      'id': sessionId,
      'title': 'Tracked Session',
      'updatedAt': DateTime.now().toIso8601String(),
      'messages': [
        {
          'role': 'assistant',
          'text': 'Tracked session detail',
          'timestamp': DateTime.now().toIso8601String(),
        },
      ],
      'timeline': const [],
      'rawEvents': const [],
      'nextCursor': null,
    };
  }
}

class _DispatchContinueSessionRuntime extends _DispatchTrackingRuntime {
  int loadSessionDetailCalls = 0;

  @override
  Future<Map<String, dynamic>?> loadSessionDetail(
    String sessionId, {
    int? cursor,
    int pageSize = 40,
    String? conversationId,
  }) async {
    loadSessionDetailCalls += 1;
    return {
      'id': sessionId,
      'title': 'Continue dispatch session',
      'updatedAt': DateTime.now().toIso8601String(),
      'messages': [
        {
          'role': 'assistant',
          'text': 'Tracked session detail',
          'timestamp': DateTime.now().toIso8601String(),
        },
      ],
      'timeline': const [],
      'rawEvents': const [],
      'nextCursor': null,
    };
  }
}

class _MessageCleaningSessionRuntime extends _TrackingRuntime {
  _MessageCleaningSessionRuntime({
    required this.role,
    required this.text,
  }) : super(hasActiveTracking: false);

  final String role;
  final String text;
  int loadSessionDetailCalls = 0;

  @override
  Future<Map<String, dynamic>?> loadSessionDetail(
    String sessionId, {
    int? cursor,
    int pageSize = 40,
    String? conversationId,
  }) async {
    loadSessionDetailCalls += 1;
    return {
      'id': sessionId,
      'title': 'Message Cleaning Session',
      'updatedAt': DateTime.now().toIso8601String(),
      'messages': [
        {
          'role': role,
          'text': text,
          'timestamp': DateTime.now().toIso8601String(),
        },
      ],
      'timeline': const [],
      'rawEvents': const [],
      'nextCursor': null,
    };
  }
}

class _ProjectSessionRuntime extends _TrackingRuntime {
  _ProjectSessionRuntime() : super(hasActiveTracking: false);

  @override
  List<String> loadProjectIds() => const ['rustdesk', 'BlueprintHarness'];

  @override
  Future<List<Map<String, dynamic>>> loadSessions({
    String? conversationId,
  }) async {
    return [
      {
        'id': 'session-rustdesk-1',
        'title': 'RustDesk Session',
        'projectId': 'rustdesk',
        'updatedAt': DateTime.now().toIso8601String(),
      },
      {
        'id': 'session-blueprint-1',
        'title': 'Blueprint Session',
        'projectId': 'BlueprintHarness',
        'projectPath': r'E:\BlueprintHarness',
        'updatedAt': DateTime.now().toIso8601String(),
      },
    ];
  }

  @override
  Future<Map<String, dynamic>?> loadSessionDetail(
    String sessionId, {
    int? cursor,
    int pageSize = 40,
    String? conversationId,
  }) async {
    final projectId =
        sessionId == 'session-blueprint-1' ? 'BlueprintHarness' : 'rustdesk';
    return {
      'id': sessionId,
      'title': 'Restored $projectId',
      'projectId': projectId,
      'updatedAt': DateTime.now().toIso8601String(),
      'messages': [
        {
          'role': 'assistant',
          'text': 'Restored $projectId session',
          'timestamp': DateTime.now().toIso8601String(),
        },
      ],
      'timeline': const [],
      'rawEvents': const [],
      'nextCursor': null,
    };
  }
}

class _SessionPathOnlyProjectRuntime extends _TrackingRuntime {
  _SessionPathOnlyProjectRuntime() : super(hasActiveTracking: false);

  int loadSessionDetailCalls = 0;

  @override
  List<String> loadProjectIds() => const ['rustdesk'];

  @override
  Future<List<Map<String, dynamic>>> loadSessions({
    String? conversationId,
  }) async {
    return [
      {
        'id': 'session-rustdesk-1',
        'title': 'RustDesk Session',
        'projectId': 'rustdesk',
        'updatedAt': DateTime.now().toIso8601String(),
      },
      {
        'id': 'session-blueprint-path-1',
        'title': 'Blueprint Path Session',
        'cwd': r'E:\BlueprintHarness',
        'updatedAt': DateTime.now().toIso8601String(),
      },
    ];
  }

  @override
  Future<Map<String, dynamic>?> loadSessionDetail(
    String sessionId, {
    int? cursor,
    int pageSize = 40,
    String? conversationId,
  }) async {
    loadSessionDetailCalls += 1;
    return {
      'id': sessionId,
      'title': 'Restored BlueprintHarness',
      'payload': {
        'cwd': r'E:\BlueprintHarness',
      },
      'updatedAt': DateTime.now().toIso8601String(),
      'messages': [
        {
          'role': 'assistant',
          'text': 'Restored BlueprintHarness session',
          'timestamp': DateTime.now().toIso8601String(),
        },
      ],
      'timeline': const [],
      'rawEvents': const [],
      'nextCursor': null,
    };
  }
}

class _SessionPathOnlyProjectDispatchRuntime
    extends _SessionPathOnlyProjectRuntime {
  int dispatchEnvelopeCalls = 0;
  Map<String, dynamic>? lastEnvelope;

  @override
  Future<void> dispatchEnvelope(Map<String, dynamic> envelope) async {
    dispatchEnvelopeCalls += 1;
    lastEnvelope = Map<String, dynamic>.from(envelope);
  }
}

class _SessionDetailPathOnlyRuntime extends _TrackingRuntime {
  _SessionDetailPathOnlyRuntime() : super(hasActiveTracking: false);

  int loadSessionDetailCalls = 0;

  @override
  List<String> loadProjectIds() => const ['rustdesk'];

  @override
  Future<Map<String, dynamic>?> loadSessionDetail(
    String sessionId, {
    int? cursor,
    int pageSize = 40,
    String? conversationId,
  }) async {
    loadSessionDetailCalls += 1;
    return {
      'id': sessionId,
      'title': 'Detail-only BlueprintHarness',
      'payload': {
        'project_path': r'E:\BlueprintHarness',
      },
      'updatedAt': DateTime.now().toIso8601String(),
      'messages': [
        {
          'role': 'assistant',
          'text': 'Detail-only BlueprintHarness session',
          'timestamp': DateTime.now().toIso8601String(),
        },
      ],
      'timeline': const [],
      'rawEvents': const [],
      'nextCursor': null,
    };
  }
}

class _ConflictingSessionSummaryProjectRuntime extends _TrackingRuntime {
  _ConflictingSessionSummaryProjectRuntime() : super(hasActiveTracking: false);

  @override
  List<String> loadProjectIds() => const ['rustdesk'];

  @override
  Future<List<Map<String, dynamic>>> loadSessions({
    String? conversationId,
  }) async {
    return [
      {
        'id': 'session-blueprint-conflict-1',
        'title': 'Blueprint Conflict Session',
        'projectId': 'rustdesk',
        'projectPath': r'E:\BlueprintHarness',
        'updatedAt': DateTime.now().toIso8601String(),
      },
    ];
  }
}

class _PagedSessionRestoreRuntime extends _TrackingRuntime {
  _PagedSessionRestoreRuntime() : super(hasActiveTracking: false);

  int loadSessionDetailCalls = 0;

  @override
  Future<Map<String, dynamic>?> loadSessionDetail(
    String sessionId, {
    int? cursor,
    int pageSize = 40,
    String? conversationId,
  }) async {
    loadSessionDetailCalls += 1;
    if (cursor == null) {
      return {
        'id': sessionId,
        'title': 'Paged Session',
        'updatedAt': DateTime.now().toIso8601String(),
        'messages': [
          {
            'role': 'assistant',
            'text': 'Newest page',
            'timestamp': DateTime.now().toIso8601String(),
          },
        ],
        'timeline': const [],
        'rawEvents': const [],
        'nextCursor': 1,
      };
    }
    return {
      'id': sessionId,
      'title': 'Paged Session',
      'updatedAt': DateTime.now().toIso8601String(),
      'messages': [
        {
          'role': 'user',
          'text': 'Older page',
          'timestamp': DateTime.now()
              .subtract(const Duration(minutes: 1))
              .toIso8601String(),
        },
      ],
      'timeline': const [],
      'rawEvents': const [],
      'nextCursor': null,
    };
  }
}

class _SnakeCasePagedSessionRestoreRuntime extends _TrackingRuntime {
  _SnakeCasePagedSessionRestoreRuntime() : super(hasActiveTracking: false);

  int loadSessionDetailCalls = 0;

  @override
  Future<Map<String, dynamic>?> loadSessionDetail(
    String sessionId, {
    int? cursor,
    int pageSize = 40,
    String? conversationId,
  }) async {
    loadSessionDetailCalls += 1;
    if (cursor == null) {
      return {
        'id': sessionId,
        'title': 'Snake Case Paged Session',
        'updatedAt': DateTime.now().toIso8601String(),
        'messages': [
          {
            'role': 'assistant',
            'text': 'Newest page',
            'timestamp': DateTime.now().toIso8601String(),
          },
        ],
        'timeline': const [],
        'rawEvents': const [],
        'next_cursor': 1,
      };
    }
    return {
      'id': sessionId,
      'title': 'Snake Case Paged Session',
      'updatedAt': DateTime.now().toIso8601String(),
      'messages': [
        {
          'role': 'user',
          'text': 'Older page',
          'timestamp': DateTime.now()
              .subtract(const Duration(minutes: 1))
              .toIso8601String(),
        },
      ],
      'timeline': const [],
      'rawEvents': const [],
      'next_cursor': null,
    };
  }
}

class _DoneSessionRefreshRuntime extends _TrackingRuntime {
  _DoneSessionRefreshRuntime() : super(hasActiveTracking: false);

  int loadSessionDetailCalls = 0;

  @override
  Future<Map<String, dynamic>?> loadSessionDetail(
    String sessionId, {
    int? cursor,
    int pageSize = 40,
    String? conversationId,
  }) async {
    loadSessionDetailCalls += 1;
    return {
      'id': sessionId,
      'title': 'Done Session',
      'updatedAt': DateTime.now().toIso8601String(),
      'messages': [
        {
          'role': 'assistant',
          'text': 'Done session detail',
          'timestamp': DateTime.now().toIso8601String(),
        },
      ],
      'timeline': const [],
      'rawEvents': const [],
      'nextCursor': null,
    };
  }
}

class _LaggingDoneSessionRefreshRuntime extends _TrackingRuntime {
  _LaggingDoneSessionRefreshRuntime() : super(hasActiveTracking: false);

  int loadSessionDetailCalls = 0;

  @override
  Future<Map<String, dynamic>?> loadSessionDetail(
    String sessionId, {
    int? cursor,
    int pageSize = 40,
    String? conversationId,
  }) async {
    loadSessionDetailCalls += 1;
    return {
      'id': sessionId,
      'title': 'Lagging Done Session',
      'updatedAt': DateTime.now().toIso8601String(),
      'messages': [
        {
          'role': 'assistant',
          'text': 'Older synced session detail',
          'timestamp': DateTime.now()
              .subtract(const Duration(minutes: 1))
              .toIso8601String(),
        },
      ],
      'timeline': const [],
      'rawEvents': const [],
      'nextCursor': null,
    };
  }
}

class _AutoAttachLatestSessionRuntime extends _TrackingRuntime {
  _AutoAttachLatestSessionRuntime() : super(hasActiveTracking: false);

  int loadSessionDetailCalls = 0;

  @override
  Future<List<Map<String, dynamic>>> loadSessions({
    String? conversationId,
  }) async {
    return [
      {
        'id': 'session-latest-auto-1',
        'title': 'Latest Auto Session',
        'updatedAt': DateTime.now().toIso8601String(),
      },
    ];
  }

  @override
  Future<Map<String, dynamic>?> loadSessionDetail(
    String sessionId, {
    int? cursor,
    int pageSize = 40,
    String? conversationId,
  }) async {
    loadSessionDetailCalls += 1;
    return {
      'id': sessionId,
      'title': 'Latest Auto Session',
      'updatedAt': DateTime.now().toIso8601String(),
      'messages': [
        {
          'role': 'assistant',
          'text': 'Auto attached latest session',
          'timestamp': DateTime.now().toIso8601String(),
        },
      ],
      'timeline': const [],
      'rawEvents': const [],
      'nextCursor': null,
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AgentDashboardRuntime envelope dispatch', () {
    test('continue route expands to explicit session run request fields', () {
      final body = buildAgentRunRequestBodyFromEnvelope({
        'requestId': 'route-body-1',
        'mode': 'read-only',
        'requireConfirmation': true,
        'prompt': 'Continue the selected session',
        'route': {
          'projectId': 'BlueprintHarness',
          'threadMode': 'continue',
          'activeThreadId': 'active-session-1',
          'codexThreadId': 'codex-session-1',
          'profileId': 'analysis',
        },
      });

      expect(body['request_id'], 'route-body-1');
      expect(body['project'], 'BlueprintHarness');
      expect(body['session'], 'codex-session-1');
      expect(body['resume_last'], true);
      expect(body['profile'], 'analysis');
      expect(body['require_confirmation'], true);
      expect(jsonDecode(body['prompt'] as String)['prompt'],
          'Continue the selected session');
    });

    test('new route omits session and does not request resume last', () {
      final body = buildAgentRunRequestBodyFromEnvelope({
        'requestId': 'route-body-2',
        'prompt': 'Start a new thread',
        'route': {
          'projectId': 'rustdesk',
          'threadMode': 'new',
          'activeThreadId': null,
          'codexThreadId': null,
        },
      });

      expect(body['project'], 'rustdesk');
      expect(body.containsKey('session'), false);
      expect(body['resume_last'], false);
    });
  });

  group('AgentDashboardModel status recovery', () {
    Future<AgentDashboardModel> createModel(_TrackingRuntime runtime) async {
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();
      return model;
    }

    test(
        'does not immediately request task status when runtime already tracks the request',
        () async {
      final runtime = _TrackingRuntime(hasActiveTracking: true);
      final model = await createModel(runtime);
      final conversationId = model.selectedConversation!.id;
      const requestId = '11111111-1111-1111-1111-111111111111';

      await model.handleAgentResultEvent({
        'request_id': requestId,
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'failed',
        'text':
            'Failed to send /agent/run to codex bridge because the local socket was unavailable.',
        'token': '',
        'detail_json': '',
      });

      expect(
        model.statusDetailForConversation(conversationId),
        'Recovering task status for $requestId',
      );
      expect(runtime.requestTaskStatusCalls, 0);
    });

    test(
        'still requests task status immediately when runtime has no active tracking',
        () async {
      final runtime = _TrackingRuntime(hasActiveTracking: false);
      final model = await createModel(runtime);
      const requestId = '22222222-2222-2222-2222-222222222222';

      await model.handleAgentResultEvent({
        'request_id': requestId,
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'failed',
        'text':
            'Failed to send /agent/run to codex bridge because the local socket was unavailable.',
        'token': '',
        'detail_json': '',
      });

      await Future<void>.delayed(Duration.zero);

      expect(runtime.requestTaskStatusCalls, 1);
    });

    test('cancels deferred recovery once a structured running event arrives',
        () async {
      final runtime = _TrackingRuntime(hasActiveTracking: true);
      final model = await createModel(runtime);
      const requestId = '33333333-3333-3333-3333-333333333333';

      await model.handleAgentResultEvent({
        'request_id': requestId,
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'failed',
        'text':
            'Failed to send /agent/run to codex bridge because the local socket was unavailable.',
        'token': '',
        'detail_json': '',
      });

      await model.handleAgentResultEvent({
        'request_id': requestId,
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'running',
        'text': 'Codex is running.',
        'token': '',
        'detail_json': '',
      });

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(runtime.requestTaskStatusCalls, 0);
    });

    test(
        'status recovery attempt helper still suppresses deferred fallback after running update',
        () async {
      final runtime = _TrackingRuntime(hasActiveTracking: true);
      final model = await createModel(runtime);
      final conversationId = model.selectedConversation!.id;
      const requestId = '33333333-4444-5555-6666-333333333333';

      await model.handleAgentResultEvent({
        'request_id': requestId,
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'failed',
        'text':
            'Failed to send /agent/run to codex bridge because the local socket was unavailable.',
        'token': '',
        'detail_json': '',
      });

      await model.handleAgentResultEvent({
        'request_id': requestId,
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'running',
        'text': 'Codex is running.',
        'token': '',
        'detail_json': '',
      });

      await Future<void>.delayed(const Duration(milliseconds: 4200));

      expect(runtime.requestTaskStatusCalls, 0);
      expect(
        model.statusForConversation(conversationId),
        AgentConversationStatus.running,
      );
      expect(
        model.statusDetailForConversation(conversationId),
        'Codex is running.',
      );
    });

    test('running status also clears immediate recovery attempt state',
        () async {
      final runtime = _TrackingRuntime(hasActiveTracking: false);
      final model = await createModel(runtime);
      const requestId = '77777777-7777-7777-7777-777777777777';

      await model.handleAgentResultEvent({
        'request_id': requestId,
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'failed',
        'text':
            'Failed to send /agent/run to codex bridge because the local socket was unavailable.',
        'token': '',
        'detail_json': '',
      });

      await model.handleAgentResultEvent({
        'request_id': requestId,
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'running',
        'text': 'Codex is running.',
        'token': '',
        'detail_json': '',
      });

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(runtime.requestTaskStatusCalls, 1);
    });

    test('still updates to completed when recovered status arrives', () async {
      final runtime = _TrackingRuntime(hasActiveTracking: false)
        ..nextTaskStatusResponse = {
          'request_id': '44444444-4444-4444-4444-444444444444',
          'project': AgentDashboardModel.defaultProjectId,
          'status': 'done',
          'text': 'Recovered.',
          'token': '',
          'detail_json': '',
        };
      final model = await createModel(runtime);
      final conversationId = model.selectedConversation!.id;

      await model.handleAgentResultEvent({
        'request_id': '44444444-4444-4444-4444-444444444444',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'failed',
        'text':
            'Failed to send /agent/run to codex bridge because the local socket was unavailable.',
        'token': '',
        'detail_json': '',
      });

      await Future<void>.delayed(Duration.zero);

      expect(
        model.statusForConversation(conversationId),
        AgentConversationStatus.completed,
      );
      expect(runtime.requestTaskStatusCalls, 1);
    });

    test(
        'status recovery cleanup helper still allows repeated recovery for same request',
        () async {
      final runtime = _TrackingRuntime(hasActiveTracking: false);
      final model = await createModel(runtime);
      final conversationId = model.selectedConversation!.id;
      const requestId = '66666666-6666-6666-6666-666666666666';
      const bridgeFailureText =
          'Failed to send /agent/run to codex bridge because the local socket was unavailable.';
      final bridgeFailureEvent = {
        'request_id': requestId,
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'failed',
        'text': bridgeFailureText,
        'token': '',
        'detail_json': '',
      };

      await model.handleAgentResultEvent(bridgeFailureEvent);
      await Future<void>.delayed(Duration.zero);

      expect(runtime.requestTaskStatusCalls, 1);
      expect(
        model.statusForConversation(conversationId),
        AgentConversationStatus.completed,
      );

      await model.handleAgentResultEvent(bridgeFailureEvent);
      await Future<void>.delayed(Duration.zero);

      expect(runtime.requestTaskStatusCalls, 2);
      expect(
        model.statusForConversation(conversationId),
        AgentConversationStatus.completed,
      );
    });
  });

  group('AgentDashboardModel event notifications', () {
    Future<AgentDashboardModel> createModel() async {
      final model = AgentDashboardModel.fromRuntime(
        _TrackingRuntime(hasActiveTracking: false),
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();
      return model;
    }

    test('plain agent result appends a message with one listener notification',
        () async {
      final model = await createModel();
      var notifications = 0;
      model.addListener(() {
        notifications += 1;
      });
      final conversationId = model.selectedConversation!.id;
      final beforeCount = model.selectedConversation!.messages.length;

      await model.handleAgentResultEvent({
        'request_id': '55555555-5555-5555-5555-555555555555',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': 'Plain completion',
        'token': '',
        'detail_json': '',
      });

      expect(notifications, 1);
      expect(model.selectedConversation!.messages.length, beforeCount + 1);
      expect(model.statusForConversation(conversationId),
          AgentConversationStatus.completed);
    });

    test('sendCurrentPrompt still appends local message and dispatches once',
        () async {
      final runtime = _DispatchTrackingRuntime();
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();
      final conversationId = model.selectedConversation!.id;
      final beforeCount = model.selectedConversation!.messages.length;

      model.textController.text = 'Inspect selected route';
      await model.sendCurrentPrompt();
      await Future<void>.delayed(Duration.zero);

      expect(runtime.dispatchEnvelopeCalls, 1);
      expect(runtime.lastEnvelope, isNotNull);
      expect(runtime.lastEnvelope!['prompt'], 'Inspect selected route');
      expect(model.selectedConversation!.messages.length, beforeCount + 1);
      expect(model.selectedConversation!.messages.first.text,
          'Inspect selected route');
      expect(
        model.statusForConversation(conversationId),
        AgentConversationStatus.running,
      );
      expect(model.visibleTaskStatusBubbles, isEmpty);
    });

    test(
        'sendCurrentPrompt omits history preview when continuing a bound session',
        () async {
      final runtime = _DispatchContinueSessionRuntime();
      final storage = _MemoryAgentDashboardStorage();
      final seededConversation = AgentConversation(
        id: 'seed-continue-dispatch-1',
        title: 'Continue dispatch',
        projectId: AgentDashboardModel.defaultProjectId,
        threadMode: 'continue',
        profile: '',
        sessionRef: 'session-continue-dispatch-1',
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
      storage.seed(
        runtime.peerId,
        'agent_dashboard_conversations.json',
        '[${jsonEncode(seededConversation.toJson())}]',
      );
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: storage,
      );

      await model.ensureLoaded();
      model.textController.text = 'Follow up on current session';
      await model.sendCurrentPrompt();
      await Future<void>.delayed(Duration.zero);

      final envelope = runtime.lastEnvelope!;
      final route = Map<String, dynamic>.from(envelope['route'] as Map);
      final context = Map<String, dynamic>.from(envelope['context'] as Map);
      expect(route['threadMode'], 'continue');
      expect(route['activeThreadId'], 'session-continue-dispatch-1');
      expect(context['includeHistory'], isFalse);
      expect(context['historyPreview'], '');
    });

    test('sendCurrentPrompt keeps history preview for a new local conversation',
        () async {
      final runtime = _DispatchTrackingRuntime();
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: _MemoryAgentDashboardStorage(),
      );

      await model.ensureLoaded();
      await model.handleAgentResultEvent({
        'request_id': 'local-history-preview-1',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': 'Earlier local note',
        'token': '',
        'detail_json': '',
      });
      model.textController.text = 'Start a fresh request';
      await model.sendCurrentPrompt();
      await Future<void>.delayed(Duration.zero);

      final envelope = runtime.lastEnvelope!;
      final route = Map<String, dynamic>.from(envelope['route'] as Map);
      final context = Map<String, dynamic>.from(envelope['context'] as Map);
      expect(route['threadMode'], 'new');
      expect(route['activeThreadId'], isNull);
      expect(context['includeHistory'], isTrue);
      expect(context['historyPreview'], contains('Earlier local note'));
    });

    test('sendVoiceClip dispatches voice_run envelope without prompt',
        () async {
      final runtime = _DispatchTrackingRuntime();
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();
      final conversationId = model.selectedConversation!.id;
      final beforeCount = model.selectedConversation!.messages.length;

      await model.sendVoiceClip(duration: const Duration(seconds: 1));
      await Future<void>.delayed(Duration.zero);

      expect(runtime.dispatchEnvelopeCalls, 1);
      expect(runtime.lastEnvelope, isNotNull);
      final envelope = runtime.lastEnvelope!;
      expect(envelope['kind'], 'voice_run');
      expect(envelope['action'], 'voice_run');
      expect(envelope.containsKey('prompt'), isFalse);
      expect(envelope['conversationId'], conversationId);
      expect(
        (envelope['route'] as Map<String, dynamic>)['projectId'],
        AgentDashboardModel.defaultProjectId,
      );
      expect(
        (envelope['voice'] as Map<String, dynamic>)['audioBase64'],
        'UklGRg==',
      );
      expect(model.selectedConversation!.messages.length, beforeCount + 1);
      expect(model.selectedConversation!.messages.first.text,
          'Voice clip sent to desktop agent.');
      expect(
        model.statusForConversation(conversationId),
        AgentConversationStatus.running,
      );
    });

    test('structured done result creates one task status bubble', () async {
      final model = await createModel();
      final conversationId = model.selectedConversation!.id;

      await model.handleAgentResultEvent({
        'request_id': 'task-bubble-done-0000-0000-000000000000',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': 'Finished route analysis',
        'token': '',
        'detail_json': '',
      });

      final bubbles = model.visibleTaskStatusBubbles;
      expect(bubbles, hasLength(1));
      expect(bubbles.first.conversationId, conversationId);
      expect(bubbles.first.title, 'Done');
      expect(bubbles.first.summary, 'Finished route analysis');
      expect(bubbles.first.sticky, false);
    });

    test('same request id and status does not duplicate task status bubble',
        () async {
      final model = await createModel();
      const requestId = 'task-bubble-dedupe-0000-0000-000000000000';

      await model.handleAgentResultEvent({
        'request_id': requestId,
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'failed',
        'text': 'Bridge failed once',
        'token': '',
        'detail_json': '',
      });
      await model.handleAgentResultEvent({
        'request_id': requestId,
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'failed',
        'text': 'Bridge failed once',
        'token': '',
        'detail_json': '',
      });

      expect(model.visibleTaskStatusBubbles, hasLength(1));
      expect(model.visibleTaskStatusBubbles.first.title, 'Failed');
    });

    test(
        'openTaskStatusBubble selects routed conversation and clears its bubbles',
        () async {
      final model = await createModel();
      final firstConversationId = model.selectedConversation!.id;
      model.createConversation();
      final secondConversationId = model.selectedConversation!.id;

      await model.handleAgentResultEvent({
        'request_id': 'task-bubble-open-0000-0000-000000000000',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'needs_confirmation',
        'text': 'Approval required for workspace write',
        'token': '',
        'detail_json':
            '{"conversationId":"$firstConversationId","kind":"codexResult","error":"workspace denied"}',
      });

      final bubble = model.visibleTaskStatusBubbles.single;
      model.openTaskStatusBubble(bubble.id);

      expect(model.selectedConversation!.id, firstConversationId);
      expect(model.selectedConversation!.id, isNot(secondConversationId));
      expect(model.visibleTaskStatusBubbles, isEmpty);
    });

    test('structured confirmation token stays out of chat message text',
        () async {
      final model = await createModel();
      final conversationId = model.selectedConversation!.id;

      await model.handleAgentResultEvent({
        'request_id': 'task-token-redaction-0000-000000000000',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'needs_confirmation',
        'text': 'Approval required for workspace write',
        'token': 'private-confirmation-token',
        'detail_json':
            '{"conversationId":"$conversationId","kind":"confirmation"}',
      });

      final message = model.selectedConversation!.messages.first.text;
      expect(message, contains('needs confirmation'));
      expect(message, contains('Approval required for workspace write'));
      expect(message, isNot(contains('private-confirmation-token')));
      expect(message, isNot(contains('Token:')));
    });

    test('selectConversation clears task status bubbles for that conversation',
        () async {
      final model = await createModel();
      final firstConversationId = model.selectedConversation!.id;
      model.createConversation();

      await model.handleAgentResultEvent({
        'request_id': 'task-bubble-select-0000-0000-000000000000',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'failed',
        'text': 'Selection should clear this bubble',
        'token': '',
        'detail_json':
            '{"conversationId":"$firstConversationId","kind":"codexResult","error":"workspace denied"}',
      });

      expect(model.visibleTaskStatusBubbles, hasLength(1));
      model.selectConversation(firstConversationId);
      expect(model.visibleTaskStatusBubbles, isEmpty);
    });

    test('text agent status creates confirmation bubble', () async {
      final model = await createModel();

      final handled = model.tryHandleAgentText(
        '[Agent:rustdesk] needs confirmation: Approval required for write access',
      );

      expect(handled, true);
      final bubbles = model.visibleTaskStatusBubbles;
      expect(bubbles, hasLength(1));
      expect(bubbles.first.title, 'Needs approval');
      expect(bubbles.first.sticky, true);
    });

    test('task status bubbles keep only the latest two items', () async {
      final model = await createModel();
      final firstConversationId = model.selectedConversation!.id;
      model.createConversation();
      final secondConversationId = model.selectedConversation!.id;
      model.createConversation();
      final thirdConversationId = model.selectedConversation!.id;

      await model.handleAgentResultEvent({
        'request_id': 'task-bubble-limit-1-0000-000000000000',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': 'First bubble',
        'token': '',
        'detail_json':
            '{"conversationId":"$firstConversationId","kind":"codexResult","error":""}',
      });
      await model.handleAgentResultEvent({
        'request_id': 'task-bubble-limit-2-0000-000000000000',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'failed',
        'text': 'Second bubble',
        'token': '',
        'detail_json':
            '{"conversationId":"$secondConversationId","kind":"codexResult","error":"workspace denied"}',
      });
      await model.handleAgentResultEvent({
        'request_id': 'task-bubble-limit-3-0000-000000000000',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'needs_confirmation',
        'text': 'Third bubble',
        'token': '',
        'detail_json':
            '{"conversationId":"$thirdConversationId","kind":"codexResult","error":"workspace denied"}',
      });

      final bubbles = model.visibleTaskStatusBubbles;
      expect(bubbles, hasLength(2));
      expect(
        bubbles.map((bubble) => bubble.conversationId).toList(),
        [thirdConversationId, secondConversationId],
      );
    });

    test('sendCurrentPrompt still updates title from prompt', () async {
      final runtime = _DispatchTrackingRuntime();
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();

      model.textController.text =
          'Review the current dashboard bridge session flow carefully';
      await model.sendCurrentPrompt();
      await Future<void>.delayed(Duration.zero);

      expect(model.selectedConversation!.title, 'Review the current dashboard');
      expect(runtime.dispatchEnvelopeCalls, 1);
      expect(model.selectedConversation!.messages.first.text,
          'Review the current dashboard bridge session flow carefully');
    });

    test('detail event without request id still updates session detail path',
        () async {
      final model = await createModel();
      var notifications = 0;
      model.addListener(() {
        notifications += 1;
      });

      await model.handleAgentResultEvent({
        'request_id': '',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': '',
        'token': '',
        'detail_json':
            '{"kind":"skills","items":[{"id":"skill-1","title":"Skill 1"}]}',
      });

      expect(model.skillsLoaded, true);
      expect(model.skillCatalog.length, 1);
      expect(notifications, 1);
    });

    test('deferred skills load waits for structured result to finish catalog',
        () async {
      final runtime = _DeferredSkillsRuntime();
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: _MemoryAgentDashboardStorage(),
      );

      await model.ensureLoaded();

      expect(runtime.loadSessionsCalls, 1);
      expect(runtime.loadSkillsCalls, 1);
      expect(runtime.dispatchEnvelopeCalls, 2);
      expect(runtime.lastEnvelope?['kind'], 'list_skills');
      expect(runtime.lastConversationId, model.selectedConversation!.id);
      expect(model.skillsLoading, true);
      expect(model.skillsLoaded, false);
      expect(model.skillCatalog, isEmpty);

      await model.handleAgentResultEvent({
        'request_id': 'deferred-skill-request',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': 'Loaded skills',
        'token': '',
        'detail_json':
            '{"kind":"skills","items":[{"id":"skill-remote-1","title":"Remote Skill"}]}',
      });

      expect(model.skillsLoading, false);
      expect(model.skillsLoaded, true);
      expect(model.skillCatalog, hasLength(1));
      expect(model.skillCatalog.first['id'], 'skill-remote-1');
    });

    test('deferred sessions load waits for structured result to finish catalog',
        () async {
      final runtime = _DeferredSkillsRuntime();
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: _MemoryAgentDashboardStorage(),
      );

      await model.ensureLoaded();

      expect(runtime.loadSessionsCalls, 1);
      expect(runtime.dispatchEnvelopeCalls, 2);
      expect(runtime.lastEnvelope?['kind'], 'list_skills');
      expect(model.sessionsLoaded, false);
      expect(model.sessionSummaries, isEmpty);

      await model.handleAgentResultEvent({
        'request_id': 'deferred-sessions-request',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': 'Loaded sessions',
        'token': '',
        'detail_json':
            '{"kind":"sessions","items":[{"id":"session-remote-1","title":"Remote Session"}]}',
      });

      expect(model.sessionsLoaded, true);
      expect(model.sessionSummaries, hasLength(1));
      expect(model.sessionSummaries.first['id'], 'session-remote-1');
    });

    test('deferred session catalog reload dispatches another session request',
        () async {
      final runtime = _DeferredSkillsRuntime();
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: _MemoryAgentDashboardStorage(),
      );

      await model.ensureLoaded();
      final conversationId = model.selectedConversation!.id;

      expect(runtime.loadSessionsCalls, 1);
      expect(runtime.dispatchEnvelopeCalls, 2);
      expect(model.sessionsLoaded, false);

      await model.reloadSessionCatalog();

      expect(runtime.loadSessionsCalls, 2);
      expect(runtime.dispatchEnvelopeCalls, 3);
      expect(runtime.lastEnvelope?['kind'], 'list_sessions');
      expect(runtime.lastEnvelope?['conversationId'], conversationId);
      expect(model.sessionsLoaded, false);

      await model.handleAgentResultEvent({
        'request_id': 'deferred-sessions-request-2',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': 'Loaded sessions',
        'token': '',
        'detail_json':
            '{"kind":"sessions","items":[{"id":"session-reloaded-1","title":"Reloaded Session"}]}',
      });

      expect(model.sessionsLoaded, true);
      expect(model.sessionSummaries, hasLength(1));
      expect(model.sessionSummaries.first['id'], 'session-reloaded-1');
    });

    test('deferred session catalog retries while waiting for structured result',
        () async {
      final runtime = _DeferredSkillsRuntime();
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: _MemoryAgentDashboardStorage(),
      );
      addTearDown(model.dispose);

      await model.ensureLoaded();
      expect(runtime.loadSessionsCalls, 1);

      await Future<void>.delayed(const Duration(milliseconds: 2200));

      expect(runtime.loadSessionsCalls, greaterThanOrEqualTo(2));
      expect(runtime.lastEnvelope?['kind'], 'list_sessions');
      expect(model.sessionsLoaded, false);

      await model.handleAgentResultEvent({
        'request_id': 'deferred-sessions-retry',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': 'Loaded sessions',
        'token': '',
        'detail_json':
            '{"kind":"sessions","items":[{"id":"session-retry-1","title":"Retried Session"}]}',
      });

      final callsAfterLoaded = runtime.loadSessionsCalls;
      await Future<void>.delayed(const Duration(milliseconds: 2200));

      expect(model.sessionsLoaded, true);
      expect(runtime.loadSessionsCalls, callsAfterLoaded);
      expect(model.sessionSummaries.first['id'], 'session-retry-1');
    });

    test(
        'detail conversation id still routes event to the referenced conversation',
        () async {
      final model = await createModel();
      final originalConversationId = model.selectedConversation!.id;
      model.createConversation();
      final routedConversationId = model.selectedConversation!.id;
      expect(routedConversationId, isNot(originalConversationId));

      await model.handleAgentResultEvent({
        'request_id': '',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': 'Routed completion',
        'token': '',
        'detail_json':
            '{"conversationId":"$originalConversationId","kind":"codexResult","error":""}',
      });

      expect(model.timelineForConversation(originalConversationId), isNotEmpty);
      expect(
        model.timelineForConversation(originalConversationId).last['stage'],
        'done',
      );
      expect(model.timelineForConversation(routedConversationId), isEmpty);
    });

    test('detail session page kind still appends older messages', () async {
      final model = await createModel();

      await model.handleAgentResultEvent({
        'request_id': '',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': '',
        'token': '',
        'detail_json':
            '{"kind":"session_detail","item":{"id":"session-page-kind-1","messages":[{"role":"assistant","text":"newer","timestamp":"2024-01-02T00:00:00Z"}],"timeline":[],"raw_events":[]}}',
      });

      await model.handleAgentResultEvent({
        'request_id': '',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': '',
        'token': '',
        'detail_json':
            '{"kind":"session_page","item":{"id":"session-page-kind-1","messages":[{"role":"assistant","text":"older","timestamp":"2024-01-01T00:00:00Z"}],"timeline":[],"raw_events":[]}}',
      });

      expect(model.selectedConversation!.sessionRef, 'session-page-kind-1');
      expect(
        model.selectedConversation!.messages.map((message) => message.text),
        ['newer', 'older'],
      );
    });

    test('session detail/page kind helper still keeps page append path',
        () async {
      final model = await createModel();
      final conversationId = model.selectedConversation!.id;

      await model.handleAgentResultEvent({
        'request_id': '',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': '',
        'token': '',
        'detail_json':
            '{"kind":"session_detail","item":{"id":"session-page-helper-1","messages":[{"role":"assistant","text":"latest","timestamp":"2024-01-02T00:00:00Z"}],"timeline":[],"raw_events":[]}}',
      });

      await model.handleAgentResultEvent({
        'request_id': '',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': '',
        'token': '',
        'detail_json':
            '{"kind":"session_page","item":{"id":"session-page-helper-1","messages":[{"role":"assistant","text":"older helper","timestamp":"2024-01-01T00:00:00Z"}],"timeline":[],"raw_events":[]}}',
      });

      expect(model.selectedConversation!.sessionRef, 'session-page-helper-1');
      expect(model.timelineForConversation(conversationId), isEmpty);
      expect(model.rawEventsForConversation(conversationId), isEmpty);
      expect(
        model.selectedConversation!.messages.map((message) => message.text),
        ['latest', 'older helper'],
      );
    });

    test('detail task snapshot item still stores timeline and raw events',
        () async {
      final model = await createModel();
      final conversationId = model.selectedConversation!.id;

      await model.handleAgentResultEvent({
        'request_id': '',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'running',
        'text': '',
        'token': '',
        'detail_json':
            '{"kind":"task_snapshot","item":{"timeline":[{"stage":"running","summary":"item-path"}],"raw_events":[{"kind":"item-event","value":2}]}}',
      });

      expect(model.timelineForConversation(conversationId), hasLength(1));
      expect(model.rawEventsForConversation(conversationId), hasLength(1));
      expect(
        model.timelineForConversation(conversationId).first['summary'],
        'item-path',
      );
      expect(
        model.rawEventsForConversation(conversationId).first['kind'],
        'item-event',
      );
    });

    test('detail sessions items still refreshes session summaries', () async {
      final model = await createModel();

      await model.handleAgentResultEvent({
        'request_id': '',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': '',
        'token': '',
        'detail_json':
            '{"kind":"sessions","items":[{"id":"session-list-1","title":"Session 1"},{"id":"session-list-2","title":"Session 2"}]}',
      });

      expect(model.sessionsLoaded, true);
      expect(model.sessionSummaries, hasLength(2));
      expect(model.sessionSummaries.first['id'], 'session-list-1');
      expect(model.sessionSummaries.last['id'], 'session-list-2');
    });

    test(
        'structured detail catalog or session kind still clears mapped request and notifies once',
        () async {
      final model = await createModel();
      var notifications = 0;
      model.addListener(() {
        notifications += 1;
      });
      final originalConversationId = model.selectedConversation!.id;

      await model.handleAgentResultEvent({
        'request_id': 'aaaaaaaa-bbbb-cccc-dddd-aaaaaaaaaaaa',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': '',
        'token': '',
        'detail_json':
            '{"kind":"session_detail","item":{"id":"structured-session-kind-1","messages":[],"timeline":[],"raw_events":[]}}',
      });

      model.createConversation();
      final newConversationId = model.selectedConversation!.id;

      await model.handleAgentResultEvent({
        'request_id': 'aaaaaaaa-bbbb-cccc-dddd-aaaaaaaaaaaa',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': 'fallback after cleanup',
        'token': '',
        'detail_json': '',
      });

      expect(notifications, 3);
      expect(model.timelineForConversation(originalConversationId), isEmpty);
      expect(model.timelineForConversation(newConversationId), isEmpty);
      expect(
        model.selectedConversation!.messages.last.text,
        contains('fallback after cleanup'),
      );
    });

    test(
        'task snapshot done suppress helper still keeps detail-only refresh path',
        () async {
      final runtime = _DoneSessionRefreshRuntime();
      final storage = _MemoryAgentDashboardStorage();
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: storage,
      );
      await model.ensureLoaded();
      final writesBeforeEvent = storage.writeCount;

      await model.handleAgentResultEvent({
        'request_id': '12121212-3434-5656-7878-121212121212',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': 'Snapshot done',
        'token': '',
        'detail_json':
            '{"kind":"task_snapshot","item":{"timeline":[{"stage":"running","summary":"step"}],"raw_events":[{"kind":"evt","value":1}]},"detail":{"sessionId":"session-snapshot-suppress-1"}}',
      });
      await Future<void>.delayed(Duration.zero);

      expect(runtime.loadSessionDetailCalls, 1);
      expect(storage.writeCount, writesBeforeEvent + 1);
      expect(
        model.selectedConversation!.sessionRef,
        'session-snapshot-suppress-1',
      );
      expect(model.selectedConversation!.messages, isNotEmpty);
    });

    test(
        'codex result running bind helper still keeps in-place session binding path',
        () async {
      final model = await createModel();
      final conversationId = model.selectedConversation!.id;

      await model.handleAgentResultEvent({
        'request_id': '56565656-7878-9090-1212-565656565656',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'running',
        'text': 'Codex result running',
        'token': '',
        'detail_json':
            '{"kind":"codexResult","sessionId":"codex-running-bind-1","error":""}',
      });

      expect(model.selectedConversation!.sessionRef, 'codex-running-bind-1');
      expect(model.selectedConversation!.threadMode, 'continue');
      expect(
        model.statusForConversation(conversationId),
        AgentConversationStatus.running,
      );
      expect(model.selectedConversation!.messages, isNotEmpty);
      expect(
        model.selectedConversation!.messages.last.text,
        contains('Codex result running'),
      );
    });

    test('task snapshot still binds conversation session once', () async {
      final model = await createModel();
      final conversationId = model.selectedConversation!.id;
      var notifications = 0;
      model.addListener(() {
        notifications += 1;
      });

      await model.handleAgentResultEvent({
        'request_id': '88888888-8888-8888-8888-888888888888',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'running',
        'text': 'Snapshot',
        'token': '',
        'detail_json':
            '{"kind":"task_snapshot","item":{"timeline":[],"raw_events":[]},"detail":{"sessionId":"session-snapshot-1"}}',
      });

      expect(model.selectedConversation!.sessionRef, 'session-snapshot-1');
      expect(model.selectedConversation!.threadMode, 'continue');
      expect(model.statusForConversation(conversationId),
          AgentConversationStatus.running);
      expect(notifications, greaterThanOrEqualTo(1));
    });

    test(
        'task snapshot running still binds session with snake_case id in detail',
        () async {
      final model = await createModel();
      final conversationId = model.selectedConversation!.id;

      await model.handleAgentResultEvent({
        'request_id': '88888888-7777-6666-5555-888888888888',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'running',
        'text': 'Snapshot',
        'token': '',
        'detail_json':
            '{"kind":"task_snapshot","item":{"timeline":[],"raw_events":[]},"detail":{"session_id":"session-snapshot-running-snake-1"}}',
      });

      expect(
        model.selectedConversation!.sessionRef,
        'session-snapshot-running-snake-1',
      );
      expect(model.selectedConversation!.threadMode, 'continue');
      expect(
        model.statusForConversation(conversationId),
        AgentConversationStatus.running,
      );
    });

    test(
        'task snapshot without session binding still stores timeline and raw events',
        () async {
      final model = await createModel();
      final conversationId = model.selectedConversation!.id;

      await model.handleAgentResultEvent({
        'request_id': '88888888-9999-aaaa-bbbb-888888888888',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'running',
        'text': 'Snapshot',
        'token': '',
        'detail_json':
            '{"kind":"task_snapshot","item":{"timeline":[{"stage":"running","summary":"step"}],"raw_events":[{"kind":"event","value":1}]}}',
      });

      expect(model.timelineForConversation(conversationId), hasLength(1));
      expect(model.rawEventsForConversation(conversationId), hasLength(1));
      expect(
        model.timelineForConversation(conversationId).first['stage'],
        'running',
      );
      expect(
        model.rawEventsForConversation(conversationId).first['kind'],
        'event',
      );
    });

    test(
        'session rebinding still clears messages and only schedules one storage write',
        () async {
      final storage = _MemoryAgentDashboardStorage();
      final model = AgentDashboardModel.fromRuntime(
        _TrackingRuntime(hasActiveTracking: false),
        storage: storage,
      );
      await model.ensureLoaded();
      final conversationId = model.selectedConversation!.id;

      await model.handleAgentResultEvent({
        'request_id': '99999999-9999-9999-9999-999999999999',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': 'Prime one message',
        'token': '',
        'detail_json': '',
      });

      final writesBeforeReset = storage.writeCount;
      expect(model.selectedConversation!.messages, isNotEmpty);

      model.updateConversationSettings(
        conversationId: conversationId,
        threadMode: 'continue',
        sessionRef: 'session-reset-1',
      );

      await Future<void>.delayed(Duration.zero);

      expect(model.selectedConversation!.messages, isEmpty);
      expect(model.selectedConversation!.sessionRef, 'session-reset-1');
      expect(storage.writeCount, writesBeforeReset + 1);
    });

    test(
        'clearing session restore still resets conversation state with one storage write',
        () async {
      final storage = _MemoryAgentDashboardStorage();
      final model = AgentDashboardModel.fromRuntime(
        _TrackingRuntime(hasActiveTracking: false),
        storage: storage,
      );
      await model.ensureLoaded();
      final conversationId = model.selectedConversation!.id;

      await model.handleAgentResultEvent({
        'request_id': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': 'Prime one message',
        'token': '',
        'detail_json': '',
      });

      model.updateConversationSettings(
        conversationId: conversationId,
        threadMode: 'continue',
        sessionRef: 'session-to-clear',
      );
      await Future<void>.delayed(Duration.zero);

      final writesBeforeClear = storage.writeCount;
      expect(model.selectedConversation!.messages, isEmpty);
      expect(model.selectedConversation!.sessionRef, 'session-to-clear');

      await model.restoreSessionIntoConversation(
        conversationId: conversationId,
        sessionId: '',
      );
      await Future<void>.delayed(Duration.zero);

      expect(model.selectedConversation!.messages, isEmpty);
      expect(model.selectedConversation!.sessionRef, isEmpty);
      expect(model.selectedConversation!.threadMode, 'new');
      expect(storage.writeCount, writesBeforeClear + 1);
    });

    test('clearing an already blank conversation skips storage write',
        () async {
      final storage = _MemoryAgentDashboardStorage();
      final model = AgentDashboardModel.fromRuntime(
        _TrackingRuntime(hasActiveTracking: false),
        storage: storage,
      );
      await model.ensureLoaded();
      final conversationId = model.selectedConversation!.id;
      final writesBeforeClear = storage.writeCount;
      final updatedAtBeforeClear = model.selectedConversation!.updatedAt;

      await model.restoreSessionIntoConversation(
        conversationId: conversationId,
        sessionId: '',
      );
      await Future<void>.delayed(Duration.zero);

      expect(model.selectedConversation!.messages, isEmpty);
      expect(model.selectedConversation!.sessionRef, isEmpty);
      expect(model.selectedConversation!.threadMode, 'new');
      expect(model.selectedConversation!.updatedAt, updatedAtBeforeClear);
      expect(storage.writeCount, writesBeforeClear);
    });

    test(
        'clearing session restore still preserves blank timeline state with one write',
        () async {
      final storage = _MemoryAgentDashboardStorage();
      final model = AgentDashboardModel.fromRuntime(
        _TrackingRuntime(hasActiveTracking: false),
        storage: storage,
      );
      await model.ensureLoaded();
      final conversationId = model.selectedConversation!.id;

      model.updateConversationSettings(
        conversationId: conversationId,
        threadMode: 'continue',
        sessionRef: 'session-to-clear-2',
      );
      await Future<void>.delayed(Duration.zero);

      final writesBeforeClear = storage.writeCount;

      await model.restoreSessionIntoConversation(
        conversationId: conversationId,
        sessionId: '',
      );
      await Future<void>.delayed(Duration.zero);

      expect(model.selectedConversation!.sessionRef, isEmpty);
      expect(model.selectedConversation!.threadMode, 'new');
      expect(model.selectedConversation!.messages, isEmpty);
      expect(storage.writeCount, writesBeforeClear + 1);
    });

    test(
        'session restore loads first page immediately before background prefetch',
        () async {
      final runtime = _SessionRestoreTrackingRuntime();
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();
      final conversationId = model.selectedConversation!.id;

      await model.restoreSessionIntoConversation(
        conversationId: conversationId,
        sessionId: 'session-once-1',
      );
      await Future<void>.delayed(Duration.zero);

      expect(runtime.loadSessionDetailCalls, 1);
      expect(model.selectedConversation!.sessionRef, 'session-once-1');
      expect(model.selectedConversation!.messages, isNotEmpty);
    });

    test('session restore cleans assistant-only Codex metadata', () async {
      final runtime = _MessageCleaningSessionRuntime(
        role: 'assistant',
        text: 'Visible session answer\n\n'
            '<oai-mem-citation>\n'
            '<citation_entries>\n'
            'MEMORY.md:1-2|note=[internal]\n'
            '</citation_entries>\n'
            '<rollout_ids>\n'
            '019e815c-78ce-7553-a264-6310ed2c75e9\n'
            '</rollout_ids>\n'
            '</oai-mem-citation>',
      );
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();
      final conversationId = model.selectedConversation!.id;

      await model.restoreSessionIntoConversation(
        conversationId: conversationId,
        sessionId: 'session-clean-assistant-1',
      );
      await Future<void>.delayed(Duration.zero);

      expect(runtime.loadSessionDetailCalls, 1);
      expect(model.selectedConversation!.messages.single.text,
          'Visible session answer');
    });

    test('session restore cleans trailing metadata after transcript fence',
        () async {
      final runtime = _MessageCleaningSessionRuntime(
        role: 'assistant',
        text: 'Visible session answer\n'
            '```text\n'
            '- focused validation passed\n\n'
            '<oai-mem-citation>\n'
            '<citation_entries>\n'
            'MEMORY.md:55-62|note=[internal]\n'
            '</citation_entries>\n'
            '<rollout_ids>\n'
            '019e815c-78ce-7553-a264-6310ed2c75e9\n'
            '</rollout_ids>\n'
            '</oai-mem-citation>',
      );
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();
      final conversationId = model.selectedConversation!.id;

      await model.restoreSessionIntoConversation(
        conversationId: conversationId,
        sessionId: 'session-clean-transcript-fence-1',
      );
      await Future<void>.delayed(Duration.zero);

      expect(
          model.selectedConversation!.messages.single.text,
          'Visible session answer\n'
          '```text\n'
          '- focused validation passed');
      expect(model.selectedConversation!.messages.single.text,
          isNot(contains('<oai-mem-citation>')));
    });

    test('session restore keeps user-authored metadata-looking text', () async {
      const userText = 'Please explain this tag literally:\n'
          '<oai-mem-citation>\n'
          '</oai-mem-citation>';
      final runtime = _MessageCleaningSessionRuntime(
        role: 'user',
        text: userText,
      );
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();
      final conversationId = model.selectedConversation!.id;

      await model.restoreSessionIntoConversation(
        conversationId: conversationId,
        sessionId: 'session-keep-user-text-1',
      );
      await Future<void>.delayed(Duration.zero);

      expect(runtime.loadSessionDetailCalls, 1);
      expect(model.selectedConversation!.messages.single.text, userText);
      expect(model.selectedConversation!.messages.single.user.id,
          isNot(model.assistant.id));
    });

    test('session restore shows dashboard wrapped prompt as user request',
        () async {
      const wrappedPrompt = 'Runtime info: rustdesk-dashboard\n\n'
          'Current request:\n'
          '当前项目目录';
      final runtime = _MessageCleaningSessionRuntime(
        role: 'user',
        text: wrappedPrompt,
      );
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();
      final conversationId = model.selectedConversation!.id;

      await model.restoreSessionIntoConversation(
        conversationId: conversationId,
        sessionId: 'session-dashboard-wrapped-prompt-1',
      );
      await Future<void>.delayed(Duration.zero);

      expect(runtime.loadSessionDetailCalls, 1);
      expect(model.selectedConversation!.messages.single.text, '当前项目目录');
      expect(model.selectedConversation!.messages.single.user.id,
          isNot(model.assistant.id));
    });

    test('project filter also filters session summaries', () async {
      final model = AgentDashboardModel.fromRuntime(
        _ProjectSessionRuntime(),
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();

      expect(model.sessionSummaries, hasLength(2));
      model.setProjectFilter('BlueprintHarness');

      expect(model.filteredSessionSummaries, hasLength(1));
      expect(
        model.filteredSessionSummaries.single['id'],
        'session-blueprint-1',
      );
      expect(
        model.sessionProjectId(model.filteredSessionSummaries.single),
        'BlueprintHarness',
      );
    });

    test(
        'session summaries prefer path-derived project over fallback rustdesk id',
        () async {
      final model = AgentDashboardModel.fromRuntime(
        _ConflictingSessionSummaryProjectRuntime(),
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();

      expect(model.sessionSummaries, hasLength(1));
      expect(
        model.sessionProjectId(model.sessionSummaries.single),
        'BlueprintHarness',
      );

      model.setProjectFilter('BlueprintHarness');
      expect(model.filteredSessionSummaries, hasLength(1));
      expect(model.availableProjects, contains('BlueprintHarness'));
    });

    test('restoring a session updates conversation project from summary',
        () async {
      final model = AgentDashboardModel.fromRuntime(
        _ProjectSessionRuntime(),
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();
      final conversationId = model.selectedConversation!.id;

      await model.restoreSessionIntoConversation(
        conversationId: conversationId,
        sessionId: 'session-blueprint-1',
      );
      await Future<void>.delayed(Duration.zero);

      expect(model.selectedConversation!.sessionRef, 'session-blueprint-1');
      expect(model.selectedConversation!.projectId, 'BlueprintHarness');
      expect(model.selectedConversation!.messages.first.text,
          'Restored BlueprintHarness session');
    });

    test(
        'available projects include session-derived directories outside configured list',
        () async {
      final model = AgentDashboardModel.fromRuntime(
        _SessionPathOnlyProjectRuntime(),
        storage: _MemoryAgentDashboardStorage(),
      );

      await model.ensureLoaded();

      expect(model.availableProjects, contains('rustdesk'));
      expect(model.availableProjects, contains('BlueprintHarness'));
      expect(model.sessionProjectId(model.sessionSummaries.last),
          'BlueprintHarness');
    });

    test(
        'ensureLoaded reconciles seeded continue conversation project from session metadata',
        () async {
      final runtime = _SessionPathOnlyProjectRuntime();
      final storage = _MemoryAgentDashboardStorage();
      final seededConversation = AgentConversation(
        id: 'seed-blueprint-conversation-1',
        title: 'Seeded Blueprint conversation',
        projectId: AgentDashboardModel.defaultProjectId,
        threadMode: 'continue',
        profile: '',
        sessionRef: 'session-blueprint-path-1',
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
      storage.seed(
        runtime.peerId,
        'agent_dashboard_conversations.json',
        '[${jsonEncode(seededConversation.toJson())}]',
      );
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: storage,
      );

      await model.ensureLoaded();
      expect(model.selectedConversation!.projectId, 'BlueprintHarness');

      await Future<void>.delayed(Duration.zero);

      expect(runtime.loadSessionDetailCalls, 1);
      expect(model.selectedConversation!.projectId, 'BlueprintHarness');
      expect(model.selectedConversation!.messages, isNotEmpty);
      expect(model.availableProjects, contains('BlueprintHarness'));
    });

    test(
        'sendCurrentPrompt preserves restored session route when project is not preconfigured',
        () async {
      final runtime = _SessionPathOnlyProjectDispatchRuntime();
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();
      final conversationId = model.selectedConversation!.id;

      await model.restoreSessionIntoConversation(
        conversationId: conversationId,
        sessionId: 'session-blueprint-path-1',
      );
      await Future<void>.delayed(Duration.zero);

      expect(model.selectedConversation!.projectId, 'BlueprintHarness');
      expect(model.selectedConversation!.threadMode, 'continue');
      expect(
          model.selectedConversation!.sessionRef, 'session-blueprint-path-1');

      model.textController.text = 'Continue through restored session project';
      await model.sendCurrentPrompt();
      await Future<void>.delayed(Duration.zero);

      expect(runtime.dispatchEnvelopeCalls, 1);
      final route = runtime.lastEnvelope!['route'] as Map<String, dynamic>;
      expect(route['projectId'], 'BlueprintHarness');
      expect(route['threadMode'], 'continue');
      expect(route['activeThreadId'], 'session-blueprint-path-1');
      expect(route['codexThreadId'], 'session-blueprint-path-1');
      expect(runtime.lastEnvelope!['context']['includeHistory'], false);
    });

    test(
        'session picker opens target session instead of reusing active rustdesk conversation',
        () async {
      final runtime = _SessionPathOnlyProjectDispatchRuntime();
      final storage = _MemoryAgentDashboardStorage();
      final now = DateTime.now();
      final rustdeskConversation = AgentConversation(
        id: 'conversation-rustdesk-active',
        title: 'Active RustDesk conversation',
        projectId: 'rustdesk',
        threadMode: 'continue',
        profile: '',
        sessionRef: 'session-rustdesk-1',
        selectedSkillIds: const [],
        pinned: false,
        archived: false,
        draft: '',
        includeConversationHistory: true,
        includeTerminalContext: true,
        createdAt: now,
        updatedAt: now,
        lastReadAt: now,
        messages: const [],
      );
      storage.seed(
        runtime.peerId,
        'agent_dashboard_conversations.json',
        '[${jsonEncode(rustdeskConversation.toJson())}]',
      );
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: storage,
      );
      await model.ensureLoaded();

      expect(model.selectedConversation!.id, 'conversation-rustdesk-active');
      expect(model.selectedConversation!.projectId, 'rustdesk');

      await model
          .restoreSessionAsCurrentConversation('session-blueprint-path-1');
      await Future<void>.delayed(Duration.zero);

      expect(model.selectedConversation!.id,
          isNot('conversation-rustdesk-active'));
      expect(model.selectedConversation!.projectId, 'BlueprintHarness');
      expect(
          model.selectedConversation!.sessionRef, 'session-blueprint-path-1');

      model.textController.text = 'Route this to BlueprintHarness';
      await model.sendCurrentPrompt();
      await Future<void>.delayed(Duration.zero);

      expect(runtime.dispatchEnvelopeCalls, 1);
      final route = runtime.lastEnvelope!['route'] as Map<String, dynamic>;
      expect(route['projectId'], 'BlueprintHarness');
      expect(route['threadMode'], 'continue');
      expect(route['activeThreadId'], 'session-blueprint-path-1');
      expect(route['codexThreadId'], 'session-blueprint-path-1');
      expect(runtime.lastEnvelope!['context']['includeHistory'], false);
    });

    test(
        'sendCurrentPrompt preserves continue route when project differs only by case',
        () async {
      final runtime = _DispatchTrackingRuntime();
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();
      final conversationId = model.selectedConversation!.id;

      model.updateConversationSettings(
        conversationId: conversationId,
        projectId: 'rustDesk',
        threadMode: 'continue',
        sessionRef: 'case-only-session-1',
      );
      await Future<void>.delayed(Duration.zero);

      expect(model.selectedConversation!.projectId, 'rustdesk');

      model.textController.text = 'Continue same project despite casing';
      await model.sendCurrentPrompt();
      await Future<void>.delayed(Duration.zero);

      expect(runtime.dispatchEnvelopeCalls, 1);
      final route = runtime.lastEnvelope!['route'] as Map<String, dynamic>;
      expect(runtime.lastEnvelope!['conversationId'], conversationId);
      expect(route['projectId'], 'rustdesk');
      expect(route['threadMode'], 'continue');
      expect(route['activeThreadId'], 'case-only-session-1');
      expect(route['codexThreadId'], 'case-only-session-1');
    });

    test(
        'new conversation from continue template still dispatches as new when session ref is blank',
        () async {
      final runtime = _DispatchTrackingRuntime();
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();
      final conversationId = model.selectedConversation!.id;

      model.updateConversationSettings(
        conversationId: conversationId,
        threadMode: 'continue',
        sessionRef: 'seed-session-route-1',
      );
      await Future<void>.delayed(Duration.zero);

      final created = model.createConversation();
      expect(created.threadMode, 'new');
      expect(created.sessionRef, isEmpty);

      model.textController.text = 'Send from blank new conversation';
      await model.sendCurrentPrompt();
      await Future<void>.delayed(Duration.zero);

      expect(runtime.dispatchEnvelopeCalls, 1);
      final route = runtime.lastEnvelope!['route'] as Map<String, dynamic>;
      expect(route['projectId'], AgentDashboardModel.defaultProjectId);
      expect(route['threadMode'], 'new');
      expect(route['activeThreadId'], isNull);
      expect(route['codexThreadId'], isNull);
    });

    test(
        'session detail metadata rewrites project when bound session is missing from summaries',
        () async {
      final runtime = _SessionDetailPathOnlyRuntime();
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: _MemoryAgentDashboardStorage(),
      );

      await model.ensureLoaded();
      final conversationId = model.selectedConversation!.id;

      model.updateConversationSettings(
        conversationId: conversationId,
        threadMode: 'continue',
        sessionRef: 'session-detail-path-1',
      );
      await Future<void>.delayed(Duration.zero);

      expect(runtime.loadSessionDetailCalls, 1);
      expect(model.selectedConversation!.sessionRef, 'session-detail-path-1');
      expect(model.selectedConversation!.projectId, 'BlueprintHarness');
      expect(model.selectedConversation!.messages.first.text,
          'Detail-only BlueprintHarness session');
      expect(model.availableProjects, contains('BlueprintHarness'));
    });

    test(
        'paged session restore shows latest page immediately then prefetches one older page in background',
        () async {
      final runtime = _PagedSessionRestoreRuntime();
      final storage = _MemoryAgentDashboardStorage();
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: storage,
      );
      await model.ensureLoaded();
      final conversationId = model.selectedConversation!.id;
      final writesBeforeRestore = storage.writeCount;

      await model.restoreSessionIntoConversation(
        conversationId: conversationId,
        sessionId: 'session-paged-1',
      );
      await Future<void>.delayed(Duration.zero);

      expect(runtime.loadSessionDetailCalls, 1);
      expect(model.selectedConversation!.sessionRef, 'session-paged-1');
      expect(model.selectedConversation!.messages.length, 1);
      expect(model.selectedConversation!.messages.single.text, 'Newest page');
      expect(model.canLoadMoreSessionHistory(conversationId), isTrue);
      expect(model.visibleConversations.first.id, conversationId);

      await Future<void>.delayed(const Duration(milliseconds: 260));

      expect(runtime.loadSessionDetailCalls, 2);
      expect(storage.writeCount, writesBeforeRestore + 2);
      expect(model.selectedConversation!.messages.length, 2);
      expect(model.selectedConversation!.messages.first.text, 'Newest page');
      expect(model.selectedConversation!.messages.last.text, 'Older page');
      expect(model.canLoadMoreSessionHistory(conversationId), isFalse);
    });

    test(
        'session restore still stores empty timeline and raw events from detail',
        () async {
      final runtime = _SessionRestoreTrackingRuntime();
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();
      final conversationId = model.selectedConversation!.id;

      await model.restoreSessionIntoConversation(
        conversationId: conversationId,
        sessionId: 'session-store-detail-1',
      );
      await Future<void>.delayed(Duration.zero);

      expect(model.timelineForConversation(conversationId), isEmpty);
      expect(model.rawEventsForConversation(conversationId), isEmpty);
    });

    test('task snapshot done refreshes session detail once', () async {
      final runtime = _DoneSessionRefreshRuntime();
      final storage = _MemoryAgentDashboardStorage();
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: storage,
      );
      await model.ensureLoaded();
      final writesBeforeEvent = storage.writeCount;

      await model.handleAgentResultEvent({
        'request_id': 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': 'Snapshot done',
        'token': '',
        'detail_json':
            '{"kind":"task_snapshot","item":{"timeline":[],"raw_events":[]},"detail":{"sessionId":"session-snapshot-done-1"}}',
      });
      await Future<void>.delayed(Duration.zero);

      expect(runtime.loadSessionDetailCalls, 1);
      expect(storage.writeCount, writesBeforeEvent + 1);
      expect(model.selectedConversation!.sessionRef, 'session-snapshot-done-1');
      expect(model.selectedConversation!.messages, isNotEmpty);
    });

    test(
        'task snapshot done still refreshes session detail with snake_case session id',
        () async {
      final runtime = _DoneSessionRefreshRuntime();
      final storage = _MemoryAgentDashboardStorage();
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: storage,
      );
      await model.ensureLoaded();
      final writesBeforeEvent = storage.writeCount;

      await model.handleAgentResultEvent({
        'request_id': 'bbbbbbbb-cccc-dddd-eeee-bbbbbbbbbbbb',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': 'Snapshot done',
        'token': '',
        'detail_json':
            '{"kind":"task_snapshot","item":{"timeline":[],"raw_events":[]},"detail":{"session_id":"session-snapshot-done-snake-1"}}',
      });
      await Future<void>.delayed(Duration.zero);

      expect(runtime.loadSessionDetailCalls, 1);
      expect(storage.writeCount, writesBeforeEvent + 1);
      expect(
        model.selectedConversation!.sessionRef,
        'session-snapshot-done-snake-1',
      );
      expect(model.selectedConversation!.messages, isNotEmpty);
    });

    test('task snapshot done still notifies listeners twice', () async {
      final runtime = _DoneSessionRefreshRuntime();
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();
      var notifications = 0;
      model.addListener(() {
        notifications += 1;
      });

      await model.handleAgentResultEvent({
        'request_id': 'bbbbbbbb-1111-2222-3333-bbbbbbbbbbbb',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': 'Snapshot done',
        'token': '',
        'detail_json':
            '{"kind":"task_snapshot","item":{"timeline":[],"raw_events":[]},"detail":{"sessionId":"session-snapshot-done-notify-1"}}',
      });
      await Future<void>.delayed(Duration.zero);

      expect(notifications, 2);
    });

    test(
        'task snapshot done without session id still appends final message to conversation',
        () async {
      final storage = _MemoryAgentDashboardStorage();
      final model = AgentDashboardModel.fromRuntime(
        _TrackingRuntime(hasActiveTracking: false),
        storage: storage,
      );
      await model.ensureLoaded();
      final writesBeforeEvent = storage.writeCount;

      await model.handleAgentResultEvent({
        'request_id': 'bbbbbbbb-9999-2222-3333-bbbbbbbbbbbb',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': 'Final text without session binding',
        'token': '',
        'detail_json':
            '{"kind":"task_snapshot","item":{"timeline":[],"raw_events":[]},"detail":{}}',
      });

      expect(
        model.selectedConversation!.messages.first.text,
        contains('Final text without session binding'),
      );
      expect(model.selectedConversation!.sessionRef, isEmpty);
      expect(storage.writeCount, writesBeforeEvent + 1);
    });

    test(
        'task snapshot done request cleanup still routes later updates to selection',
        () async {
      final runtime = _DoneSessionRefreshRuntime();
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();
      final originalConversationId = model.selectedConversation!.id;

      await model.handleAgentResultEvent({
        'request_id': 'bcbcbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': 'Snapshot done',
        'token': '',
        'detail_json':
            '{"kind":"task_snapshot","item":{"timeline":[],"raw_events":[]},"detail":{"sessionId":"session-snapshot-done-2"}}',
      });
      await Future<void>.delayed(Duration.zero);

      model.createConversation();
      final nextSelectedConversationId = model.selectedConversation!.id;
      expect(nextSelectedConversationId, isNot(originalConversationId));

      await model.handleAgentResultEvent({
        'request_id': 'bcbcbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': 'Plain completion after cleanup',
        'token': '',
        'detail_json': '',
      });

      expect(
        model.selectedConversation!.id,
        nextSelectedConversationId,
      );
      expect(
        model.selectedConversation!.messages.first.text,
        contains('Plain completion after cleanup'),
      );
    });

    test(
        'task snapshot failed cleanup helper still routes later updates to selection',
        () async {
      final model = await createModel();
      final originalConversationId = model.selectedConversation!.id;

      await model.handleAgentResultEvent({
        'request_id': 'cdcdcccc-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'failed',
        'text': 'Snapshot failed',
        'token': '',
        'detail_json':
            '{"kind":"task_snapshot","item":{"timeline":[],"raw_events":[]},"detail":{"sessionId":"session-snapshot-failed-1"}}',
      });

      model.createConversation();
      final nextSelectedConversationId = model.selectedConversation!.id;
      expect(nextSelectedConversationId, isNot(originalConversationId));

      await model.handleAgentResultEvent({
        'request_id': 'cdcdcccc-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': 'Plain completion after failed cleanup',
        'token': '',
        'detail_json': '',
      });

      expect(model.selectedConversation!.id, nextSelectedConversationId);
      expect(
        model.selectedConversation!.messages.first.text,
        contains('Plain completion after failed cleanup'),
      );
    });

    test('codex result done refreshes session detail once', () async {
      final runtime = _DoneSessionRefreshRuntime();
      final storage = _MemoryAgentDashboardStorage();
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: storage,
      );
      await model.ensureLoaded();
      final writesBeforeEvent = storage.writeCount;

      await model.handleAgentResultEvent({
        'request_id': 'cccccccc-cccc-cccc-cccc-cccccccccccc',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': 'Codex result done',
        'token': '',
        'detail_json':
            '{"kind":"codexResult","sessionId":"session-codex-done-1"}',
      });
      await Future<void>.delayed(Duration.zero);

      expect(runtime.loadSessionDetailCalls, 1);
      expect(storage.writeCount, writesBeforeEvent + 1);
      expect(model.selectedConversation!.sessionRef, 'session-codex-done-1');
      expect(model.selectedConversation!.messages, isNotEmpty);
    });

    test(
        'codex result done still keeps visible final text when session detail lags behind',
        () async {
      final runtime = _LaggingDoneSessionRefreshRuntime();
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();

      await model.handleAgentResultEvent({
        'request_id': 'cccccccc-lag0-lag0-lag0-cccccccccccc',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': 'CONT_OK',
        'token': '',
        'detail_json':
            '{"kind":"codexResult","sessionId":"session-codex-lagging-1"}',
      });
      await Future<void>.delayed(Duration.zero);

      expect(runtime.loadSessionDetailCalls, 1);
      expect(model.selectedConversation!.sessionRef, 'session-codex-lagging-1');
      expect(model.selectedConversation!.messages, isNotEmpty);
      expect(
        model.selectedConversation!.messages.first.text,
        contains('CONT_OK'),
      );
    });

    test('codex result done still notifies listeners twice', () async {
      final runtime = _DoneSessionRefreshRuntime();
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();
      var notifications = 0;
      model.addListener(() {
        notifications += 1;
      });

      await model.handleAgentResultEvent({
        'request_id': 'cccccccc-1111-2222-3333-cccccccccccc',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': 'Codex result done',
        'token': '',
        'detail_json':
            '{"kind":"codexResult","sessionId":"session-codex-done-notify-1"}',
      });
      await Future<void>.delayed(Duration.zero);

      expect(notifications, 2);
    });

    test(
        'codex result done request cleanup still routes later updates to selection',
        () async {
      final runtime = _DoneSessionRefreshRuntime();
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();
      final originalConversationId = model.selectedConversation!.id;

      await model.handleAgentResultEvent({
        'request_id': 'cececccc-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': 'Codex result done',
        'token': '',
        'detail_json':
            '{"kind":"codexResult","sessionId":"session-codex-done-2"}',
      });
      await Future<void>.delayed(Duration.zero);

      model.createConversation();
      final nextSelectedConversationId = model.selectedConversation!.id;
      expect(nextSelectedConversationId, isNot(originalConversationId));

      await model.handleAgentResultEvent({
        'request_id': 'cececccc-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': 'Plain codex completion after cleanup',
        'token': '',
        'detail_json': '',
      });

      expect(model.selectedConversation!.id, nextSelectedConversationId);
      expect(
        model.selectedConversation!.messages.first.text,
        contains('Plain codex completion after cleanup'),
      );
    });

    test(
        'cancelled status cleanup helper still clears active request before later plain update',
        () async {
      final runtime = _DispatchTrackingRuntime();
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();
      final originalConversationId = model.selectedConversation!.id;

      model.textController.text = 'Inspect active request cleanup';
      await model.sendCurrentPrompt();
      await Future<void>.delayed(Duration.zero);

      model.createConversation();
      final nextSelectedConversationId = model.selectedConversation!.id;
      expect(nextSelectedConversationId, isNot(originalConversationId));

      await model.handleAgentResultEvent({
        'request_id': '',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'cancelled',
        'text': 'Cancelled by operator',
        'token': '',
        'detail_json': '',
      });

      await model.handleAgentResultEvent({
        'request_id': '',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': 'Plain completion after cancelled cleanup',
        'token': '',
        'detail_json': '',
      });

      expect(model.selectedConversation!.id, nextSelectedConversationId);
      expect(
        model.selectedConversation!.messages.first.text,
        contains('Plain completion after cancelled cleanup'),
      );
    });

    test('codex result without session id still skips session refresh',
        () async {
      final runtime = _DoneSessionRefreshRuntime();
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();

      await model.handleAgentResultEvent({
        'request_id': 'cccccccc-4444-5555-6666-cccccccccccc',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': 'Codex result done',
        'token': '',
        'detail_json': '{"kind":"codexResult","sessionId":"   "}',
      });
      await Future<void>.delayed(Duration.zero);

      expect(runtime.loadSessionDetailCalls, 0);
      expect(model.selectedConversation!.sessionRef, isEmpty);
    });

    test(
        'codex result failed refresh helper still keeps binding-only detail hydration path',
        () async {
      final runtime = _DoneSessionRefreshRuntime();
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();

      await model.handleAgentResultEvent({
        'request_id': 'cccccccc-7777-8888-9999-cccccccccccc',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'failed',
        'text': 'Codex result failed',
        'token': '',
        'detail_json':
            '{"kind":"codexResult","sessionId":"session-codex-failed-no-refresh-1","error":"workspace denied"}',
      });
      await Future<void>.delayed(Duration.zero);

      expect(runtime.loadSessionDetailCalls, 1);
      expect(
        model.selectedConversation!.sessionRef,
        'session-codex-failed-no-refresh-1',
      );
    });

    test(
        'codex result without session binding still appends timeline and raw events through shared store',
        () async {
      final model = await createModel();
      final conversationId = model.selectedConversation!.id;

      await model.handleAgentResultEvent({
        'request_id': 'dddddddd-dddd-dddd-dddd-dddddddddddd',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'done',
        'text': 'Codex result detail',
        'token': '',
        'detail_json': '{"kind":"codexResult","error":""}',
      });

      expect(model.timelineForConversation(conversationId), isNotEmpty);
      expect(model.rawEventsForConversation(conversationId), isNotEmpty);
      expect(
        model.timelineForConversation(conversationId).last['stage'],
        'done',
      );
      expect(
        model.rawEventsForConversation(conversationId).last['kind'],
        'codexResult',
      );
    });

    test(
        'codex result error without session binding still records failed timeline',
        () async {
      final model = await createModel();
      final conversationId = model.selectedConversation!.id;

      await model.handleAgentResultEvent({
        'request_id': 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'failed',
        'text': 'Codex result failed',
        'token': '',
        'detail_json': '{"kind":"codexResult","error":"workspace denied"}',
      });

      expect(model.timelineForConversation(conversationId), isNotEmpty);
      expect(model.rawEventsForConversation(conversationId), isNotEmpty);
      expect(
        model.timelineForConversation(conversationId).last['stage'],
        'failed',
      );
      expect(
        model.timelineForConversation(conversationId).last['summary'],
        'workspace denied',
      );
      expect(
        model.rawEventsForConversation(conversationId).last['error'],
        'workspace denied',
      );
    });

    test('ensureLoaded auto-attached latest session persists only final state',
        () async {
      final runtime = _AutoAttachLatestSessionRuntime();
      final storage = _MemoryAgentDashboardStorage();
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: storage,
      );

      await model.ensureLoaded();
      await Future<void>.delayed(Duration.zero);

      expect(runtime.loadSessionDetailCalls, 1);
      expect(storage.writeCount, 1);
      expect(model.selectedConversation!.sessionRef, 'session-latest-auto-1');
      expect(model.selectedConversation!.messages, isNotEmpty);
    });

    test(
        'ensureLoaded still skips auto-attach when selected conversation has draft',
        () async {
      final runtime = _AutoAttachLatestSessionRuntime();
      final storage = _MemoryAgentDashboardStorage();
      final seededConversation = AgentConversation(
        id: 'seed-conversation-1',
        title: 'Seeded draft conversation',
        projectId: AgentDashboardModel.defaultProjectId,
        threadMode: 'new',
        profile: '',
        sessionRef: '',
        selectedSkillIds: const [],
        pinned: false,
        archived: false,
        draft: 'Keep this draft before auto attach.',
        includeConversationHistory: true,
        includeTerminalContext: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        lastReadAt: DateTime.now(),
        messages: const [],
      );
      storage.seed(
        runtime.peerId,
        'agent_dashboard_conversations.json',
        '[${jsonEncode(seededConversation.toJson())}]',
      );
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: storage,
      );

      await model.ensureLoaded();
      await Future<void>.delayed(Duration.zero);

      expect(runtime.loadSessionDetailCalls, 0);
      expect(model.selectedConversation!.id, 'seed-conversation-1');
      expect(model.selectedConversation!.draft,
          'Keep this draft before auto attach.');
      expect(model.textController.text, 'Keep this draft before auto attach.');
      expect(model.selectedConversation!.sessionRef, isEmpty);
      expect(storage.writeCount, 0);
    });

    test(
        'ensureLoaded still hydrates seeded selected continue conversation once',
        () async {
      final runtime = _SessionRestoreTrackingRuntime();
      final storage = _MemoryAgentDashboardStorage();
      final seededConversation = AgentConversation(
        id: 'seed-continue-conversation-1',
        title: 'Seeded continue conversation',
        projectId: AgentDashboardModel.defaultProjectId,
        threadMode: 'continue',
        profile: '',
        sessionRef: 'seed-session-1',
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
      storage.seed(
        runtime.peerId,
        'agent_dashboard_conversations.json',
        '[${jsonEncode(seededConversation.toJson())}]',
      );
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: storage,
      );

      await model.ensureLoaded();
      await Future<void>.delayed(Duration.zero);

      expect(runtime.loadSessionDetailCalls, 1);
      expect(runtime.lastSessionDetailConversationId,
          'seed-continue-conversation-1');
      expect(model.selectedConversation!.sessionRef, 'seed-session-1');
      expect(model.selectedConversation!.messages, isNotEmpty);
    });

    test(
        'selecting missing conversation still keeps fallback selection without write',
        () async {
      final storage = _MemoryAgentDashboardStorage();
      final model = AgentDashboardModel.fromRuntime(
        _TrackingRuntime(hasActiveTracking: false),
        storage: storage,
      );
      await model.ensureLoaded();
      final selectedId = model.selectedConversation!.id;
      final writesBeforeSelect = storage.writeCount;

      model.selectConversation('missing-conversation-id');
      await Future<void>.delayed(Duration.zero);

      expect(model.selectedConversation!.id, selectedId);
      expect(storage.writeCount, writesBeforeSelect);
    });

    test('selecting missing conversation before load stays empty without write',
        () async {
      final storage = _MemoryAgentDashboardStorage();
      final model = AgentDashboardModel.fromRuntime(
        _TrackingRuntime(hasActiveTracking: false),
        storage: storage,
      );
      final writesBeforeSelect = storage.writeCount;
      expect(model.conversations, isEmpty);
      expect(model.selectedConversation, isNull);
      expect(model.textController.text, isEmpty);

      model.selectConversation('missing-conversation-id');
      await Future<void>.delayed(Duration.zero);

      expect(model.conversations, isEmpty);
      expect(model.selectedConversation, isNull);
      expect(model.textController.text, isEmpty);
      expect(storage.writeCount, writesBeforeSelect);
    });

    test('loading more history for missing conversation still skips write',
        () async {
      final storage = _MemoryAgentDashboardStorage();
      final model = AgentDashboardModel.fromRuntime(
        _TrackingRuntime(hasActiveTracking: false),
        storage: storage,
      );
      await model.ensureLoaded();
      final selectedId = model.selectedConversation!.id;
      final writesBeforeLoad = storage.writeCount;

      await model.loadMoreSessionHistory('missing-conversation-id');
      await Future<void>.delayed(Duration.zero);

      expect(model.selectedConversation!.id, selectedId);
      expect(storage.writeCount, writesBeforeLoad);
    });

    test('deleteConversation persists replacement selection once', () async {
      final storage = _MemoryAgentDashboardStorage();
      final model = AgentDashboardModel.fromRuntime(
        MockAgentDashboardRuntime(),
        seedDemoData: true,
        storage: storage,
      );
      await model.ensureLoaded();

      final selectedId = model.selectedConversation!.id;
      expect(model.conversations.length, greaterThan(1));
      final writesBeforeDelete = storage.writeCount;

      model.deleteConversation(selectedId);
      await Future<void>.delayed(Duration.zero);

      expect(model.conversations.length, greaterThanOrEqualTo(1));
      expect(model.selectedConversation, isNotNull);
      expect(model.selectedConversation!.id, isNot(selectedId));
      expect(storage.writeCount, writesBeforeDelete + 1);
    });

    test('deleteConversation preserves remaining conversation order', () async {
      final model = AgentDashboardModel.fromRuntime(
        MockAgentDashboardRuntime(),
        seedDemoData: true,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();

      final beforeOrder =
          model.visibleConversations.map((item) => item.id).toList();
      expect(beforeOrder.length, greaterThan(1));

      model.deleteConversation(beforeOrder.first);
      await Future<void>.delayed(Duration.zero);

      final afterOrder =
          model.visibleConversations.map((item) => item.id).toList();
      expect(afterOrder.length, beforeOrder.length - 1);
      expect(afterOrder.first, beforeOrder[1]);
      expect(afterOrder, isNot(contains(beforeOrder.first)));
    });

    test(
        'deleteConversation still syncs composer draft from replacement conversation',
        () async {
      final storage = _MemoryAgentDashboardStorage();
      final model = AgentDashboardModel.fromRuntime(
        MockAgentDashboardRuntime(),
        seedDemoData: true,
        storage: storage,
      );
      await model.ensureLoaded();

      final deletedId = model.selectedConversation!.id;
      final replacement = model.visibleConversations[1];
      expect(replacement.draft, isNotEmpty);

      model.deleteConversation(deletedId);
      await Future<void>.delayed(Duration.zero);

      expect(model.selectedConversation, isNotNull);
      expect(model.selectedConversation!.id, replacement.id);
      expect(model.textController.text, replacement.draft);
    });

    test(
        'deleteConversation on unselected conversation still keeps current selection',
        () async {
      final model = AgentDashboardModel.fromRuntime(
        MockAgentDashboardRuntime(),
        seedDemoData: true,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();

      final selectedBeforeDelete = model.selectedConversation!;
      final deletedId = model.visibleConversations[1].id;

      model.deleteConversation(deletedId);
      await Future<void>.delayed(Duration.zero);

      expect(model.selectedConversation, isNotNull);
      expect(model.selectedConversation!.id, selectedBeforeDelete.id);
      expect(model.textController.text, selectedBeforeDelete.draft);
    });

    test('deleteConversation with missing id skips storage write', () async {
      final storage = _MemoryAgentDashboardStorage();
      final model = AgentDashboardModel.fromRuntime(
        MockAgentDashboardRuntime(),
        seedDemoData: true,
        storage: storage,
      );
      await model.ensureLoaded();

      final selectedId = model.selectedConversation!.id;
      final conversationCountBeforeDelete = model.conversations.length;
      final writesBeforeDelete = storage.writeCount;

      model.deleteConversation('missing-conversation-id');
      await Future<void>.delayed(Duration.zero);

      expect(model.conversations.length, conversationCountBeforeDelete);
      expect(model.selectedConversation, isNotNull);
      expect(model.selectedConversation!.id, selectedId);
      expect(storage.writeCount, writesBeforeDelete);
    });

    test('selecting an already-read conversation does not persist again',
        () async {
      final storage = _MemoryAgentDashboardStorage();
      final model = AgentDashboardModel.fromRuntime(
        MockAgentDashboardRuntime(),
        seedDemoData: true,
        storage: storage,
      );
      await model.ensureLoaded();

      final selectedId = model.selectedConversation!.id;
      final writesBeforeSelect = storage.writeCount;

      model.selectConversation(selectedId);
      await Future<void>.delayed(Duration.zero);

      expect(model.selectedConversation!.id, selectedId);
      expect(storage.writeCount, writesBeforeSelect);
    });

    test('selecting a conversation with unread messages persists once',
        () async {
      final storage = _MemoryAgentDashboardStorage();
      final model = AgentDashboardModel.fromRuntime(
        MockAgentDashboardRuntime(),
        seedDemoData: true,
        storage: storage,
      );
      await model.ensureLoaded();

      final target = model.visibleConversations.firstWhere(
          (conversation) => model.conversationHasUnread(conversation.id));
      final writesBeforeSelect = storage.writeCount;

      model.selectConversation(target.id);
      await Future<void>.delayed(Duration.zero);

      expect(model.selectedConversation!.id, target.id);
      expect(model.conversationHasUnread(target.id), false);
      expect(storage.writeCount, writesBeforeSelect + 1);
    });

    test('demo unread conversation count stays consistent', () async {
      final model = AgentDashboardModel.fromRuntime(
        MockAgentDashboardRuntime(),
        seedDemoData: true,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();

      expect(model.unreadConversationCount, 2);
    });

    test('status label helper stays aligned with conversation status mapping',
        () async {
      final model = AgentDashboardModel.fromRuntime(
        MockAgentDashboardRuntime(),
        seedDemoData: true,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();

      for (final conversation in model.visibleConversations) {
        final status = model.statusForConversation(conversation.id);
        expect(
          model.statusLabelForStatus(status),
          model.statusLabelForConversation(conversation.id),
        );
      }
    });

    test('status label object helper stays aligned with status label mapping',
        () async {
      final model = AgentDashboardModel.fromRuntime(
        MockAgentDashboardRuntime(),
        seedDemoData: true,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();

      for (final conversation in model.visibleConversations) {
        expect(
          model.statusLabelForConversationObject(conversation),
          model.statusLabelForConversation(conversation.id),
        );
      }
    });

    test('status helper stays aligned with conversation status mapping',
        () async {
      final model = AgentDashboardModel.fromRuntime(
        MockAgentDashboardRuntime(),
        seedDemoData: true,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();

      for (final conversation in model.visibleConversations) {
        expect(
          model.statusForConversationObject(conversation),
          model.statusForConversation(conversation.id),
        );
      }
    });

    test('unread helper stays aligned with conversation unread mapping',
        () async {
      final model = AgentDashboardModel.fromRuntime(
        MockAgentDashboardRuntime(),
        seedDemoData: true,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();

      for (final conversation in model.visibleConversations) {
        expect(
          model.conversationHasUnreadForConversation(conversation),
          model.conversationHasUnread(conversation.id),
        );
      }
    });

    test('status detail helper stays aligned with conversation detail mapping',
        () async {
      final model = AgentDashboardModel.fromRuntime(
        MockAgentDashboardRuntime(),
        seedDemoData: true,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();

      for (final conversation in model.visibleConversations) {
        expect(
          model.statusDetailForConversationObject(conversation),
          model.statusDetailForConversation(conversation.id),
        );
      }
    });

    test('timeline helper stays aligned with conversation timeline mapping',
        () async {
      final model = AgentDashboardModel.fromRuntime(
        MockAgentDashboardRuntime(),
        seedDemoData: true,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();

      for (final conversation in model.visibleConversations) {
        expect(
          model.timelineForConversationObject(conversation),
          model.timelineForConversation(conversation.id),
        );
      }
    });

    test('raw-events helper stays aligned with conversation raw-events mapping',
        () async {
      final model = await createModel();
      final conversation = model.selectedConversation!;

      await model.handleAgentResultEvent({
        'request_id': '99999999-aaaa-bbbb-cccc-999999999999',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'running',
        'text': 'Snapshot',
        'token': '',
        'detail_json':
            '{"kind":"task_snapshot","item":{"timeline":[{"stage":"running","summary":"step"}],"raw_events":[{"kind":"event","value":1}]}}',
      });

      expect(
        model.rawEventsForConversationObject(conversation),
        model.rawEventsForConversation(conversation.id),
      );
      expect(
        model.rawEventsForConversationObject(conversation).first['kind'],
        'event',
      );
    });

    test('load-more helper stays aligned with conversation paging mapping',
        () async {
      final model = AgentDashboardModel.fromRuntime(
        MockAgentDashboardRuntime(),
        seedDemoData: true,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();

      for (final conversation in model.visibleConversations) {
        expect(
          model.canLoadMoreSessionHistoryForConversation(conversation),
          model.canLoadMoreSessionHistory(conversation.id),
        );
      }
    });

    test(
        'load-more helper stays aligned after blank-session short-circuit cleanup',
        () async {
      final model = await createModel();
      final conversation = model.selectedConversation!;

      expect(
        model.canLoadMoreSessionHistoryForConversation(conversation),
        model.canLoadMoreSessionHistory(conversation.id),
      );
    });

    test(
        'session-next-cursor helper stays aligned with conversation paging state',
        () async {
      final runtime = _PagedSessionRestoreRuntime();
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();
      final conversationId = model.selectedConversation!.id;

      await model.restoreSessionIntoConversation(
        conversationId: conversationId,
        sessionId: 'session-cursor-helper-1',
      );
      await Future<void>.delayed(Duration.zero);

      final conversation = model.selectedConversation!;
      expect(
        model.sessionNextCursorForConversationObject(conversation),
        1,
      );
      expect(
        model.canLoadMoreSessionHistoryForConversation(conversation),
        model.canLoadMoreSessionHistory(conversation.id),
      );
    });

    test(
        'session-next-cursor helper stays aligned after background older-history prefetch',
        () async {
      final runtime = _PagedSessionRestoreRuntime();
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();
      final conversationId = model.selectedConversation!.id;

      await model.restoreSessionIntoConversation(
        conversationId: conversationId,
        sessionId: 'session-cursor-helper-2',
      );
      await Future<void>.delayed(const Duration(milliseconds: 260));

      final conversation = model.selectedConversation!;
      expect(
        model.sessionNextCursorForConversationObject(conversation),
        isNull,
      );
      expect(model.selectedConversation!.messages.length, 2);
    });

    test('session-next-cursor helper still parses snake_case paging detail',
        () async {
      final runtime = _SnakeCasePagedSessionRestoreRuntime();
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();
      final conversationId = model.selectedConversation!.id;

      await model.restoreSessionIntoConversation(
        conversationId: conversationId,
        sessionId: 'session-cursor-helper-snake-1',
      );
      await Future<void>.delayed(Duration.zero);

      final conversation = model.selectedConversation!;
      expect(runtime.loadSessionDetailCalls, 1);
      expect(
        model.sessionNextCursorForConversationObject(conversation),
        1,
      );
      expect(model.selectedConversation!.messages.length, 1);

      await Future<void>.delayed(const Duration(milliseconds: 260));

      expect(runtime.loadSessionDetailCalls, 2);
      expect(
        model.sessionNextCursorForConversationObject(
          model.selectedConversation!,
        ),
        isNull,
      );
      expect(model.selectedConversation!.messages.length, 2);
    });

    test('busy helper stays aligned with conversation busy mapping', () async {
      final model = AgentDashboardModel.fromRuntime(
        MockAgentDashboardRuntime(),
        seedDemoData: true,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();

      for (final conversation in model.visibleConversations) {
        expect(
          model.isConversationBusyForConversation(conversation),
          model.isConversationBusy(conversation.id),
        );
      }
    });

    test(
        'needs-confirmation helper stays aligned with conversation status mapping',
        () async {
      final model = AgentDashboardModel.fromRuntime(
        MockAgentDashboardRuntime(),
        seedDemoData: true,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();

      for (final conversation in model.visibleConversations) {
        expect(
          model.conversationNeedsConfirmationForConversation(conversation),
          model.conversationNeedsConfirmation(conversation.id),
        );
      }
    });

    test(
        'status-tracking stop helper stays aligned with conversation status mapping',
        () async {
      final model = AgentDashboardModel.fromRuntime(
        MockAgentDashboardRuntime(),
        seedDemoData: true,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();

      for (final conversation in model.visibleConversations) {
        expect(
          model.shouldStopStatusTrackingForConversation(conversation),
          model.shouldStopStatusTracking(conversation.id),
        );
      }
    });

    test('missing conversation unread lookup still returns false', () async {
      final model = AgentDashboardModel.fromRuntime(
        MockAgentDashboardRuntime(),
        seedDemoData: true,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();

      expect(model.conversationHasUnread('missing-conversation-id'), false);
    });

    test('missing conversation mutation entrypoints still keep state unchanged',
        () async {
      final storage = _MemoryAgentDashboardStorage();
      final model = AgentDashboardModel.fromRuntime(
        MockAgentDashboardRuntime(),
        seedDemoData: true,
        storage: storage,
      );
      await model.ensureLoaded();

      final selectedId = model.selectedConversation!.id;
      final titlesBefore = model.conversations.map((c) => c.title).toList();
      final writesBefore = storage.writeCount;

      model.toggleConversationPinned('missing-conversation-id');
      model.toggleConversationArchived('missing-conversation-id');
      model.renameConversation('missing-conversation-id', 'ignored');
      model.updateConversationSettings(
        conversationId: 'missing-conversation-id',
        title: 'ignored settings update',
      );
      await model.restoreSessionIntoConversation(
        conversationId: 'missing-conversation-id',
        sessionId: '',
      );
      await model.loadMoreSessionHistory('missing-conversation-id');
      await Future<void>.delayed(Duration.zero);

      expect(model.selectedConversation!.id, selectedId);
      expect(model.conversations.map((c) => c.title).toList(), titlesBefore);
      expect(storage.writeCount, writesBefore);
    });

    test('selecting unread conversation updates unread count once', () async {
      final storage = _MemoryAgentDashboardStorage();
      final model = AgentDashboardModel.fromRuntime(
        MockAgentDashboardRuntime(),
        seedDemoData: true,
        storage: storage,
      );
      await model.ensureLoaded();

      final target = model.visibleConversations.firstWhere(
          (conversation) => model.conversationHasUnread(conversation.id));
      expect(model.unreadConversationCount, 2);

      model.selectConversation(target.id);
      await Future<void>.delayed(Duration.zero);

      expect(model.unreadConversationCount, 1);
      expect(model.conversationHasUnread(target.id), false);
      expect(storage.writeCount, greaterThan(0));
    });

    test('selecting unread conversation still keeps lastReadAt semantics',
        () async {
      final storage = _MemoryAgentDashboardStorage();
      final model = AgentDashboardModel.fromRuntime(
        MockAgentDashboardRuntime(),
        seedDemoData: true,
        storage: storage,
      );
      await model.ensureLoaded();

      final target = model.visibleConversations.firstWhere(
          (conversation) => model.conversationHasUnread(conversation.id));
      final lastReadAtBeforeSelect = target.lastReadAt;
      final writesBeforeSelect = storage.writeCount;

      model.selectConversation(target.id);
      await Future<void>.delayed(Duration.zero);

      expect(model.selectedConversation!.id, target.id);
      expect(model.selectedConversation!.lastReadAt, isNotNull);
      expect(model.selectedConversation!.lastReadAt,
          isNot(equals(lastReadAtBeforeSelect)));
      expect(model.conversationHasUnread(target.id), false);
      expect(storage.writeCount, writesBeforeSelect + 1);
    });

    test('updating conversation with unchanged continue session skips write',
        () async {
      final storage = _MemoryAgentDashboardStorage();
      final model = AgentDashboardModel.fromRuntime(
        _TrackingRuntime(hasActiveTracking: false),
        storage: storage,
      );
      await model.ensureLoaded();
      final conversationId = model.selectedConversation!.id;

      model.updateConversationSettings(
        conversationId: conversationId,
        threadMode: 'continue',
        sessionRef: 'session-noop-1',
      );
      await Future<void>.delayed(Duration.zero);

      final writesBeforeNoop = storage.writeCount;
      final updatedAtBeforeNoop = model.selectedConversation!.updatedAt;

      model.updateConversationSettings(
        conversationId: conversationId,
        threadMode: 'continue',
        sessionRef: 'session-noop-1',
      );
      await Future<void>.delayed(Duration.zero);

      expect(model.selectedConversation!.sessionRef, 'session-noop-1');
      expect(model.selectedConversation!.updatedAt, updatedAtBeforeNoop);
      expect(storage.writeCount, writesBeforeNoop);
    });

    test('updating conversation title still persists once', () async {
      final storage = _MemoryAgentDashboardStorage();
      final model = AgentDashboardModel.fromRuntime(
        _TrackingRuntime(hasActiveTracking: false),
        storage: storage,
      );
      await model.ensureLoaded();
      final conversationId = model.selectedConversation!.id;
      final writesBeforeRename = storage.writeCount;

      model.updateConversationSettings(
        conversationId: conversationId,
        title: 'Renamed conversation',
      );
      await Future<void>.delayed(Duration.zero);

      expect(model.selectedConversation!.title, 'Renamed conversation');
      expect(storage.writeCount, writesBeforeRename + 1);
    });

    test(
        'updating conversation continue session still hydrates selected conversation once',
        () async {
      final runtime = _SessionRestoreTrackingRuntime();
      final storage = _MemoryAgentDashboardStorage();
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: storage,
      );
      await model.ensureLoaded();
      final conversationId = model.selectedConversation!.id;
      final writesBeforeUpdate = storage.writeCount;

      model.updateConversationSettings(
        conversationId: conversationId,
        threadMode: 'continue',
        sessionRef: 'session-settings-hydrate-1',
      );
      await Future<void>.delayed(Duration.zero);

      expect(runtime.loadSessionDetailCalls, 1);
      expect(
          model.selectedConversation!.sessionRef, 'session-settings-hydrate-1');
      expect(model.selectedConversation!.messages, isNotEmpty);
      expect(storage.writeCount, writesBeforeUpdate + 2);
    });

    test(
        'updating conversation continue session still hydrates the same conversation after sort',
        () async {
      final runtime = _SessionRestoreTrackingRuntime();
      final storage = _MemoryAgentDashboardStorage();
      final now = DateTime.now();
      final first = AgentConversation(
        id: 'conversation-old-1',
        title: 'Older conversation',
        projectId: AgentDashboardModel.defaultProjectId,
        threadMode: 'new',
        profile: '',
        sessionRef: '',
        selectedSkillIds: const [],
        pinned: false,
        archived: false,
        draft: '',
        includeConversationHistory: true,
        includeTerminalContext: true,
        createdAt: now.subtract(const Duration(hours: 2)),
        updatedAt: now.subtract(const Duration(minutes: 5)),
        lastReadAt: now.subtract(const Duration(minutes: 5)),
        messages: const [],
      );
      final second = AgentConversation(
        id: 'conversation-new-2',
        title: 'Newer conversation',
        projectId: AgentDashboardModel.defaultProjectId,
        threadMode: 'new',
        profile: '',
        sessionRef: '',
        selectedSkillIds: const [],
        pinned: false,
        archived: false,
        draft: '',
        includeConversationHistory: true,
        includeTerminalContext: true,
        createdAt: now.subtract(const Duration(hours: 1)),
        updatedAt: now.subtract(const Duration(minutes: 1)),
        lastReadAt: now.subtract(const Duration(minutes: 1)),
        messages: const [],
      );
      storage.seed(
        runtime.peerId,
        'agent_dashboard_conversations.json',
        '[${jsonEncode(first.toJson())},${jsonEncode(second.toJson())}]',
      );
      final model = AgentDashboardModel.fromRuntime(
        runtime,
        storage: storage,
      );

      await model.ensureLoaded();
      await Future<void>.delayed(Duration.zero);

      model.updateConversationSettings(
        conversationId: 'conversation-old-1',
        threadMode: 'continue',
        sessionRef: 'session-sort-hydrate-1',
      );
      await Future<void>.delayed(Duration.zero);

      expect(runtime.loadSessionDetailCalls, 1);
      expect(runtime.lastSessionDetailConversationId, 'conversation-old-1');
      final restored = model.conversations.firstWhere(
          (conversation) => conversation.id == 'conversation-old-1');
      expect(restored.sessionRef, 'session-sort-hydrate-1');
      expect(restored.messages, isNotEmpty);
      expect(model.conversations.first.id, 'conversation-old-1');
    });

    test('toggling pinned and archived still persists once per change',
        () async {
      final storage = _MemoryAgentDashboardStorage();
      final model = AgentDashboardModel.fromRuntime(
        _TrackingRuntime(hasActiveTracking: false),
        storage: storage,
      );
      await model.ensureLoaded();
      final conversationId = model.selectedConversation!.id;

      final writesBeforePinned = storage.writeCount;
      expect(model.selectedConversation!.pinned, false);

      model.toggleConversationPinned(conversationId);
      await Future<void>.delayed(Duration.zero);

      expect(model.selectedConversation!.pinned, true);
      expect(storage.writeCount, writesBeforePinned + 1);

      final writesBeforeArchived = storage.writeCount;
      expect(model.selectedConversation!.archived, false);

      model.toggleConversationArchived(conversationId);
      await Future<void>.delayed(Duration.zero);

      expect(model.selectedConversation!.archived, true);
      expect(model.selectedConversation!.lastReadAt, isNotNull);
      expect(storage.writeCount, writesBeforeArchived + 1);
    });

    test('composer draft change still persists selected conversation once',
        () async {
      final storage = _MemoryAgentDashboardStorage();
      final model = AgentDashboardModel.fromRuntime(
        _TrackingRuntime(hasActiveTracking: false),
        storage: storage,
      );
      await model.ensureLoaded();
      final conversationId = model.selectedConversation!.id;
      final writesBeforeDraft = storage.writeCount;

      model.textController.text = 'Draft from composer';
      await Future<void>.delayed(const Duration(milliseconds: 260));

      expect(model.selectedConversation!.id, conversationId);
      expect(model.selectedConversation!.draft, 'Draft from composer');
      expect(storage.writeCount, writesBeforeDraft + 1);
    });

    test(
        'updating selected conversation draft still syncs composer and persists once',
        () async {
      final storage = _MemoryAgentDashboardStorage();
      final model = AgentDashboardModel.fromRuntime(
        _TrackingRuntime(hasActiveTracking: false),
        storage: storage,
      );
      await model.ensureLoaded();
      final conversationId = model.selectedConversation!.id;
      final writesBeforeUpdate = storage.writeCount;

      model.updateConversationSettings(
        conversationId: conversationId,
        draft: 'Draft from settings update',
      );
      await Future<void>.delayed(Duration.zero);

      expect(model.selectedConversation!.id, conversationId);
      expect(model.selectedConversation!.draft, 'Draft from settings update');
      expect(model.textController.text, 'Draft from settings update');
      expect(storage.writeCount, writesBeforeUpdate + 1);
    });

    test(
        'switching conversation still syncs composer draft and keeps one write',
        () async {
      final storage = _MemoryAgentDashboardStorage();
      final model = AgentDashboardModel.fromRuntime(
        MockAgentDashboardRuntime(),
        seedDemoData: true,
        storage: storage,
      );
      await model.ensureLoaded();

      final target = model.visibleConversations
          .firstWhere((conversation) => conversation.draft.trim().isNotEmpty);
      final writesBeforeSelect = storage.writeCount;

      model.selectConversation(target.id);
      await Future<void>.delayed(Duration.zero);

      expect(model.selectedConversation!.id, target.id);
      expect(model.textController.text, target.draft);
      expect(storage.writeCount, writesBeforeSelect + 1);
    });

    test('creating conversation still inherits selected template settings',
        () async {
      final model = AgentDashboardModel.fromRuntime(
        MockAgentDashboardRuntime(),
        seedDemoData: true,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();

      final template = model.visibleConversations
          .firstWhere((conversation) => conversation.draft.trim().isNotEmpty);
      model.selectConversation(template.id);
      await Future<void>.delayed(Duration.zero);

      final created = model.createConversation();

      expect(created.projectId, template.projectId);
      expect(created.profile, template.profile);
      expect(created.selectedSkillIds, template.selectedSkillIds);
      expect(
        created.includeConversationHistory,
        template.includeConversationHistory,
      );
      expect(created.threadMode, 'new');
      expect(created.sessionRef, isEmpty);
    });

    test('creating conversation still clears composer draft', () async {
      final storage = _MemoryAgentDashboardStorage();
      final model = AgentDashboardModel.fromRuntime(
        MockAgentDashboardRuntime(),
        seedDemoData: true,
        storage: storage,
      );
      await model.ensureLoaded();

      model.textController.text = 'Draft before create';
      await Future<void>.delayed(const Duration(milliseconds: 260));
      final writesBeforeCreate = storage.writeCount;

      final created = model.createConversation();
      await Future<void>.delayed(Duration.zero);

      expect(model.selectedConversation!.id, created.id);
      expect(created.draft, '');
      expect(model.textController.text, '');
      expect(storage.writeCount, writesBeforeCreate + 1);
    });

    test('selected conversation still resolves first visible item by default',
        () async {
      final model = AgentDashboardModel.fromRuntime(
        MockAgentDashboardRuntime(),
        seedDemoData: true,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();

      expect(model.selectedConversation, isNotNull);
      expect(
          model.selectedConversation!.id, model.visibleConversations.first.id);
    });

    test('visible conversations keep demo order without getter-side sort',
        () async {
      final model = AgentDashboardModel.fromRuntime(
        MockAgentDashboardRuntime(),
        seedDemoData: true,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();

      final ordered = model.visibleConversations;

      expect(ordered.length, 3);
      expect(ordered[0].title, 'Analyze Android entry');
      expect(ordered[0].pinned, true);
      expect(ordered[1].title, 'Prepare workspace-write change');
      expect(ordered[2].title, 'Review terminal context');
    });

    test('resetDemoState restores visible conversation order', () async {
      final model = AgentDashboardModel.fromRuntime(
        MockAgentDashboardRuntime(),
        seedDemoData: true,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();

      model.renameConversation(
        model.visibleConversations.last.id,
        'Mutated title before reset',
      );
      await Future<void>.delayed(Duration.zero);

      await model.resetDemoState();

      final ordered = model.visibleConversations;
      expect(ordered.length, 3);
      expect(ordered[0].title, 'Analyze Android entry');
      expect(ordered[1].title, 'Prepare workspace-write change');
      expect(ordered[2].title, 'Review terminal context');
    });

    test('resetDemoState still syncs composer draft from restored selection',
        () async {
      final model = AgentDashboardModel.fromRuntime(
        MockAgentDashboardRuntime(),
        seedDemoData: true,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();

      model.textController.text = 'temporary composer text';
      await model.resetDemoState();

      expect(model.selectedConversation, isNotNull);
      expect(model.textController.text, model.selectedConversation!.draft);
    });

    test(
        'resetDemoState still restores first visible conversation as selection',
        () async {
      final model = AgentDashboardModel.fromRuntime(
        MockAgentDashboardRuntime(),
        seedDemoData: true,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();

      model.createConversation();
      expect(
        model.selectedConversation!.id,
        isNot(model.visibleConversations.first.id),
      );

      await model.resetDemoState();

      expect(model.selectedConversation, isNotNull);
      expect(
        model.selectedConversation!.id,
        model.visibleConversations.first.id,
      );
    });

    test('resetDemoState restores demo runtime statuses', () async {
      final model = AgentDashboardModel.fromRuntime(
        MockAgentDashboardRuntime(),
        seedDemoData: true,
        storage: _MemoryAgentDashboardStorage(),
      );
      await model.ensureLoaded();

      await model.handleAgentResultEvent({
        'request_id': 'dddddddd-dddd-dddd-dddd-dddddddddddd',
        'project': AgentDashboardModel.defaultProjectId,
        'status': 'failed',
        'text': 'Mutate current demo status',
        'token': '',
        'detail_json': '',
      });

      await model.resetDemoState();

      final ordered = model.visibleConversations;
      expect(
        model.statusForConversation(ordered[0].id),
        AgentConversationStatus.completed,
      );
      expect(
        model.statusForConversation(ordered[1].id),
        AgentConversationStatus.needsConfirmation,
      );
      expect(
        model.statusForConversation(ordered[2].id),
        AgentConversationStatus.running,
      );
    });
  });
}
