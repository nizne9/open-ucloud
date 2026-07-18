import 'dart:async';
import 'dart:convert';
import 'dart:typed_data' as typed_data;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:open_cloud_ffi/open_cloud_ffi.dart';
import 'package:url_launcher/url_launcher.dart';

import 'assignment_content_view.dart';
import 'client_controller.dart';
import 'theme_mode_controller.dart';

part 'home_screen_widgets.dart';
part 'home_screen_dashboard.dart';
part 'home_screen_assignments.dart';
part 'home_screen_resources.dart';
part 'home_screen_attendance.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _bootstrapped = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bootstrapped) {
      return;
    }
    _bootstrapped = true;
    Future.microtask(
      () => ref.read(clientControllerProvider.notifier).bootstrap(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final phase = ref.watch(
      clientControllerProvider.select((state) => state.phase),
    );
    final themeMode = ref.watch(themeModeControllerProvider);
    final authenticated =
        phase == ClientPhase.authenticated ||
        phase == ClientPhase.loadingCourses;
    final showBottomNav =
        authenticated && MediaQuery.sizeOf(context).width < 700;
    return Scaffold(
      appBar: authenticated
          ? null
          : AppBar(
              title: const Text('Open UCloud'),
              actions: [_ThemeModeMenu(themeMode: themeMode)],
            ),
      bottomNavigationBar: showBottomNav ? const _ClientNavigationBar() : null,
      body: SafeArea(
        bottom: !showBottomNav,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: switch (phase) {
            ClientPhase.bootstrapping => const _LoadingPane(label: '正在恢复会话'),
            ClientPhase.startingLogin => const _LoadingPane(label: '正在初始化登录'),
            ClientPhase.finishingLogin => const _LoadingPane(label: '正在登录'),
            ClientPhase.loadingCourses => const _AuthenticatedPane(),
            ClientPhase.authenticated => const _AuthenticatedPane(),
            ClientPhase.awaitingCaptcha => const _LoginPane(),
            ClientPhase.unauthenticated => const _LoginPane(),
          },
        ),
      ),
    );
  }
}

class _ThemeModeMenu extends ConsumerWidget {
  const _ThemeModeMenu({required this.themeMode});

  final AppThemeMode themeMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<AppThemeMode>(
      tooltip: '主题',
      icon: const Icon(Icons.brightness_6_outlined),
      initialValue: themeMode,
      onSelected: (mode) =>
          ref.read(themeModeControllerProvider.notifier).setThemeMode(mode),
      itemBuilder: (context) => [
        CheckedPopupMenuItem<AppThemeMode>(
          value: AppThemeMode.system,
          checked: themeMode == AppThemeMode.system,
          child: const Text('跟随系统'),
        ),
        CheckedPopupMenuItem<AppThemeMode>(
          value: AppThemeMode.light,
          checked: themeMode == AppThemeMode.light,
          child: const Text('浅色'),
        ),
        CheckedPopupMenuItem<AppThemeMode>(
          value: AppThemeMode.dark,
          checked: themeMode == AppThemeMode.dark,
          child: const Text('深色'),
        ),
      ],
    );
  }
}

class _ClientDestination {
  const _ClientDestination({
    required this.tab,
    required this.icon,
    required this.label,
    required this.title,
    required this.subtitle,
  });

  final ClientTab tab;
  final IconData icon;
  final String label;
  final String title;
  final String subtitle;
}

typedef _AssignmentsPaneState = ({
  bool assignmentDetailLoading,
  bool assignmentSubmitting,
  bool assignmentUploading,
  AssignmentView assignmentView,
  List<FfiAssignmentSummary> assignments,
  bool assignmentsLoading,
  List<CourseItem> courses,
  String? errorMessage,
  OperationContext? operationContext,
  String? operationMessage,
  FfiAssignmentDetailResponse? assignmentDetail,
  String? selectedAssignmentCourseId,
  String? selectedAssignmentId,
});

typedef _AssignmentDetailState = ({
  bool assignmentDetailLoading,
  bool assignmentSubmitting,
  bool assignmentUploading,
  List<AssignmentAttachmentState> assignmentAttachments,
  FfiAssignmentDetailResponse? assignmentDetail,
  List<FfiAssignmentSummary> assignments,
  List<CourseItem> courses,
});

_AssignmentsPaneState _selectAssignmentsPaneState(ClientState state) {
  return (
    assignmentDetailLoading: state.assignmentDetailLoading,
    assignmentSubmitting: state.assignmentSubmitting,
    assignmentUploading: state.assignmentUploading,
    assignmentView: state.assignmentView,
    assignments: state.assignments,
    assignmentsLoading: state.assignmentsLoading,
    courses: state.courses,
    errorMessage: state.errorMessage,
    operationContext: state.operationContext,
    operationMessage: state.operationMessage,
    assignmentDetail: state.assignmentDetail,
    selectedAssignmentCourseId: state.selectedAssignmentCourseId,
    selectedAssignmentId: state.selectedAssignmentId,
  );
}

_AssignmentDetailState _selectAssignmentDetailState(ClientState state) {
  return (
    assignmentDetailLoading: state.assignmentDetailLoading,
    assignmentSubmitting: state.assignmentSubmitting,
    assignmentUploading: state.assignmentUploading,
    assignmentAttachments: state.assignmentAttachments,
    assignmentDetail: state.assignmentDetail,
    assignments: state.assignments,
    courses: state.courses,
  );
}

typedef _ResourcesPaneState = ({
  List<CourseItem> courses,
  List<String> downloadedPaths,
  OperationContext? operationContext,
  String? errorMessage,
  String? operationMessage,
  FfiCourseResourceDetail? resourceDetail,
  bool resourceDetailLoading,
  bool resourceDownloading,
  List<FfiCourseResourceSummary> resources,
  bool resourcesLoading,
  String? selectedResourceCourseId,
  String? selectedResourceId,
});

typedef _ResourceDownloadProgressState = ({
  String? currentFileName,
  int bytes,
  int current,
  int total,
});

_ResourcesPaneState _selectResourcesPaneState(ClientState state) {
  return (
    courses: state.courses,
    downloadedPaths: state.downloadedPaths,
    operationContext: state.operationContext,
    errorMessage: state.errorMessage,
    operationMessage: state.operationMessage,
    resourceDetail: state.resourceDetail,
    resourceDetailLoading: state.resourceDetailLoading,
    resourceDownloading: state.resourceDownloading,
    resources: state.resources,
    resourcesLoading: state.resourcesLoading,
    selectedResourceCourseId: state.selectedResourceCourseId,
    selectedResourceId: state.selectedResourceId,
  );
}

_ResourceDownloadProgressState _selectResourceDownloadProgressState(
  ClientState state,
) {
  return (
    currentFileName: state.resourceDownloadCurrentFileName,
    bytes: state.resourceDownloadBytes,
    current: state.resourceDownloadProgressCurrent,
    total: state.resourceDownloadProgressTotal,
  );
}

typedef _AccountPaneState = ({FfiAuthSessionResponse? session, bool isBusy});

_AccountPaneState _selectAccountPaneState(ClientState state) {
  return (session: state.session, isBusy: state.isBusy);
}

const _clientDestinations = [
  _ClientDestination(
    tab: ClientTab.dashboard,
    icon: Icons.dashboard_outlined,
    label: '总览',
    title: '总览工作台',
    subtitle: '查看课程、待交作业和资料更新。',
  ),
  _ClientDestination(
    tab: ClientTab.assignments,
    icon: Icons.assignment_outlined,
    label: '作业',
    title: '作业处理',
    subtitle: '查看要求、上传附件并提交作业。',
  ),
  _ClientDestination(
    tab: ClientTab.resources,
    icon: Icons.folder_outlined,
    label: '资料',
    title: '资料下载',
    subtitle: '按课程查看和下载资料。',
  ),
  _ClientDestination(
    tab: ClientTab.account,
    icon: Icons.person_outline,
    label: '账户',
    title: '登录状态',
    subtitle: '查看当前账号并管理登录。',
  ),
];

_ClientDestination _destinationFor(ClientTab tab) {
  return _clientDestinations.firstWhere(
    (destination) => destination.tab == tab,
    orElse: () => _clientDestinations.first,
  );
}

int _destinationIndex(ClientTab tab) {
  final index = _clientDestinations.indexWhere(
    (destination) => destination.tab == tab,
  );
  return index < 0 ? 0 : index;
}

class _ClientNavigationBar extends ConsumerWidget {
  const _ClientNavigationBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTab = ref.watch(
      clientControllerProvider.select((state) => state.selectedTab),
    );
    return BottomNavigationBar(
      currentIndex: _destinationIndex(selectedTab),
      onTap: (index) {
        unawaited(
          _selectClientTab(_clientDestinations[index].tab, ref, context),
        );
      },
      items: [
        for (final destination in _clientDestinations)
          BottomNavigationBarItem(
            icon: Icon(destination.icon),
            label: destination.label,
          ),
      ],
    );
  }
}

class _AuthenticatedPane extends ConsumerWidget {
  const _AuthenticatedPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTab = ref.watch(
      clientControllerProvider.select((state) => state.selectedTab),
    );
    final themeMode = ref.watch(themeModeControllerProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final content = switch (selectedTab) {
          ClientTab.dashboard => const _DashboardPane(),
          ClientTab.assignments => const _AssignmentsPane(),
          ClientTab.resources => const _ResourcesPane(),
          ClientTab.account => const _AccountPane(),
        };
        if (constraints.maxWidth >= 1100) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SideNavigation(),
              const VerticalDivider(width: 1),
              Expanded(
                child: _WorkbenchFrame(
                  selectedTab: selectedTab,
                  themeMode: themeMode,
                  child: content,
                ),
              ),
            ],
          );
        }
        if (constraints.maxWidth >= 700) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NavigationRail(
                selectedIndex: _destinationIndex(selectedTab),
                labelType: NavigationRailLabelType.all,
                onDestinationSelected: (index) {
                  unawaited(
                    _selectClientTab(
                      _clientDestinations[index].tab,
                      ref,
                      context,
                    ),
                  );
                },
                destinations: [
                  for (final destination in _clientDestinations)
                    NavigationRailDestination(
                      icon: Icon(destination.icon),
                      label: Text(destination.label),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _WorkbenchFrame(
                  selectedTab: selectedTab,
                  themeMode: themeMode,
                  child: content,
                ),
              ),
            ],
          );
        }
        return _WorkbenchFrame(
          selectedTab: selectedTab,
          themeMode: themeMode,
          compact: true,
          child: content,
        );
      },
    );
  }
}

class _SideNavigation extends ConsumerWidget {
  const _SideNavigation();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigationState = ref.watch(
      clientControllerProvider.select(
        (state) => (selectedTab: state.selectedTab, session: state.session),
      ),
    );
    final colorScheme = Theme.of(context).colorScheme;
    final session = navigationState.session;
    return SizedBox(
      width: 248,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(right: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 14, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _BrandHeader(subtitle: '学生桌面端'),
              const SizedBox(height: 24),
              for (var index = 0; index < _clientDestinations.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _SideNavigationItem(
                    number: '${index + 1}'.padLeft(2, '0'),
                    destination: _clientDestinations[index],
                    selected:
                        navigationState.selectedTab ==
                        _clientDestinations[index].tab,
                    onTap: () {
                      unawaited(
                        _selectClientTab(
                          _clientDestinations[index].tab,
                          ref,
                          context,
                        ),
                      );
                    },
                  ),
                ),
              const Spacer(),
              if (session != null)
                _AccountBadge(name: session.user.realName, subtitle: '已登录'),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _BrandMark(),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Open UCloud',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.primary),
        borderRadius: BorderRadius.circular(8),
        color: colorScheme.primaryContainer.withValues(alpha: 0.28),
      ),
      child: SizedBox(
        width: 28,
        height: 28,
        child: Center(
          child: Text(
            'OU',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _SideNavigationItem extends StatelessWidget {
  const _SideNavigationItem({
    required this.number,
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final String number;
  final _ClientDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? colorScheme.primaryContainer.withValues(alpha: 0.42)
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected ? colorScheme.primary : colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                child: Text(
                  number,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Icon(destination.icon, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  destination.tab == ClientTab.account
                      ? destination.title
                      : destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountBadge extends StatelessWidget {
  const _AccountBadge({required this.name, required this.subtitle});

  final String name;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final initial = name.trim().isEmpty ? '?' : name.trim().substring(0, 1);
    return DecoratedBox(
      decoration: _outlinedBoxDecoration(colorScheme),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(radius: 18, child: Text(initial)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkbenchFrame extends ConsumerWidget {
  const _WorkbenchFrame({
    required this.selectedTab,
    required this.themeMode,
    required this.child,
    this.compact = false,
  });

  final ClientTab selectedTab;
  final AppThemeMode themeMode;
  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBusy = ref.watch(
      clientControllerProvider.select((state) => state.isBusy),
    );
    final destination = _destinationFor(selectedTab);
    final controller = ref.read(clientControllerProvider.notifier);
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: colorScheme.surfaceContainerLowest),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WorkbenchTopBar(
            destination: destination,
            compact: compact,
            themeMode: themeMode,
            onRefresh: isBusy
                ? null
                : () {
                    unawaited(_refreshActiveTab(context, ref));
                  },
            onLogout: isBusy ? null : controller.logout,
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _WorkbenchTopBar extends StatelessWidget {
  const _WorkbenchTopBar({
    required this.destination,
    required this.compact,
    required this.themeMode,
    required this.onRefresh,
    required this.onLogout,
  });

  final _ClientDestination destination;
  final bool compact;
  final AppThemeMode themeMode;
  final VoidCallback? onRefresh;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = compact || constraints.maxWidth < 760;
          final titleBlock = Row(
            children: [
              if (narrow) ...[const _BrandMark(), const SizedBox(width: 10)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      destination.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      destination.subtitle,
                      maxLines: narrow ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('刷新'),
              ),
              _ThemeModeMenu(themeMode: themeMode),
              IconButton(
                tooltip: '退出登录',
                onPressed: onLogout == null
                    ? null
                    : () => _logoutWithConfirmation(context, onLogout!),
                icon: const Icon(Icons.logout),
              ),
            ],
          );
          if (narrow) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [titleBlock, const SizedBox(height: 10), actions],
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 20, 12),
            child: Row(
              children: [
                Expanded(child: titleBlock),
                const SizedBox(width: 16),
                actions,
              ],
            ),
          );
        },
      ),
    );
  }
}

Future<bool> _prepareForTabDeparture(
  BuildContext context,
  WidgetRef ref,
  ClientState state,
) async {
  if (state.selectedTab == ClientTab.assignments) {
    return _prepareForAssignmentContextChange(context, ref);
  }
  if (state.selectedTab == ClientTab.resources && state.resourceDownloading) {
    return _confirmCancelResourceDownload(context, ref);
  }
  return true;
}

Future<bool> _selectClientTab(
  ClientTab tab,
  WidgetRef ref,
  BuildContext context,
) async {
  final controller = ref.read(clientControllerProvider.notifier);
  final state = ref.read(clientControllerProvider);
  if (state.selectedTab == tab) {
    return true;
  }
  if (!await _prepareForTabDeparture(context, ref, state)) {
    return false;
  }
  controller.selectTab(tab);
  final nextState = ref.read(clientControllerProvider);
  if (tab == ClientTab.dashboard &&
      !nextState.undoneAssignmentsLoaded &&
      !nextState.assignmentsLoading) {
    controller.loadUndoneAssignments(selectedTab: ClientTab.dashboard);
  }
  if (tab == ClientTab.assignments &&
      !nextState.undoneAssignmentsLoaded &&
      !nextState.assignmentsLoading) {
    controller.loadUndoneAssignments();
  }
  if (tab == ClientTab.resources &&
      nextState.resources.isEmpty &&
      nextState.courses.isNotEmpty) {
    controller.loadResourcesForCourse(nextState.courses.first.id);
  }
  return true;
}

Future<void> _refreshCoursesWithGuards(
  BuildContext context,
  WidgetRef ref,
) async {
  final state = ref.read(clientControllerProvider);
  if (!await _prepareForTabDeparture(context, ref, state)) {
    return;
  }
  await ref.read(clientControllerProvider.notifier).refreshCourses();
}

/// Refreshes whatever the active tab is showing: the dashboard reloads both
/// courses and pending assignments, the assignments/resources tabs reload
/// their current list, and the account tab reloads courses.
Future<void> _refreshActiveTab(BuildContext context, WidgetRef ref) async {
  final state = ref.read(clientControllerProvider);
  if (!await _prepareForTabDeparture(context, ref, state)) {
    return;
  }
  if (!context.mounted) {
    return;
  }
  final controller = ref.read(clientControllerProvider.notifier);
  switch (state.selectedTab) {
    case ClientTab.dashboard:
      await controller.refreshCourses();
      if (context.mounted) {
        await controller.loadUndoneAssignments(
          selectedTab: ClientTab.dashboard,
          refresh: true,
        );
      }
    case ClientTab.assignments:
      await _refreshAssignments(context, ref);
    case ClientTab.resources:
      await _refreshResources(context, ref);
    case ClientTab.account:
      await controller.refreshCourses();
  }
}

bool _canLeaveAssignmentDetail(ClientState state) {
  return !state.assignmentUploading && !state.assignmentSubmitting;
}

bool _hasUnsavedAssignmentChanges(ClientState state) {
  final detail = state.assignmentDetail;
  if (detail == null) {
    return false;
  }
  if (state.assignmentDraft != detail.submittedContent) {
    return true;
  }
  if (state.assignmentAttachments.length !=
      detail.submittedAttachments.length) {
    return true;
  }
  for (var index = 0; index < state.assignmentAttachments.length; index += 1) {
    final draft = state.assignmentAttachments[index];
    final submitted = detail.submittedAttachments[index];
    if (draft.name != submitted.name ||
        draft.resourceId != submitted.resourceId ||
        draft.previewUrl != submitted.previewUrl) {
      return true;
    }
  }
  return false;
}

Future<bool> _confirmDiscardAssignmentChanges(BuildContext context) {
  return _confirm(
    context,
    title: '放弃未提交的修改？',
    content: '当前作业的正文或附件还没有提交。继续后将丢弃这些本地修改。',
    confirmLabel: '放弃修改',
  );
}

Future<bool> _confirmLogout(BuildContext context) {
  return _confirm(
    context,
    title: '退出登录',
    content: '退出后将清除本地会话，需要重新登录。',
    confirmLabel: '退出',
  );
}

Future<void> _logoutWithConfirmation(
  BuildContext context,
  VoidCallback onLogout,
) async {
  final ok = await _confirmLogout(context);
  if (ok && context.mounted) {
    onLogout();
  }
}

Future<bool> _confirmCancelResourceDownload(
  BuildContext context,
  WidgetRef ref,
) async {
  final ok = await _confirm(
    context,
    title: '取消当前下载？',
    content: '当前资料下载还在进行。继续前需要先取消这个下载任务。',
    confirmLabel: '取消下载',
  );
  if (!ok || !context.mounted) {
    return false;
  }
  final contextHint =
      ref.read(clientControllerProvider).operationContext ??
      OperationContext.resourceList;
  await ref
      .read(clientControllerProvider.notifier)
      .cancelActiveResourceDownload(context: contextHint);
  return true;
}

Future<bool> _prepareForResourceContextChange(
  BuildContext context,
  WidgetRef ref,
) async {
  final state = ref.read(clientControllerProvider);
  if (!state.resourceDownloading) {
    return true;
  }
  return _confirmCancelResourceDownload(context, ref);
}

Future<bool> _prepareForAssignmentContextChange(
  BuildContext context,
  WidgetRef ref,
) async {
  final state = ref.read(clientControllerProvider);
  if (!_canLeaveAssignmentDetail(state)) {
    return false;
  }
  if (!_hasUnsavedAssignmentChanges(state)) {
    return true;
  }
  final discard = await _confirmDiscardAssignmentChanges(context);
  if (!context.mounted) {
    return false;
  }
  if (!discard) {
    return false;
  }
  ref.read(clientControllerProvider.notifier).clearAssignmentSelection();
  return true;
}

class _LoginPane extends ConsumerStatefulWidget {
  const _LoginPane();

  @override
  ConsumerState<_LoginPane> createState() => _LoginPaneState();
}

class _LoginPaneState extends ConsumerState<_LoginPane> {
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _captchaController;
  String? _usernameError;
  String? _passwordError;
  String? _captchaError;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    final initialState = ref.read(clientControllerProvider);
    _usernameController = TextEditingController(
      text: initialState.pendingUsername ?? '',
    );
    _passwordController = TextEditingController();
    _captchaController = TextEditingController();
    _clearFieldOnError(_usernameController, () => _usernameError, () {
      _usernameError = null;
    });
    _clearFieldOnError(_passwordController, () => _passwordError, () {
      _passwordError = null;
    });
    _clearFieldOnError(_captchaController, () => _captchaError, () {
      _captchaError = null;
    });
  }

  void _clearFieldOnError(
    TextEditingController controller,
    String? Function() getter,
    void Function() setter,
  ) {
    controller.addListener(() {
      if (getter() != null) {
        setState(setter);
      }
    });
  }

  @override
  void dispose() {
    // Per-field listeners set by _clearFieldOnError are anonymous closures
    // that cannot be removed individually, but TextEditingController.dispose()
    // implicitly removes all listeners, making explicit removeListener calls
    // unnecessary.
    _usernameController.dispose();
    _passwordController.dispose();
    _captchaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      clientControllerProvider.select(
        (state) => (
          phase: state.phase,
          captchaImage: state.captchaImage,
          errorMessage: state.errorMessage,
        ),
      ),
    );
    final controller = ref.read(clientControllerProvider.notifier);
    final awaitingCaptcha = state.phase == ClientPhase.awaitingCaptcha;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            Icon(
              Icons.school_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              '登录 Open UCloud',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            AutofillGroup(
              child: Column(
                children: [
                  TextField(
                    controller: _usernameController,
                    enabled: !awaitingCaptcha,
                    autofillHints: const [AutofillHints.username],
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: '用户名',
                      prefixIcon: const Icon(Icons.person_outline),
                      errorText: _usernameError,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    enabled: !awaitingCaptcha,
                    obscureText: _obscurePassword,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) =>
                        _submitPrimary(controller, awaitingCaptcha),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: '密码',
                      prefixIcon: const Icon(Icons.lock_outline),
                      errorText: _passwordError,
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (awaitingCaptcha) ...[
              const SizedBox(height: 16),
              Tooltip(
                message: '点击刷新验证码',
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _restartLogin(controller),
                  child: _CaptchaImage(dataUri: state.captchaImage),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _captchaController,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submitPrimary(controller, awaitingCaptcha),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: '验证码',
                  prefixIcon: const Icon(Icons.verified_outlined),
                  errorText: _captchaError,
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _submitPrimary(controller, awaitingCaptcha),
              icon: Icon(awaitingCaptcha ? Icons.login : Icons.arrow_forward),
              label: Text(awaitingCaptcha ? '完成登录' : '继续'),
            ),
            if (awaitingCaptcha) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {
                  _passwordController.clear();
                  _captchaController.clear();
                  controller.editLoginCredentials();
                },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('修改账号密码'),
              ),
              TextButton.icon(
                onPressed: () => _restartLogin(controller),
                icon: const Icon(Icons.restart_alt),
                label: const Text('重新获取验证码'),
              ),
            ],
            if (state.errorMessage != null) ...[
              const SizedBox(height: 16),
              _StatusBanner(
                kind: _BannerKind.error,
                message: state.errorMessage!,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _restartLogin(ClientController controller) {
    controller.startLogin(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );
  }

  void _submitPrimary(ClientController controller, bool awaitingCaptcha) {
    if (awaitingCaptcha) {
      final captcha = _captchaController.text.trim();
      if (captcha.isEmpty) {
        setState(() {
          _captchaError = '请输入验证码';
        });
        return;
      }
      controller.finishLogin(captcha: captcha);
      return;
    }
    final username = _usernameController.text.trim();
    // Password is intentionally NOT trimmed: whitespace may be part of
    // the actual password, unlike username which is an identifier.
    final password = _passwordController.text;
    String? usernameError;
    String? passwordError;
    if (username.isEmpty) {
      usernameError = '请输入用户名';
    }
    if (password.isEmpty) {
      passwordError = '请输入密码';
    }
    if (usernameError != null || passwordError != null) {
      setState(() {
        _usernameError = usernameError;
        _passwordError = passwordError;
      });
      return;
    }
    controller.startLogin(username: username, password: password);
  }
}

class _WorkbenchCard extends StatelessWidget {
  const _WorkbenchCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }
}

class _LabelValueRow extends StatelessWidget {
  const _LabelValueRow({
    required this.label,
    required this.value,
    this.labelWidth = 86,
    this.labelStyle,
    this.bottomPadding = 10,
    this.selectable = false,
  });

  final String label;
  final String value;
  final double labelWidth;
  final TextStyle? labelStyle;
  final double bottomPadding;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final defaultLabelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(label, style: labelStyle ?? defaultLabelStyle),
          ),
          Expanded(child: selectable ? SelectableText(value) : Text(value)),
        ],
      ),
    );
  }
}

IconData _assignmentIcon(FfiAssignmentStatus status) {
  return switch (status) {
    FfiAssignmentStatus.pending => Icons.edit_note_outlined,
    FfiAssignmentStatus.submitted => Icons.task_alt,
    FfiAssignmentStatus.expired => Icons.event_busy_outlined,
  };
}

String _roleLabel(FfiRoleName role) {
  return switch (role) {
    FfiRoleName.student => '学生',
    FfiRoleName.teacher => '教师',
    FfiRoleName.assistant => '助教',
  };
}
