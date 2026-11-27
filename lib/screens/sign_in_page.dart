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
    const purple = Color(0xFF6325A6);
    const ink = Color(0xFF21194F);
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5FC),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final canvasHeight = wide
              ? (height < 620 ? 620.0 : height)
              : (height < width * 1.95 ? width * 1.95 : height);
          final formWidth = wide ? width * .39 : width * .84;
          return SingleChildScrollView(
            child: SizedBox(
              width: width,
              height: canvasHeight,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      wide ? 'assets/screens/login/desktop.png'
                          : 'assets/screens/login/mobile.png',
                      fit: BoxFit.fill,
                      semanticLabel: 'Suffah High School, School Management System',
                    ),
                  ),
                  Positioned(
                    top: canvasHeight * (wide ? .32 : .46),
                    left: wide ? width * .56 : width * .08,
                    width: formWidth,
                    bottom: canvasHeight * (wide ? .14 : .10),
                    child: Theme(
                      data: ThemeData.light().copyWith(
                        colorScheme: ColorScheme.fromSeed(seedColor: purple),
                        inputDecorationTheme: InputDecorationTheme(
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: .75),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFFDAD6E6)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFFDAD6E6)),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                        ),
                      ),
                      child: SingleChildScrollView(
                        child: AutofillGroup(
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text('Welcome Back', style: TextStyle(
                                  color: ink, fontSize: wide ? 30 : 24,
                                  fontWeight: FontWeight.w800,
                                )),
                                const SizedBox(height: 5),
                                const Text('Sign in to access your account',
                                  style: TextStyle(color: Color(0xFF68647D), fontSize: 14)),
                                const SizedBox(height: 18),
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
                                decoration: BoxDecoration(color: const Color(0xFFECE5F7), borderRadius: BorderRadius.circular(10)),
                                child: Text(_message!, style: const TextStyle(fontSize: 12)),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          FilledButton(
                            onPressed: _busy ? null : _signIn,
                            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6325A6), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: _busy
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.login_rounded), SizedBox(width: 10), Text('Sign In')]),
                            ),
                          ),

                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
