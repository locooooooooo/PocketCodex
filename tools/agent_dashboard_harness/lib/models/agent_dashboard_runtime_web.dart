import 'dart:convert';
import 'dart:async';

import 'package:http/http.dart' as http;

import 'agent_dashboard_model.dart';

const _bridgeBaseUrl = String.fromEnvironment(
  'RUSTDESK_AGENT_DASHBOARD_BRIDGE_URL',
  defaultValue: 'http://127.0.0.1:17321',
);

AgentDashboardRuntime createRustDeskAgentDashboardRuntime(Object parent) {
  return RustDeskAgentDashboardWebRuntime();
}

class RustDeskAgentDashboardWebRuntime implements AgentDashboardRuntime {
  final Map<String, Timer> _statusPollers = <String, Timer>{};

  int get _bridgePort {
    final uri = Uri.tryParse(_bridgeBaseUrl);
    return uri?.hasPort == true ? uri!.port : 17321;
  }

  @override
  bool get defersSkillCatalogLoad => false;

  @override
  bool get supportsBridgeDiagnostics => true;

  @override
  String get peerId {
    final uri = Uri.tryParse(_bridgeBaseUrl);
    final port = uri?.hasPort == true ? uri!.port : 17321;
    return 'dashboard-web-live-$port';
  }

  @override
  List<String> loadProjectIds() => const [AgentDashboardModel.defaultProjectId];

  @override
  String loadTerminalContext() => '';

  Future<Map<String, dynamic>> _getJson(String path) async {
    final response = await http.get(Uri.parse('$_bridgeBaseUrl$path'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Bridge GET $path failed: ${response.statusCode}');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await http.post(
      Uri.parse('$_bridgeBaseUrl$path'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Bridge POST $path failed: ${response.statusCode} ${response.body}',
      );
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  @override
  Future<AgentBridgeDiagnostics?> loadBridgeDiagnostics({
    bool attemptStart = false,
  }) async {
    final _ = attemptStart;
    try {
      final config = await _getJson('/agent/config');
      return _parseBridgeDiagnostics(config);
    } catch (e) {
      return buildBridgeUnreachableDiagnostics(error: e, port: _bridgePort);
    }
  }

  @override
  Future<void> dispatchCommand({
    required String requestId,
    required String projectId,
    required String prompt,
    required String mode,
    required bool requireConfirmation,
  }) async {
    await _postJson('/agent/run', {
      'request_id': requestId,
      'project': projectId,
      'prompt': prompt,
      'mode': mode,
      'require_confirmation': requireConfirmation,
    });
  }

  @override
  Future<void> dispatchEnvelope(Map<String, dynamic> envelope) {
    return _postJson(
            '/agent/run', buildAgentRunRequestBodyFromEnvelope(envelope))
        .then((_) {});
  }

  @override
  Future<List<Map<String, dynamic>>> loadSessions({
    String? conversationId,
  }) async {
    final response =
        await http.get(Uri.parse('$_bridgeBaseUrl/agent/sessions'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Bridge sessions failed: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded
        .whereType<Map>()
        .map((e) => _normalizeSessionSummary(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  Future<Map<String, dynamic>?> loadSessionDetail(
    String sessionId, {
    int? cursor,
    int pageSize = 40,
    String? conversationId,
  }) async {
    final suffix = cursor == null
        ? '/agent/sessions/$sessionId'
        : '/agent/sessions/$sessionId/page?cursor=$cursor&page_size=$pageSize';
    return _normalizeSessionDetail(await _getJson(suffix));
  }

  @override
  Future<List<Map<String, dynamic>>> loadSkills(
      {String? conversationId}) async {
    final response = await http.get(Uri.parse('$_bridgeBaseUrl/agent/skills'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Bridge skills failed: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  @override
  Future<Map<String, dynamic>> upsertSkill(Map<String, dynamic> payload) {
    return _postJson('/agent/skills', payload);
  }

  @override
  Future<void> deleteSkill(String skillId) async {
    final response =
        await http.delete(Uri.parse('$_bridgeBaseUrl/agent/skills/$skillId'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Bridge delete skill failed: ${response.statusCode}');
    }
  }

  @override
  Future<Map<String, dynamic>> syncSkills() {
    return _postJson('/agent/skills/sync', const {});
  }

  @override
  Future<Map<String, dynamic>> transcribeVoice(
    Map<String, dynamic> payload,
  ) {
    return _postJson('/agent/voice/transcribe', payload);
  }

  @override
  Future<String> recordVoiceClipBase64({
    Duration duration = const Duration(seconds: 5),
  }) async {
    throw UnsupportedError('Voice recording is not available in web runtime.');
  }

  @override
  Future<Map<String, dynamic>?> requestTaskStatus({
    required String requestId,
    required String projectId,
  }) async {
    try {
      final item = await _getJson('/agent/tasks/$requestId');
      return {
        'request_id': item['request_id'] ?? requestId,
        'project': item['project'] ?? projectId,
        'status': item['status'] ?? 'running',
        'text': item['text'] ?? '',
        'token': item['token'] ?? '',
        'detail_json': jsonEncode({
          'kind': 'task_snapshot',
          'item': item,
          if ((item['detail_json']?.toString().trim().isNotEmpty ?? false))
            'detail': jsonDecode(item['detail_json'].toString()),
        }),
      };
    } catch (_) {
      return null;
    }
  }

  @override
  bool hasActiveStatusTracking(String requestId) {
    return _statusPollers.containsKey(requestId);
  }

  @override
  Future<void> onCommandDispatched({
    required AgentDashboardModel model,
    required AgentConversation conversation,
    required String prompt,
    required String requestId,
  }) async {
    _statusPollers[requestId]?.cancel();
    _statusPollers[requestId] = Timer.periodic(const Duration(seconds: 2), (
      timer,
    ) async {
      try {
        final evt = await requestTaskStatus(
          requestId: requestId,
          projectId: conversation.projectId,
        );
        if (evt != null) {
          await model.handleAgentResultEvent(evt);
        }
        if (model.shouldStopStatusTrackingForConversation(conversation)) {
          timer.cancel();
          _statusPollers.remove(requestId);
        }
      } catch (_) {
        timer.cancel();
        _statusPollers.remove(requestId);
      }
    });
  }

  Map<String, dynamic> _normalizeSessionSummary(Map<String, dynamic> item) {
    final updatedAt =
        item['updatedAt']?.toString() ?? item['updated_at']?.toString() ?? '';
    final projectId =
        item['projectId']?.toString() ?? item['project_id']?.toString() ?? '';
    final projectPath = item['projectPath']?.toString() ??
        item['project_path']?.toString() ??
        '';
    return {
      ...item,
      'updatedAt': updatedAt,
      'updated_at': updatedAt,
      'projectId': projectId,
      'project_id': projectId,
      'projectPath': projectPath,
      'project_path': projectPath,
    };
  }

  Map<String, dynamic> _normalizeSessionDetail(Map<String, dynamic> item) {
    final updatedAt =
        item['updatedAt']?.toString() ?? item['updated_at']?.toString() ?? '';
    final projectId =
        item['projectId']?.toString() ?? item['project_id']?.toString() ?? '';
    final projectPath = item['projectPath']?.toString() ??
        item['project_path']?.toString() ??
        '';
    final rawEvents = (item['rawEvents'] as List<dynamic>? ??
            item['raw_events'] as List<dynamic>? ??
            const <dynamic>[])
        .toList();
    final nextCursor = item['nextCursor'] ?? item['next_cursor'];
    return {
      ...item,
      'updatedAt': updatedAt,
      'updated_at': updatedAt,
      'projectId': projectId,
      'project_id': projectId,
      'projectPath': projectPath,
      'project_path': projectPath,
      'rawEvents': rawEvents,
      'raw_events': rawEvents,
      'nextCursor': nextCursor,
      'next_cursor': nextCursor,
    };
  }

  AgentBridgeDiagnostics _parseBridgeDiagnostics(Map<String, dynamic> config) {
    final enabled = config['enabled'] == true;
    final port = int.tryParse(config['port']?.toString() ?? '') ?? _bridgePort;
    final command = config['command']?.toString().trim() ?? '';
    final requireConfirmation = config['require_confirmation'] == true;
    final errors = (config['errors'] as List<dynamic>? ?? const <dynamic>[])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final projectCount = (config['projects'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .length;

    final AgentBridgeHealthState state;
    final String summary;
    final String detail;

    if (!enabled) {
      state = AgentBridgeHealthState.disabled;
      summary = 'Bridge is disabled';
      detail = 'Enable the codex bridge before loading sessions.';
    } else if (errors.isNotEmpty) {
      state = AgentBridgeHealthState.misconfigured;
      summary = 'Bridge config has errors';
      detail = errors.first;
    } else if (projectCount == 0 || command.isEmpty) {
      state = AgentBridgeHealthState.misconfigured;
      summary = 'Bridge config is incomplete';
      detail = projectCount == 0
          ? 'No bridge projects are configured.'
          : 'No bridge command is configured.';
    } else {
      state = AgentBridgeHealthState.healthy;
      summary = 'Bridge service is listening on $port';
      detail =
          'Command: $command | Projects: $projectCount | Confirmation: ${requireConfirmation ? "on" : "off"}';
    }

    return AgentBridgeDiagnostics(
      state: state,
      port: port,
      checkedAt: DateTime.now(),
      summary: summary,
      detail: detail,
      enabled: enabled,
      command: command,
      projectCount: projectCount,
      requireConfirmation: requireConfirmation,
      errors: errors,
    );
  }
}
