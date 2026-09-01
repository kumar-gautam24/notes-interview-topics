enum CallStatus {
  inFlight,
  success,
  clientError,
  serverError,
  networkError,
  timeout,
  cancelled,
  unknown;

  static CallStatus fromStatusCode(int? code) {
    if (code == null) return CallStatus.unknown;
    if (code >= 200 && code < 400) return CallStatus.success;
    if (code >= 400 && code < 500) return CallStatus.clientError;
    if (code >= 500) return CallStatus.serverError;
    return CallStatus.unknown;
  }
}

enum ErrorKind {
  timeout,
  network,
  cancelled,
  badResponse,
  parse,
  unknown;

  String get label => switch (this) {
        ErrorKind.timeout => 'Timeout',
        ErrorKind.network => 'Network',
        ErrorKind.cancelled => 'Cancelled',
        ErrorKind.badResponse => 'Bad Response',
        ErrorKind.parse => 'Parse Error',
        ErrorKind.unknown => 'Unknown',
      };
}
