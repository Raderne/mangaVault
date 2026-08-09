import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/server_config.dart';

/// Outcome of probing a server the user has typed in but not yet saved.
///
/// Modelled as distinct cases rather than a bool + message because the setup
/// screen acts differently on each: a bad token is the *token* field's problem,
/// an unreachable host is the *address* field's, and a reachable box that isn't
/// a Manga Vault server is neither — it means they typed the right address for
/// the wrong thing.
sealed class ConnectionResult {
  const ConnectionResult();
}

/// Reached the server and the token was accepted.
class ConnectionOk extends ConnectionResult {
  const ConnectionOk();
}

/// Nothing answered at that address.
class ConnectionUnreachable extends ConnectionResult {
  const ConnectionUnreachable(this.detail);

  final String detail;
}

/// Something answered, but it isn't a Manga Vault server.
class ConnectionNotVault extends ConnectionResult {
  const ConnectionNotVault();
}

/// The server is there; the token is wrong.
class ConnectionBadToken extends ConnectionResult {
  const ConnectionBadToken();
}

/// Reached it, but it answered with something unexpected.
class ConnectionFailed extends ConnectionResult {
  const ConnectionFailed(this.detail);

  final String detail;
}

/// Verifies a server address and token before the app commits to them.
///
/// Two probes, in order, because they fail for different reasons:
///
/// 1. `GET /health` — public, so it proves the *address* reaches a Manga Vault
///    server without involving the token at all. It also catches the common
///    mistake of pointing at a router admin page or an unrelated service,
///    which would otherwise surface as a baffling 401.
/// 2. `GET /categories` — guarded and cheap, so it proves the *token*.
///
/// Doing it in one shot against a guarded route could not tell "wrong address"
/// from "wrong token", and that is the entire difficulty of setting this up.
class ConnectionChecker {
  const ConnectionChecker({Dio Function(BaseOptions)? clientFactory})
      : _clientFactory = clientFactory ?? Dio.new;

  final Dio Function(BaseOptions) _clientFactory;

  Future<ConnectionResult> check(ServerConfig config) async {
    if (config.baseUrl.isEmpty) {
      return const ConnectionUnreachable('No server address.');
    }

    final dio = _clientFactory(
      BaseOptions(
        baseUrl: config.apiBase,
        // Short: this runs while someone watches a spinner, and a LAN address
        // that isn't listening should fail fast, not hang for 30 seconds.
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        // We inspect non-2xx ourselves — a 401 is an answer, not an error.
        validateStatus: (_) => true,
      ),
    );

    try {
      final health = await dio.get<dynamic>('/health');
      if (health.statusCode != 200) {
        return ConnectionFailed(
          'The server answered with HTTP ${health.statusCode}.',
        );
      }
      final body = health.data;
      if (body is! Map || body['service'] != 'mangavault-server') {
        return const ConnectionNotVault();
      }
    } on DioException catch (error) {
      return ConnectionUnreachable(_reachabilityDetail(error));
    } on Object catch (error) {
      return ConnectionUnreachable(error.toString());
    }

    try {
      final auth = await dio.get<dynamic>(
        '/categories',
        options: Options(
          headers: {'Authorization': 'Bearer ${config.apiToken}'},
        ),
      );
      return switch (auth.statusCode) {
        200 => const ConnectionOk(),
        401 || 403 => const ConnectionBadToken(),
        final code => ConnectionFailed('The server answered with HTTP $code.'),
      };
    } on DioException catch (error) {
      return ConnectionUnreachable(_reachabilityDetail(error));
    } on Object catch (error) {
      return ConnectionFailed(error.toString());
    }
  }

  String _reachabilityDetail(DioException error) => switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout =>
          'The server did not respond in time.',
        DioExceptionType.badCertificate =>
          "The server's HTTPS certificate was rejected.",
        _ => 'Could not connect. Check the address and that you are on the '
            'same network.',
      };
}

final connectionCheckerProvider = Provider<ConnectionChecker>(
  (ref) => const ConnectionChecker(),
);
