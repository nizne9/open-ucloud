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
    return Scaffold(
      appBar: authenticated
          ? null
          : AppBar(
              title: const Text('Open UCloud'),
              actions: [_ThemeModeMenu(themeMode: themeMode)],
            ),
      body: SafeArea(
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
    return NavigationBar(
      selectedIndex: _destinationIndex(selectedTab),
      onDestinationSelected: (index) =>
          _selectClientTab(_clientDestinations[index].tab, ref),
      destinations: [
        for (final destination in _clientDestinations)
          NavigationDestination(
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
          ClientTab.courses => const _CoursePane(),
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
                  _selectClientTab(_clientDestinations[index].tab, ref);
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
        return Column(
          children: [
            Expanded(
              child: _WorkbenchFrame(
                selectedTab: selectedTab,
                themeMode: themeMode,
                compact: true,
                child: content,
              ),
            ),
            const _ClientNavigationBar(),
          ],
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
                    onTap: () =>
                        _selectClientTab(_clientDestinations[index].tab, ref),
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
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
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
            onRefresh: isBusy ? null : controller.refreshCourses,
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
                label: const Text('同步课程'),
              ),
              _ThemeModeMenu(themeMode: themeMode),
              IconButton(
                tooltip: '退出登录',
                onPressed: onLogout,
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

void _selectClientTab(ClientTab tab, WidgetRef ref) {
  final controller = ref.read(clientControllerProvider.notifier);
  final state = ref.read(clientControllerProvider);
  controller.selectTab(tab);
  if (tab == ClientTab.dashboard &&
      !state.undoneAssignmentsLoaded &&
      !state.assignmentsLoading) {
    controller.loadUndoneAssignments(selectedTab: ClientTab.dashboard);
  }
  if (tab == ClientTab.assignments &&
      !state.undoneAssignmentsLoaded &&
      !state.assignmentsLoading) {
    controller.loadUndoneAssignments();
  }
  if (tab == ClientTab.resources &&
      state.resources.isEmpty &&
      state.courses.isNotEmpty) {
    controller.loadResourcesForCourse(state.courses.first.id);
  }
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

  @override
  void initState() {
    super.initState();
    final initialState = ref.read(clientControllerProvider);
    _usernameController = TextEditingController(
      text: initialState.pendingUsername ?? '',
    );
    _passwordController = TextEditingController(
      text: initialState.pendingPassword ?? '',
    );
    _captchaController = TextEditingController();
  }

  @override
  void dispose() {
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
            TextField(
              controller: _usernameController,
              enabled: !awaitingCaptcha,
              autofillHints: const [AutofillHints.username],
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '用户名',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              enabled: !awaitingCaptcha,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submitPrimary(controller, awaitingCaptcha),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '密码',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            if (awaitingCaptcha) ...[
              const SizedBox(height: 16),
              _CaptchaImage(dataUri: state.captchaImage),
              const SizedBox(height: 12),
              TextField(
                controller: _captchaController,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) =>
                    controller.finishLogin(captcha: _captchaController.text),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '验证码',
                  prefixIcon: Icon(Icons.verified_outlined),
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
                onPressed: controller.editLoginCredentials,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('修改账号密码'),
              ),
              TextButton.icon(
                onPressed: () => controller.startLogin(
                  username: _usernameController.text,
                  password: _passwordController.text,
                ),
                icon: const Icon(Icons.restart_alt),
                label: const Text('重新获取验证码'),
              ),
            ],
            if (state.errorMessage != null) ...[
              const SizedBox(height: 16),
              _ErrorBanner(message: state.errorMessage!),
            ],
          ],
        ),
      ),
    );
  }

  void _submitPrimary(ClientController controller, bool awaitingCaptcha) {
    if (awaitingCaptcha) {
      controller.finishLogin(captcha: _captchaController.text);
      return;
    }
    controller.startLogin(
      username: _usernameController.text,
      password: _passwordController.text,
    );
  }
}

class _DashboardPane extends ConsumerWidget {
  const _DashboardPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(clientControllerProvider);
    if (state.phase == ClientPhase.authenticated &&
        state.pendingAssignmentsErrorMessage == null &&
        !state.undoneAssignmentsLoaded &&
        !state.assignmentsLoading) {
      Future.microtask(
        () => ref
            .read(clientControllerProvider.notifier)
            .loadUndoneAssignments(
              selectedTab: ClientTab.dashboard,
              clearGlobalError: false,
            ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 860;
        final dashboardError =
            state.errorMessage != null &&
                state.errorMessage != state.pendingAssignmentsErrorMessage
            ? state.errorMessage
            : null;
        final primary = [
          if (dashboardError != null) _ErrorBanner(message: dashboardError),
          _DashboardStatsCard(state: state),
          _CourseContextCard(state: state),
          _PendingAssignmentsCard(state: state),
        ];
        final nextAction = _NextActionCard.maybe(state: state);
        final secondary = [?nextAction];
        if (wide && secondary.isNotEmpty) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 10, 24),
                  children: primary,
                ),
              ),
              Expanded(
                flex: 2,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(10, 16, 20, 24),
                  children: secondary,
                ),
              ),
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [...primary, ...secondary],
        );
      },
    );
  }
}

class _DashboardStatsCard extends ConsumerWidget {
  const _DashboardStatsCard({required this.state});

  final ClientState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = state.session;
    final displayName = session?.user.realName.trim();
    final accountName = displayName == null || displayName.isEmpty
        ? session?.user.userName.trim()
        : displayName;
    return _WorkbenchCard(
      title: '今天需要关注',
      subtitle: state.phase == ClientPhase.loadingCourses
          ? '正在同步课程'
          : '最后同步完成 · 会话有效',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (accountName != null && accountName.isNotEmpty) ...[
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  child: Text(accountName.substring(0, 1)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(accountName),
                      Text(
                        '已登录',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 520 ? 2 : 4;
              return GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: columns == 2 ? 1.2 : 1.75,
                children: [
                  _MetricTile(value: '${state.courses.length}', label: '本期课程'),
                  _MetricTile(
                    value: state.assignmentsLoading
                        ? '...'
                        : '${state.assignments.length}',
                    label: '待提交作业',
                  ),
                  _MetricTile(
                    value: state.resources.isEmpty
                        ? '按课程'
                        : '${state.resources.length}',
                    label: '可下载资料',
                  ),
                  _MetricTile(
                    value: state.capabilities.attendanceQrPayloadParsing
                        ? '可解析'
                        : '只读',
                    label: '签到状态',
                  ),
                ],
              );
            },
          ),
          if (state.capabilities.attendanceQrPayloadParsing) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _openAttendanceQrDialog(context, ref),
                icon: const Icon(Icons.qr_code_scanner_outlined),
                label: const Text('解析二维码'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CourseContextCard extends ConsumerWidget {
  const _CourseContextCard({required this.state});

  final ClientState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(clientControllerProvider.notifier);
    return _WorkbenchCard(
      title: '课程上下文',
      subtitle: '选择课程后查看作业或资料。',
      child: state.courses.isEmpty
          ? const _EmptyInline(icon: Icons.menu_book_outlined, label: '暂无课程')
          : Column(
              children: [
                for (final course in state.courses)
                  _CourseContextRow(
                    course: course,
                    onAssignments: () =>
                        controller.loadCourseAssignments(course.id),
                    onResources: () =>
                        controller.loadResourcesForCourse(course.id),
                  ),
              ],
            ),
    );
  }
}

class _CourseContextRow extends StatelessWidget {
  const _CourseContextRow({
    required this.course,
    required this.onAssignments,
    required this.onResources,
  });

  final CourseItem course;
  final VoidCallback onAssignments;
  final VoidCallback onResources;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackActions = constraints.maxWidth < 560;
          final summary = Row(
            children: [
              Icon(
                course.going
                    ? Icons.notifications_active_outlined
                    : Icons.menu_book_outlined,
                color: course.going ? colorScheme.primary : colorScheme.outline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      course.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      course.going ? '${course.id} · going' : course.id,
                      maxLines: 1,
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
            alignment: stackActions ? WrapAlignment.end : WrapAlignment.start,
            children: [
              OutlinedButton(
                onPressed: onAssignments,
                child: const Text('查看作业'),
              ),
              FilledButton.tonal(
                onPressed: onResources,
                child: const Text('查看资料'),
              ),
            ],
          );
          return Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: stackActions
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [summary, const SizedBox(height: 10), actions],
                  )
                : Row(
                    children: [
                      Expanded(child: summary),
                      const SizedBox(width: 12),
                      actions,
                    ],
                  ),
          );
        },
      ),
    );
  }
}

class _PendingAssignmentsCard extends ConsumerWidget {
  const _PendingAssignmentsCard({required this.state});

  final ClientState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(clientControllerProvider.notifier);
    final loadError =
        !state.assignmentsLoaded &&
        state.pendingAssignmentsErrorMessage != null;
    return _WorkbenchCard(
      title: '待办队列',
      subtitle: '优先处理仍可提交的作业。',
      child: state.assignmentsLoading
          ? const _LoadingPane(label: '正在加载待提交作业')
          : loadError
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ErrorBanner(message: state.pendingAssignmentsErrorMessage!),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => controller.loadUndoneAssignments(
                      selectedTab: ClientTab.dashboard,
                    ),
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试待办'),
                  ),
                ),
              ],
            )
          : state.assignments.isEmpty
          ? const _EmptyInline(
              icon: Icons.assignment_late_outlined,
              label: '当前没有待提交作业',
            )
          : Column(
              children: [
                for (final assignment in state.assignments)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(_assignmentIcon(assignment.status)),
                      title: Text(
                        assignment.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${assignment.siteName} · 截止 ${assignment.endTime}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: FilledButton.tonal(
                        onPressed: () async {
                          controller.selectTab(ClientTab.assignments);
                          await controller.selectAssignment(assignment);
                        },
                        child: const Text('继续提交'),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _NextActionCard extends ConsumerWidget {
  const _NextActionCard({required this.state});

  static Widget? maybe({required ClientState state}) {
    return state.assignments.isEmpty ? null : _NextActionCard(state: state);
  }

  final ClientState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(clientControllerProvider.notifier);
    final next = state.assignments.isEmpty ? null : state.assignments.first;
    return _WorkbenchCard(
      title: '下一步动作',
      subtitle: '从最近的待提交作业继续。',
      child: next == null
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  next.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text('${next.siteName} · 截止 ${next.endTime}'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _AssignmentMetaChip(
                      icon: _assignmentIcon(next.status),
                      label: _assignmentStatusText(next.status),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () async {
                    controller.selectTab(ClientTab.assignments);
                    await controller.selectAssignment(next);
                  },
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('进入提交'),
                ),
              ],
            ),
    );
  }
}

class _AccountPane extends ConsumerWidget {
  const _AccountPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(clientControllerProvider);
    final controller = ref.read(clientControllerProvider.notifier);
    final session = state.session;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        _WorkbenchCard(
          title: '账户状态',
          subtitle: '当前登录账号。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (session != null) ...[
                _AccountBadge(name: session.user.realName, subtitle: '已登录'),
                const SizedBox(height: 12),
                _InfoRow(label: '角色', value: _roleLabel(session.selectedRole)),
                _InfoRow(label: '账号', value: session.user.account),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: state.isBusy ? null : controller.refreshCourses,
                    icon: const Icon(Icons.refresh),
                    label: const Text('同步课程'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: state.isBusy ? null : controller.logout,
                    icon: const Icon(Icons.logout),
                    label: const Text('退出登录'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _EmptyInline extends StatelessWidget {
  const _EmptyInline({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(icon, size: 36, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 8),
          Text(label, textAlign: TextAlign.center),
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

void _openAttendanceQrDialog(BuildContext context, WidgetRef ref) {
  ref
      .read(clientControllerProvider.notifier)
      .clearAttendanceQrPayloadParseState();
  showDialog<void>(
    context: context,
    builder: (_) => const _AttendanceQrPayloadDialog(),
  );
}

class _CoursePane extends ConsumerWidget {
  const _CoursePane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(clientControllerProvider);
    final session = state.session;
    final controller = ref.read(clientControllerProvider.notifier);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (session != null)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text(session.user.realName),
            subtitle: Text(_roleLabel(session.selectedRole)),
          ),
        if (state.errorMessage != null) ...[
          const SizedBox(height: 8),
          _ErrorBanner(message: state.errorMessage!),
        ],
        if (state.phase == ClientPhase.loadingCourses) ...[
          const SizedBox(height: 24),
          const _LoadingPane(label: '正在加载课程'),
        ] else ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '课程',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (state.capabilities.attendanceQrPayloadParsing)
                OutlinedButton.icon(
                  onPressed: () {
                    ref
                        .read(clientControllerProvider.notifier)
                        .clearAttendanceQrPayloadParseState();
                    showDialog<void>(
                      context: context,
                      builder: (_) => const _AttendanceQrPayloadDialog(),
                    );
                  },
                  icon: const Icon(Icons.qr_code_scanner_outlined),
                  label: const Text('解析二维码'),
                ),
            ],
          ),
          if (state.courses.isEmpty) ...[
            const SizedBox(height: 48),
            Icon(
              Icons.inbox_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              '暂无课程',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ] else ...[
            const SizedBox(height: 8),
            for (final course in state.courses)
              _CourseCard(
                course: course,
                onAssignments: () =>
                    controller.loadCourseAssignments(course.id),
                onResources: () => controller.loadResourcesForCourse(course.id),
              ),
          ],
        ],
      ],
    );
  }

  String _roleLabel(FfiRoleName role) {
    return switch (role) {
      FfiRoleName.student => '学生',
      FfiRoleName.teacher => '教师',
      FfiRoleName.assistant => '助教',
    };
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({
    required this.course,
    required this.onAssignments,
    required this.onResources,
  });

  final CourseItem course;
  final VoidCallback onAssignments;
  final VoidCallback onResources;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackActions = constraints.maxWidth < 520;
          final courseSummary = Row(
            children: [
              Icon(
                course.going
                    ? Icons.radio_button_checked
                    : Icons.menu_book_outlined,
                color: course.going ? colorScheme.primary : colorScheme.outline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      course.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          course.id,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                        if (course.going)
                          _StatusPill(
                            icon: Icons.notifications_active_outlined,
                            label: '正在进行',
                            color: colorScheme.primary,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
          final actions = Wrap(
            alignment: stackActions ? WrapAlignment.end : WrapAlignment.start,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onAssignments,
                icon: const Icon(Icons.assignment_outlined),
                label: const Text('查看作业'),
              ),
              FilledButton.tonalIcon(
                onPressed: onResources,
                icon: const Icon(Icons.folder_outlined),
                label: const Text('查看资料'),
              ),
            ],
          );

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: stackActions
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      courseSummary,
                      const SizedBox(height: 12),
                      actions,
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: courseSummary),
                      const SizedBox(width: 12),
                      actions,
                    ],
                  ),
          );
        },
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttendanceQrPayloadDialog extends ConsumerStatefulWidget {
  const _AttendanceQrPayloadDialog();

  @override
  ConsumerState<_AttendanceQrPayloadDialog> createState() =>
      _AttendanceQrPayloadDialogState();
}

class _AttendanceQrPayloadDialogState
    extends ConsumerState<_AttendanceQrPayloadDialog> {
  late final TextEditingController _payloadController;

  @override
  void initState() {
    super.initState();
    _payloadController = TextEditingController();
  }

  @override
  void dispose() {
    _payloadController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      clientControllerProvider.select(
        (state) => (
          parsedAttendanceQrPayload: state.parsedAttendanceQrPayload,
          attendanceQrInputError: state.attendanceQrInputError,
          courses: state.courses,
        ),
      ),
    );
    final parsed = state.parsedAttendanceQrPayload;
    final matchedCourse = parsed == null
        ? null
        : state.courses
              .where((course) => course.id == parsed.siteId)
              .firstOrNull;
    return AlertDialog(
      title: const Text('解析签到二维码内容'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _payloadController,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '二维码文本',
                ),
              ),
              if (state.attendanceQrInputError != null) ...[
                const SizedBox(height: 12),
                _ErrorBanner(message: state.attendanceQrInputError!),
              ],
              if (parsed != null) ...[
                const SizedBox(height: 16),
                _QrPayloadField(label: '签到 ID', value: parsed.attendanceId),
                _QrPayloadField(label: '课程 ID', value: parsed.siteId),
                _QrPayloadField(label: '创建时间', value: parsed.createTime),
                _QrPayloadField(label: '课节 ID', value: parsed.classLessonId),
                if (matchedCourse != null)
                  _QrPayloadField(label: '课程', value: matchedCourse.name),
                if (matchedCourse?.going ?? false)
                  const _QrPayloadField(label: '状态', value: '正在进行'),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        FilledButton.icon(
          onPressed: () => ref
              .read(clientControllerProvider.notifier)
              .parseAttendanceQrPayloadText(_payloadController.text),
          icon: const Icon(Icons.qr_code_scanner_outlined),
          label: const Text('解析'),
        ),
      ],
    );
  }
}

class _QrPayloadField extends StatelessWidget {
  const _QrPayloadField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

class _AssignmentsPane extends ConsumerWidget {
  const _AssignmentsPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(clientControllerProvider);
    final controller = ref.read(clientControllerProvider.notifier);
    return LayoutBuilder(
      builder: (context, constraints) {
        final useSplit = constraints.maxWidth >= 900;
        if (!useSplit) {
          final showDetail =
              state.selectedAssignmentId != null ||
              state.assignmentDetail != null ||
              state.assignmentDetailLoading;
          if (showDetail) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _FeedbackBanners(
                  state: state,
                  operationContext: OperationContext.assignmentDetail,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed:
                        state.assignmentUploading || state.assignmentSubmitting
                        ? null
                        : controller.clearAssignmentSelection,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('返回作业列表'),
                  ),
                ),
                const SizedBox(height: 8),
                _AssignmentDetailCard(state: state),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: _listChildren(context, ref, state),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: constraints.maxWidth >= 1120 ? 440 : 380,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: _listChildren(context, ref, state),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 24, 24),
                children: [
                  if (state.assignmentDetail == null &&
                      !state.assignmentDetailLoading)
                    const _DetailPlaceholder(
                      icon: Icons.assignment_outlined,
                      title: '选择一个作业',
                      subtitle: '作业要求、附件和提交入口会显示在这里。',
                    )
                  else ...[
                    _FeedbackBanners(
                      state: state,
                      operationContext: OperationContext.assignmentDetail,
                    ),
                    if (state.errorMessage != null ||
                        state.operationMessage != null)
                      const SizedBox(height: 12),
                    _AssignmentDetailCard(state: state),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _listChildren(
    BuildContext context,
    WidgetRef ref,
    ClientState state,
  ) {
    final controller = ref.read(clientControllerProvider.notifier);
    return [
      if (state.errorMessage != null) ...[
        _ErrorBanner(message: state.errorMessage!),
        const SizedBox(height: 12),
      ],
      Row(
        children: [
          Expanded(
            child: SegmentedButton<AssignmentView>(
              segments: const [
                ButtonSegment(
                  value: AssignmentView.undone,
                  icon: Icon(Icons.pending_actions_outlined),
                  label: Text('待提交'),
                ),
                ButtonSegment(
                  value: AssignmentView.course,
                  icon: Icon(Icons.class_outlined),
                  label: Text('按课程'),
                ),
              ],
              selected: {state.assignmentView},
              onSelectionChanged: (selection) {
                final next = selection.single;
                if (next == AssignmentView.undone) {
                  controller.loadUndoneAssignments();
                } else if (state.courses.isNotEmpty) {
                  controller.loadCourseAssignments(state.courses.first.id);
                }
              },
            ),
          ),
          IconButton(
            tooltip: '刷新作业',
            onPressed: state.assignmentsLoading
                ? null
                : () {
                    if (state.assignmentView == AssignmentView.undone) {
                      controller.loadUndoneAssignments();
                    } else {
                      final siteId =
                          state.selectedAssignmentCourseId ??
                          (state.courses.isEmpty
                              ? null
                              : state.courses.first.id);
                      if (siteId != null) {
                        controller.loadCourseAssignments(siteId);
                      }
                    }
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      if (state.assignmentView == AssignmentView.course) ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue:
              state.selectedAssignmentCourseId ??
              (state.courses.isEmpty ? null : state.courses.first.id),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: '课程',
          ),
          items: [
            for (final course in state.courses)
              DropdownMenuItem(
                value: course.id,
                child: Text(
                  course.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) {
              controller.loadCourseAssignments(value);
            }
          },
        ),
      ],
      if (state.assignmentsLoading)
        const _LoadingPane(label: '正在加载作业')
      else if (state.assignments.isEmpty) ...[
        const SizedBox(height: 48),
        _EmptyText(
          icon: Icons.assignment_late_outlined,
          label: state.assignmentView == AssignmentView.undone
              ? '当前没有待提交作业'
              : '当前课程暂无作业',
        ),
      ] else ...[
        const SizedBox(height: 12),
        for (final assignment in state.assignments)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              selected: state.selectedAssignmentId == assignment.id,
              leading: Icon(_assignmentIcon(assignment.status)),
              title: Text(assignment.title),
              subtitle: Text(
                '${assignment.siteName}\n截止：${assignment.endTime}',
              ),
              isThreeLine: true,
              trailing: Text(_assignmentStatusLabel(assignment.status)),
              onTap: () => controller.selectAssignment(assignment),
            ),
          ),
      ],
    ];
  }

  IconData _assignmentIcon(FfiAssignmentStatus status) {
    return switch (status) {
      FfiAssignmentStatus.pending => Icons.edit_note_outlined,
      FfiAssignmentStatus.submitted => Icons.task_alt,
      FfiAssignmentStatus.expired => Icons.event_busy_outlined,
    };
  }

  String _assignmentStatusLabel(FfiAssignmentStatus status) {
    return _assignmentStatusText(status);
  }
}

String _assignmentStatusText(FfiAssignmentStatus status) {
  return switch (status) {
    FfiAssignmentStatus.pending => '待提交',
    FfiAssignmentStatus.submitted => '已提交',
    FfiAssignmentStatus.expired => '已截止',
  };
}

class _AssignmentDetailCard extends ConsumerStatefulWidget {
  const _AssignmentDetailCard({required this.state});

  final ClientState state;

  @override
  ConsumerState<_AssignmentDetailCard> createState() =>
      _AssignmentDetailCardState();
}

class _AssignmentDetailCardState extends ConsumerState<_AssignmentDetailCard> {
  late final TextEditingController _draftController;
  String? _editingAssignmentId;
  String _syncedDraftText = '';
  bool _draftDirty = false;

  @override
  void initState() {
    super.initState();
    _draftController = TextEditingController();
    _syncDraftController();
  }

  @override
  void didUpdateWidget(covariant _AssignmentDetailCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncDraftController();
  }

  @override
  void dispose() {
    _draftController.dispose();
    super.dispose();
  }

  void _syncDraftController() {
    final detail = widget.state.assignmentDetail;
    final nextAssignmentId = detail?.id;
    final nextText = widget.state.assignmentDraft;
    final assignmentChanged = _editingAssignmentId != nextAssignmentId;
    final draftChanged = _syncedDraftText != nextText;
    if (!assignmentChanged && (!draftChanged || _draftDirty)) {
      return;
    }
    _editingAssignmentId = nextAssignmentId;
    _syncedDraftText = nextText;
    _draftDirty = false;
    final oldSelection = _draftController.selection;
    _draftController.text = nextText;
    final offset = oldSelection.baseOffset.clamp(0, nextText.length);
    _draftController.selection = TextSelection.collapsed(offset: offset);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final detail = state.assignmentDetail;
    final controller = ref.read(clientControllerProvider.notifier);
    if (state.assignmentDetailLoading) {
      return const _LoadingPane(label: '正在加载作业详情');
    }
    if (detail == null) {
      return const SizedBox.shrink();
    }
    final expired = detail.status == FfiAssignmentStatus.expired;
    final readOnly = expired;
    final courseName = _assignmentCourseName(state, detail);
    final submittedAttachments = detail.submittedAttachments;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(detail.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _AssignmentMetaChip(
                  icon: Icons.class_outlined,
                  label: courseName,
                ),
                if (detail.endTime.isNotEmpty)
                  _AssignmentMetaChip(
                    icon: Icons.event_outlined,
                    label: '截止 ${detail.endTime}',
                  ),
                _AssignmentMetaChip(
                  icon: expired
                      ? Icons.event_busy_outlined
                      : Icons.edit_note_outlined,
                  label: _assignmentStatusText(detail.status),
                ),
                if (detail.className.trim().isNotEmpty)
                  _AssignmentMetaChip(
                    icon: Icons.groups_outlined,
                    label: detail.className.trim(),
                  ),
                if (detail.startTime.trim().isNotEmpty)
                  _AssignmentMetaChip(
                    icon: Icons.play_circle_outline,
                    label: '开始 ${detail.startTime.trim()}',
                  ),
                if (detail.submittedAt.trim().isNotEmpty)
                  _AssignmentMetaChip(
                    icon: Icons.task_alt,
                    label: '提交 ${detail.submittedAt.trim()}',
                  ),
                if (detail.score != null)
                  _AssignmentMetaChip(
                    icon: Icons.grade_outlined,
                    label: '成绩 ${detail.score}',
                  ),
                if (detail.isOvertimeCommit)
                  const _AssignmentMetaChip(
                    icon: Icons.more_time_outlined,
                    label: '允许超时提交',
                  ),
              ],
            ),
            if (detail.comment.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              _AssignmentSection(
                title: '教师批语',
                child: SelectableText(detail.comment.trim()),
              ),
            ],
            if (detail.content.isNotEmpty) ...[
              const SizedBox(height: 16),
              _AssignmentSection(
                title: '作业要求',
                child: AssignmentContentView(content: detail.content),
              ),
            ],
            if (detail.teacherResources.isNotEmpty) ...[
              const SizedBox(height: 16),
              _AssignmentSection(
                title: '教师附件',
                child: _AssignmentResourceList(
                  resources: detail.teacherResources,
                ),
              ),
            ],
            if (submittedAttachments.isNotEmpty) ...[
              const SizedBox(height: 16),
              _AssignmentSection(
                title: '已提交附件',
                child: _AssignmentResourceList(resources: submittedAttachments),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              minLines: 4,
              maxLines: 8,
              enabled:
                  !readOnly &&
                  !state.assignmentSubmitting &&
                  !state.assignmentUploading,
              controller: _draftController,
              onChanged: (_) {
                _draftDirty = true;
              },
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: readOnly ? '提交内容（只读）' : '提交内容',
              ),
            ),
            const SizedBox(height: 12),
            if (state.assignmentUploading) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text('正在上传附件', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final attachment in state.assignmentAttachments)
                  InputChip(
                    avatar: const Icon(Icons.attach_file, size: 18),
                    label: Text(attachment.name),
                    onDeleted: readOnly || state.assignmentSubmitting
                        ? null
                        : () => controller.removeAssignmentAttachment(
                            attachment.resourceId,
                          ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed:
                      readOnly ||
                          state.assignmentUploading ||
                          state.assignmentSubmitting
                      ? null
                      : () async {
                          final files = await openFiles();
                          for (final file in files) {
                            await controller.uploadAssignmentAttachment(
                              file.path,
                            );
                          }
                        },
                  icon: const Icon(Icons.attach_file),
                  label: Text(state.assignmentUploading ? '上传中' : '添加附件'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed:
                      readOnly ||
                          state.assignmentSubmitting ||
                          state.assignmentUploading
                      ? null
                      : () async {
                          final ok = await _confirm(
                            context,
                            title: '提交作业',
                            content:
                                '将提交「${detail.title}」\n'
                                '课程：$courseName\n'
                                '附件：${state.assignmentAttachments.length} 个',
                          );
                          if (ok) {
                            await controller.submitAssignmentDraft(
                              _draftController.text,
                            );
                          }
                        },
                  icon: const Icon(Icons.send_outlined),
                  label: Text(state.assignmentSubmitting ? '提交中' : '提交'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AssignmentSection extends StatelessWidget {
  const _AssignmentSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _AssignmentMetaChip extends StatelessWidget {
  const _AssignmentMetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _AssignmentResourceList extends StatelessWidget {
  const _AssignmentResourceList({required this.resources});

  final List<FfiAssignmentResource> resources;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          for (final resource in resources)
            ListTile(
              dense: true,
              leading: const Icon(Icons.attach_file),
              title: Text(resource.name),
              subtitle: resource.previewUrl == null
                  ? null
                  : SelectableText(resource.previewUrl!),
              trailing:
                  resource.previewUrl == null || resource.previewUrl!.isEmpty
                  ? null
                  : _LinkActions(url: resource.previewUrl!),
            ),
        ],
      ),
    );
  }
}

class _LinkActions extends StatelessWidget {
  const _LinkActions({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '打开链接',
          onPressed: () => _openExternalLink(context, url),
          icon: const Icon(Icons.open_in_new_outlined),
        ),
        IconButton(
          tooltip: '复制链接',
          onPressed: () => _copyText(context, url),
          icon: const Icon(Icons.copy_outlined),
        ),
      ],
    );
  }
}

class _LinkValue extends StatelessWidget {
  const _LinkValue({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(child: SelectableText(url)),
            _LinkActions(url: url),
          ],
        ),
      ),
    );
  }
}

String _assignmentCourseName(
  ClientState state,
  FfiAssignmentDetailResponse detail,
) {
  final detailName = detail.siteName.trim();
  if (detailName.isNotEmpty) {
    return detailName;
  }
  final detailSiteId = detail.siteId.trim();
  if (detailSiteId.isNotEmpty) {
    for (final course in state.courses) {
      if (course.id == detailSiteId && course.name.trim().isNotEmpty) {
        return course.name;
      }
    }
  }
  for (final assignment in state.assignments) {
    if (assignment.id == detail.id && assignment.siteName.trim().isNotEmpty) {
      return assignment.siteName;
    }
    if (assignment.id == detail.id && assignment.siteId.trim().isNotEmpty) {
      for (final course in state.courses) {
        if (course.id == assignment.siteId && course.name.trim().isNotEmpty) {
          return course.name;
        }
      }
    }
  }
  return '未知课程';
}

String _resourceSummaryText(FfiCourseResourceSummary resource) {
  final parts = [
    if (resource.ext != null && resource.ext!.trim().isNotEmpty)
      resource.ext!.trim().toUpperCase(),
    if (resource.sizeBytes != null) _formatBytes(resource.sizeBytes!),
    if (resource.updatedAt.trim().isNotEmpty) resource.updatedAt.trim(),
  ];
  return parts.isEmpty ? '暂无文件信息' : parts.join(' · ');
}

String _selectedResourceCourseName(ClientState state) {
  final selected = state.selectedResourceCourseId;
  if (selected != null) {
    for (final course in state.courses) {
      if (course.id == selected && course.name.trim().isNotEmpty) {
        return course.name.trim();
      }
    }
  }
  if (state.resources.isNotEmpty && state.resources.first.siteName.isNotEmpty) {
    return state.resources.first.siteName;
  }
  return '当前课程';
}

String _resourceDownloadStatusText(ClientState state) {
  final progress = state.resourceDownloadProgressTotal == 0
      ? '正在准备下载'
      : '正在下载 ${state.resourceDownloadProgressCurrent} / ${state.resourceDownloadProgressTotal} 个文件';
  final fileName = state.resourceDownloadCurrentFileName;
  final bytes = state.resourceDownloadBytes <= 0
      ? null
      : _formatBytes(BigInt.from(state.resourceDownloadBytes));
  final fileNameText = fileName?.trim();
  final details = [
    ?(fileNameText == null || fileNameText.isEmpty ? null : fileNameText),
    ?bytes,
  ];
  return details.isEmpty ? progress : '$progress · ${details.join(' · ')}';
}

String _formatBytes(BigInt bytes) {
  final value = bytes.toDouble();
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = value;
  var unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex += 1;
  }
  final text = unitIndex == 0 || size >= 10
      ? size.toStringAsFixed(0)
      : size.toStringAsFixed(1);
  return '$text ${units[unitIndex]}';
}

class _ResourcesPane extends ConsumerWidget {
  const _ResourcesPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(clientControllerProvider);
    final controller = ref.read(clientControllerProvider.notifier);
    return LayoutBuilder(
      builder: (context, constraints) {
        final useSplit = constraints.maxWidth >= 900;
        if (!useSplit) {
          final showDetail =
              state.selectedResourceId != null ||
              state.resourceDetail != null ||
              state.resourceDetailLoading;
          if (showDetail) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _FeedbackBanners(
                  state: state,
                  operationContext: OperationContext.resourceDetail,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: controller.clearResourceSelection,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('返回资料列表'),
                  ),
                ),
                const SizedBox(height: 8),
                _ResourceDetailCard(state: state),
                if (state.downloadedPaths.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _DownloadSummary(paths: state.downloadedPaths),
                ],
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              ..._listChildren(context, ref, state),
              if (state.downloadedPaths.isNotEmpty) ...[
                const SizedBox(height: 12),
                _DownloadSummary(paths: state.downloadedPaths),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: constraints.maxWidth >= 1120 ? 440 : 380,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: _listChildren(context, ref, state),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 24, 24),
                children: [
                  if (state.resourceDetail == null &&
                      !state.resourceDetailLoading)
                    const _DetailPlaceholder(
                      icon: Icons.insert_drive_file_outlined,
                      title: '选择一个资料',
                      subtitle: '资料说明和单文件下载入口会显示在这里。',
                    )
                  else ...[
                    _FeedbackBanners(
                      state: state,
                      operationContext: OperationContext.resourceDetail,
                    ),
                    if (state.errorMessage != null ||
                        state.operationMessage != null)
                      const SizedBox(height: 12),
                    _ResourceDetailCard(state: state),
                  ],
                  if (state.downloadedPaths.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _DownloadSummary(paths: state.downloadedPaths),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _listChildren(
    BuildContext context,
    WidgetRef ref,
    ClientState state,
  ) {
    final controller = ref.read(clientControllerProvider.notifier);
    return [
      _FeedbackBanners(
        state: state,
        operationContext: OperationContext.resourceList,
      ),
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue:
                  state.selectedResourceCourseId ??
                  (state.courses.isEmpty ? null : state.courses.first.id),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '课程',
              ),
              items: [
                for (final course in state.courses)
                  DropdownMenuItem(
                    value: course.id,
                    child: Text(
                      course.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  controller.loadResourcesForCourse(value);
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: '刷新资料',
            onPressed: state.resourcesLoading || state.courses.isEmpty
                ? null
                : () => controller.loadResourcesForCourse(
                    state.selectedResourceCourseId ?? state.courses.first.id,
                  ),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '下载全部',
            onPressed: state.resourceDownloading || state.resources.isEmpty
                ? null
                : () async {
                    final ok = await _confirm(
                      context,
                      title: '下载全部资料',
                      content:
                          '课程：${_selectedResourceCourseName(state)}\n'
                          '文件：${state.resources.length} 个\n'
                          '选择目录后将下载当前列表中的全部资料。',
                    );
                    if (!ok) {
                      return;
                    }
                    final directory = await getDirectoryPath();
                    if (directory != null) {
                      await controller.downloadCourseResources(directory);
                    }
                  },
            icon: const Icon(Icons.download_for_offline_outlined),
          ),
        ],
      ),
      if (state.resourceDownloading) ...[
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                _resourceDownloadStatusText(state),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            TextButton.icon(
              onPressed: () => controller.cancelActiveResourceDownload(),
              icon: const Icon(Icons.close),
              label: const Text('取消'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: state.resourceDownloadProgressTotal == 0
              ? null
              : state.resourceDownloadProgressCurrent /
                    state.resourceDownloadProgressTotal,
        ),
      ],
      if (state.resourcesLoading)
        const _LoadingPane(label: '正在加载资料')
      else if (state.resources.isEmpty) ...[
        const SizedBox(height: 48),
        const _EmptyText(icon: Icons.folder_off_outlined, label: '当前课程暂无资料'),
      ] else ...[
        const SizedBox(height: 12),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: state.resources.length,
          itemBuilder: (context, index) {
            final resource = state.resources[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                selected: state.selectedResourceId == resource.resourceId,
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(resource.name),
                subtitle: Text(_resourceSummaryText(resource)),
                onTap: () => controller.selectResource(resource),
              ),
            );
          },
        ),
      ],
    ];
  }
}

class _ResourceDetailCard extends ConsumerWidget {
  const _ResourceDetailCard({required this.state});

  final ClientState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = state.resourceDetail;
    final controller = ref.read(clientControllerProvider.notifier);
    if (state.resourceDetailLoading) {
      return const _LoadingPane(label: '正在加载资料详情');
    }
    if (detail == null) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(detail.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (detail.siteName.trim().isNotEmpty)
                  _AssignmentMetaChip(
                    icon: Icons.class_outlined,
                    label: detail.siteName.trim(),
                  ),
                if (detail.ext != null && detail.ext!.trim().isNotEmpty)
                  _AssignmentMetaChip(
                    icon: Icons.insert_drive_file_outlined,
                    label: detail.ext!.trim().toUpperCase(),
                  ),
                if (detail.sizeBytes != null)
                  _AssignmentMetaChip(
                    icon: Icons.data_usage_outlined,
                    label: _formatBytes(detail.sizeBytes!),
                  ),
                if (detail.updatedAt.trim().isNotEmpty)
                  _AssignmentMetaChip(
                    icon: Icons.schedule_outlined,
                    label: detail.updatedAt.trim(),
                  ),
              ],
            ),
            if (detail.description != null &&
                detail.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(detail.description!.trim()),
            ],
            if (detail.downloadUrl != null &&
                detail.downloadUrl!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              _LinkValue(url: detail.downloadUrl!.trim()),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: state.resourceDownloading
                    ? null
                    : () async {
                        final location = await getSaveLocation(
                          suggestedName: detail.name,
                        );
                        if (location != null) {
                          await controller.downloadResource(location.path);
                        }
                      },
                icon: const Icon(Icons.download_outlined),
                label: const Text('下载'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailPlaceholder extends StatelessWidget {
  const _DetailPlaceholder({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: colorScheme.outline),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadSummary extends StatelessWidget {
  const _DownloadSummary({required this.paths});

  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '已下载 ${paths.length} 个文件',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final path in paths)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: SelectableText(path),
              ),
          ],
        ),
      ),
    );
  }
}

class _FeedbackBanners extends StatelessWidget {
  const _FeedbackBanners({required this.state, this.operationContext});

  final ClientState state;
  final OperationContext? operationContext;

  @override
  Widget build(BuildContext context) {
    final operationMessage = state.operationContext == operationContext
        ? state.operationMessage
        : null;
    if (state.errorMessage == null && operationMessage == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.errorMessage != null) ...[
          _ErrorBanner(message: state.errorMessage!),
          const SizedBox(height: 12),
        ],
        if (operationMessage != null) ...[
          _InfoBanner(message: operationMessage),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _EmptyText extends StatelessWidget {
  const _EmptyText({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
        const SizedBox(height: 12),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    );
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String content,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认'),
            ),
          ],
        ),
      ) ??
      false;
}

Future<void> _openExternalLink(BuildContext context, String value) async {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || !uri.hasScheme) {
    _showSnackBar(context, '链接格式无效');
    return;
  }
  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) {
    _showSnackBar(context, '无法打开链接');
  }
}

Future<void> _copyText(BuildContext context, String value) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (context.mounted) {
    _showSnackBar(context, '已复制链接');
  }
}

void _showSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class _LoadingPane extends StatelessWidget {
  const _LoadingPane({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.check_circle_outline,
              color: colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colorScheme.onPrimaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptchaImage extends StatelessWidget {
  const _CaptchaImage({required this.dataUri});

  final String? dataUri;

  @override
  Widget build(BuildContext context) {
    final bytes = _decodeDataUri(dataUri);
    if (bytes == null) {
      return const Text('验证码图片加载失败', textAlign: TextAlign.center);
    }
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Image.memory(
            bytes,
            height: 72,
            fit: BoxFit.contain,
            semanticLabel: '验证码图片',
          ),
        ),
      ),
    );
  }

  typed_data.Uint8List? _decodeDataUri(String? dataUri) {
    if (dataUri == null) {
      return null;
    }
    final comma = dataUri.indexOf(',');
    if (comma == -1) {
      return null;
    }
    try {
      return base64Decode(dataUri.substring(comma + 1));
    } on FormatException {
      return null;
    }
  }
}
