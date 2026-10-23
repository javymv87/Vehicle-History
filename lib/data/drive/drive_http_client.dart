import 'dart:async';

import 'package:http/http.dart' as http;

/// Gives an access token, and drops one that Drive refused.
abstract interface class AccessTokenSource {
  /// A token to send now.
  Future<String> token();

  /// Forgets [token] after a 401, so the next [token] is a fresh one.
  Future<void> invalidate(String token);
}

/// An HTTP client that adds `Authorization: Bearer …` to every request and,
/// when Drive answers 401 (the token expired, typically after an hour),
/// gets a fresh token and sends the request once more.
///
/// To send a request twice its body must be kept, so bodies are buffered
/// up to [maxReplayableBytes]: every metadata request and every chunk of a
/// resumable upload (which is how a 401 in the middle of a long upload is
/// survived). A larger body is streamed through and a 401 on it is
/// returned as is. Tokens never appear in logs or exceptions.
class DriveHttpClient extends http.BaseClient {
  /// Creates the client on [_inner] with tokens from [_tokens].
  DriveHttpClient(
    this._tokens, {
    http.Client? inner,
    this.maxReplayableBytes = 16 * 1024 * 1024,
  }) : _inner = inner ?? http.Client();

  /// The source of the access tokens.
  final AccessTokenSource _tokens;

  /// The client that sends the requests.
  final http.Client _inner;

  /// The largest body kept to be sent again after a 401.
  final int maxReplayableBytes;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final declared = request.contentLength ??
        int.tryParse(request.headers['content-length'] ?? '');
    final replayable = declared == null || declared <= maxReplayableBytes;
    if (!replayable) {
      return _inner.send(
        _copy(request, request.finalize(), await _tokens.token(), declared),
      );
    }

    final body = await request.finalize().toBytes();
    final token = await _tokens.token();
    final response =
        await _inner.send(_copy(request, _bytes(body), token, body.length));
    if (response.statusCode != 401) return response;

    await response.stream.drain<void>();
    await _tokens.invalidate(token);
    return _inner.send(
      _copy(request, _bytes(body), await _tokens.token(), body.length),
    );
  }

  /// A one-shot stream of [body].
  static Stream<List<int>> _bytes(List<int> body) =>
      Stream<List<int>>.value(body);

  /// A new request like [original], with [body] of [length] bytes and the
  /// bearer [token].
  static http.StreamedRequest _copy(
    http.BaseRequest original,
    Stream<List<int>> body,
    String token,
    int? length,
  ) {
    final copy = http.StreamedRequest(original.method, original.url)
      ..followRedirects = original.followRedirects
      ..maxRedirects = original.maxRedirects
      ..persistentConnection = original.persistentConnection
      ..contentLength = length
      ..headers.addAll(original.headers)
      ..headers['authorization'] = 'Bearer $token';
    body.listen(
      copy.sink.add,
      onError: copy.sink.addError,
      onDone: copy.sink.close,
      cancelOnError: true,
    );
    return copy;
  }

  @override
  void close() => _inner.close();
}
