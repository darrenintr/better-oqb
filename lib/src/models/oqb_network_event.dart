class OqbNetworkEvent {
  const OqbNetworkEvent({
    required this.kind,
    required this.method,
    required this.url,
    required this.timestamp,
    this.status,
    this.contentType = '',
    this.requestBody = '',
    this.responsePreview = '',
    this.durationMs,
  });

  final String kind;
  final String method;
  final String url;
  final String timestamp;
  final int? status;
  final String contentType;
  final String requestBody;
  final String responsePreview;
  final double? durationMs;

  bool get looksLikeApi {
    final lowerUrl = url.toLowerCase();
    final lowerType = contentType.toLowerCase();
    final isOqb = lowerUrl.startsWith('/api/') ||
        lowerUrl.startsWith('/public/') ||
        lowerUrl.contains('oqb.edcity.hk/api/') ||
        lowerUrl.contains('oqb.edcity.hk/public/');
    final isIrrelevantRoster = lowerUrl.contains('/api/get_teachers');
    return isOqb &&
        !isIrrelevantRoster &&
        (lowerType.contains('json') ||
            lowerUrl.contains('/api/') ||
            lowerUrl.contains('/public/'));
  }

  String get signature => '$method $url';

  factory OqbNetworkEvent.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status'];
    final rawDuration = json['durationMs'];

    return OqbNetworkEvent(
      kind: json['kind']?.toString() ?? 'resource',
      method: json['method']?.toString().toUpperCase() ?? 'GET',
      url: json['url']?.toString() ?? '',
      timestamp: json['timestamp']?.toString() ?? '',
      status: rawStatus is num
          ? rawStatus.toInt()
          : int.tryParse(rawStatus?.toString() ?? ''),
      contentType: json['contentType']?.toString() ?? '',
      requestBody: json['requestBody']?.toString() ?? '',
      responsePreview: json['responsePreview']?.toString() ?? '',
      durationMs: rawDuration is num
          ? rawDuration.toDouble()
          : double.tryParse(rawDuration?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'method': method,
        'url': url,
        'timestamp': timestamp,
        if (status != null) 'status': status,
        if (contentType.isNotEmpty) 'contentType': contentType,
        if (requestBody.isNotEmpty) 'requestBody': requestBody,
        if (responsePreview.isNotEmpty) 'responsePreview': responsePreview,
        if (durationMs != null) 'durationMs': durationMs,
      };
}
