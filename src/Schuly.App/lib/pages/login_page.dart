import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../providers/api_store.dart';
import '../main.dart';
import 'microsoft_auth_page.dart';

/// Login is Microsoft/Entra-via-Schulnetz only, talking directly to the
/// school's own Schulnetz instance - no Schuly backend, no email+password
/// path (that went through the now-defunct SchulwareAPI proxy).
class LoginPage extends StatefulWidget {
  final void Function(String)? onApiBaseUrlChanged;
  final String? initialApiBaseUrl;
  const LoginPage({super.key, this.onApiBaseUrlChanged, this.initialApiBaseUrl});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _schulnetzUrlController = TextEditingController();
  bool _isLoading = false;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _schulnetzUrlController.text = widget.initialApiBaseUrl ?? apiBaseUrl;
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = 'v${packageInfo.version}';
        });
      }
    } catch (e) {
      // Keep empty string if package info fails
    }
  }

  Future<void> _signInWithMicrosoft() async {
    if (_formKey.currentState == null || !_formKey.currentState!.validate()) return;
    logDebug('Microsoft sign-in button pressed', source: 'LoginPage');

    final schulnetzUrl = _schulnetzUrlController.text.trim();
    setApiBaseUrl(schulnetzUrl);
    widget.onApiBaseUrlChanged?.call(schulnetzUrl);

    setState(() => _isLoading = true);
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => MicrosoftAuthPage(
          apiBaseUrl: schulnetzUrl,
          existingUserEmail: null, // New account
          onAuthSuccess: (token, refreshToken, email) async {
            logDebug('Microsoft auth successful', source: 'LoginPage');

            final apiStore = Provider.of<ApiStore>(context, listen: false);
            await apiStore.addMicrosoftUser(token, refreshToken);
            await apiStore.fetchAll();
          },
        ),
      ),
    );
    if (mounted) setState(() => _isLoading = false);

    if (result == true && mounted) {
      logDebug('Microsoft authentication completed successfully', source: 'LoginPage');
      // Authentication successful - navigation handled by main app
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Form(
                    key: _formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Anmelden',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Verbindet dieses Gerät direkt mit dem Schulnetz deiner '
                            'Schule - kein Schuly-Server dazwischen.',
                            style: Theme.of(context).textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _schulnetzUrlController,
                            decoration: InputDecoration(
                              labelText: 'Schulnetz-URL',
                              hintText: 'https://schulnetz.beispielschule.ch',
                              prefixIcon: const Icon(Icons.school_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.done,
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Bitte Schulnetz-URL eingeben'
                                : null,
                            onFieldSubmitted: (_) {
                              if (!_isLoading) _signInWithMicrosoft();
                            },
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _isLoading ? null : _signInWithMicrosoft,
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: _isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Image.network(
                                      'https://upload.wikimedia.org/wikipedia/commons/4/44/Microsoft_logo.svg',
                                      width: 20,
                                      height: 20,
                                      errorBuilder: (context, error, stackTrace) =>
                                          const Icon(Icons.business, size: 20),
                                    ),
                              label: const Text('Mit Microsoft anmelden'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Version display at the bottom
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: AnimatedOpacity(
                opacity: _appVersion.isNotEmpty ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 500),
                child: Text(
                  _appVersion,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
