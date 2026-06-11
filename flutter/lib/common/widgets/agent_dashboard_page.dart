import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/agent_dashboard_message_presentation.dart';
import 'package:flutter_hbb/models/agent_dashboard_model.dart';
import 'package:provider/provider.dart';

enum AgentDashboardPresentation {
  fullPage,
  floatingWindow,
}

class _AgentDashboardColors {
  static const appBackground = Color(0xFF020617);
  static const remoteDim = Color(0xFF07111F);
  static const floatingSurface = Color(0xFF0F172A);
  static const elevatedSurface = Color(0xFF172033);
  static const elevatedSurfaceAlt = Color(0xFF101827);
  static const hairline = Color(0xFF24324A);
  static const primary = Color(0xFF3B82F6);
  static const ready = Color(0xFF22C55E);
  static const running = Color(0xFF38BDF8);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFEF4444);
  static const text = Color(0xFFF8FAFC);
  static const secondaryText = Color(0xFFA8B3C7);
  static const mutedText = Color(0xFF71809B);
}

class _AgentDashboardMetrics {
  static const minTouchTarget = 48.0;
  static const compactTouchTarget = 44.0;
  static const panelRadius = 18.0;
  static const controlRadius = 12.0;
  static const sheetRadius = 24.0;
}

class AgentDashboardPage extends StatelessWidget {
  const AgentDashboardPage({
    super.key,
    required this.model,
    this.presentation = AgentDashboardPresentation.fullPage,
    this.header,
  });

  final AgentDashboardModel model;
  final AgentDashboardPresentation presentation;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return _AgentDashboardPresentationScope(
      presentation: presentation,
      child: ChangeNotifierProvider.value(
        value: model,
        child: Consumer<AgentDashboardModel>(
          builder: (context, dashboard, child) {
            return FutureBuilder<void>(
              future: dashboard.ensureLoaded(),
              builder: (context, snapshot) {
                final conversation = dashboard.selectedConversation;
                if (!dashboard.loaded || conversation == null) {
                  return _buildLoading();
                }
                if (presentation == AgentDashboardPresentation.floatingWindow) {
                  return _FloatingAgentDashboardScaffold(
                    model: dashboard,
                    header: header,
                  );
                }
                return _FullPageAgentDashboardScaffold(model: dashboard);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Material(
      color: const Color(0xFF0B1020),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _FullPageAgentDashboardScaffold extends StatelessWidget {
  const _FullPageAgentDashboardScaffold({required this.model});

  final AgentDashboardModel model;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0B1020),
              Color(0xFF121A2F),
              Color(0xFF081019),
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isMobileWorkspace = constraints.maxWidth < 760;
              if (isMobileWorkspace) {
                return _MobileAgentDashboardScaffold(model: model);
              }
              final useStackedLayout = constraints.maxWidth < 980;
              if (useStackedLayout) {
                return Column(
                  children: [
                    _WorkspaceTopBar(model: model),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        children: [
                          _GlassPanel(
                            padding: const EdgeInsets.all(0),
                            child: SizedBox(
                              height: 260,
                              child: _ConversationRail(model: model),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _GlassPanel(
                            padding: const EdgeInsets.all(0),
                            child: _ChatWorkspace(model: model),
                          ),
                          const SizedBox(height: 12),
                          _GlassPanel(
                            padding: const EdgeInsets.all(0),
                            child: _InspectorPanel(model: model),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 296,
                      child: _GlassPanel(
                        padding: const EdgeInsets.all(0),
                        child: _ConversationRail(model: model),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 7,
                      child: Column(
                        children: [
                          _WorkspaceTopBar(model: model),
                          const SizedBox(height: 12),
                          Expanded(
                            child: _GlassPanel(
                              padding: const EdgeInsets.all(0),
                              child: _ChatWorkspace(model: model),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 332,
                      child: _GlassPanel(
                        padding: const EdgeInsets.all(0),
                        child: _InspectorPanel(model: model),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MobileAgentDashboardScaffold extends StatefulWidget {
  const _MobileAgentDashboardScaffold({required this.model});

  final AgentDashboardModel model;

  @override
  State<_MobileAgentDashboardScaffold> createState() =>
      _MobileAgentDashboardScaffoldState();
}

class _MobileAgentDashboardScaffoldState
    extends State<_MobileAgentDashboardScaffold> {
  int _selectedPanelIndex = 0;
  static const _fullTabLabels = [
    'Chat',
    'Timeline',
    'Sessions',
    'Context',
    'Skills'
  ];
  static const _compactTabLabels = ['Chat', 'Sessions', 'More'];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactNavigation = constraints.maxWidth < 560;
        final labels = compactNavigation ? _compactTabLabels : _fullTabLabels;
        final selectedTabIndex = compactNavigation
            ? _compactSelectedTabIndex(_selectedPanelIndex)
            : _selectedPanelIndex;
        final navHeight = compactNavigation
            ? _AgentDashboardMetrics.compactTouchTarget
            : _AgentDashboardMetrics.minTouchTarget;
        return Column(
          children: [
            if (!compactNavigation)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: _WorkspaceTopBar(model: widget.model),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                compactNavigation ? 8 : 12,
                compactNavigation ? 8 : 12,
                compactNavigation ? 8 : 12,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _ConversationLauncher(
                      model: widget.model,
                      onTap: _openConversationSheet,
                      panelVisible: false,
                      dense: compactNavigation,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: navHeight,
                    height: navHeight,
                    child: IconButton.filledTonal(
                      tooltip: 'New conversation',
                      onPressed: widget.model.createConversation,
                      icon: const Icon(Icons.add_comment_outlined, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                compactNavigation ? 8 : 12,
                compactNavigation ? 8 : 12,
                compactNavigation ? 8 : 12,
                0,
              ),
              child: SizedBox(
                height: navHeight,
                child: _FloatingTabSwitcher(
                  labels: labels,
                  selectedIndex: selectedTabIndex,
                  compact: compactNavigation,
                  height: navHeight,
                  onChanged: (value) {
                    _handleTabChanged(value, compactNavigation);
                  },
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(compactNavigation ? 8 : 12),
                child: IndexedStack(
                  index: _selectedPanelIndex,
                  children: [
                    _GlassPanel(
                      padding: const EdgeInsets.all(0),
                      child: _ChatWorkspace(
                        model: widget.model,
                        compactHeader: true,
                        showHeader: !compactNavigation,
                        denseInput: compactNavigation,
                      ),
                    ),
                    _GlassPanel(
                      padding: const EdgeInsets.all(0),
                      child: _TimelinePanel(model: widget.model),
                    ),
                    _GlassPanel(
                      padding: const EdgeInsets.all(0),
                      child: _SessionsPanel(
                        model: widget.model,
                        onSessionRestored: _showChatPanel,
                      ),
                    ),
                    _GlassPanel(
                      padding: const EdgeInsets.all(0),
                      child: _InspectorPanel(model: widget.model),
                    ),
                    _GlassPanel(
                      padding: const EdgeInsets.all(0),
                      child: _SkillsPanel(model: widget.model),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  int _compactSelectedTabIndex(int panelIndex) {
    if (panelIndex == 0) return 0;
    if (panelIndex == 2) return 1;
    return 2;
  }

  void _showChatPanel() {
    if (!mounted || _selectedPanelIndex == 0) {
      return;
    }
    setState(() {
      _selectedPanelIndex = 0;
    });
  }

  void _handleTabChanged(int value, bool compactNavigation) {
    if (!compactNavigation) {
      setState(() {
        _selectedPanelIndex = value;
      });
      return;
    }
    if (value == 0) {
      setState(() {
        _selectedPanelIndex = 0;
      });
      return;
    }
    if (value == 1) {
      setState(() {
        _selectedPanelIndex = 2;
      });
      return;
    }
    unawaited(_openMoreSheet());
  }

  Future<void> _openMoreSheet() async {
    final selected = await _showDashboardPanelSheet(
      context,
      selectedPanelIndex: _selectedPanelIndex,
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selectedPanelIndex = selected;
    });
  }

  Future<void> _openConversationSheet() async {
    await _showDashboardOverlayPanel<void>(
      context,
      builder: (overlayContext, close) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                height: MediaQuery.of(overlayContext).size.height * 0.72,
                child: _ConversationPickerPanel(
                  model: widget.model,
                  onClose: close,
                  onConversationSelected: close,
                  showCloseButton: true,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FloatingAgentDashboardScaffold extends StatefulWidget {
  const _FloatingAgentDashboardScaffold({
    required this.model,
    this.header,
  });

  final AgentDashboardModel model;
  final Widget? header;

  @override
  State<_FloatingAgentDashboardScaffold> createState() =>
      _FloatingAgentDashboardScaffoldState();
}

class _FloatingAgentDashboardScaffoldState
    extends State<_FloatingAgentDashboardScaffold> {
  bool _showConversationPanel = false;
  int _selectedPanelIndex = 0;
  static const _fullTabLabels = [
    'Chat',
    'Timeline',
    'Sessions',
    'Context',
    'Skills'
  ];
  static const _compactTabLabels = ['Chat', 'Sessions', 'More'];

  void _toggleConversationPanel() {
    setState(() {
      _showConversationPanel = !_showConversationPanel;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _AgentDashboardColors.appBackground,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _AgentDashboardColors.appBackground,
              _AgentDashboardColors.floatingSurface,
              _AgentDashboardColors.remoteDim,
            ],
          ),
        ),
        child: Column(
          children: [
            if (widget.header != null) widget.header!,
            LayoutBuilder(
              builder: (context, constraints) {
                final stackedHeader = constraints.maxWidth < 560;
                final compactNavigation = constraints.maxWidth < 500;
                final labels =
                    compactNavigation ? _compactTabLabels : _fullTabLabels;
                final selectedTabIndex = compactNavigation
                    ? _compactSelectedTabIndex(_selectedPanelIndex)
                    : _selectedPanelIndex;
                final navHeight = compactNavigation
                    ? _AgentDashboardMetrics.compactTouchTarget
                    : _AgentDashboardMetrics.minTouchTarget;
                final launcher = _ConversationLauncher(
                  model: widget.model,
                  onTap: _toggleConversationPanel,
                  panelVisible: _showConversationPanel,
                  dense: compactNavigation,
                );
                final tabs = _FloatingTabSwitcher(
                  labels: labels,
                  selectedIndex: selectedTabIndex,
                  compact: compactNavigation,
                  height: navHeight,
                  onChanged: (value) {
                    _handleTabChanged(value, compactNavigation);
                  },
                );
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    compactNavigation ? 8 : 12,
                    compactNavigation ? 6 : 10,
                    compactNavigation ? 8 : 12,
                    compactNavigation ? 6 : 10,
                  ),
                  child: stackedHeader
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            launcher,
                            SizedBox(height: compactNavigation ? 6 : 8),
                            SizedBox(
                              height: navHeight,
                              child: tabs,
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(child: launcher),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 360,
                              height: navHeight,
                              child: tabs,
                            ),
                          ],
                        ),
                );
              },
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 760;
                  final compactPanel = constraints.maxWidth < 500;
                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      compactPanel ? 8 : 12,
                      0,
                      compactPanel ? 8 : 12,
                      compactPanel ? 8 : 12,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final mainPane = Row(
                          children: [
                            if (isWide && _showConversationPanel) ...[
                              SizedBox(
                                width: 292,
                                child: _ConversationPickerPanel(
                                  model: widget.model,
                                  onClose: _toggleConversationPanel,
                                  onConversationSelected:
                                      _toggleConversationPanel,
                                  showCloseButton: true,
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: IndexedStack(
                                index: _selectedPanelIndex,
                                children: [
                                  _GlassPanel(
                                    padding: const EdgeInsets.all(0),
                                    child: _ChatWorkspace(
                                      model: widget.model,
                                      compactHeader: true,
                                      showHeader: !compactPanel,
                                      denseInput: compactPanel,
                                    ),
                                  ),
                                  _GlassPanel(
                                    padding: const EdgeInsets.all(0),
                                    child: _TimelinePanel(model: widget.model),
                                  ),
                                  _GlassPanel(
                                    padding: const EdgeInsets.all(0),
                                    child: _SessionsPanel(
                                      model: widget.model,
                                      onSessionRestored: _showChatPanel,
                                    ),
                                  ),
                                  _GlassPanel(
                                    padding: const EdgeInsets.all(0),
                                    child: _InspectorPanel(model: widget.model),
                                  ),
                                  _GlassPanel(
                                    padding: const EdgeInsets.all(0),
                                    child: _SkillsPanel(model: widget.model),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                        if (isWide || !_showConversationPanel) {
                          return mainPane;
                        }
                        return Stack(
                          children: [
                            Positioned.fill(child: mainPane),
                            Positioned.fill(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: _toggleConversationPanel,
                                child: ColoredBox(
                                  color: Colors.black.withOpacity(0.28),
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: SafeArea(
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: SizedBox(
                                    width: constraints.maxWidth,
                                    height: math.max(
                                      320,
                                      constraints.maxHeight - 16,
                                    ),
                                    child: _ConversationPickerPanel(
                                      model: widget.model,
                                      onClose: _toggleConversationPanel,
                                      onConversationSelected:
                                          _toggleConversationPanel,
                                      showCloseButton: true,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _compactSelectedTabIndex(int panelIndex) {
    if (panelIndex == 0) return 0;
    if (panelIndex == 2) return 1;
    return 2;
  }

  void _showChatPanel() {
    if (!mounted || _selectedPanelIndex == 0) {
      return;
    }
    setState(() {
      _selectedPanelIndex = 0;
      _showConversationPanel = false;
    });
  }

  void _handleTabChanged(int value, bool compactNavigation) {
    if (!compactNavigation) {
      setState(() {
        _selectedPanelIndex = value;
      });
      return;
    }
    if (value == 0) {
      setState(() {
        _selectedPanelIndex = 0;
      });
      return;
    }
    if (value == 1) {
      setState(() {
        _selectedPanelIndex = 2;
      });
      return;
    }
    unawaited(_openMoreSheet());
  }

  Future<void> _openMoreSheet() async {
    final selected = await _showDashboardPanelSheet(
      context,
      selectedPanelIndex: _selectedPanelIndex,
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selectedPanelIndex = selected;
    });
  }
}

class _WorkspaceTopBar extends StatelessWidget {
  const _WorkspaceTopBar({required this.model});

  final AgentDashboardModel model;

  @override
  Widget build(BuildContext context) {
    final conversation = model.selectedConversation!;
    final status = model.statusForConversationObject(conversation);
    final statusLabel = model.statusLabelForConversationObject(conversation);
    final bridgeDiagnostics = model.bridgeDiagnostics;
    final compact = MediaQuery.of(context).size.width < 520;
    return _GlassPanel(
      padding:
          EdgeInsets.fromLTRB(compact ? 14 : 18, 14, compact ? 14 : 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Agent Dashboard',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (compact
                    ? Theme.of(context).textTheme.titleMedium
                    : Theme.of(context).textTheme.titleLarge)
                ?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${conversation.projectId} | ${_sessionLabel(conversation.sessionRef)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF8EA2C7),
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: compact ? 6 : 8,
            runSpacing: compact ? 6 : 8,
            children: [
              _StatusBadge(
                label: statusLabel,
                color: _statusColor(status),
                dense: compact,
              ),
              _StatusBadge(
                label: conversation.profile.trim().isEmpty
                    ? 'profile:auto'
                    : 'profile:${conversation.profile}',
                color: const Color(0xFF8B5CF6),
                dense: compact,
              ),
              _StatusBadge(
                label: conversation.includeTerminalContext
                    ? 'terminal:on'
                    : 'terminal:off',
                color: const Color(0xFF0EA5E9),
                dense: compact,
              ),
              _StatusBadge(
                label: conversation.includeConversationHistory
                    ? 'history:on'
                    : 'history:off',
                color: const Color(0xFF22C55E),
                dense: compact,
              ),
              if (model.supportsBridgeDiagnostics)
                _StatusBadge(
                  label: bridgeDiagnostics?.badgeLabel ??
                      (model.bridgeDiagnosticsLoading
                          ? 'bridge:checking'
                          : 'bridge:unknown'),
                  color: bridgeDiagnostics == null
                      ? _AgentDashboardColors.running
                      : _bridgeHealthColor(bridgeDiagnostics.state),
                  dense: compact,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConversationRail extends StatelessWidget {
  const _ConversationRail({
    required this.model,
    this.onConversationSelected,
    this.compactTiles = false,
  });

  final AgentDashboardModel model;
  final VoidCallback? onConversationSelected;
  final bool compactTiles;

  @override
  Widget build(BuildContext context) {
    final items = model.visibleConversations;
    final selectedConversationId = model.selectedConversation?.id;
    final compactControls = compactTiles;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            compactControls ? 12 : 16,
            compactControls ? 10 : 16,
            compactControls ? 12 : 16,
            compactControls ? 8 : 12,
          ),
          child: Column(
            children: [
              if (!compactControls) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Recent conversations',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'New conversation',
                      onPressed: model.createConversation,
                      icon: const Icon(Icons.add_comment_outlined,
                          color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  compactControls
                      ? '${items.length} conversations | ${model.unreadConversationCount} unread'
                      : 'Showing ${items.length} conversations | ${model.unreadConversationCount} unread',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF93A4C3),
                      ),
                ),
              ),
              SizedBox(height: compactControls ? 8 : 12),
              TextField(
                onChanged: model.setSearchQuery,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration(
                  hintText: 'Search conversations',
                  prefixIcon: const Icon(Icons.search, size: 18),
                ),
              ),
              SizedBox(height: compactControls ? 8 : 10),
              Wrap(
                spacing: 8,
                runSpacing: compactControls ? 6 : 8,
                children: [
                  _ConversationFilterChip(
                    label: 'Active',
                    selected:
                        model.listFilter == AgentConversationListFilter.active,
                    onTap: () => model.setListFilter(
                      AgentConversationListFilter.active,
                    ),
                  ),
                  _ConversationFilterChip(
                    label: 'Pinned',
                    selected:
                        model.listFilter == AgentConversationListFilter.pinned,
                    onTap: () => model.setListFilter(
                      AgentConversationListFilter.pinned,
                    ),
                  ),
                  _ConversationFilterChip(
                    label: 'Archived',
                    selected: model.listFilter ==
                        AgentConversationListFilter.archived,
                    onTap: () => model.setListFilter(
                      AgentConversationListFilter.archived,
                    ),
                  ),
                  _ConversationFilterChip(
                    label: 'All',
                    selected:
                        model.listFilter == AgentConversationListFilter.all,
                    onTap: () => model.setListFilter(
                      AgentConversationListFilter.all,
                    ),
                  ),
                ],
              ),
              if (!compactControls) ...[
                const SizedBox(height: 10),
                _ProjectFilterField(model: model),
              ],
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0x223D5174)),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    'No conversations',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF7C8CAB),
                        ),
                  ),
                )
              : ListView.separated(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final selected = selectedConversationId == item.id;
                    return _ConversationTile(
                      model: model,
                      conversation: item,
                      selected: selected,
                      onSelected: onConversationSelected,
                      compact: compactTiles,
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemCount: items.length,
                ),
        ),
      ],
    );
  }
}

class _ConversationLauncher extends StatelessWidget {
  const _ConversationLauncher({
    required this.model,
    required this.onTap,
    required this.panelVisible,
    this.dense = false,
  });

  final AgentDashboardModel model;
  final VoidCallback onTap;
  final bool panelVisible;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final conversation = model.selectedConversation!;
    final status = model.statusForConversationObject(conversation);
    final statusLabel = model.statusLabelForConversationObject(conversation);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: dense ? _AgentDashboardMetrics.compactTouchTarget : 0,
        ),
        child: Ink(
          padding: EdgeInsets.symmetric(
            horizontal: dense ? 10 : 12,
            vertical: dense ? 7 : 10,
          ),
          decoration: BoxDecoration(
            color: const Color(0xCC131B2C),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x223D5174)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.forum_outlined,
                color: Colors.white,
                size: dense ? 17 : 18,
              ),
              SizedBox(width: dense ? 8 : 10),
              Expanded(
                child: dense
                    ? Text(
                        conversation.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            conversation.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${conversation.projectId}  |  $statusLabel',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: const Color(0xFF8EA2C7),
                                    ),
                          ),
                        ],
                      ),
              ),
              if (dense) ...[
                const SizedBox(width: 8),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _statusColor(status),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ],
              if (model.unreadConversationCount > 0)
                Padding(
                  padding: EdgeInsets.only(left: dense ? 8 : 0, right: 8),
                  child: Container(
                    constraints: BoxConstraints(minWidth: dense ? 30 : 64),
                    height: dense ? 20 : 22,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFEF4444),
                      borderRadius: BorderRadius.all(Radius.circular(999)),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      dense
                          ? '${model.unreadConversationCount}'
                          : 'Unread ${model.unreadConversationCount}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ),
              Icon(
                panelVisible ? Icons.expand_less : Icons.expand_more,
                color: Color(0xFF93A4C3),
                size: dense ? 24 : 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationPickerPanel extends StatelessWidget {
  const _ConversationPickerPanel({
    required this.model,
    this.onClose,
    this.onConversationSelected,
    this.showCloseButton = true,
  });

  final AgentDashboardModel model;
  final VoidCallback? onClose;
  final VoidCallback? onConversationSelected;
  final bool showCloseButton;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: const EdgeInsets.all(0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Switch conversation',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'New conversation',
                  onPressed: model.createConversation,
                  icon: const Icon(
                    Icons.add_comment_outlined,
                    color: Colors.white,
                  ),
                ),
                if (showCloseButton)
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () {
                      if (onClose != null) {
                        onClose!();
                      } else {
                        Navigator.of(context).maybePop();
                      }
                    },
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0x223D5174)),
          Expanded(
            child: _ConversationRail(
              model: model,
              onConversationSelected: onConversationSelected ?? onClose,
              compactTiles: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingTabSwitcher extends StatelessWidget {
  const _FloatingTabSwitcher({
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
    this.compact = false,
    this.height = _AgentDashboardMetrics.minTouchTarget,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final bool compact;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: _AgentDashboardColors.elevatedSurfaceAlt.withOpacity(0.86),
        borderRadius:
            BorderRadius.circular(_AgentDashboardMetrics.controlRadius),
        border: Border.all(color: _AgentDashboardColors.hairline),
      ),
      padding: EdgeInsets.all(compact ? 3 : 4),
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++) ...[
            if (index > 0) const SizedBox(width: 4),
            Expanded(
              child: _FloatingTabButton(
                label: labels[index],
                selected: selectedIndex == index,
                compact: compact,
                onTap: () => onChanged(index),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FloatingTabButton extends StatelessWidget {
  const _FloatingTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.compact,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label tab',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color:
                selected ? _AgentDashboardColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (compact
                      ? Theme.of(context).textTheme.labelMedium
                      : Theme.of(context).textTheme.labelLarge)
                  ?.copyWith(
                color: selected
                    ? _AgentDashboardColors.text
                    : _AgentDashboardColors.secondaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.model,
    required this.conversation,
    required this.selected,
    this.onSelected,
    this.compact = false,
  });

  final AgentDashboardModel model;
  final AgentConversation conversation;
  final bool selected;
  final VoidCallback? onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final status = model.statusForConversationObject(conversation);
    final statusLabel = model.statusLabelForConversationObject(conversation);
    final unread = model.conversationHasUnreadForConversation(conversation);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          model.selectConversation(conversation.id);
          onSelected?.call();
        },
        onLongPress: () => _showConversationActions(context),
        child: Container(
          padding: compact
              ? const EdgeInsets.symmetric(horizontal: 10, vertical: 9)
              : const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: selected ? const Color(0x264F8CFF) : const Color(0x99131B2C),
            border: Border.all(
              color:
                  selected ? const Color(0xFF4F8CFF) : const Color(0x223D5174),
              width: selected ? 1 : 0.8,
            ),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x224F8CFF),
                      blurRadius: 16,
                      spreadRadius: 1,
                    )
                  ]
                : null,
          ),
          child: compact
              ? _buildCompact(context, statusLabel, unread)
              : _buildRich(context, status, statusLabel, unread),
        ),
      ),
    );
  }

  Widget _buildRich(
    BuildContext context,
    AgentConversationStatus status,
    String statusLabel,
    bool unread,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                conversation.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
              ),
            ),
            if (conversation.pinned) ...[
              const SizedBox(width: 8),
              _StatusBadge(
                label: 'Pinned',
                color: const Color(0xFFF59E0B),
                dense: true,
              ),
            ],
            if (unread)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.brightness_1,
                    size: 10, color: Color(0xFF4F8CFF)),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${conversation.projectId} | ${_sessionLabel(conversation.sessionRef)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF8EA2C7),
              ),
        ),
        const SizedBox(height: 8),
        Text(
          model.latestSnippet(conversation),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFFB8C2D8),
                height: 1.35,
              ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _StatusBadge(
              label: statusLabel,
              color: _statusColor(status),
              dense: true,
            ),
            Text(
              _formatUpdatedAt(conversation.updatedAt),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF7082A3),
                  ),
            ),
            if (conversation.draft.trim().isNotEmpty)
              _StatusBadge(
                label: 'Draft saved',
                color: const Color(0xFFF59E0B),
                dense: true,
              ),
            if (conversation.archived)
              _StatusBadge(
                label: 'Archived',
                color: const Color(0xFF93A4C3),
                dense: true,
              ),
            Text(
              '${conversation.messages.length} msgs',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF7082A3),
                fontFeatures: const [],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCompact(
    BuildContext context,
    String statusLabel,
    bool unread,
  ) {
    final details = [
      conversation.projectId,
      statusLabel,
      if (conversation.pinned) 'Pinned',
      if (unread) 'Unread',
      '${conversation.messages.length} msgs',
    ].join(' | ');
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      conversation.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Colors.white,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w600,
                          ),
                    ),
                  ),
                  if (unread)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(
                        Icons.circle,
                        size: 8,
                        color: Color(0xFF4F8CFF),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                details,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF93A4C3),
                    ),
              ),
              if (conversation.draft.trim().isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  'Draft saved',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFF59E0B),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Icon(
          selected ? Icons.check_circle : Icons.chevron_right,
          size: 18,
          color: selected ? const Color(0xFF4F8CFF) : const Color(0xFF7082A3),
        ),
      ],
    );
  }

  void _showConversationActions(BuildContext context) {
    final nameController = TextEditingController(text: conversation.title);
    final floatingDialogRoute =
        presentationOf(context) == AgentDashboardPresentation.floatingWindow;
    if (floatingDialogRoute) {
      unawaited(_showDashboardOverlayPanel<void>(
        context,
        builder: (overlayContext, close) {
          return Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _buildConversationActionsPanel(
                  overlayContext,
                  nameController,
                  close,
                ),
              ),
            ),
          );
        },
      ));
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _buildConversationActionsPanel(
              sheetContext,
              nameController,
              () => Navigator.of(sheetContext).pop(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildConversationActionsPanel(
    BuildContext context,
    TextEditingController nameController,
    VoidCallback close,
  ) {
    return _GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Conversation actions',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: nameController,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration(
              hintText: 'Conversation name',
              prefixIcon: const Icon(Icons.edit_outlined, size: 18),
            ),
            onSubmitted: (value) {
              model.renameConversation(conversation.id, value);
              close();
            },
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    model.toggleConversationPinned(conversation.id);
                    close();
                  },
                  icon: Icon(
                    conversation.pinned
                        ? Icons.push_pin_outlined
                        : Icons.push_pin,
                    size: 18,
                  ),
                  label: Text(conversation.pinned ? 'Unpin' : 'Pin'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    model.toggleConversationArchived(conversation.id);
                    close();
                  },
                  icon: Icon(
                    conversation.archived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                    size: 18,
                  ),
                  label: Text(conversation.archived ? 'Restore' : 'Archive'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    model.updateConversationSettings(
                      conversationId: conversation.id,
                      draft: '',
                    );
                    close();
                  },
                  icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                  label: const Text('Clear draft'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFF87171),
                    side: const BorderSide(color: Color(0x33F87171)),
                  ),
                  onPressed: () {
                    model.deleteConversation(conversation.id);
                    close();
                  },
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Delete'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChatWorkspace extends StatelessWidget {
  const _ChatWorkspace({
    required this.model,
    this.compactHeader = false,
    this.showHeader = true,
    this.denseInput = false,
  });

  final AgentDashboardModel model;
  final bool compactHeader;
  final bool showHeader;
  final bool denseInput;

  @override
  Widget build(BuildContext context) {
    final conversation = model.selectedConversation!;
    final statusDetail = model.statusDetailForConversationObject(conversation);
    final needsConfirmation =
        model.conversationNeedsConfirmationForConversation(conversation);
    final busy = model.isConversationBusyForConversation(conversation);
    final canLoadOlderHistory =
        model.canLoadMoreSessionHistoryForConversation(conversation);
    final historyLoading =
        model.isSessionHistoryLoadingForConversation(conversation);
    return Column(
      children: [
        if (showHeader) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(18, compactHeader ? 14 : 16, 18, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        conversation.title,
                        maxLines: compactHeader ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: (compactHeader
                                ? Theme.of(context).textTheme.titleMedium
                                : Theme.of(context).textTheme.titleLarge)
                            ?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        statusDetail.isEmpty
                            ? 'Send task text to the local Codex bridge'
                            : statusDetail,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF8EA2C7),
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'New conversation',
                  onPressed: model.createConversation,
                  icon:
                      const Icon(Icons.add_circle_outline, color: Colors.white),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0x223D5174)),
        ],
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final messageMaxWidth = math.min(
                520.0,
                math.max(
                  120.0,
                  constraints.maxWidth - (denseInput ? 38 : 64),
                ),
              );
              final compactMessages = constraints.maxWidth < 640;
              final inputHorizontal = denseInput ? 10.0 : 16.0;
              final inputBottom = denseInput ? 10.0 : 16.0;
              return DashChat(
                currentUser: model.me,
                onSend: (_) => model.sendCurrentPrompt(),
                messages: conversation.messages,
                messageListOptions: MessageListOptions(
                  onLoadEarlier: canLoadOlderHistory && !historyLoading
                      ? () => model.loadMoreSessionHistory(conversation.id)
                      : null,
                ),
                scrollToBottomOptions: ScrollToBottomOptions(
                  disabled: false,
                  scrollToBottomBuilder: _agentDashboardScrollToBottomButton,
                ),
                messageOptions: MessageOptions(
                  showOtherUsersAvatar: true,
                  showOtherUsersName: false,
                  maxWidth: messageMaxWidth,
                  currentUserContainerColor: const Color(0xFF2F6BFF),
                  containerColor: const Color(0xFF1B2537),
                  textColor: Colors.white,
                  borderRadius: 16,
                  messageTextBuilder: (message, _, __) {
                    final isOwn = message.user.id == model.me.id;
                    return _MessageBubble(
                      message: message,
                      isOwn: isOwn,
                      maxWidth: messageMaxWidth,
                      compact: compactMessages,
                    );
                  },
                  top: (_, previousMessage, nextMessage) {
                    final isTopOfTimeline =
                        previousMessage == null && canLoadOlderHistory;
                    if (!isTopOfTimeline) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Align(
                        alignment: Alignment.center,
                        child: _LoadOlderHistoryChip(
                          loading: historyLoading,
                          onPressed: historyLoading
                              ? null
                              : () => model.loadMoreSessionHistory(
                                    conversation.id,
                                  ),
                        ),
                      ),
                    );
                  },
                  avatarBuilder: (user, _, __) {
                    final isOwn = user.id == model.me.id;
                    return _AvatarBadge(
                      label: isOwn ? 'ME' : 'AG',
                      color: isOwn
                          ? const Color(0xFF2F6BFF)
                          : const Color(0xFF10B981),
                    );
                  },
                ),
                inputOptions: InputOptions(
                  textController: model.textController,
                  focusNode: model.inputFocusNode,
                  sendOnEnter: true,
                  alwaysShowSend: true,
                  inputToolbarPadding: EdgeInsets.fromLTRB(
                    inputHorizontal,
                    denseInput ? 2 : 0,
                    inputHorizontal,
                    inputBottom,
                  ),
                  inputDisabled: false,
                  inputDecoration: _inputDecoration(
                    hintText: needsConfirmation
                        ? 'Waiting for approval before continuing.'
                        : busy
                            ? 'Agent is thinking. You can queue the next instruction.'
                            : 'Message your desktop agent',
                    trailingIcon: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _VoiceButton(model: model),
                    ),
                  ),
                  sendButtonBuilder: (_) => _SendButton(model: model),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LoadOlderHistoryChip extends StatelessWidget {
  const _LoadOlderHistoryChip({
    required this.loading,
    required this.onPressed,
  });

  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Load older history for current Codex session',
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          foregroundColor: _AgentDashboardColors.secondaryText,
          side: const BorderSide(color: _AgentDashboardColors.hairline),
        ),
        icon: loading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.history, size: 15),
        label: Text(loading ? 'Loading history' : 'Load older history'),
      ),
    );
  }
}

class _InspectorPanel extends StatelessWidget {
  const _InspectorPanel({required this.model});

  final AgentDashboardModel model;

  @override
  Widget build(BuildContext context) {
    final conversation = model.selectedConversation!;
    final statusDetail = model.statusDetailForConversationObject(conversation);
    final historyPreview = model.composeHistoryPreview(conversation);
    final terminalPreview = model.composeTerminalContext(conversation);
    final sessionRef = conversation.sessionRef.trim();
    final profile = conversation.profile.trim();
    final selectedSkillCount = conversation.selectedSkillIds.length;
    final attachmentSummary = <String>[
      if (conversation.includeConversationHistory) 'conversation history',
      if (conversation.includeTerminalContext) 'terminal transcript',
    ];
    final sessionController =
        TextEditingController(text: conversation.sessionRef);
    final profileController = TextEditingController(text: conversation.profile);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PanelHeader(
          title: 'Context',
          subtitle:
              'Define where the next command runs and what extra context gets attached.',
          icon: Icons.tune_outlined,
        ),
        const SizedBox(height: 14),
        _SectionBlock(
          title: 'Next run',
          child: Column(
            children: [
              _ContextSummaryRow(
                icon: Icons.work_outline,
                label: 'Project',
                value: conversation.projectId,
              ),
              const SizedBox(height: 10),
              _ContextSummaryRow(
                icon: conversation.threadMode == 'continue'
                    ? Icons.history_toggle_off
                    : Icons.fiber_new_outlined,
                label: 'Thread',
                value: conversation.threadMode == 'continue'
                    ? (sessionRef.isEmpty
                        ? 'Continue the bound Codex thread'
                        : 'Continue ${_shortSessionId(sessionRef)}')
                    : 'Start a new Codex thread',
              ),
              const SizedBox(height: 10),
              _ContextSummaryRow(
                icon: Icons.tune_outlined,
                label: 'Profile',
                value: profile.isEmpty ? 'Default profile' : profile,
              ),
              const SizedBox(height: 10),
              _ContextSummaryRow(
                icon: Icons.attachment_outlined,
                label: 'Attached',
                value: attachmentSummary.isEmpty
                    ? 'Nothing extra will be attached'
                    : attachmentSummary.join(' + '),
              ),
              const SizedBox(height: 10),
              _ContextSummaryRow(
                icon: Icons.extension_outlined,
                label: 'Skills',
                value: selectedSkillCount == 0
                    ? 'No skills selected'
                    : '$selectedSkillCount selected',
              ),
              if (statusDetail.isNotEmpty) ...[
                const SizedBox(height: 10),
                _ContextSummaryRow(
                  icon: Icons.bolt_outlined,
                  label: 'Latest status',
                  value: statusDetail,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SectionBlock(
          title: 'Execution target',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose the workspace, Codex thread binding, and optional profile override.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _AgentDashboardColors.secondaryText,
                      height: 1.4,
                    ),
              ),
              const SizedBox(height: 12),
              _ProjectSelectorField(
                value: conversation.projectId,
                projects: model.availableProjects,
                hintText: 'Project',
                prefixIcon: const Icon(Icons.work_outline, size: 18),
                onSelected: (value) {
                  model.updateConversationSettings(
                    conversationId: conversation.id,
                    projectId: value,
                  );
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sessionController,
                minLines: 1,
                style: const TextStyle(color: _AgentDashboardColors.text),
                decoration: _inputDecoration(
                  hintText: 'Leave empty for a new Codex session',
                  prefixIcon: const Icon(Icons.link_outlined, size: 18),
                ),
                onSubmitted: (value) => model.updateConversationSettings(
                  conversationId: conversation.id,
                  sessionRef: value.trim(),
                  threadMode: value.trim().isEmpty ? 'new' : 'continue',
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment<String>(
                    value: 'new',
                    label: Text('New thread'),
                    icon: Icon(Icons.fiber_new_outlined, size: 16),
                  ),
                  ButtonSegment<String>(
                    value: 'continue',
                    label: Text('Continue'),
                    icon: Icon(Icons.history_toggle_off, size: 16),
                  ),
                ],
                selected: {conversation.threadMode},
                showSelectedIcon: false,
                style: ButtonStyle(
                  minimumSize: WidgetStateProperty.all(
                    const Size(0, _AgentDashboardMetrics.minTouchTarget),
                  ),
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return _AgentDashboardColors.primary.withOpacity(0.18);
                    }
                    return _AgentDashboardColors.floatingSurface
                        .withOpacity(0.86);
                  }),
                  foregroundColor:
                      WidgetStateProperty.all(_AgentDashboardColors.text),
                  side: WidgetStateProperty.resolveWith((states) {
                    return BorderSide(
                      color: states.contains(WidgetState.selected)
                          ? _AgentDashboardColors.primary
                          : _AgentDashboardColors.hairline,
                    );
                  }),
                ),
                onSelectionChanged: (selection) {
                  final nextMode =
                      selection.contains('continue') ? 'continue' : 'new';
                  model.updateConversationSettings(
                    conversationId: conversation.id,
                    threadMode: nextMode,
                    sessionRef:
                        nextMode == 'new' ? '' : conversation.sessionRef,
                  );
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: profileController,
                style: const TextStyle(color: _AgentDashboardColors.text),
                decoration: _inputDecoration(
                  hintText: 'default profile',
                  prefixIcon: const Icon(Icons.tune_outlined, size: 18),
                ),
                onSubmitted: (value) => model.updateConversationSettings(
                  conversationId: conversation.id,
                  profile: value.trim(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SectionBlock(
          title: 'Attached context',
          child: Column(
            children: [
              _ToggleRow(
                title: 'Include conversation history',
                subtitle:
                    'Use recent messages from this conversation as prompt context.',
                value: conversation.includeConversationHistory,
                onChanged: (value) => model.updateConversationSettings(
                  conversationId: conversation.id,
                  includeConversationHistory: value,
                ),
              ),
              const SizedBox(height: 10),
              _ToggleRow(
                title: 'Include terminal transcript',
                subtitle:
                    'Attach recent terminal output from the controlled machine.',
                value: conversation.includeTerminalContext,
                onChanged: (value) => model.updateConversationSettings(
                  conversationId: conversation.id,
                  includeTerminalContext: value,
                ),
              ),
            ],
          ),
        ),
        if (historyPreview.isNotEmpty || terminalPreview.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionBlock(
            title: 'Attached content preview',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (historyPreview.isNotEmpty) ...[
                  Text(
                    'Conversation history',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: _AgentDashboardColors.secondaryText,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  _ContextPreview(text: historyPreview),
                ],
                if (historyPreview.isNotEmpty && terminalPreview.isNotEmpty)
                  const SizedBox(height: 14),
                if (terminalPreview.isNotEmpty) ...[
                  Text(
                    'Terminal transcript',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: _AgentDashboardColors.secondaryText,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  _ContextPreview(text: terminalPreview),
                ],
              ],
            ),
          ),
        ],
        if (historyPreview.isEmpty && terminalPreview.isEmpty) ...[
          const SizedBox(height: 16),
          _SectionBlock(
            title: 'Context preview',
            child: const _DashboardEmptyState(
              icon: Icons.subject_outlined,
              title: 'No attached context',
              detail:
                  'Enable conversation history or terminal transcript to see what will be attached to the next prompt.',
              compact: true,
            ),
          ),
        ],
      ],
    );
  }
}

class _TimelinePanel extends StatelessWidget {
  const _TimelinePanel({required this.model});

  final AgentDashboardModel model;

  @override
  Widget build(BuildContext context) {
    final conversation = model.selectedConversation!;
    final items = model.timelineForConversationObject(conversation);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PanelHeader(
          title: 'Timeline',
          subtitle: 'Structured task events from the current conversation.',
          icon: Icons.timeline_outlined,
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          const _DashboardEmptyState(
            icon: Icons.timeline_outlined,
            title: 'No timeline events',
            detail: 'Agent status updates will appear here as work progresses.',
          ),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SectionBlock(
              title: item['stage']?.toString() ?? 'event',
              child: Text(
                item['summary']?.toString() ?? '',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _AgentDashboardColors.text,
                      height: 1.45,
                    ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SessionsPanel extends StatefulWidget {
  const _SessionsPanel({
    required this.model,
    this.onSessionRestored,
  });

  final AgentDashboardModel model;
  final VoidCallback? onSessionRestored;

  @override
  State<_SessionsPanel> createState() => _SessionsPanelState();
}

class _SessionsPanelState extends State<_SessionsPanel> {
  final Set<String> _collapsedProjects = <String>{};
  String? _restoringSessionId;
  bool _loadingOlderHistory = false;
  bool _refreshingSessionCatalog = false;
  bool _autoRefreshRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoRefreshSessionCatalog();
    });
  }

  @override
  void didUpdateWidget(covariant _SessionsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model != widget.model) {
      _autoRefreshRequested = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoRefreshSessionCatalog();
      });
    }
  }

  void _autoRefreshSessionCatalog() {
    if (!mounted ||
        _autoRefreshRequested ||
        widget.model.sessionsLoaded ||
        _refreshingSessionCatalog) {
      return;
    }
    _autoRefreshRequested = true;
    unawaited(_refreshSessionCatalog());
  }

  Future<void> _refreshSessionCatalog() async {
    if (_refreshingSessionCatalog) {
      return;
    }
    setState(() {
      _refreshingSessionCatalog = true;
    });
    try {
      await widget.model.reloadSessionCatalog();
    } finally {
      if (mounted) {
        setState(() {
          _refreshingSessionCatalog = false;
        });
      }
    }
  }

  Future<void> _refreshBridgeDiagnostics() async {
    await widget.model.refreshBridgeDiagnostics();
  }

  Future<void> _restoreSession(String sessionId) async {
    if (sessionId.trim().isEmpty || _restoringSessionId != null) {
      return;
    }
    setState(() {
      _restoringSessionId = sessionId;
    });
    try {
      await widget.model.restoreSessionAsCurrentConversation(sessionId);
      widget.onSessionRestored?.call();
    } finally {
      if (mounted) {
        setState(() {
          _restoringSessionId = null;
        });
      }
    }
  }

  Future<void> _loadOlderHistory(String conversationId) async {
    if (_loadingOlderHistory) {
      return;
    }
    setState(() {
      _loadingOlderHistory = true;
    });
    try {
      await widget.model.loadMoreSessionHistory(conversationId);
    } finally {
      if (mounted) {
        setState(() {
          _loadingOlderHistory = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final conversation = model.selectedConversation!;
    final historyLoading = _loadingOlderHistory ||
        model.isSessionHistoryLoadingForConversation(
          conversation,
        );
    final sessions = model.filteredSessionSummaries;
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final session in sessions) {
      final projectId = model.sessionProjectId(session);
      grouped.putIfAbsent(projectId, () => []).add(session);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PanelHeader(
          title: 'Sessions',
          subtitle: 'Open a desktop Codex session as the active conversation.',
          icon: Icons.history_outlined,
        ),
        const SizedBox(height: 12),
        if (model.supportsBridgeDiagnostics) ...[
          _BridgeStatusCard(
            diagnostics: model.bridgeDiagnostics,
            loading: model.bridgeDiagnosticsLoading,
            lastSessionCatalogError: model.lastSessionCatalogError,
            onRefresh: model.bridgeDiagnosticsLoading
                ? null
                : _refreshBridgeDiagnostics,
          ),
          const SizedBox(height: 12),
        ],
        if (!model.sessionsLoaded)
          _DashboardEmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Session index not loaded',
            detail:
                'Open the bridge session catalog again after the desktop agent is reachable.',
            tone: _AgentDashboardColors.warning,
            actionLabel:
                _refreshingSessionCatalog ? 'Refreshing...' : 'Refresh',
            actionIcon: Icons.refresh_outlined,
            onAction: _refreshingSessionCatalog ? null : _refreshSessionCatalog,
          ),
        if (model.sessionsLoaded && sessions.isEmpty)
          _DashboardEmptyState(
            icon: Icons.folder_off_outlined,
            title: model.projectFilter == null
                ? 'No sessions'
                : 'No sessions for ${model.projectFilter}',
            detail:
                'Sessions created by desktop Codex will appear here when the catalog is available.',
            actionLabel: model.projectFilter == null ? null : 'Show all',
            actionIcon: Icons.filter_alt_off_outlined,
            onAction: model.projectFilter == null
                ? null
                : () {
                    model.setProjectFilter(null);
                  },
          ),
        ...grouped.entries.expand((entry) {
          final collapsed = _collapsedProjects.contains(entry.key);
          final containsSelectedSession = entry.value.any((session) {
            final sessionId = session['id']?.toString() ?? '';
            return conversation.sessionRef == sessionId;
          });
          return [
            Padding(
              padding: const EdgeInsets.only(top: 18, bottom: 8),
              child: _SessionProjectHeader(
                projectId: entry.key,
                count: entry.value.length,
                collapsed: collapsed,
                containsSelectedSession: containsSelectedSession,
                onTap: () {
                  setState(() {
                    if (collapsed) {
                      _collapsedProjects.remove(entry.key);
                    } else {
                      _collapsedProjects.add(entry.key);
                    }
                  });
                },
              ),
            ),
            if (!collapsed)
              ...entry.value.map((session) {
                final sessionId = session['id']?.toString() ?? '';
                final selected = conversation.sessionRef == sessionId;
                final restoring = _restoringSessionId == sessionId;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _SessionSummaryCard(
                    session: session,
                    projectId: entry.key,
                    projectPath: model.sessionProjectPath(session),
                    selected: selected,
                    restoring: restoring,
                    onTap: () => _restoreSession(sessionId),
                  ),
                );
              }),
          ];
        }),
        if (conversation.sessionRef.trim().isNotEmpty &&
            model.canLoadMoreSessionHistoryForConversation(conversation)) ...[
          const SizedBox(height: 8),
          Semantics(
            button: true,
            label: 'Load older history for current Codex session',
            child: OutlinedButton.icon(
              onPressed: historyLoading
                  ? null
                  : () => _loadOlderHistory(conversation.id),
              icon: historyLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.history, size: 16),
              label: Text(
                historyLoading ? 'Loading history' : 'Load older history',
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ProjectFilterField extends StatelessWidget {
  const _ProjectFilterField({required this.model});

  final AgentDashboardModel model;

  @override
  Widget build(BuildContext context) {
    return _ProjectSelectorField(
      value: model.projectFilter,
      projects: model.availableProjects,
      hintText: 'All projects',
      prefixIcon: const Icon(Icons.folder_outlined, size: 18),
      includeAll: true,
      onSelected: model.setProjectFilter,
    );
  }
}

class _ProjectSelectorField extends StatelessWidget {
  const _ProjectSelectorField({
    required this.value,
    required this.projects,
    required this.hintText,
    required this.prefixIcon,
    required this.onSelected,
    this.includeAll = false,
  });

  final String? value;
  final List<String> projects;
  final String hintText;
  final Widget prefixIcon;
  final ValueChanged<String?> onSelected;
  final bool includeAll;

  @override
  Widget build(BuildContext context) {
    final selectedLabel =
        value?.trim().isNotEmpty == true ? value!.trim() : hintText;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        final selected = await _showDashboardOverlayPanel<String?>(
          context,
          builder: (overlayContext, close) {
            return Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 420, maxHeight: 420),
                child: _GlassPanel(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            hintText,
                            style: Theme.of(overlayContext)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: close,
                            icon: const Icon(Icons.close, color: Colors.white),
                          ),
                        ],
                      ),
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            if (includeAll)
                              _ProjectSheetTile(
                                label: 'All projects',
                                selected:
                                    value == null || value!.trim().isEmpty,
                                onTap: close,
                              ),
                            ...projects.map(
                              (project) => _ProjectSheetTile(
                                label: project,
                                selected: value == project,
                                onTap: () => close(project),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
        if (selected != null || includeAll) {
          onSelected(selected);
        }
      },
      child: InputDecorator(
        decoration: _inputDecoration(
          hintText: hintText,
          prefixIcon: prefixIcon,
          trailingIcon: const Icon(
            Icons.arrow_drop_down,
            color: Color(0xFF9FB1D5),
          ),
        ),
        child: Text(
          selectedLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}

class _ProjectSheetTile extends StatelessWidget {
  const _ProjectSheetTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? const Color(0x264F8CFF) : const Color(0x66131B2C),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  selected ? const Color(0xFF4F8CFF) : const Color(0x223D5174),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              if (selected)
                const Icon(Icons.check, size: 18, color: Color(0xFF6DA2FF)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkillsPanel extends StatelessWidget {
  const _SkillsPanel({required this.model});

  final AgentDashboardModel model;

  @override
  Widget build(BuildContext context) {
    final conversation = model.selectedConversation!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PanelHeader(
          title: 'Skills',
          subtitle: 'Pick reusable assistant capabilities for this run.',
          icon: Icons.extension_outlined,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: Semantics(
            button: true,
            label: model.skillsLoading
                ? 'Skills catalog request in progress'
                : 'Reload skills catalog',
            child: OutlinedButton.icon(
              onPressed: model.skillsLoading ? null : model.reloadSkillCatalog,
              icon: model.skillsLoading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 16),
              label: Text(model.skillsLoading ? 'Loading' : 'Reload'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (model.skillsLoading && model.skillCatalog.isEmpty)
          const _DashboardEmptyState(
            icon: Icons.sync,
            title: 'Loading skills catalog',
            detail:
                'Waiting for the controlled desktop to return available skills.',
            tone: _AgentDashboardColors.primary,
          ),
        if (!model.skillsLoading && !model.skillsLoaded)
          _DashboardEmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Skills catalog not loaded',
            detail:
                'Reload after the desktop bridge is reachable to fetch available skills.',
            tone: _AgentDashboardColors.warning,
            actionLabel: 'Reload skills',
            actionIcon: Icons.refresh,
            onAction: model.reloadSkillCatalog,
          ),
        if (!model.skillsLoading &&
            model.skillsLoaded &&
            model.skillCatalog.isEmpty)
          _DashboardEmptyState(
            icon: Icons.extension_off_outlined,
            title: 'No skills available',
            detail:
                'Skills discovered by the local Codex environment will appear here.',
            actionLabel: 'Check again',
            actionIcon: Icons.refresh,
            onAction: model.reloadSkillCatalog,
          ),
        ...model.skillCatalog.map((skill) {
          final skillId = skill['id']?.toString() ?? '';
          final selected = conversation.selectedSkillIds.contains(skillId);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SkillCatalogCard(
              skill: skill,
              selected: selected,
              onChanged: () {
                final next = List<String>.from(conversation.selectedSkillIds);
                if (selected) {
                  next.remove(skillId);
                } else {
                  next.add(skillId);
                }
                model.updateConversationSettings(
                  conversationId: conversation.id,
                  selectedSkillIds: next,
                );
              },
            ),
          );
        }),
      ],
    );
  }
}

class _ContextSummaryRow extends StatelessWidget {
  const _ContextSummaryRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _AgentDashboardColors.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 16,
            color: _AgentDashboardColors.secondaryText,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: _AgentDashboardColors.secondaryText,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _AgentDashboardColors.text,
                      height: 1.4,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _AgentDashboardColors.primary.withOpacity(0.16),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _AgentDashboardColors.primary.withOpacity(0.32),
            ),
          ),
          child: Icon(icon, size: 20, color: _AgentDashboardColors.text),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: _AgentDashboardColors.text,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _AgentDashboardColors.secondaryText,
                      height: 1.35,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DashboardEmptyState extends StatelessWidget {
  const _DashboardEmptyState({
    required this.icon,
    required this.title,
    required this.detail,
    this.tone = _AgentDashboardColors.primary,
    this.compact = false,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Color tone;
  final bool compact;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$title. $detail',
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(compact ? 12 : 16),
        decoration: BoxDecoration(
          color: _AgentDashboardColors.elevatedSurface.withOpacity(0.52),
          borderRadius:
              BorderRadius.circular(_AgentDashboardMetrics.controlRadius),
          border: Border.all(color: tone.withOpacity(0.28)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: compact ? 32 : 40,
              height: compact ? 32 : 40,
              decoration: BoxDecoration(
                color: tone.withOpacity(0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: tone, size: compact ? 18 : 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: _AgentDashboardColors.text,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _AgentDashboardColors.secondaryText,
                          height: 1.4,
                        ),
                  ),
                  if (actionLabel != null) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: onAction,
                        icon: Icon(actionIcon ?? Icons.refresh, size: 16),
                        label: Text(actionLabel!),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionProjectHeader extends StatelessWidget {
  const _SessionProjectHeader({
    required this.projectId,
    required this.count,
    required this.collapsed,
    required this.containsSelectedSession,
    required this.onTap,
  });

  final String projectId;
  final int count;
  final bool collapsed;
  final bool containsSelectedSession;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = containsSelectedSession
        ? _AgentDashboardColors.ready
        : _AgentDashboardColors.secondaryText;
    final label = collapsed
        ? 'Expand $projectId sessions'
        : 'Collapse $projectId sessions';
    return Semantics(
      button: true,
      expanded: !collapsed,
      selected: containsSelectedSession,
      label: label,
      child: InkWell(
        borderRadius:
            BorderRadius.circular(_AgentDashboardMetrics.controlRadius),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: _AgentDashboardMetrics.minTouchTarget,
          ),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: containsSelectedSession
                  ? _AgentDashboardColors.ready.withOpacity(0.08)
                  : Colors.transparent,
              borderRadius:
                  BorderRadius.circular(_AgentDashboardMetrics.controlRadius),
              border: Border.all(
                color: containsSelectedSession
                    ? _AgentDashboardColors.ready.withOpacity(0.24)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  collapsed
                      ? Icons.folder_outlined
                      : Icons.folder_open_outlined,
                  size: 18,
                  color: tone,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    projectId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _AgentDashboardColors.text,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color:
                        _AgentDashboardColors.elevatedSurface.withOpacity(0.72),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _AgentDashboardColors.hairline),
                  ),
                  child: Text(
                    count.toString(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: _AgentDashboardColors.secondaryText,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                if (containsSelectedSession) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.radio_button_checked,
                    size: 16,
                    color: _AgentDashboardColors.ready,
                  ),
                ],
                const SizedBox(width: 8),
                Icon(
                  collapsed ? Icons.expand_more : Icons.expand_less,
                  size: 20,
                  color: _AgentDashboardColors.secondaryText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionSummaryCard extends StatelessWidget {
  const _SessionSummaryCard({
    required this.session,
    required this.projectId,
    required this.projectPath,
    required this.selected,
    required this.restoring,
    required this.onTap,
  });

  final Map<String, dynamic> session;
  final String projectId;
  final String projectPath;
  final bool selected;
  final bool restoring;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sessionId = session['id']?.toString() ?? '';
    final title = session['title']?.toString().trim();
    final updatedAt = session['updatedAt']?.toString() ??
        session['updated_at']?.toString() ??
        '';
    final displayTitle = title == null || title.isEmpty ? sessionId : title;
    final shortId = _shortSessionId(sessionId);
    final meta = [
      if (projectPath.trim().isNotEmpty) projectPath.trim() else projectId,
      if (updatedAt.isNotEmpty) _formatSessionUpdatedAt(updatedAt),
    ].join('  |  ');
    return Semantics(
      button: true,
      selected: selected,
      label: selected
          ? 'Current session $displayTitle'
          : 'Restore session $displayTitle',
      child: InkWell(
        borderRadius:
            BorderRadius.circular(_AgentDashboardMetrics.controlRadius),
        onTap: restoring ? null : onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 68),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: selected
                  ? _AgentDashboardColors.primary.withOpacity(0.18)
                  : _AgentDashboardColors.elevatedSurface.withOpacity(0.62),
              borderRadius:
                  BorderRadius.circular(_AgentDashboardMetrics.controlRadius),
              border: Border.all(
                color: selected
                    ? _AgentDashboardColors.primary
                    : _AgentDashboardColors.hairline,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: selected
                        ? _AgentDashboardColors.primary.withOpacity(0.24)
                        : _AgentDashboardColors.floatingSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? _AgentDashboardColors.primary.withOpacity(0.6)
                          : _AgentDashboardColors.hairline,
                    ),
                  ),
                  child: Icon(
                    selected
                        ? Icons.check_circle_outline
                        : restoring
                            ? Icons.sync
                            : Icons.history,
                    size: 19,
                    color: selected
                        ? _AgentDashboardColors.ready
                        : restoring
                            ? _AgentDashboardColors.running
                            : _AgentDashboardColors.secondaryText,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: _AgentDashboardColors.text,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w600,
                              height: 1.25,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: _AgentDashboardColors.secondaryText,
                            ),
                      ),
                      if (shortId.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          restoring
                              ? 'Restoring session...'
                              : selected
                                  ? 'Current conversation'
                                  : shortId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: selected
                                        ? _AgentDashboardColors.ready
                                        : restoring
                                            ? _AgentDashboardColors.running
                                            : _AgentDashboardColors.mutedText,
                                    fontFamily: 'monospace',
                                  ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.restore_outlined,
                  size: 20,
                  color: selected
                      ? _AgentDashboardColors.ready
                      : _AgentDashboardColors.secondaryText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SkillCatalogCard extends StatelessWidget {
  const _SkillCatalogCard({
    required this.skill,
    required this.selected,
    required this.onChanged,
  });

  final Map<String, dynamic> skill;
  final bool selected;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final skillId = skill['id']?.toString() ?? '';
    final title = skill['title']?.toString().trim();
    final description = skill['description']?.toString().trim() ?? '';
    final displayTitle = title == null || title.isEmpty ? skillId : title;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Skill $displayTitle',
      child: InkWell(
        borderRadius:
            BorderRadius.circular(_AgentDashboardMetrics.controlRadius),
        onTap: onChanged,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: _AgentDashboardMetrics.minTouchTarget,
          ),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(12, 10, 14, 12),
            decoration: BoxDecoration(
              color: selected
                  ? _AgentDashboardColors.primary.withOpacity(0.16)
                  : _AgentDashboardColors.elevatedSurface.withOpacity(0.58),
              borderRadius:
                  BorderRadius.circular(_AgentDashboardMetrics.controlRadius),
              border: Border.all(
                color: selected
                    ? _AgentDashboardColors.primary
                    : _AgentDashboardColors.hairline,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: selected,
                  visualDensity: VisualDensity.compact,
                  activeColor: _AgentDashboardColors.primary,
                  checkColor: _AgentDashboardColors.text,
                  onChanged: (_) => onChanged(),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: _AgentDashboardColors.text,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          description,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: _AgentDashboardColors.secondaryText,
                                    height: 1.4,
                                  ),
                        ),
                      ],
                      if (skillId.isNotEmpty && skillId != displayTitle) ...[
                        const SizedBox(height: 6),
                        Text(
                          skillId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: _AgentDashboardColors.mutedText,
                                    fontFamily: 'monospace',
                                  ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: const Color(0xFFB7C5DF),
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0x66131B2C),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x223D5174)),
          ),
          child: child,
        ),
      ],
    );
  }
}

class _BridgeStatusCard extends StatelessWidget {
  const _BridgeStatusCard({
    required this.diagnostics,
    required this.loading,
    required this.lastSessionCatalogError,
    required this.onRefresh,
  });

  final AgentBridgeDiagnostics? diagnostics;
  final bool loading;
  final String? lastSessionCatalogError;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final status = diagnostics?.state ?? AgentBridgeHealthState.checking;
    final tone = _bridgeHealthColor(status);
    final summary = diagnostics?.summary ??
        (loading
            ? 'Checking local bridge status'
            : 'Bridge status unavailable');
    final detail = diagnostics?.detail ??
        'The dashboard will probe the local bridge service on the controlled desktop.';
    final rawProbeError =
        diagnostics?.errors.isNotEmpty == true ? diagnostics!.errors.first : '';
    final checkedAt = diagnostics?.checkedAt;
    final actionLabel = loading
        ? 'Checking'
        : (status == AgentBridgeHealthState.unreachable &&
                (diagnostics?.enabled ?? false)
            ? 'Start bridge'
            : 'Refresh');
    final meta = <String>[
      if (diagnostics != null) 'Port ${diagnostics!.port}',
      if ((diagnostics?.command ?? '').isNotEmpty)
        'Command ${diagnostics!.command}',
      if (diagnostics != null) 'Projects ${diagnostics!.projectCount}',
      if (diagnostics != null)
        diagnostics!.requireConfirmation ? 'Confirm on' : 'Confirm off',
      if (checkedAt != null) 'Checked ${_formatTimeOfDay(checkedAt)}',
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final detailStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _AgentDashboardColors.secondaryText,
              height: 1.35,
            );
        final titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Local bridge service',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: _AgentDashboardColors.text,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              summary,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _AgentDashboardColors.text,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 4),
            _BridgeStatusTextBlock(
              text: detail,
              style: detailStyle,
              maxHeight: compact ? 96 : 72,
            ),
          ],
        );
        final refreshButton = compact
            ? SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onRefresh,
                  icon: loading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 16),
                  label: Text(actionLabel),
                ),
              )
            : OutlinedButton.icon(
                onPressed: onRefresh,
                icon: loading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 16),
                label: Text(actionLabel),
              );
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _AgentDashboardColors.elevatedSurface.withOpacity(0.56),
            borderRadius: BorderRadius.circular(
              _AgentDashboardMetrics.controlRadius,
            ),
            border: Border.all(color: tone.withOpacity(0.28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (compact)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: tone.withOpacity(0.16),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: loading
                              ? Padding(
                                  padding: const EdgeInsets.all(9),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: tone,
                                  ),
                                )
                              : Icon(
                                  _bridgeHealthIcon(status),
                                  size: 18,
                                  color: tone,
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: titleBlock),
                      ],
                    ),
                    const SizedBox(height: 12),
                    refreshButton,
                  ],
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: tone.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: loading
                          ? Padding(
                              padding: const EdgeInsets.all(9),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: tone,
                              ),
                            )
                          : Icon(
                              _bridgeHealthIcon(status),
                              size: 18,
                              color: tone,
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: titleBlock),
                    const SizedBox(width: 8),
                    refreshButton,
                  ],
                ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: meta
                      .map(
                        (item) => _StatusBadge(
                          label: item,
                          color: tone,
                          dense: true,
                        ),
                      )
                      .toList(),
                ),
              ],
              if (rawProbeError.isNotEmpty && rawProbeError != detail) ...[
                const SizedBox(height: 12),
                _SectionBlock(
                  title: 'Probe error',
                  child: _BridgeStatusTextBlock(
                    text: rawProbeError,
                    style: detailStyle,
                    maxHeight: 84,
                  ),
                ),
              ],
              if ((lastSessionCatalogError ?? '').trim().isNotEmpty &&
                  (lastSessionCatalogError ?? '').trim() != rawProbeError &&
                  (lastSessionCatalogError ?? '').trim() != detail) ...[
                const SizedBox(height: 12),
                _SectionBlock(
                  title: 'Last session catalog error',
                  child: _BridgeStatusTextBlock(
                    text: lastSessionCatalogError!,
                    style: detailStyle,
                    maxHeight: 96,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _BridgeStatusTextBlock extends StatelessWidget {
  const _BridgeStatusTextBlock({
    required this.text,
    required this.style,
    required this.maxHeight,
  });

  final String text;
  final TextStyle? style;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        child: Text(text, style: style),
      ),
    );
  }
}

class _ContextPreview extends StatelessWidget {
  const _ContextPreview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 220),
      child: SingleChildScrollView(
        child: SelectableText(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFFD8E1F5),
                fontFamily: 'monospace',
                height: 1.5,
              ),
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x66131B2C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x223D5174)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF4F8CFF),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF93A4C3),
                        height: 1.4,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationFilterChip extends StatelessWidget {
  const _ConversationFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label conversation filter',
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: _AgentDashboardMetrics.minTouchTarget,
          ),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color:
                  selected ? const Color(0xFF2F6BFF) : const Color(0x66131B2C),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected
                    ? const Color(0xFF2F6BFF)
                    : const Color(0x223D5174),
              ),
            ),
            child: Center(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: selected ? Colors.white : const Color(0xFF93A4C3),
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceButton extends StatelessWidget {
  const _VoiceButton({required this.model});

  final AgentDashboardModel model;

  @override
  Widget build(BuildContext context) {
    final recording = model.isVoiceRecording;
    return Tooltip(
      message: recording ? 'Recording voice clip' : 'Send voice clip',
      child: Semantics(
        button: true,
        label: recording ? 'Recording voice clip' : 'Send voice clip',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: recording ? null : model.sendVoiceClip,
            child: Ink(
              width: _AgentDashboardMetrics.minTouchTarget,
              height: _AgentDashboardMetrics.minTouchTarget,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: recording
                    ? const Color(0x55EF4444)
                    : const Color(0xFF1B2537),
                border: Border.all(color: const Color(0xFF24324A)),
              ),
              child: Center(
                child: recording
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.mic_none, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.model});

  final AgentDashboardModel model;

  @override
  Widget build(BuildContext context) {
    final conversation = model.selectedConversation!;
    final busy = model.isConversationBusyForConversation(conversation);
    return Semantics(
      button: true,
      label: busy ? 'Queue message for desktop agent' : 'Send message',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: model.sendCurrentPrompt,
          child: Ink(
            width: _AgentDashboardMetrics.minTouchTarget,
            height: _AgentDashboardMetrics.minTouchTarget,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: busy ? const Color(0x553B82F6) : const Color(0xFF2F6BFF),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x332F6BFF),
                  blurRadius: 12,
                )
              ],
            ),
            child: Icon(
              busy ? Icons.pending_outlined : Icons.arrow_upward,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

AgentDashboardPresentation presentationOf(BuildContext context) {
  final inherited = context
      .dependOnInheritedWidgetOfExactType<_AgentDashboardPresentationScope>();
  return inherited?.presentation ?? AgentDashboardPresentation.fullPage;
}

class _AgentDashboardPresentationScope extends InheritedWidget {
  const _AgentDashboardPresentationScope({
    required super.child,
    required this.presentation,
  });

  final AgentDashboardPresentation presentation;

  @override
  bool updateShouldNotify(_AgentDashboardPresentationScope oldWidget) {
    return oldWidget.presentation != presentation;
  }
}

Future<T?> _showDashboardOverlayPanel<T>(
  BuildContext context, {
  required Widget Function(
    BuildContext context,
    void Function([T? result]) close,
  ) builder,
  Color barrierColor = const Color(0x73000000),
  bool barrierDismissible = true,
}) {
  final overlayState = Overlay.of(context, rootOverlay: true);
  final completer = Completer<T?>();
  late final OverlayEntry entry;
  void close([T? result]) {
    entry.remove();
    if (!completer.isCompleted) {
      completer.complete(result);
    }
  }

  entry = OverlayEntry(
    builder: (overlayContext) {
      return Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: barrierDismissible ? close : null,
                child: ColoredBox(color: barrierColor),
              ),
            ),
            SafeArea(
              child: builder(overlayContext, close),
            ),
          ],
        ),
      );
    },
  );
  overlayState.insert(entry);
  return completer.future;
}

Future<int?> _showDashboardPanelSheet(
  BuildContext context, {
  required int selectedPanelIndex,
}) {
  const options = [
    _DashboardPanelOption(
      index: 1,
      title: 'Timeline',
      subtitle: 'Review structured agent events',
      icon: Icons.timeline_outlined,
    ),
    _DashboardPanelOption(
      index: 3,
      title: 'Context',
      subtitle: 'Project, session, and prompt inputs',
      icon: Icons.tune_outlined,
    ),
    _DashboardPanelOption(
      index: 4,
      title: 'Skills',
      subtitle: 'Select reusable assistant capabilities',
      icon: Icons.extension_outlined,
    ),
  ];
  return _showDashboardOverlayPanel<int>(
    context,
    barrierColor: const Color(0x99000000),
    builder: (overlayContext, close) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(_AgentDashboardMetrics.sheetRadius),
                bottom: Radius.circular(_AgentDashboardMetrics.panelRadius),
              ),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  decoration: BoxDecoration(
                    color: _AgentDashboardColors.elevatedSurfaceAlt.withOpacity(
                      0.92,
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(_AgentDashboardMetrics.sheetRadius),
                      bottom:
                          Radius.circular(_AgentDashboardMetrics.panelRadius),
                    ),
                    border: Border.all(color: _AgentDashboardColors.hairline),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: _AgentDashboardColors.hairline,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'More panels',
                              style: Theme.of(overlayContext)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: _AgentDashboardColors.text,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: close,
                            icon: const Icon(
                              Icons.close,
                              color: _AgentDashboardColors.text,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...options.map(
                        (option) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _DashboardPanelTile(
                            option: option,
                            selected: selectedPanelIndex == option.index,
                            onTap: () => close(option.index),
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
  );
}

class _DashboardPanelOption {
  const _DashboardPanelOption({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final int index;
  final String title;
  final String subtitle;
  final IconData icon;
}

class _DashboardPanelTile extends StatelessWidget {
  const _DashboardPanelTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _DashboardPanelOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${option.title} panel',
      child: InkWell(
        borderRadius:
            BorderRadius.circular(_AgentDashboardMetrics.controlRadius),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: _AgentDashboardMetrics.minTouchTarget,
          ),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? _AgentDashboardColors.primary.withOpacity(0.18)
                  : _AgentDashboardColors.elevatedSurface.withOpacity(0.72),
              borderRadius:
                  BorderRadius.circular(_AgentDashboardMetrics.controlRadius),
              border: Border.all(
                color: selected
                    ? _AgentDashboardColors.primary
                    : _AgentDashboardColors.hairline,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  option.icon,
                  color: selected
                      ? _AgentDashboardColors.text
                      : _AgentDashboardColors.secondaryText,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.title,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: _AgentDashboardColors.text,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        option.subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: _AgentDashboardColors.secondaryText,
                            ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.check_circle,
                    color: _AgentDashboardColors.ready,
                    size: 18,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _sessionLabel(String sessionRef) {
  final normalized = sessionRef.trim();
  return normalized.isEmpty ? 'new session' : normalized;
}

String _shortSessionId(String sessionId) {
  final normalized = sessionId.trim();
  if (normalized.isEmpty) return '';
  if (normalized.length <= 18) return normalized;
  return '${normalized.substring(0, 8)}...${normalized.substring(normalized.length - 6)}';
}

String _formatTimeOfDay(DateTime time) {
  final local = time.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  final second = local.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}

Color _bridgeHealthColor(AgentBridgeHealthState state) {
  switch (state) {
    case AgentBridgeHealthState.healthy:
      return _AgentDashboardColors.ready;
    case AgentBridgeHealthState.checking:
      return _AgentDashboardColors.running;
    case AgentBridgeHealthState.disabled:
      return _AgentDashboardColors.warning;
    case AgentBridgeHealthState.misconfigured:
      return _AgentDashboardColors.error;
    case AgentBridgeHealthState.unreachable:
      return _AgentDashboardColors.error;
  }
}

IconData _bridgeHealthIcon(AgentBridgeHealthState state) {
  switch (state) {
    case AgentBridgeHealthState.healthy:
      return Icons.cloud_done_outlined;
    case AgentBridgeHealthState.checking:
      return Icons.sync;
    case AgentBridgeHealthState.disabled:
      return Icons.toggle_off_outlined;
    case AgentBridgeHealthState.misconfigured:
      return Icons.warning_amber_outlined;
    case AgentBridgeHealthState.unreachable:
      return Icons.cloud_off_outlined;
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.color,
    this.dense = false,
  });

  final String label;
  final Color color;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.width < 520;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontSize: compact ? 10.5 : (dense ? 11 : 12),
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

const _messagePresentationHarness = AgentDashboardMessagePresentationHarness();

Widget _agentDashboardScrollToBottomButton(ScrollController controller) {
  return DefaultScrollToBottom(
    scrollController: controller,
    bottom: 12,
    height: _AgentDashboardMetrics.minTouchTarget,
    width: _AgentDashboardMetrics.minTouchTarget,
    elevation: 10,
    backgroundColor: _AgentDashboardColors.primary,
    textColor: _AgentDashboardColors.text,
    icon: Icons.vertical_align_bottom_rounded,
    iconSize: 24,
  );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isOwn,
    required this.maxWidth,
    required this.compact,
  });

  final ChatMessage message;
  final bool isOwn;
  final double maxWidth;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final baseColor = isOwn ? Colors.white : const Color(0xFFD8E1F5);
    final event = isOwn ? null : _AgentEventViewModel.tryParse(message.text);
    final presentation = isOwn || event != null
        ? null
        : _messagePresentationHarness.present(message.text);
    final useResponseCard = presentation?.shouldUseCard ?? false;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        crossAxisAlignment:
            isOwn ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isOwn && !(compact && event == null))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                event != null
                    ? 'Agent update'
                    : useResponseCard
                        ? 'Response'
                        : 'Message',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF93A4C3),
                    ),
              ),
            ),
          if (event != null) _AgentEventCard(event: event),
          if (event == null && useResponseCard)
            _AgentResponseCard(
              presentation: presentation!,
              compact: compact,
              onViewFull: () => _showAgentResponseDetails(
                context,
                presentation,
                compact: compact,
              ),
            ),
          if (event == null && !useResponseCard)
            SelectableText(
              _wrapLongTokens(message.text),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: baseColor,
                    height: 1.45,
                  ),
            ),
          const SizedBox(height: 6),
          Text(
            _formatMessageTime(message.createdAt),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF7082A3),
                  fontSize: 11,
                ),
          ),
        ],
      ),
    );
  }
}

class _AgentResponseCard extends StatelessWidget {
  const _AgentResponseCard({
    required this.presentation,
    required this.compact,
    required this.onViewFull,
  });

  final AgentResponsePresentation presentation;
  final bool compact;
  final VoidCallback onViewFull;

  @override
  Widget build(BuildContext context) {
    final statusColor = _agentResponseStatusColor(presentation.status);
    if (compact) {
      return _buildCompact(context, statusColor);
    }
    final titleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          color: _AgentDashboardColors.text,
          fontWeight: FontWeight.w700,
        );
    final bodyStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: _AgentDashboardColors.secondaryText,
          height: 1.45,
        );
    final visibleSections = compact
        ? const <AgentResponsePresentationSection>[]
        : presentation.sections;

    return Semantics(
      container: true,
      label: 'Agent response, ${presentation.statusLabel}',
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _AgentDashboardColors.elevatedSurface.withOpacity(0.84),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: statusColor.withOpacity(0.32)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withOpacity(0.28)),
                  ),
                  child: Icon(
                    _agentResponseStatusIcon(presentation.status),
                    color: statusColor,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    presentation.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                ),
                const SizedBox(width: 8),
                _StatusBadge(
                  label: presentation.statusLabel,
                  color: statusColor,
                  dense: true,
                ),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(
              _wrapLongTokens(presentation.summary),
              maxLines: compact ? 3 : 5,
              style: bodyStyle,
            ),
            if (presentation.chips.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final chip in presentation.chips)
                    _ResponseChip(label: chip),
                ],
              ),
            ],
            if (visibleSections.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final section in visibleSections)
                _AgentResponseSectionTile(section: section),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onViewFull,
                style: TextButton.styleFrom(
                  foregroundColor: _AgentDashboardColors.primary,
                  minimumSize: const Size(
                    112,
                    _AgentDashboardMetrics.minTouchTarget,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: const Icon(Icons.open_in_full_outlined, size: 17),
                label: Text(compact ? 'View full response' : 'Full response'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompact(BuildContext context, Color statusColor) {
    final showStatus =
        presentation.status != AgentResponsePresentationStatus.informational;
    return Semantics(
      container: true,
      button: true,
      label: 'Agent response, ${presentation.statusLabel}. View full response.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _wrapLongTokens(presentation.summary),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _AgentDashboardColors.text,
                  height: 1.42,
                  fontWeight: FontWeight.w500,
                ),
          ),
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onViewFull,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                children: [
                  if (showStatus) ...[
                    _CompactStatusPill(
                      label: presentation.statusLabel,
                      color: statusColor,
                      icon: _agentResponseStatusIcon(presentation.status),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      _compactResponseHint(presentation),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: _AgentDashboardColors.mutedText,
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'View',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: _AgentDashboardColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.chevron_right,
                    color: _AgentDashboardColors.primary,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResponseChip extends StatelessWidget {
  const _ResponseChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1222),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x3324324A)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: _AgentDashboardColors.secondaryText,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _CompactStatusPill extends StatelessWidget {
  const _CompactStatusPill({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

String _compactResponseHint(AgentResponsePresentation presentation) {
  final sectionIds = presentation.sections.map((section) => section.id).toSet();
  if (sectionIds.contains('validation')) {
    return 'Validation included';
  }
  if (sectionIds.contains('risks')) {
    return 'Review risks';
  }
  if (sectionIds.contains('next-actions')) {
    return 'Next actions available';
  }
  if (presentation.rawText.length > presentation.summary.length + 48) {
    return 'Tap to read full response';
  }
  return 'Tap for details';
}

class _AgentResponseSectionTile extends StatelessWidget {
  const _AgentResponseSectionTile({required this.section});

  final AgentResponsePresentationSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        dividerColor: Colors.transparent,
        splashColor: _AgentDashboardColors.primary.withOpacity(0.08),
        highlightColor: _AgentDashboardColors.primary.withOpacity(0.06),
      ),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
        iconColor: _AgentDashboardColors.secondaryText,
        collapsedIconColor: _AgentDashboardColors.mutedText,
        minTileHeight: _AgentDashboardMetrics.minTouchTarget,
        title: Text(
          section.title,
          style: theme.textTheme.labelLarge?.copyWith(
            color: _AgentDashboardColors.text,
            fontWeight: FontWeight.w700,
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              _wrapLongTokens(section.content),
              style: theme.textTheme.bodySmall?.copyWith(
                color: _AgentDashboardColors.secondaryText,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showAgentResponseDetails(
  BuildContext context,
  AgentResponsePresentation presentation, {
  required bool compact,
}) {
  final isFloating =
      presentationOf(context) == AgentDashboardPresentation.floatingWindow;
  if (isFloating) {
    return _showDashboardOverlayPanel<void>(
      context,
      barrierColor: const Color(0x99000000),
      builder: (overlayContext, close) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: _AgentResponseDetailPanel(
              presentation: presentation,
              compact: compact,
              onClose: () => close(),
            ),
          ),
        );
      },
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x99000000),
    builder: (sheetContext) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: _AgentResponseDetailPanel(
          presentation: presentation,
          compact: compact,
          onClose: () => Navigator.of(sheetContext).maybePop(),
        ),
      );
    },
  );
}

class _AgentResponseDetailPanel extends StatelessWidget {
  const _AgentResponseDetailPanel({
    required this.presentation,
    required this.compact,
    required this.onClose,
  });

  final AgentResponsePresentation presentation;
  final bool compact;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final maxHeight =
        MediaQuery.of(context).size.height * (compact ? 0.84 : 0.78);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 620, maxHeight: maxHeight),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(_AgentDashboardMetrics.sheetRadius),
          bottom: Radius.circular(_AgentDashboardMetrics.panelRadius),
        ),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: _AgentDashboardColors.elevatedSurfaceAlt.withOpacity(0.94),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(_AgentDashboardMetrics.sheetRadius),
                bottom: Radius.circular(_AgentDashboardMetrics.panelRadius),
              ),
              border: Border.all(color: _AgentDashboardColors.hairline),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
                  child: Column(
                    children: [
                      Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _AgentDashboardColors.hairline,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Full response',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: _AgentDashboardColors.text,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: onClose,
                            icon: const Icon(
                              Icons.close,
                              color: _AgentDashboardColors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: _AgentDashboardColors.hairline),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _agentResponseStatusIcon(presentation.status),
                            color:
                                _agentResponseStatusColor(presentation.status),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              presentation.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    color: _AgentDashboardColors.text,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SelectableText(
                        _wrapLongTokens(presentation.summary),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: _AgentDashboardColors.secondaryText,
                              height: 1.45,
                            ),
                      ),
                      if (presentation.sections.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        for (final section in presentation.sections)
                          _AgentResponseDetailSection(section: section),
                      ],
                      const SizedBox(height: 16),
                      _AgentResponseDetailSection(
                        section: AgentResponsePresentationSection(
                          id: 'raw',
                          title: 'Raw',
                          content: presentation.rawText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AgentResponseDetailSection extends StatelessWidget {
  const _AgentResponseDetailSection({required this.section});

  final AgentResponsePresentationSection section;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: _AgentDashboardColors.text,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            _wrapLongTokens(section.content),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _AgentDashboardColors.secondaryText,
                  height: 1.5,
                ),
          ),
        ],
      ),
    );
  }
}

Color _agentResponseStatusColor(AgentResponsePresentationStatus status) {
  switch (status) {
    case AgentResponsePresentationStatus.completed:
      return _AgentDashboardColors.ready;
    case AgentResponsePresentationStatus.running:
      return _AgentDashboardColors.running;
    case AgentResponsePresentationStatus.needsConfirmation:
      return _AgentDashboardColors.warning;
    case AgentResponsePresentationStatus.failed:
      return _AgentDashboardColors.error;
    case AgentResponsePresentationStatus.informational:
      return _AgentDashboardColors.primary;
  }
}

IconData _agentResponseStatusIcon(AgentResponsePresentationStatus status) {
  switch (status) {
    case AgentResponsePresentationStatus.completed:
      return Icons.task_alt_outlined;
    case AgentResponsePresentationStatus.running:
      return Icons.sync_outlined;
    case AgentResponsePresentationStatus.needsConfirmation:
      return Icons.priority_high_outlined;
    case AgentResponsePresentationStatus.failed:
      return Icons.error_outline;
    case AgentResponsePresentationStatus.informational:
      return Icons.notes_outlined;
  }
}

class _AgentEventCard extends StatelessWidget {
  const _AgentEventCard({required this.event});

  final _AgentEventViewModel event;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: event.color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: event.color.withOpacity(0.34)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(event.icon, color: event.color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  event.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _StatusBadge(
                label: event.statusLabel,
                color: event.color,
                dense: true,
              ),
              _StatusBadge(
                label: event.project,
                color: const Color(0xFF8B5CF6),
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: 10),
          SelectableText(
            _wrapLongTokens(event.body),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFD8E1F5),
                  height: 1.45,
                ),
          ),
        ],
      ),
    );
  }
}

class _AgentEventViewModel {
  const _AgentEventViewModel({
    required this.project,
    required this.title,
    required this.statusLabel,
    required this.body,
    required this.color,
    required this.icon,
  });

  final String project;
  final String title;
  final String statusLabel;
  final String body;
  final Color color;
  final IconData icon;

  static _AgentEventViewModel? tryParse(String text) {
    final normalized = text.replaceAll('\r\n', '\n').trimLeft();
    if (!normalized.startsWith('[Agent:')) return null;
    final firstBreak = normalized.indexOf('\n');
    final firstLine =
        (firstBreak == -1 ? normalized : normalized.substring(0, firstBreak))
            .trimRight();
    final rest =
        firstBreak == -1 ? '' : normalized.substring(firstBreak + 1).trim();
    final match = RegExp(r'^\[Agent:([^\]]+)\]\s+([^:]+):?\s*(.*)$')
        .firstMatch(firstLine);
    if (match == null) return null;
    final project = match.group(1)?.trim();
    if (project == null || project.isEmpty) return null;
    final matchedStatus = match.group(2);
    if (matchedStatus == null) return null;
    final rawStatus = matchedStatus.trim();
    final key = rawStatus
        .toLowerCase()
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    final inlineBody = (match.group(3) ?? '').trim();
    final mergedBody = [
      if (inlineBody.isNotEmpty) inlineBody,
      if (rest.isNotEmpty) rest,
    ].join('\n').trim();

    switch (key) {
      case 'started':
      case 'running':
        return _AgentEventViewModel(
          project: project,
          title: 'Thinking',
          statusLabel: 'Processing',
          body: mergedBody.isEmpty
              ? 'The assistant received the request and is analyzing context.'
              : mergedBody,
          color: const Color(0xFF4F8CFF),
          icon: Icons.psychology_outlined,
        );
      case 'needs confirmation':
        return _AgentEventViewModel(
          project: project,
          title: 'Waiting for approval',
          statusLabel: 'Needs approval',
          body: mergedBody.isEmpty
              ? 'The assistant needs confirmation before it can continue.'
              : mergedBody,
          color: const Color(0xFFF59E0B),
          icon: Icons.fact_check_outlined,
        );
      case 'done':
      case 'completed':
      case 'cancelled':
        return _AgentEventViewModel(
          project: project,
          title: 'Completed',
          statusLabel: 'Done',
          body: mergedBody.isEmpty
              ? 'The assistant finished this request.'
              : mergedBody,
          color: const Color(0xFF10B981),
          icon: Icons.check_circle_outline,
        );
      case 'failed':
      case 'error':
        return _AgentEventViewModel(
          project: project,
          title: 'Error',
          statusLabel: 'Failed',
          body: mergedBody.isEmpty
              ? 'The assistant could not complete this request.'
              : mergedBody,
          color: const Color(0xFFEF4444),
          icon: Icons.error_outline,
        );
      default:
        return _AgentEventViewModel(
          project: project,
          title: 'Agent update',
          statusLabel: rawStatus.isEmpty ? 'Update' : rawStatus,
          body: mergedBody.isEmpty
              ? 'The assistant sent a status update.'
              : mergedBody,
          color: const Color(0xFF93A4C3),
          icon: Icons.smart_toy_outlined,
        );
    }
  }
}

class _AvatarBadge extends StatelessWidget {
  const _AvatarBadge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_AgentDashboardMetrics.panelRadius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: _AgentDashboardColors.elevatedSurfaceAlt.withOpacity(0.8),
            borderRadius:
                BorderRadius.circular(_AgentDashboardMetrics.panelRadius),
            border: Border.all(color: _AgentDashboardColors.hairline),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 22,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

InputDecoration _inputDecoration({
  required String hintText,
  Widget? prefixIcon,
  Widget? trailingIcon,
}) {
  return InputDecoration(
    isDense: true,
    hintText: hintText,
    hintStyle: const TextStyle(color: Color(0xFF7082A3)),
    prefixIcon: prefixIcon,
    prefixIconColor: const Color(0xFF93A4C3),
    suffixIcon: trailingIcon,
    filled: true,
    fillColor: const Color(0xCC131B2C),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0x223D5174)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF4F8CFF)),
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0x223D5174)),
    ),
  );
}

Color _statusColor(AgentConversationStatus status) {
  switch (status) {
    case AgentConversationStatus.running:
      return _AgentDashboardColors.running;
    case AgentConversationStatus.needsConfirmation:
      return _AgentDashboardColors.warning;
    case AgentConversationStatus.completed:
      return _AgentDashboardColors.ready;
    case AgentConversationStatus.failed:
      return _AgentDashboardColors.error;
    case AgentConversationStatus.idle:
      return _AgentDashboardColors.secondaryText;
  }
}

String _formatUpdatedAt(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$month-$day $hour:$minute';
}

String _formatSessionUpdatedAt(String value) {
  final updatedAt = DateTime.tryParse(value);
  if (updatedAt == null) {
    return value;
  }
  final elapsed = DateTime.now().difference(updatedAt.toLocal());
  if (elapsed.inMinutes < 1) {
    return 'just now';
  }
  if (elapsed.inHours < 1) {
    return '${elapsed.inMinutes} min';
  }
  if (elapsed.inDays < 1) {
    return '${elapsed.inHours} h';
  }
  if (elapsed.inDays < 7) {
    return '${elapsed.inDays} d';
  }
  if (elapsed.inDays < 30) {
    return '${elapsed.inDays ~/ 7} wk';
  }
  return _formatUpdatedAt(updatedAt);
}

String _formatMessageTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _wrapLongTokens(String value) {
  return value.splitMapJoin(
    RegExp(r'([^\s]{28})(?=[^\s])'),
    onMatch: (match) => '${match.group(1)}\u{200B}',
    onNonMatch: (part) => part,
  );
}
