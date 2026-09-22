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
  final _nameController = TextEditingController();
  bool _isLogin = true; // true = login, false = create account
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
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
            .createAccount(email, password, name: _nameController.text.trim());
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
    final notifier = ref.read(authControllerProvider.notifier);
    await notifier.signInWithGoogle();
    // ref/context NÃO podem ser usados pós-await (widget pode ter sido
    // desmontado — crash "Cannot use ref after disposed" visto no A15).
    // Captura tudo antes; usa os handles capturados depois.
    if (!context.mounted) return;
    final auth = ref.read(authControllerProvider);
    if (auth.isAuthenticated) {
      await notifier.syncWithBackend();
      if (!context.mounted) return;
      router.go(await OnboardingStore.isComplete() ? '/agenda' : '/onboarding');
    }
  }

  /// Esqueci minha senha: Firebase manda e-mail de redefinição.
  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showError('Digita teu e-mail aí em cima pra recuperar a senha');
      return;
    }
    try {
      await ref
          .read(authControllerProvider.notifier)
          .sendPasswordReset(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Enviamos um link de recuperação pra $email'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (_) {
      // erro já exposto via provider
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
                    // Logo da MARCA AGENVA (A + checkmark) — o app é
                    // multi-segmento; ícone de segmento (tesoura) aqui
                    // acoplava a marca à beleza.
                    Image.asset('assets/images/agenva_logo.png',
                        width: 80, height: 80),
                    const SizedBox(height: 16),
                    Text('AGENVA',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('Sua agenda, seu negócio',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.neutral)),
                  ],
                ),
              ),
              const SizedBox(height: 48),
              // Form
              Text(_isLogin ? 'Bem-vindo de volta' : 'Cria tua conta',
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
              // Nome do prestador: só no cadastro (contas Google já trazem
              // o nome da conta; email/senha precisam pedir).
              if (!_isLogin) ...[
                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Teu nome',
                    hintText: 'Como os clientes vão te ver',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 16),
              ],
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
              // Esqueci minha senha: só no modo login (conta nova ainda
              // não tem senha pra recuperar).
              if (_isLogin)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: auth.isLoading ? null : _resetPassword,
                    child: const Text('Esqueci minha senha'),
                  ),
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
