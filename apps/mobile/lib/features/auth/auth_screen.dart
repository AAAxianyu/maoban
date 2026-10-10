import 'package:flutter/material.dart';

import '../../app/controller.dart';
import '../../core/api.dart';
import '../growth/room_scene.dart';

class AuthScreen extends StatefulWidget {
  final AppController app;
  const AuthScreen(this.app, {super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final username = TextEditingController();
  final password = TextEditingController();
  final activation = TextEditingController();
  final nickname = TextEditingController();
  bool activating = false, busy = false;
  String? error;
  bool attempted = false;
  final fieldErrors = <String, String>{};
  var form = GlobalKey<FormState>();

  void edited(String field) => setState(() {
    fieldErrors.remove(field);
    error = null;
  });

  String? validateUsername(String? value) {
    final text = (value ?? '').trim();
    if (text.length < 3 || text.length > 80) return '账号须为 3–80 个字符';
    if (!RegExp(r'^[a-zA-Z0-9_.@-]+$').hasMatch(text)) {
      return '账号请用英文字母、数字或 _ . @ -；中文可用作昵称';
    }
    return fieldErrors['username'];
  }

  String? validatePassword(String? value) {
    final length = (value ?? '').trim().runes.length;
    if (length < 10 || length > 128) {
      return '密码须为 10–128 个字符，首尾空格不计入长度';
    }
    return fieldErrors['password'];
  }

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    activation.dispose();
    nickname.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    setState(() {
      attempted = true;
      fieldErrors.clear();
      error = null;
    });
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    var activated = false;
    try {
      if (activating) {
        await widget.app.api.post('/auth/activate', {
          'token': activation.text.trim(),
          'username': username.text.trim(),
          'password': password.text.trim(),
          'nickname': nickname.text.trim(),
        });
        activated = true;
        if (mounted) setState(() => activating = false);
      }
      await widget.app.login(username.text.trim(), password.text.trim());
    } catch (e) {
      if (mounted) {
        setState(() {
          if (e is ApiFailure && !activated) {
            final details = e.details['field_errors'];
            if (details is Map) {
              for (final field in [
                'username',
                'password',
                'token',
                'nickname',
              ]) {
                final message = details[field];
                if (message is String) {
                  fieldErrors[field] = message;
                }
              }
            }
          }
          final message = e is ApiFailure ? e.message : '连接失败，请重试';
          error = activated
              ? '账号已激活。$message\n请直接登录，无需再次使用激活码。'
              : fieldErrors.isEmpty
              ? message
              : null;
        });
        form.currentState?.validate();
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('喵伴', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          const Text('两只小猫，一起升级。'),
          const SizedBox(height: 24),
          const RoomScene(height: 180),
          const SizedBox(height: 24),
          Form(
            key: form,
            autovalidateMode: attempted
                ? AutovalidateMode.onUserInteraction
                : AutovalidateMode.disabled,
            child: Column(
              children: [
                if (activating) ...[
                  TextFormField(
                    key: const ValueKey('auth-token'),
                    controller: activation,
                    enabled: !busy,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '一次性激活码或小屋邀请码',
                      errorMaxLines: 3,
                    ),
                    onChanged: (_) => edited('token'),
                    validator: (v) {
                      final length = (v ?? '').trim().runes.length;
                      return length < 20 || length > 128
                          ? '请粘贴完整激活码或邀请码（20–128 个字符）'
                          : fieldErrors['token'];
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('auth-nickname'),
                    controller: nickname,
                    enabled: !busy,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '昵称（可用中文）',
                      errorMaxLines: 3,
                    ),
                    maxLength: 40,
                    onChanged: (_) => edited('nickname'),
                    validator: (v) {
                      final length = (v ?? '').trim().runes.length;
                      return length < 1 || length > 40
                          ? '昵称须为 1–40 个字符'
                          : fieldErrors['nickname'];
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  key: const ValueKey('auth-username'),
                  controller: username,
                  enabled: !busy,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '账号',
                    helperText: '3–80 位英文字母、数字，或 _ . @ -',
                    helperMaxLines: 2,
                    errorMaxLines: 3,
                  ),
                  autofillHints: const [AutofillHints.username],
                  onChanged: (_) => edited('username'),
                  validator: validateUsername,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('auth-password'),
                  controller: password,
                  enabled: !busy,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => submit(),
                  decoration: const InputDecoration(
                    labelText: '密码',
                    helperText: '10–128 个字符，首尾空格不计入长度',
                    helperMaxLines: 2,
                    errorMaxLines: 3,
                  ),
                  autofillHints: const [AutofillHints.password],
                  onChanged: (_) => edited('password'),
                  validator: validatePassword,
                ),
                const SizedBox(height: 16),
                if (error != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: busy ? null : submit,
                    child: Text(
                      busy
                          ? '正在连接…'
                          : activating
                          ? '激活并登录'
                          : '登录',
                    ),
                  ),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          activating = !activating;
                          attempted = false;
                          fieldErrors.clear();
                          error = null;
                          form = GlobalKey<FormState>();
                        }),
                  child: Text(activating ? '已有账号，去登录' : '首次使用？激活账号'),
                ),
                const Text(
                  '喵伴仅对受邀成员开放。第一次使用的激活码由服务器维护者提供。',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
