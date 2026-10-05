class OqbOption {
  const OqbOption({
    required this.key,
    required this.label,
    required this.html,
    this.selected = false,
  });

  final String key;
  final String label;
  final String html;
  final bool selected;

  factory OqbOption.fromJson(Map<String, dynamic> json) => OqbOption(
        key: json['key']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        html: json['html']?.toString() ?? '',
        selected: json['selected'] == true,
      );
}

class OqbQuestion {
  const OqbQuestion({
    required this.current,
    required this.total,
    required this.html,
    required this.options,
  });

  final int current;
  final int total;
  final String html;
  final List<OqbOption> options;

  factory OqbQuestion.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    return OqbQuestion(
      current: int.tryParse(json['current']?.toString() ?? '') ?? 0,
      total: int.tryParse(json['total']?.toString() ?? '') ?? 0,
      html: json['html']?.toString() ?? '',
      options: rawOptions is List
          ? rawOptions
              .whereType<Map>()
              .map((item) => OqbOption.fromJson(Map<String, dynamic>.from(item)))
              .toList()
          : const <OqbOption>[],
    );
  }
}

class OqbPageState {
  const OqbPageState({
    this.url = '',
    this.title = '',
    this.headings = const <String>[],
    this.actions = const <String>[],
    this.isLoggedIn,
    this.question,
  });

  final String url;
  final String title;
  final List<String> headings;
  final List<String> actions;
  final bool? isLoggedIn;
  final OqbQuestion? question;

  bool get hasQuestion =>
      question != null &&
      question!.html.trim().isNotEmpty &&
      question!.options.isNotEmpty;

  factory OqbPageState.fromJson(Map<String, dynamic> json) {
    List<String> strings(dynamic value) => value is List
        ? value.whereType<Object>().map((item) => item.toString()).toList()
        : const <String>[];

    final rawQuestion = json['question'];
    return OqbPageState(
      url: json['url']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      headings: strings(json['headings']),
      actions: strings(json['actions']),
      isLoggedIn: json['isLoggedIn'] is bool ? json['isLoggedIn'] as bool : null,
      question: rawQuestion is Map
          ? OqbQuestion.fromJson(Map<String, dynamic>.from(rawQuestion))
          : null,
    );
  }
}
