import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_cloud_ffi/open_cloud_ffi.dart' show FfiRoleName;

import 'client_controller.dart';

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
    final state = ref.watch(clientControllerProvider);
    final controller = ref.read(clientControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Open UCloud'),
        actions: [
          if (state.phase == ClientPhase.authenticated ||
              state.phase == ClientPhase.loadingCourses) ...[
            IconButton(
              tooltip: '刷新课程',
              onPressed: state.isBusy ? null : controller.refreshCourses,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: '退出登录',
              onPressed: state.isBusy ? null : controller.logout,
              icon: const Icon(Icons.logout),
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: switch (state.phase) {
            ClientPhase.bootstrapping => const _LoadingPane(label: '正在恢复会话'),
            ClientPhase.startingLogin => const _LoadingPane(label: '正在初始化登录'),
            ClientPhase.finishingLogin => const _LoadingPane(label: '正在登录'),
            ClientPhase.loadingCourses => _CoursePane(state: state),
            ClientPhase.authenticated => _CoursePane(state: state),
            ClientPhase.awaitingCaptcha => _LoginPane(state: state),
            ClientPhase.unauthenticated => _LoginPane(state: state),
          },
        ),
      ),
    );
  }
}

class _LoginPane extends ConsumerStatefulWidget {
  const _LoginPane({required this.state});

  final ClientState state;

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
    _usernameController = TextEditingController(
      text: widget.state.pendingUsername ?? '',
    );
    _passwordController = TextEditingController(
      text: widget.state.pendingPassword ?? '',
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
    final state = widget.state;
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

class _CoursePane extends StatelessWidget {
  const _CoursePane({required this.state});

  final ClientState state;

  @override
  Widget build(BuildContext context) {
    final session = state.session;
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
        ] else if (state.courses.isEmpty) ...[
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
          const SizedBox(height: 12),
          Text('课程', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final course in state.courses)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(
                  course.going
                      ? Icons.radio_button_checked
                      : Icons.menu_book_outlined,
                  color: course.going
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                title: Text(course.name),
                subtitle: Text(course.id),
                trailing: course.going
                    ? const Tooltip(
                        message: '正在进行',
                        child: Icon(Icons.notifications_active_outlined),
                      )
                    : null,
              ),
            ),
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

class _CaptchaImage extends StatelessWidget {
  const _CaptchaImage({required this.dataUri});

  final String? dataUri;

  @override
  Widget build(BuildContext context) {
    final bytes = _decodeDataUri(dataUri);
    if (bytes == null) {
      return const SizedBox.shrink();
    }
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Image.memory(bytes, height: 72, fit: BoxFit.contain),
        ),
      ),
    );
  }

  Uint8List? _decodeDataUri(String? dataUri) {
    if (dataUri == null) {
      return null;
    }
    final comma = dataUri.indexOf(',');
    if (comma == -1) {
      return null;
    }
    return base64Decode(dataUri.substring(comma + 1));
  }
}
