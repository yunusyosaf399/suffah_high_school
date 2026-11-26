import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hidden = true;
  String? _message;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate() || _busy) return;
    setState(() { _busy = true; _message = null; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _message = switch (error.code) {
          'invalid-email' => 'Enter a valid email address.',
          'invalid-credential' || 'wrong-password' || 'user-not-found' =>
            'The email or password is incorrect.',
          'too-many-requests' => 'Too many attempts. Try again later.',
          'network-request-failed' => 'Check your internet connection.',
          _ => 'Sign-in failed. Please try again.',
        };
      });
    } catch (_) {
      if (mounted) setState(() => _message = 'Unable to sign in right now.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _message = 'Enter your email first to reset your password.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) setState(() => _message = 'If this account exists, a reset email will arrive shortly.');
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not request a password reset. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? 440 : 420),
                child: Card(
                  elevation: 0,
                  color: scheme.surface,
                  child: Padding(
                    padding: EdgeInsets.all(wide ? 36 : 24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Align(
                            alignment: Alignment.center,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: Image.asset(
                                'assets/icon/app_icon.png',
                                width: 112,
                                height: 112,
                                fit: BoxFit.contain,
                                semanticLabel: 'Suffah High School logo',
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          Text('Welcome back', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text('Suffah High School • Management portal', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                          const SizedBox(height: 28),
                          TextFormField(
                            controller: _email,
                            enabled: !_busy,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(labelText: 'Email address', prefixIcon: Icon(Icons.mail_outline_rounded)),
                            validator: (value) => value == null || !value.trim().contains('@') ? 'Enter your email address' : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _password,
                            enabled: !_busy,
                            obscureText: _hidden,
                            autofillHints: const [AutofillHints.password],
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _signIn(),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline_rounded),
                              suffixIcon: IconButton(
                                tooltip: _hidden ? 'Show password' : 'Hide password',
                                icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                onPressed: () => setState(() => _hidden = !_hidden),
                              ),
                            ),
                            validator: (value) => value == null || value.isEmpty ? 'Enter your password' : null,
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(onPressed: _busy ? null : _resetPassword, child: const Text('Forgot password?')),
                          ),
                          if (_message != null) ...[
                            Semantics(
                              liveRegion: true,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
                                child: Text(_message!, style: const TextStyle(fontSize: 12)),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          FilledButton(
                            onPressed: _busy ? null : _signIn,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: _busy
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Text('Sign in'),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text('Staff and parents receive access from school administration.', textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
