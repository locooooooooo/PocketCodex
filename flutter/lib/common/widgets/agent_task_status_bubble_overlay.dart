import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/agent_dashboard_model.dart';

class AgentTaskStatusBubbleOverlay extends StatelessWidget {
  const AgentTaskStatusBubbleOverlay({
    super.key,
    required this.model,
    this.onOpenDashboard,
    this.padding = const EdgeInsets.fromLTRB(14, 18, 14, 0),
  });

  final AgentDashboardModel model;
  final VoidCallback? onOpenDashboard;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: false,
      child: AnimatedBuilder(
        animation: model,
        builder: (context, _) {
          final bubbles = model.visibleTaskStatusBubbles;
          if (bubbles.isEmpty) {
            return const SizedBox.shrink();
          }
          return SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: padding,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < bubbles.length; i++) ...[
                        if (i > 0) const SizedBox(height: 10),
                        _AgentTaskStatusBubbleCard(
                          bubble: bubbles[i],
                          onOpen: () {
                            model.openTaskStatusBubble(bubbles[i].id);
                            onOpenDashboard?.call();
                          },
                          onDismiss: () {
                            model.dismissTaskStatusBubble(bubbles[i].id);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AgentTaskStatusBubbleCard extends StatelessWidget {
  const _AgentTaskStatusBubbleCard({
    required this.bubble,
    required this.onOpen,
    required this.onDismiss,
  });

  final AgentTaskStatusBubble bubble;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = _toneForStatus(bubble.status);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onOpen,
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xEE101827),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: tone.withOpacity(0.5)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 22,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: tone.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _iconForStatus(bubble.status),
                    size: 20,
                    color: tone,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bubble.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        bubble.projectId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: const Color(0xFF93A4C3),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        bubble.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFE2E8F0),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Dismiss',
                  visualDensity: VisualDensity.compact,
                  onPressed: onDismiss,
                  icon: const Icon(
                    Icons.close,
                    size: 18,
                    color: Color(0xFFCBD5E1),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconForStatus(AgentConversationStatus status) {
    switch (status) {
      case AgentConversationStatus.needsConfirmation:
        return Icons.pending_actions_outlined;
      case AgentConversationStatus.completed:
        return Icons.check_circle_outline;
      case AgentConversationStatus.failed:
        return Icons.error_outline;
      case AgentConversationStatus.running:
        return Icons.hourglass_top;
      case AgentConversationStatus.idle:
        return Icons.info_outline;
    }
  }

  Color _toneForStatus(AgentConversationStatus status) {
    switch (status) {
      case AgentConversationStatus.needsConfirmation:
        return const Color(0xFFF59E0B);
      case AgentConversationStatus.completed:
        return const Color(0xFF22C55E);
      case AgentConversationStatus.failed:
        return const Color(0xFFEF4444);
      case AgentConversationStatus.running:
        return const Color(0xFF38BDF8);
      case AgentConversationStatus.idle:
        return const Color(0xFF94A3B8);
    }
  }
}
