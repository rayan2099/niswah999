import 'dart:async';
import 'dart:io';

/// True when [error] is a connectivity failure (no route to the server,
/// refused connection, DNS failure, timeout) rather than a server-side or
/// validation answer. Used to show a plain-language, recoverable message
/// instead of a raw exception string — which can carry a server URL and
/// port and tells the user nothing she can act on.
///
/// Matches on the exception types where available and, because the auth and
/// HTTP layers wrap them inconsistently, on the stable substrings those
/// wrappers keep in their text.
bool isNetworkFailure(Object error) {
  if (error is SocketException || error is TimeoutException) return true;
  final text = error.toString().toLowerCase();
  const markers = [
    'socketexception',
    'clientexception',
    'connection refused',
    'connection reset',
    'connection closed',
    'failed host lookup',
    'network is unreachable',
    'no route to host',
    'timed out',
    'timeoutexception',
    'authretryablefetchexception',
    'xmlhttprequest error',
  ];
  return markers.any(text.contains);
}
