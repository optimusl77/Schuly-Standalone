import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

/// Result of a token request (initial code exchange or refresh) against
/// Schulnetz's own `/token.php`.
class LocalTokenResult {
  final bool success;
  final String? accessToken;
  final String? refreshToken;
  final String? message;
  const LocalTokenResult({
    required this.success,
    this.accessToken,
    this.refreshToken,
    this.message,
  });
}

/// Pure, context-free helpers for talking to a Schulnetz instance's own OAuth
/// endpoints directly from the device - no Schuly/SchulwareAPI backend
/// involved. Ported from the (open-source) SchulwareAPI proxy's `auth.py`:
/// same client id, same PKCE construction, same `/authorize.php` +
/// `/token.php` shape. The one piece deliberately NOT ported is driving the
/// Microsoft Entra login itself - that's done interactively in an embedded
/// WebView ([MicrosoftAuthPage]) instead of headless HTTP replay, since a
/// real browser engine passes Microsoft's anti-bot challenge and any MFA
/// prompt for free.
class LocalSchulnetzAuth {
  LocalSchulnetzAuth._();

  /// Public, instance-invariant client id - identical for every Schulnetz
  /// install, not a secret (see SchulwareAPI's `DEFAULT_SCHULNETZ_CLIENT_ID`).
  static const _clientId = 'ppyybShnMerHdtBQ';

  static const _alnum =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

  static final Dio _dio = Dio();

  /// Cryptographically random alphanumeric string of [length].
  static String _randomString(int length) {
    final rand = Random.secure();
    return String.fromCharCodes(
      Iterable.generate(length, (_) => _alnum.codeUnitAt(rand.nextInt(_alnum.length))),
    );
  }

  /// One PKCE pair: a 128-char verifier and its S256 challenge
  /// (base64url(SHA256(verifier)), padding stripped).
  static ({String verifier, String challenge}) generatePkce() {
    final verifier = _randomString(128);
    final challenge =
        base64Url.encode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');
    return (verifier: verifier, challenge: challenge);
  }

  /// A CSRF-grade random token, used for both `state` and `nonce`.
  static String randomToken() => _randomString(32);

  /// Builds Schulnetz's PKCE authorize URL. `redirect_uri` is deliberately
  /// empty - Schulnetz then bounces the final callback through an
  /// intermediate `authorize.php` hop and on to its shared cross-school PWA
  /// callback (`schulnetz.web.app/callback?code=..&state=..`), which the
  /// embedded WebView intercepts by matching `state` rather than by host/path
  /// or an app-registered custom scheme.
  static String buildAuthorizeUrl({
    required String baseUrl,
    required String codeChallenge,
    required String state,
    required String nonce,
  }) {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final query = _formEncode({
      'response_type': 'code',
      'client_id': _clientId,
      'state': state,
      'redirect_uri': '',
      'scope': 'openid ',
      'nonce': nonce,
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
    });
    return '$base/authorize.php?$query';
  }

  /// Form-urlencodes [params] the way `application/x-www-form-urlencoded`
  /// (and Python's `urlencode`) actually does: every key keeps its `=`, even
  /// when the value is empty (`redirect_uri=`). `Uri(queryParameters:)`
  /// instead drops the `=` for empty values (`redirect_uri`, no equals sign),
  /// which Schulnetz's PHP backend does not treat as equivalent to an
  /// explicit empty `redirect_uri` - mismatched between the authorize and
  /// token requests, that's a textbook `invalid_grant`.
  static String _formEncode(Map<String, String> params) => params.entries
      .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');

  /// Exchanges an authorization `code` for `access_token`/`refresh_token` at
  /// Schulnetz's own `/token.php` - plain HTTP, no cookies involved.
  static Future<LocalTokenResult> exchangeCode({
    required String baseUrl,
    required String code,
    required String codeVerifier,
  }) {
    return _tokenRequest(baseUrl, {
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': '',
      'code_verifier': codeVerifier,
      'client_id': _clientId,
    });
  }

  /// Standard OAuth2 refresh-token grant against the same `/token.php`. Fast
  /// and silent when it works; the caller falls back to a fresh interactive
  /// login when it doesn't (Schulnetz's refresh-token lifetime isn't
  /// documented, so failure here is an expected, not exceptional, outcome).
  static Future<LocalTokenResult> refreshToken({
    required String baseUrl,
    required String refreshToken,
  }) {
    return _tokenRequest(baseUrl, {
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      'client_id': _clientId,
    });
  }

  static Future<LocalTokenResult> _tokenRequest(
      String baseUrl, Map<String, String> form) async {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '$base/token.php',
        data: _formEncode(form),
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'Accept': 'application/json'},
        ),
      );
      final body = res.data ?? const {};
      final accessToken = body['access_token'] as String?;
      if (accessToken == null) {
        return const LocalTokenResult(success: false, message: 'No access_token in response');
      }
      return LocalTokenResult(
        success: true,
        accessToken: accessToken,
        refreshToken: body['refresh_token'] as String?,
      );
    } on DioException catch (e) {
      return LocalTokenResult(
        success: false,
        message: 'HTTP ${e.response?.statusCode ?? '?'}: ${e.response?.data ?? e.message}',
      );
    }
  }
}
