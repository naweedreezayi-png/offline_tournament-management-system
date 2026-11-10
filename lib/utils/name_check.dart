import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';

/// Result of checking a list of names for duplicates.
class NameCheckResult {
  /// Names that can be used (first occurrence of each distinct name).
  final List<String> unique;

  /// Names that were rejected because they repeat an earlier or existing name.
  final List<String> duplicates;
  const NameCheckResult(this.unique, this.duplicates);
  bool get hasDuplicates => duplicates.isNotEmpty;
}

/// One single rule for "are these two names the same?", used everywhere a
/// team / player is registered (new tournament, bulk add, add-later).
///
/// Two names are the same when they match after: trimming, collapsing
/// repeated spaces, ignoring upper/lower case, and unifying look-alike
/// Arabic / Persian letters (ي ی ى, ك ک, ة ه ۀ, أ إ آ ا), removing
/// diacritics and tatweel. So "احمدی", " احمدي " and "احمدی" are one name.
class NameCheck {
  NameCheck._();

  static final RegExp _marks = RegExp('[ً-ٰٟـ‌‍]');
  static final RegExp _spaces = RegExp(r'\s+');

  static String key(String name) {
    var s = name.trim().toLowerCase();
    s = s.replaceAll(_marks, '');
    s = s
        .replaceAll('ي', 'ی') // ي -> ی
        .replaceAll('ى', 'ی') // ى -> ی
        .replaceAll('ك', 'ک') // ك -> ک
        .replaceAll('ة', 'ه') // ة -> ه
        .replaceAll('ۀ', 'ه') // ۀ -> ه
        .replaceAll('أ', 'ا') // أ -> ا
        .replaceAll('إ', 'ا') // إ -> ا
        .replaceAll('آ', 'ا'); // آ -> ا
    return s.replaceAll(_spaces, ' ');
  }

  /// Splits [names] into usable and duplicate names. Names equal to one in
  /// [existing] (already registered) or repeated inside [names] are rejected.
  static NameCheckResult check(Iterable<String> names, {Iterable<String> existing = const []}) {
    final seen = <String>{for (final e in existing) key(e)};
    final unique = <String>[];
    final dups = <String>[];
    for (final raw in names) {
      final n = raw.trim();
      if (n.isEmpty) continue;
      if (seen.add(key(n))) {
        unique.add(n);
      } else {
        dups.add(n);
      }
    }
    return NameCheckResult(unique, dups);
  }

  /// Keys that appear more than once in [names] (blank names are ignored).
  static Set<String> repeatedKeys(Iterable<String> names) {
    final seen = <String>{};
    final rep = <String>{};
    for (final raw in names) {
      if (raw.trim().isEmpty) continue;
      final k = key(raw);
      if (!seen.add(k)) rep.add(k);
    }
    return rep;
  }

  /// True when [name] is already used by one of [existing] tournament names.
  static bool isTaken(String name, Iterable<String> existing) {
    final k = key(name);
    if (k.isEmpty) return false;
    return existing.any((e) => key(e) == k);
  }

  /// Message box for a tournament name that already exists.
  static Future<void> showDuplicateTournamentDialog(BuildContext context, String name) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 44),
        title: Text(ctx.tr('dupTourTitle'), textAlign: TextAlign.center),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(ctx.tr('dupTourBody'), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Chip(
              label: Text(name),
              backgroundColor: Colors.orange.withValues(alpha: 0.15),
            ),
            const SizedBox(height: 12),
            Text(ctx.tr('dupTourHint'),
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
          ]),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.tr('dupOk')),
          ),
        ],
      ),
    );
  }

  /// The message box: two identical names are not allowed, use a nickname.
  static Future<void> showDuplicateDialog(BuildContext context, List<String> names) {
    final shown = names.toSet().toList();
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 44),
        title: Text(ctx.tr('dupTitle'), textAlign: TextAlign.center),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(ctx.tr('dupBody'), textAlign: TextAlign.center),
            if (shown.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  for (final n in shown)
                    Chip(
                      label: Text(n),
                      backgroundColor: Colors.orange.withValues(alpha: 0.15),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.lightbulb_outline, size: 20, color: Colors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(ctx.tr('dupHint'), style: const TextStyle(fontSize: 13)),
                ),
              ]),
            ),
          ]),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.tr('dupOk')),
          ),
        ],
      ),
    );
  }
}
