import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../common.dart';
import '../consts.dart';
import '../desktop/pages/terminal_connection_manager.dart';
import 'agent_dashboard_model.dart';

AgentDashboardRuntime createRustDeskAgentDashboardRuntime(Object parent) {
  if (parent is! FFI) {
    throw ArgumentError.value(
      parent,
      'parent',
      'Expected a Pocket-Codex FFI instance for the agent dashboard runtime.',
    );
  }
  return RustDeskAgentDashboardRuntime(parent);
}

class RustDeskAgentDashboardRuntime implements AgentDashboardRuntime {
  RustDeskAgentDashboardRuntime(this.parent);

  final FFI parent;
  static const _bridgeBaseUrl = 'http://127.0.0.1:17321';
  static const _bridgeEnabledOption = 'codex-bridge-enabled';
  static const _bridgePortOption = 'codex-bridge-port';
  static const _bridgeCommandOption = 'codex-bridge-command';
  static const _bridgeProjectsOption = 'codex-bridge-projects';
  static const _bridgeRequireConfirmationOption =
      'codex-bridge-require-confirmation';
  final Map<String, Timer> _statusPollers = <String, Timer>{};

  bool get _hasActiveRemoteSession => parent.id.trim().isNotEmpty;

  bool get _routeThroughRemoteSession => _hasActiveRemoteSession;

  bool get _useDirectLocalBridge => !_routeThroughRemoteSession && !isMobile;

  String get _resolvedBridgeBaseUrl => 'http://127.0.0.1:$_bridgePort';

  int get _bridgePort {
    final configured = int.tryParse(
      bind.mainGetOptionSync(key: _bridgePortOption).trim(),
    );
    if (configured != null && configured > 0) {
      return configured;
    }
    final uri = Uri.tryParse(_bridgeBaseUrl);
    return uri?.hasPort == true ? uri!.port : 17321;
  }

  @override
  bool get defersSkillCatalogLoad => _routeThroughRemoteSession;

  @override
  bool get supportsBridgeDiagnostics => _useDirectLocalBridge;

  @override
  String get peerId => parent.id;

  @override
  List<String> loadProjectIds() {
    final raw = bind.mainGetOptionSync(key: 'codex-bridge-projects');
    if (raw.trim().isEmpty) {
      return const [AgentDashboardModel.defaultProjectId];
    }
    final decoded = jsonDecode(raw) as List<dynamic>;
    final ids = decoded
        .whereType<Map>()
        .map((e) => e['id']?.toString().trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    return ids.isEmpty ? const [AgentDashboardModel.defaultProjectId] : ids;
  }

  @override
  String loadTerminalContext() {
    if (peerId.isEmpty) return '';
    final terminalFfi = TerminalConnectionManager.getExistingConnection(peerId);
    if (terminalFfi == null || terminalFfi.terminalModels.isEmpty) {
      return '';
    }
    final chunks = <String>[];
    for (final entry in terminalFfi.terminalModels.entries) {
      final transcript = entry.value.getRecentTranscript(maxChars: 4000).trim();
      if (transcript.isEmpty) continue;
      chunks.add('Terminal ${entry.key}:\n$transcript');
    }
    return chunks.join('\n\n');
  }

  @override
  Future<void> dispatchCommand({
    required String requestId,
    required String projectId,
    required String prompt,
    required String mode,
    required bool requireConfirmation,
  }) async {
    if (_routeThroughRemoteSession) {
      await bind.sessionSendAgentCommand(
        sessionId: parent.sessionId,
        requestId: requestId,
        project: projectId,
        prompt: prompt,
        mode: mode,
        requireConfirmation: requireConfirmation,
      );
      return;
    }
    if (!_useDirectLocalBridge) {
      throw Exception(
        'No active remote session is available for agent dispatch.',
      );
    }
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
    final body = buildAgentRunRequestBodyFromEnvelope(envelope);
    if (_routeThroughRemoteSession) {
      debugPrint(
        '[AgentDashboardRuntime] send envelope action=${envelope['action'] ?? envelope['kind']} '
        'request=${body['request_id']} session=${parent.sessionId} peer=$peerId',
      );
      return dispatchCommand(
        requestId: body['request_id']?.toString() ?? const Uuid().v4(),
        projectId:
            body['project']?.toString() ?? AgentDashboardModel.defaultProjectId,
        prompt: body['prompt']?.toString() ?? jsonEncode(envelope),
        mode: body['mode']?.toString() ?? 'read-only',
        requireConfirmation: body['require_confirmation'] == true,
      );
    }
    return _postJson('/agent/run', body).then((_) {});
  }

  Future<Map<String, dynamic>> _getJson(String path) async {
    if (!_useDirectLocalBridge) {
      throw UnsupportedError(
        'Direct bridge access is only available on the controlled desktop.',
      );
    }
    _ensureLocalBridgeReady();
    final response = await http.get(Uri.parse('$_resolvedBridgeBaseUrl$path'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Bridge GET $path failed: ${response.statusCode}');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<List<Map<String, dynamic>>> _getJsonList(String path) async {
    if (!_useDirectLocalBridge) {
      throw UnsupportedError(
        'Direct bridge access is only available on the controlled desktop.',
      );
    }
    _ensureLocalBridgeReady();
    final response = await http.get(Uri.parse('$_resolvedBridgeBaseUrl$path'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Bridge GET $path failed: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> _postJson(
      String path, Map<String, dynamic> body) async {
    if (!_useDirectLocalBridge) {
      throw UnsupportedError(
        'Direct bridge access is only available on the controlled desktop.',
      );
    }
    _ensureLocalBridgeReady();
    final response = await http.post(
      Uri.parse('$_resolvedBridgeBaseUrl$path'),
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

  Future<void> _deleteJson(String path) async {
    if (!_useDirectLocalBridge) {
      throw UnsupportedError(
        'Direct bridge access is only available on the controlled desktop.',
      );
    }
    _ensureLocalBridgeReady();
    final response = await http.delete(
      Uri.parse('$_resolvedBridgeBaseUrl$path'),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Bridge DELETE $path failed: ${response.statusCode}');
    }
  }

  @override
  Future<AgentBridgeDiagnostics?> loadBridgeDiagnostics({
    bool attemptStart = false,
  }) async {
    if (!_useDirectLocalBridge) {
      return null;
    }
    try {
      final raw = bind
          .mainGetCodexBridgeStatusSync(
            attemptStart: attemptStart,
          )
          .trim();
      if (raw.isNotEmpty) {
        final config = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        return _parseBridgeDiagnostics(config);
      }
      final config = await _getJson('/agent/config');
      return _parseBridgeDiagnostics(config);
    } catch (e) {
      return _buildLocalConfigAwareDiagnostics(
        error: e,
        attemptStart: attemptStart,
      );
    }
  }

  @override
  Future<List<Map<String, dynamic>>> loadSessions(
      {String? conversationId}) async {
    if (_routeThroughRemoteSession) {
      debugPrint(
        '[AgentDashboardRuntime] request sessions conversation=$conversationId '
        'session=${parent.sessionId} peer=$peerId',
      );
      await dispatchEnvelope({
        'requestId': const Uuid().v4(),
        'kind': 'list_sessions',
        'action': 'list_sessions',
        if (conversationId != null) 'conversationId': conversationId,
        'mode': 'read-only',
        'requireConfirmation': false,
        'route': {
          'projectId': AgentDashboardModel.defaultProjectId,
        },
      });
      return const [];
    }
    if (!_useDirectLocalBridge) {
      return const [];
    }
    final decoded = await _getJsonList('/agent/sessions');
    return decoded
        .map((e) => _normalizeSessionSummary(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  Future<Map<String, dynamic>?> loadSessionDetail(String sessionId,
      {int? cursor, int pageSize = 40, String? conversationId}) async {
    if (_routeThroughRemoteSession) {
      await dispatchEnvelope({
        'requestId': const Uuid().v4(),
        'kind': cursor == null ? 'get_session' : 'page_session',
        'action': cursor == null ? 'get_session' : 'page_session',
        if (conversationId != null) 'conversationId': conversationId,
        'mode': 'read-only',
        'requireConfirmation': false,
        'sessionId': sessionId,
        if (cursor != null) 'cursor': cursor,
        'pageSize': pageSize,
        'route': {
          'projectId': AgentDashboardModel.defaultProjectId,
        },
      });
      return null;
    }
    if (!_useDirectLocalBridge) {
      return null;
    }
    final suffix = cursor == null
        ? '/agent/sessions/$sessionId'
        : '/agent/sessions/$sessionId/page?cursor=$cursor&page_size=$pageSize';
    return _normalizeSessionDetail(await _getJson(suffix));
  }

  @override
  Future<List<Map<String, dynamic>>> loadSkills(
      {String? conversationId}) async {
    if (_routeThroughRemoteSession) {
      await dispatchEnvelope({
        'requestId': const Uuid().v4(),
        'kind': 'list_skills',
        'action': 'list_skills',
        if (conversationId != null) 'conversationId': conversationId,
        'mode': 'read-only',
        'requireConfirmation': false,
        'route': {
          'projectId': AgentDashboardModel.defaultProjectId,
        },
      });
      return const [];
    }
    if (!_useDirectLocalBridge) {
      return const [];
    }
    return _getJsonList('/agent/skills');
  }

  @override
  Future<Map<String, dynamic>> upsertSkill(Map<String, dynamic> payload) {
    if (!_useDirectLocalBridge) {
      throw UnsupportedError(
        'Skill management is only available from the controlled desktop bridge.',
      );
    }
    return _postJson('/agent/skills', payload);
  }

  @override
  Future<void> deleteSkill(String skillId) async {
    if (!_useDirectLocalBridge) {
      throw UnsupportedError(
        'Skill management is only available from the controlled desktop bridge.',
      );
    }
    await _deleteJson('/agent/skills/$skillId');
  }

  @override
  Future<Map<String, dynamic>> syncSkills() {
    if (!_useDirectLocalBridge) {
      throw UnsupportedError(
        'Skill sync is only available from the controlled desktop bridge.',
      );
    }
    return _postJson('/agent/skills/sync', const {});
  }

  @override
  Future<Map<String, dynamic>> transcribeVoice(Map<String, dynamic> payload) {
    if (!_useDirectLocalBridge) {
      throw UnsupportedError(
        'Voice transcription is only available from the controlled desktop bridge.',
      );
    }
    return _postJson('/agent/voice/transcribe', payload);
  }

  @override
  Future<String> recordVoiceClipBase64({
    Duration duration = const Duration(seconds: 5),
  }) async {
    if (!isAndroid) {
      throw UnsupportedError('Voice recording is only available on Android.');
    }
    if (!await AndroidPermissionManager.check(kRecordAudio)) {
      final granted = await AndroidPermissionManager.request(kRecordAudio);
      if (!granted) {
        throw Exception('RECORD_AUDIO permission was denied.');
      }
    }
    final result = await parent.invokeMethod('record_agent_voice_clip', {
      'durationMs': duration.inMilliseconds,
    });
    final audioBase64 = result.toString().trim();
    if (audioBase64.isEmpty) {
      throw Exception('Recorded voice clip is empty.');
    }
    return audioBase64;
  }

  @override
  Future<Map<String, dynamic>?> requestTaskStatus({
    required String requestId,
    required String projectId,
  }) async {
    final normalizedRequestId = requestId.trim();
    if (normalizedRequestId.isEmpty) {
      return null;
    }
    if (_routeThroughRemoteSession) {
      await bind.sessionSendAgentCommand(
        sessionId: parent.sessionId,
        requestId: normalizedRequestId,
        project: projectId,
        prompt: '',
        mode: 'status',
        requireConfirmation: false,
      );
      return null;
    }
    if (!_useDirectLocalBridge) {
      return null;
    }
    try {
      final item = await _getJson('/agent/tasks/$normalizedRequestId');
      return {
        'request_id': item['request_id'] ?? normalizedRequestId,
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
    if (!_routeThroughRemoteSession) {
      return;
    }
    _statusPollers[requestId]?.cancel();
    _statusPollers[requestId] = Timer.periodic(const Duration(seconds: 2), (
      timer,
    ) async {
      try {
        await bind.sessionSendAgentCommand(
          sessionId: parent.sessionId,
          requestId: requestId,
          project: conversation.projectId,
          prompt: '',
          mode: 'status',
          requireConfirmation: false,
        );
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
    final port = _parsePort(config['port']) ?? _bridgePort;
    final command = config['command']?.toString().trim() ?? '';
    final requireConfirmation = config['require_confirmation'] == true;
    final healthy = config['healthy'] == true;
    final healthError = config['health_error']?.toString().trim() ?? '';
    final lastStartError = config['last_start_error']?.toString().trim() ?? '';
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
      detail = 'Set codex bridge enabled before requesting sessions.';
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
    } else if (!healthy) {
      state = AgentBridgeHealthState.unreachable;
      summary = 'Bridge service is not reachable';
      detail = [
        'The local bridge is enabled, but port $port is not serving requests yet.',
        if (lastStartError.isNotEmpty) 'Start failed: $lastStartError',
        if (healthError.isNotEmpty) 'Probe: $healthError',
      ].join(' ');
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

  int? _parsePort(dynamic raw) {
    return int.tryParse(raw?.toString() ?? '');
  }

  AgentBridgeDiagnostics _buildLocalConfigAwareDiagnostics({
    required Object error,
    required bool attemptStart,
  }) {
    final status = _readLocalBridgeStatusSnapshot(attemptStart: attemptStart);
    final enabled = (status?['enabled'] == true) ||
        bind.mainGetOptionSync(key: _bridgeEnabledOption).trim() == 'Y';
    final rawCommand = bind.mainGetOptionSync(key: _bridgeCommandOption).trim();
    final command = rawCommand.isEmpty ? 'codex' : rawCommand;
    final requireConfirmation = (status?['require_confirmation'] == true) ||
        bind.mainGetOptionSync(key: _bridgeRequireConfirmationOption).trim() !=
            'N';
    final configuredProjects = _readConfiguredProjects();
    final projects = configuredProjects.items;
    final projectCount = projects.length;
    final errors = <String>[];
    final rawError = error.toString().trim();
    if (rawError.isNotEmpty) {
      errors.add(rawError);
    }
    if (configuredProjects.parseError.isNotEmpty) {
      errors.add(configuredProjects.parseError);
    }
    for (final project in projects) {
      final id = project['id']?.toString().trim() ?? '';
      final path = project['path']?.toString().trim() ?? '';
      if (id.isEmpty || path.isEmpty) {
        errors.add('Bridge project entry is incomplete.');
        continue;
      }
      if (!_pathLooksPresent(path)) {
        errors.add('Project `$id` path does not exist: $path');
      }
    }

    if (!enabled) {
      return AgentBridgeDiagnostics(
        state: AgentBridgeHealthState.disabled,
        port: _bridgePort,
        checkedAt: DateTime.now(),
        summary: 'Bridge is disabled',
        detail:
            'Set `codex-bridge-enabled` to `Y` before requesting local bridge sessions.',
        enabled: false,
        command: command,
        projectCount: projectCount,
        requireConfirmation: requireConfirmation,
        errors: errors,
      );
    }

    if (projectCount == 0 ||
        configuredProjects.parseError.isNotEmpty ||
        errors.length > 1) {
      return AgentBridgeDiagnostics(
        state: AgentBridgeHealthState.misconfigured,
        port: _bridgePort,
        checkedAt: DateTime.now(),
        summary: projectCount == 0 || configuredProjects.parseError.isNotEmpty
            ? 'Bridge config is incomplete'
            : 'Bridge config has errors',
        detail: projectCount == 0
            ? 'No bridge projects are configured.'
            : errors.firstWhere(
                (item) => item != rawError,
                orElse: () => rawError,
              ),
        enabled: true,
        command: command,
        projectCount: projectCount,
        requireConfirmation: requireConfirmation,
        errors: errors,
      );
    }

    final diagnostics =
        buildBridgeUnreachableDiagnostics(error: error, port: _bridgePort);
    final healthError = status?['health_error']?.toString().trim() ?? '';
    final lastStartError = status?['last_start_error']?.toString().trim() ?? '';
    final startupHint = lastStartError.isNotEmpty
        ? 'Start failed: $lastStartError'
        : (healthError.isNotEmpty ? 'Probe: $healthError' : '');
    return AgentBridgeDiagnostics(
      state: diagnostics.state,
      port: _bridgePort,
      checkedAt: diagnostics.checkedAt,
      summary: diagnostics.summary,
      detail: [
        diagnostics.detail,
        if (startupHint.isNotEmpty) startupHint,
        'Command: ${command.isEmpty ? "codex" : command} | Projects: $projectCount | Confirmation: ${requireConfirmation ? "on" : "off"}',
      ].join(' '),
      enabled: true,
      command: command,
      projectCount: projectCount,
      requireConfirmation: requireConfirmation,
      errors: diagnostics.errors,
    );
  }

  _LocalBridgeProjects _readConfiguredProjects() {
    final raw = bind.mainGetOptionSync(key: _bridgeProjectsOption).trim();
    if (raw.isEmpty) {
      return const _LocalBridgeProjects();
    }
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return _LocalBridgeProjects(
        items: decoded
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(),
      );
    } catch (e) {
      return _LocalBridgeProjects(
        parseError: 'Invalid bridge projects JSON: $e',
      );
    }
  }

  bool _pathLooksPresent(String path) {
    final normalized = path.trim();
    if (normalized.isEmpty) return false;
    if (normalized.length >= 3 &&
        normalized[1] == ':' &&
        (normalized[2] == '\\' || normalized[2] == '/')) {
      return true;
    }
    return normalized.startsWith('/') || normalized.startsWith('\\\\');
  }

  Map<String, dynamic>? _readLocalBridgeStatusSnapshot({
    required bool attemptStart,
  }) {
    try {
      final raw =
          bind.mainGetCodexBridgeStatusSync(attemptStart: attemptStart).trim();
      if (raw.isEmpty) {
        return null;
      }
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  void _ensureLocalBridgeReady() {
    final status = _readLocalBridgeStatusSnapshot(attemptStart: true);
    if (status == null) {
      return;
    }
    final diagnostics = _parseBridgeDiagnostics(status);
    if (diagnostics.state == AgentBridgeHealthState.healthy) {
      return;
    }
    final parts = <String>[
      diagnostics.summary,
      diagnostics.detail,
      ...diagnostics.errors,
    ];
    final seen = <String>{};
    final message = parts
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && seen.add(item))
        .join(' ');
    throw Exception(message);
  }
}

class _LocalBridgeProjects {
  const _LocalBridgeProjects({
    this.items = const <Map<String, dynamic>>[],
    this.parseError = '',
  });

  final List<Map<String, dynamic>> items;
  final String parseError;
}
