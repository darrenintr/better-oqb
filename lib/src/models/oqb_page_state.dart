class OqbPageState {
  const OqbPageState({
    this.url = '',
    this.title = '',
    this.headings = const <String>[],
    this.actions = const <String>[],
    this.isLoggedIn,
  });

  final String url;
  final String title;
  final List<String> headings;
  final List<String> actions;
  final bool? isLoggedIn;

  OqbPageState copyWith({
    String? url,
    String? title,
    List<String>? headings,
    List<String>? actions,
    bool? isLoggedIn,
  }) {
    return OqbPageState(
      url: url ?? this.url,
      title: title ?? this.title,
      headings: headings ?? this.headings,
      actions: actions ?? this.actions,
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
    );
  }

  factory OqbPageState.fromJson(Map<String, dynamic> json) {
    List<String> strings(dynamic value) => value is List
        ? value.whereType<Object>().map((item) => item.toString()).toList()
        : const <String>[];

    return OqbPageState(
      url: json['url']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      headings: strings(json['headings']),
      actions: strings(json['actions']),
      isLoggedIn: json['isLoggedIn'] is bool ? json['isLoggedIn'] as bool : null,
    );
  }
}
