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
  final Map<String, Timer> _statusPollers = <String, Timer>{};

  bool get _hasActiveRemoteSession => parent.id.trim().isNotEmpty;

  bool get _routeThroughRemoteSession => _hasActiveRemoteSession;

  bool get _useDirectLocalBridge => !_routeThroughRemoteSession && !isMobile;

  @override
  bool get defersSkillCatalogLoad => _routeThroughRemoteSession;

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
    final response = await http.get(Uri.parse('$_bridgeBaseUrl$path'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Bridge GET $path failed: ${response.statusCode}');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<Map<String, dynamic>> _postJson(
      String path, Map<String, dynamic> body) async {
    if (!_useDirectLocalBridge) {
      throw UnsupportedError(
        'Direct bridge access is only available on the controlled desktop.',
      );
    }
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
    final response =
        await http.delete(Uri.parse('$_bridgeBaseUrl/agent/skills/$skillId'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Bridge delete skill failed: ${response.statusCode}');
    }
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
}
