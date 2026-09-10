import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/storage/onboarding_store.dart';
import '../../theme/app_theme.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true; // true = login, false = create account
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || !email.contains('@')) {
      _showError('E-mail inválido');
      return;
    }
    if (password.length < 8) {
      _showError('Senha deve ter pelo menos 8 caracteres');
      return;
    }

    try {
      if (_isLogin) {
        await ref
            .read(authControllerProvider.notifier)
            .signInWithEmail(email, password);
      } else {
        await ref
            .read(authControllerProvider.notifier)
            .createAccount(email, password);
      }

      if (mounted && ref.read(authControllerProvider).isAuthenticated) {
        // Sync with backend
        await ref.read(authControllerProvider.notifier).syncWithBackend();
        if (!mounted) return;
        // Navigate based on onboarding completion
        context
            .go(await OnboardingStore.isComplete() ? '/agenda' : '/onboarding');
      }
    } catch (_) {
      // error shown via provider
    }
  }

  Future<void> _handleGoogleSignIn() async {
    final router = GoRouter.of(context);
    await ref.read(authControllerProvider.notifier).signInWithGoogle();
    if (ref.read(authControllerProvider).isAuthenticated) {
      await ref.read(authControllerProvider.notifier).syncWithBackend();
      if (!mounted) return;
      router.go(await OnboardingStore.isComplete() ? '/agenda' : '/onboarding');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),
              // Logo
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.primaryOf(context),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.content_cut,
                          size: 40, color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    Text('Minha Agenda',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('Agenda pra profissionais da beleza',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.neutral)),
                  ],
                ),
              ),
              const SizedBox(height: 48),
              // Form
              Text(_isLogin ? 'Bem-vinda de volta' : 'Cria tua conta',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                  _isLogin
                      ? 'Entra com teu e-mail e senha'
                      : 'É rápido, a gente promete',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.neutral)),
              const SizedBox(height: 24),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'E-mail',
                  hintText: 'voce@exemplo.com',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Senha',
                  hintText: _isLogin ? 'Tua senha' : 'Mínimo 8 caracteres',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword
                        ? Icons.visibility
                        : Icons.visibility_off),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              if (auth.error != null) ...[
                const SizedBox(height: 12),
                Text(auth.error!,
                    style:
                        const TextStyle(color: AppColors.error, fontSize: 13)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: auth.isLoading ? null : _submit,
                child: auth.isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(_isLogin ? 'Entrar' : 'Criar conta'),
              ),
              const SizedBox(height: 16),
              // Google sign in
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('ou',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.neutral)),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon:
                      Image.asset('assets/images/google_logo.png', height: 20),
                  label: const Text('Continuar com Google'),
                  onPressed: auth.isLoading ? null : _handleGoogleSignIn,
                ),
              ),
              const SizedBox(height: 24),
              // Toggle login/register
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_isLogin ? 'Não tem conta? ' : 'Já tem conta? ',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.neutral)),
                  TextButton(
                    onPressed: () => setState(() => _isLogin = !_isLogin),
                    child: Text(_isLogin ? 'Criar conta' : 'Entrar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
