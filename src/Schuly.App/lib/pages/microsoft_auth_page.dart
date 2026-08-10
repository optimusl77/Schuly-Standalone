import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import '../l10n/app_localizations.dart';
import '../services/local_schulnetz_auth.dart';
import '../utils/logger.dart';

/// Drives Schulnetz's Microsoft/Entra login directly against the school's own
/// Schulnetz instance - no Schuly/SchulwareAPI backend involved at any step.
/// [apiBaseUrl] is the school's Schulnetz base URL (e.g.
/// `https://schulnetz.bbbaden.ch`); the name is kept as-is so every existing
/// call site (which already passes the app-wide `apiBaseUrl`) needs no change.
///
/// PKCE is generated on-device ([LocalSchulnetzAuth]) and the resulting
/// `authorize.php` URL is loaded directly in this WebView - a real browser
/// engine, so it passes Microsoft's anti-bot challenge and any MFA prompt for
/// free. The redirect chain can pass through an intermediate
/// `authorize.php?code=..&state=..` hop carrying Microsoft's own code and an
/// opaque Schulnetz-generated composite state; that must be left to navigate
/// through untouched (grabbing it produces `invalid_grant`). Only the final
/// hop - wherever it lands, typically `schulnetz.web.app/callback` - whose
/// `state` matches the one generated for this attempt is intercepted.
class MicrosoftAuthPage extends StatefulWidget {
  final String apiBaseUrl;
  final String? existingUserEmail; // For re-authentication
  final Function(String token, String refreshToken, String email) onAuthSuccess;

  const MicrosoftAuthPage({
    super.key,
    required this.apiBaseUrl,
    this.existingUserEmail,
    required this.onAuthSuccess,
  });

  @override
  State<MicrosoftAuthPage> createState() => _MicrosoftAuthPageState();
}

class _MicrosoftAuthPageState extends State<MicrosoftAuthPage> {
  WebViewController? _controller;
  late final String _codeVerifier;
  late final String _expectedState;
  late final String _authUrl;
  bool _isLoading = true;
  bool _isWebViewReady = false;
  bool _done = false;
  String _statusMessage = 'Initializing Microsoft authentication...';

  @override
  void initState() {
    super.initState();
    _initializeAuth();
  }

  Future<void> _initializeAuth() async {
    try {
      final pkce = LocalSchulnetzAuth.generatePkce();
      _codeVerifier = pkce.verifier;
      _expectedState = LocalSchulnetzAuth.randomToken();
      _authUrl = LocalSchulnetzAuth.buildAuthorizeUrl(
        baseUrl: widget.apiBaseUrl,
        codeChallenge: pkce.challenge,
        state: _expectedState,
        nonce: LocalSchulnetzAuth.randomToken(),
      );

      logInfo('Generated local OAuth URL and code verifier', source: 'MicrosoftAuthPage');
      logDebug('OAuth URL: $_authUrl', source: 'MicrosoftAuthPage');

      if (widget.existingUserEmail != null) {
        logInfo('Re-authentication for user: ${widget.existingUserEmail}', source: 'MicrosoftAuthPage');
      }

      await _initializeWebView();

      if (mounted) {
        setState(() {
          _statusMessage = 'Loading Microsoft login page...';
          _isWebViewReady = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      logError('Failed to initialize OAuth', source: 'MicrosoftAuthPage', error: e);
      setState(() {
        _isLoading = false;
        _statusMessage = 'Failed to initialize: ${e.toString()}';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.failedToInitializeMicrosoftAuth(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _initializeWebView() async {
    // Don't clear cookies - keep the WebView session persistent so a later
    // silent refresh (or re-auth) can reuse Microsoft's own session cookie.
    logDebug('Using shared WebView session', source: 'MicrosoftAuthPage');

    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(false)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            logDebug('Page started loading: $url', source: 'MicrosoftAuthPage');
            if (mounted) {
              setState(() => _statusMessage = 'Loading Microsoft login...');
            }
          },
          onPageFinished: (String url) {
            logDebug('Page finished loading', source: 'MicrosoftAuthPage');
            if (mounted) {
              setState(() {
                _isLoading = false;
                _statusMessage = '';
              });
            }
          },
          onNavigationRequest: _onNavigationRequest,
          onWebResourceError: (WebResourceError error) {
            logError('WebView error: ${error.description}', source: 'MicrosoftAuthPage');
            if (mounted) {
              setState(() => _statusMessage = 'Error: ${error.description}');
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_authUrl));
  }

  /// Only intercepts the hop whose `state` matches [_expectedState] exactly -
  /// deliberately host/path-agnostic (see class doc): the real final callback
  /// doesn't necessarily land back on the school's own Schulnetz domain, and
  /// an intermediate hop can carry a similarly `code=..&state=..`-shaped URL
  /// that must be left to navigate through untouched.
  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    logDebug('Navigation request to: ${request.url}', source: 'MicrosoftAuthPage');
    final uri = Uri.tryParse(request.url);
    final code = uri?.queryParameters['code'];
    final state = uri?.queryParameters['state'];
    if (code != null && state == _expectedState) {
      logInfo('Matched final callback with authorization code', source: 'MicrosoftAuthPage');
      _handleAuthorizationCode(code);
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  Future<void> _handleAuthorizationCode(String code) async {
    if (_done) return;
    _done = true;
    logInfo('Handling authorization code', source: 'MicrosoftAuthPage');

    setState(() {
      _isLoading = true;
      _statusMessage = 'Processing authentication...';
    });

    try {
      final result = await LocalSchulnetzAuth.exchangeCode(
        baseUrl: widget.apiBaseUrl,
        code: code,
        codeVerifier: _codeVerifier,
      );

      if (result.success && result.accessToken != null) {
        logInfo('Authentication successful', source: 'MicrosoftAuthPage');
        final userEmail = widget.existingUserEmail ?? '';
        widget.onAuthSuccess(result.accessToken!, result.refreshToken ?? '', userEmail);
        if (mounted) Navigator.of(context).pop(true);
      } else {
        throw Exception(result.message ?? 'No access token in response');
      }
    } catch (e) {
      logError('Failed to complete OAuth callback', source: 'MicrosoftAuthPage', error: e);
      _done = false;

      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Authentication failed';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.authenticationFailed(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.signInWithMicrosoft),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: Stack(
        children: [
          if (_isWebViewReady && _controller != null)
            WebViewWidget(controller: _controller!),

          if (_isLoading)
            Container(
              color: Colors.white.withValues(alpha: 0.9),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      _statusMessage,
                      style: const TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
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
