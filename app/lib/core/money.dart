/// Money helpers. All amounts in the app are **integer cents** of a fictional
/// dollar; nothing here ever touches a `double` for arithmetic.
library;

/// Formats integer cents for display.
///
/// * `fr`: `1 234,56 $` (narrow no-break space for groups, no-break space
///   before the symbol).
/// * `en` (and anything else): `$1,234.56`.
///
/// [signed] adds a leading `+` for positive amounts (deltas, payouts).
/// [compact] drops the cents when the amount is a whole number of dollars.
String formatCents(
  int cents, {
  String locale = 'fr',
  bool signed = false,
  bool compact = false,
}) {
  final isFr = locale.toLowerCase().startsWith('fr');
  final negative = cents < 0;
  // Use BigInt-free integer math; abs of the min int is not an issue for
  // realistic balances, but guard anyway.
  final abs = negative ? -cents : cents;
  final whole = abs ~/ 100;
  final frac = abs % 100;

  final groupSep = isFr ? ' ' : ',';
  final decimalSep = isFr ? ',' : '.';

  final grouped = groupDigits(whole, groupSep);
  final showFrac = !(compact && frac == 0);
  final number =
      showFrac ? '$grouped$decimalSep${frac.toString().padLeft(2, '0')}' : grouped;

  final sign = negative ? '-' : (signed && cents > 0 ? '+' : '');
  return isFr ? '$sign$number \$' : '$sign\$$number';
}

/// Inserts [separator] every three digits from the right.
String groupDigits(int value, String separator) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final fromRight = digits.length - i;
    buffer.write(digits[i]);
    if (fromRight > 1 && fromRight % 3 == 1) buffer.write(separator);
  }
  return buffer.toString();
}

/// Formats a prediction-market share price (0..100 cents) as `62¢`.
/// Sub-cent prices are clamped to `<1¢` / `>99¢` like most market UIs.
String formatPriceCents(double priceCents) {
  if (priceCents < 1) return '<1¢';
  if (priceCents > 99) return '>99¢';
  return '${priceCents.round()}¢';
}

/// Formats a probability (0..1) as a whole percentage: `38 %` in French,
/// `38%` in English.
String formatPercent(double probability, {String locale = 'fr'}) {
  final pct = (probability * 100).round();
  return locale.toLowerCase().startsWith('fr') ? '$pct %' : '$pct%';
}

/// Parses a user-entered amount (`12`, `12,5`, `12.50`) into cents.
/// Returns `null` for anything that is not a positive amount with at most two
/// decimals. Used by bet/deposit inputs; the server re-validates anyway.
int? parseCents(String input) {
  final text = input.trim().replaceAll(RegExp(r'[\s  $]'), '');
  final match = RegExp(r'^(\d{1,9})(?:[.,](\d{1,2}))?$').firstMatch(text);
  if (match == null) return null;
  final whole = int.parse(match.group(1)!);
  final fracText = (match.group(2) ?? '').padRight(2, '0');
  final frac = fracText.isEmpty ? 0 : int.parse(fracText);
  return whole * 100 + frac;
}
