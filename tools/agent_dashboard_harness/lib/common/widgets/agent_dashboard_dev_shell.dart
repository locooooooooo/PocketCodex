import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/agent_dashboard_page.dart';
import 'package:flutter_hbb/common/widgets/agent_task_status_bubble_overlay.dart';
import 'package:flutter_hbb/models/agent_dashboard_model.dart';

enum AgentDashboardDevMode {
  full,
  floating,
}

enum _FloatingPreviewState {
  bubble,
  compact,
  expanded,
}

class AgentDashboardDevShell extends StatefulWidget {
  const AgentDashboardDevShell({
    super.key,
    this.mode = AgentDashboardDevMode.full,
    this.useLiveBridge = false,
  });

  final AgentDashboardDevMode mode;
  final bool useLiveBridge;

  @override
  State<AgentDashboardDevShell> createState() => _AgentDashboardDevShellState();
}

class _AgentDashboardDevShellState extends State<AgentDashboardDevShell> {
  late final AgentDashboardModel _model;
  _FloatingPreviewState? _floatingState;
  bool _showPhoneExpandedControls = false;

  @override
  void initState() {
    super.initState();
    _model = widget.useLiveBridge
        ? AgentDashboardModel.webBridge()
        : AgentDashboardModel.dev();
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final floatingMode = widget.mode == AgentDashboardDevMode.floating;
    final floatingState = _floatingState ?? _defaultFloatingState(context);
    final phoneExpandedPreview = floatingMode &&
        floatingState == _FloatingPreviewState.expanded &&
        _isPhonePortrait(MediaQuery.of(context).size);
    return Scaffold(
      backgroundColor: const Color(0xFF070B13),
      body: Stack(
        children: [
          if (floatingMode) _buildFloatingPreviewScaffold(context),
          if (!floatingMode) AgentDashboardPage(model: _model),
          if (floatingMode && floatingState == _FloatingPreviewState.expanded)
            _buildFloatingDashboard(context),
          if (floatingMode && floatingState == _FloatingPreviewState.compact)
            _buildFloatingCompactBar(context),
          if (floatingMode && floatingState == _FloatingPreviewState.bubble)
            _buildFloatingBubble(),
          AgentTaskStatusBubbleOverlay(
            model: _model,
            onOpenDashboard: () {
              if (!floatingMode) {
                return;
              }
              setState(() {
                _floatingState = _FloatingPreviewState.expanded;
              });
            },
            padding: EdgeInsets.fromLTRB(
              14,
              floatingMode ? 18 : 14,
              14,
              0,
            ),
          ),
          SafeArea(
            child: Align(
              alignment: phoneExpandedPreview
                  ? Alignment.bottomRight
                  : Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: phoneExpandedPreview
                    ? _buildPhoneExpandedControlLauncher(floatingMode)
                    : _buildDevControlBar(floatingMode),
              ),
            ),
          ),
        ],
      ),
    );
  }

  _FloatingPreviewState _defaultFloatingState(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final narrowPortrait = _isPhonePortrait(size);
    return narrowPortrait
        ? _FloatingPreviewState.compact
        : _FloatingPreviewState.expanded;
  }

  bool _isPhonePortrait(Size size) =>
      size.width < 600 && size.height >= size.width;

  void _setFloatingState(_FloatingPreviewState next) {
    setState(() {
      _floatingState = next;
      _showPhoneExpandedControls = false;
    });
  }

  Widget _buildFloatingPreviewScaffold(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final isLandscape = screen.width > screen.height;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0B1220),
            Color(0xFF111C2E),
            Color(0xFF090F18),
          ],
        ),
      ),
      child: Column(
        children: [
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0x223D5174)),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.desktop_windows_outlined,
                    color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Mock Remote Session',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                _MockStatusPill(
                  label: isLandscape ? 'landscape preview' : 'portrait preview',
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF04070C),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0x223D5174)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              const Color(0xFF151F31),
                              const Color(0xFF0B111C),
                              const Color(0xFF182536).withOpacity(0.92),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _MockRemoteGridPainter(),
                      ),
                    ),
                    Positioned(
                      top: 22,
                      left: 22,
                      child: _MockRemoteBadge(
                        icon: Icons.screenshot_monitor_outlined,
                        label: 'Remote canvas visible',
                      ),
                    ),
                    Positioned(
                      top: 22,
                      right: 22,
                      child: _MockRemoteBadge(
                        icon: Icons.pan_tool_alt_outlined,
                        label: (_floatingState ??
                                    _defaultFloatingState(context)) ==
                                _FloatingPreviewState.expanded
                            ? 'input blocked by floating dashboard'
                            : 'remote input active',
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          alignment: WrapAlignment.center,
                          children: const [
                            _MockRemoteBadge(
                              icon: Icons.open_with,
                              label: 'drag preview window',
                            ),
                            _MockRemoteBadge(
                              icon: Icons.chat_bubble_outline,
                              label: 'chat and context tabs',
                            ),
                            _MockRemoteBadge(
                              icon: Icons.flash_on_outlined,
                              label: 'hot reload ready',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingDashboard(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > size.height;
    final phonePortrait = _isPhonePortrait(size);
    final width = phonePortrait
        ? (size.width - 24).clamp(320.0, 430.0)
        : (size.width * (isLandscape ? 0.52 : 0.72)).clamp(380.0, 640.0);
    final reservedBottom = phonePortrait ? 118.0 : 96.0;
    final height = phonePortrait
        ? (size.height - reservedBottom).clamp(420.0, 690.0)
        : (size.height * (isLandscape ? 0.76 : 0.72)).clamp(420.0, 780.0);
    final alignment = phonePortrait ? Alignment.topCenter : Alignment.topLeft;
    final padding = EdgeInsets.fromLTRB(
      phonePortrait ? 12 : 14,
      phonePortrait ? 14 : (isLandscape ? 18 : 16),
      phonePortrait ? 12 : 0,
      0,
    );
    return SafeArea(
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: padding,
          child: Semantics(
            container: true,
            label: 'Expanded floating agent dashboard',
            child: SizedBox(
              width: width,
              height: height,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0x553D5174)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x44000000),
                        blurRadius: 28,
                        offset: Offset(0, 14),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: AgentDashboardPage(
                    model: _model,
                    presentation: AgentDashboardPresentation.floatingWindow,
                    header: _buildMockWindowHeader(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingCompactBar(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 0),
          child: AnimatedBuilder(
            animation: _model,
            builder: (context, _) {
              final conversation = _model.selectedConversation;
              final status = conversation == null
                  ? 'Ready'
                  : _model.statusLabelForConversationObject(conversation);
              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.min(
                    420,
                    MediaQuery.of(context).size.width - 28,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Semantics(
                    container: true,
                    label:
                        'Compact floating agent bar. Double tap open dashboard.',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () =>
                          _setFloatingState(_FloatingPreviewState.expanded),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 64),
                        child: Ink(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xEE101827),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0x443B82F6)),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 24,
                                offset: Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: const Color(0x553B82F6),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.smart_toy_outlined,
                                  size: 21,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      conversation?.title ?? 'Agent Dashboard',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      conversation == null
                                          ? 'Waiting for dashboard data'
                                          : '${conversation.projectId} | $status',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: const Color(0xFF93A4C3),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: 48,
                                height: 48,
                                child: IconButton(
                                  tooltip: 'Open dashboard',
                                  onPressed: () => _setFloatingState(
                                    _FloatingPreviewState.expanded,
                                  ),
                                  icon: const Icon(
                                    Icons.open_in_full,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 48,
                                height: 48,
                                child: IconButton(
                                  tooltip: 'Collapse to bubble',
                                  onPressed: () => _setFloatingState(
                                    _FloatingPreviewState.bubble,
                                  ),
                                  icon: const Icon(
                                    Icons.remove_circle_outline,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingBubble() {
    return SafeArea(
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 0, 0),
          child: Semantics(
            button: true,
            label: 'Agent dashboard bubble. Double tap to open compact bar.',
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _setFloatingState(_FloatingPreviewState.compact),
              child: Ink(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xEE101827),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0x334F8CFF)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 20,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(
                      Icons.smart_toy_outlined,
                      color: Colors.white,
                    ),
                    Positioned(
                      right: 12,
                      top: 12,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMockWindowHeader(BuildContext context) {
    return AnimatedBuilder(
      animation: _model,
      builder: (context, _) {
        final conversation = _model.selectedConversation;
        final status = conversation == null
            ? 'Ready'
            : _model.statusLabelForConversationObject(conversation);
        final size = MediaQuery.of(context).size;
        final dense = _isPhonePortrait(size);
        return Container(
          height: dense ? 44 : 52,
          padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 12),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF111827),
                Color(0xFF172036),
              ],
            ),
            border: Border(
              bottom: BorderSide(color: Color(0x223D5174)),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: dense ? 28 : 30,
                height: dense ? 28 : 30,
                decoration: BoxDecoration(
                  color: const Color(0x553B82F6),
                  borderRadius: BorderRadius.circular(dense ? 9 : 10),
                ),
                child: Icon(
                  Icons.smart_toy_outlined,
                  size: dense ? 17 : 18,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: dense ? 8 : 10),
              Expanded(
                child: dense
                    ? Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Agent Dashboard',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          if (conversation != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: const Color(0xFF93A4C3),
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Floating Agent Dashboard',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            conversation == null
                                ? 'Waiting for dashboard data'
                                : '${conversation.projectId} | $status',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: const Color(0xFF93A4C3),
                                    ),
                          ),
                        ],
                      ),
              ),
              SizedBox(
                width: dense ? 44 : 48,
                height: dense ? 44 : 48,
                child: IconButton(
                  tooltip: 'Compact',
                  onPressed: () =>
                      _setFloatingState(_FloatingPreviewState.compact),
                  icon: const Icon(Icons.remove, color: Colors.white),
                ),
              ),
              SizedBox(
                width: dense ? 44 : 48,
                height: dense ? 44 : 48,
                child: IconButton(
                  tooltip: 'Collapse to bubble',
                  onPressed: () =>
                      _setFloatingState(_FloatingPreviewState.bubble),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDevControlBar(bool floatingMode) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xEE121A2F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x334F8CFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            _DevChip(
              icon: floatingMode
                  ? Icons.picture_in_picture_alt_outlined
                  : Icons.dashboard_customize_outlined,
              label: floatingMode
                  ? 'Floating window preview'
                  : 'Dashboard full preview',
            ),
            const _DevChip(
              icon: Icons.flash_on_outlined,
              label: 'flutter run + hot reload',
            ),
            OutlinedButton.icon(
              onPressed: () async {
                await _model.resetDemoState();
                if (floatingMode) {
                  setState(() {
                    _floatingState = _defaultFloatingState(context);
                  });
                }
              },
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('Reset mock data'),
            ),
            OutlinedButton.icon(
              onPressed: () {
                _model.textController.text =
                    'Analyze the current dashboard startup path.';
                _model.sendCurrentPrompt();
              },
              icon: const Icon(Icons.play_arrow_outlined, size: 18),
              label: const Text('Simulate read-only'),
            ),
            OutlinedButton.icon(
              onPressed: () {
                _model.textController.text =
                    'Fix the dashboard mock route and write the patch.';
                _model.sendCurrentPrompt();
              },
              icon: const Icon(Icons.edit_note_outlined, size: 18),
              label: const Text('Simulate confirm'),
            ),
            OutlinedButton.icon(
              onPressed: () {
                _model.textController.text =
                    'Simulate a bridge failure for the dashboard.';
                _model.sendCurrentPrompt();
              },
              icon: const Icon(Icons.error_outline, size: 18),
              label: const Text('Simulate failure'),
            ),
            if (floatingMode)
              OutlinedButton.icon(
                onPressed: () =>
                    _setFloatingState(_FloatingPreviewState.bubble),
                icon: const Icon(Icons.blur_circular_outlined, size: 18),
                label: const Text('Bubble'),
              ),
            if (floatingMode)
              OutlinedButton.icon(
                onPressed: () =>
                    _setFloatingState(_FloatingPreviewState.compact),
                icon: const Icon(Icons.view_agenda_outlined, size: 18),
                label: const Text('Compact bar'),
              ),
            if (floatingMode)
              OutlinedButton.icon(
                onPressed: () =>
                    _setFloatingState(_FloatingPreviewState.expanded),
                icon: const Icon(Icons.open_in_new_outlined, size: 18),
                label: const Text('Expanded panel'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneExpandedControlLauncher(bool floatingMode) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_showPhoneExpandedControls) ...[
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width - 24,
            ),
            child: _buildDevControlBar(floatingMode),
          ),
          const SizedBox(height: 8),
        ],
        Semantics(
          button: true,
          label: _showPhoneExpandedControls
              ? 'Hide preview controls'
              : 'Show preview controls',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () {
                setState(() {
                  _showPhoneExpandedControls = !_showPhoneExpandedControls;
                });
              },
              child: Ink(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xEE121A2F),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0x664F8CFF)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 20,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _showPhoneExpandedControls
                          ? Icons.keyboard_arrow_down
                          : Icons.tune_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _showPhoneExpandedControls
                          ? 'Hide controls'
                          : 'Preview controls',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DevChip extends StatelessWidget {
  const _DevChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x553B82F6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x444F8CFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _MockStatusPill extends StatelessWidget {
  const _MockStatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x3322C55E),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x3355D38A)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFFD8E1F5),
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _MockRemoteBadge extends StatelessWidget {
  const _MockRemoteBadge({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xCC0E1522),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x223D5174)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF93A4C3)),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFD8E1F5),
                ),
          ),
        ],
      ),
    );
  }
}

class _MockRemoteGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0x102D3E5D)
      ..strokeWidth = 1;
    const gap = 28.0;
    for (double x = 0; x <= size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
    for (double y = 0; y <= size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
