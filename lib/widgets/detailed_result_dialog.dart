import 'package:flutter/material.dart';
import '../domain/sport_scoring.dart';
import '../l10n/app_strings.dart';
import '../models/sport.dart';
import '../theme/app_theme.dart';

/// What the dialog returns: the entered values and their evaluation.
class DetailedResult {
  final Map<String, int> input;
  final ScoreOutcome outcome;
  const DetailedResult(this.input, this.outcome);
}

/// Sport-specific result entry (judo ippon/waza-ari, wrestling technical
/// points, chess result, kurash chala/yonbosh/halal, volleyball sets, ...).
/// The result is validated live by the sport's [SportScoring]; OK is only
/// possible for a valid result. Styled like the rest of the app: navy/blue
/// header, blue (side A) and cyan (side B) accents, readable in both themes.
class DetailedResultDialog extends StatefulWidget {
  final SportScoring scoring;
  final String teamA;
  final String teamB;
  final String lang;
  final Map<String, int> initial;

  const DetailedResultDialog({
    super.key,
    required this.scoring,
    required this.teamA,
    required this.teamB,
    required this.lang,
    this.initial = const {},
  });

  @override
  State<DetailedResultDialog> createState() => _DetailedResultDialogState();
}

class _DetailedResultDialogState extends State<DetailedResultDialog> {
  late final Map<String, int> _v = Map<String, int>.of(widget.initial);
  bool _showNote = false;

  int _get(String key) => _v[key] ?? 0;

  void _set(String key, int value, int max) {
    final clamped = value < 0 ? 0 : (value > max ? max : value);
    setState(() => _v[key] = clamped);
  }

  String _opt(String text) =>
      text.replaceAll('{A}', widget.teamA).replaceAll('{B}', widget.teamB);

  /// Replaces the leading "A " / "B " of a summary with the team name.
  String _named(String summary) {
    if (summary.startsWith('A ')) return '${widget.teamA} ${summary.substring(2)}';
    if (summary.startsWith('B ')) return '${widget.teamB} ${summary.substring(2)}';
    return summary;
  }

  Color _sideA(bool dark) => dark ? const Color(0xFF6EE7B7) : AppColors.primary;
  Color _sideB(bool dark) => dark ? AppColors.cyan : AppColors.cyanDeep;

  Widget _stepper(String key, int max, Color color, bool dark) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    Widget btn(IconData icon, VoidCallback onTap) => Material(
          color: color.withValues(alpha: dark ? 0.22 : 0.14),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 34,
              height: 34,
              child: Icon(icon, size: 20, color: color),
            ),
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(Icons.remove_rounded, () => _set(key, _get(key) - 1, max)),
        SizedBox(
          width: 40,
          child: Text('${_get(key)}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: onSurface)),
        ),
        btn(Icons.add_rounded, () => _set(key, _get(key) + 1, max)),
      ],
    );
  }

  Widget _card(bool dark, {required Widget child}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: dark
              ? Colors.white.withValues(alpha: 0.06)
              : AppColors.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: (dark ? AppColors.glowBlue : AppColors.primary).withValues(alpha: 0.22)),
        ),
        child: child,
      );

  Widget _fieldRow(ScoreField f, bool dark) {
    final cs = Theme.of(context).colorScheme;
    final labels = f.optionLabels(widget.lang);
    final title = Text(f.label(widget.lang),
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: cs.onSurface));
    if (labels != null) {
      return _card(
        dark,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title,
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (var i = 0; i < labels.length; i++)
                  ChoiceChip(
                    label: Text(_opt(labels[i])),
                    selected: _get(f.key) == i,
                    showCheckmark: false,
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _get(f.key) == i ? Colors.white : cs.onSurface,
                    ),
                    selectedColor: AppColors.primary,
                    onSelected: (_) => setState(() => _v[f.key] = i),
                  ),
              ],
            ),
          ],
        ),
      );
    }
    final a = _sideA(dark), b = _sideB(dark);
    return _card(
      dark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _stepper('${f.key}A', f.max, a, dark),
              _stepper('${f.key}B', f.max, b, dark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _teamTag(String name, Color color, bool dark) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: dark ? 0.2 : 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.6)),
          ),
          child: Text(name,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w800, color: color)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final outcome = widget.scoring.evaluate(_v);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;
    final sport = Sports.byId(widget.scoring.sportId);
    final a = _sideA(dark), b = _sideB(dark);
    final statusColor = outcome.isValid ? AppColors.success : AppColors.danger;
    final maxH = MediaQuery.of(context).size.height * 0.88;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 460, maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ---- header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              decoration: const BoxDecoration(gradient: AppTheme.primaryGradient),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(sport.icon, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.tr('detailedResult'),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                        Text(sport.label(widget.lang),
                            style: const TextStyle(color: Color(0xFFD5F2E5), fontSize: 12.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ---- body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _teamTag(widget.teamA, a, dark),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text('VS',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: cs.onSurfaceVariant,
                                  fontSize: 12)),
                        ),
                        _teamTag(widget.teamB, b, dark),
                      ],
                    ),
                    for (final f in widget.scoring.fields) _fieldRow(f, dark),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: dark ? 0.18 : 0.10),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: statusColor.withValues(alpha: 0.6)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                              outcome.isValid
                                  ? Icons.check_circle_rounded
                                  : Icons.error_outline_rounded,
                              color: statusColor,
                              size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (outcome.isValid) ...[
                                  Text('${outcome.scoreA}  -  ${outcome.scoreB}',
                                      style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w900,
                                          color: cs.onSurface)),
                                  const SizedBox(height: 2),
                                  Text(_named(outcome.summary),
                                      style: TextStyle(color: cs.onSurface, fontSize: 13.5)),
                                ] else
                                  Text(outcome.error ?? '',
                                      style: TextStyle(
                                          color: cs.onSurface,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13.5)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _showNote = !_showNote),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline_rounded, size: 18, color: cs.secondary),
                            const SizedBox(width: 6),
                            Text(widget.lang == 'fa' ? 'قوانین و منبع' : 'Rules and source',
                                style: TextStyle(
                                    color: cs.secondary, fontWeight: FontWeight.w700, fontSize: 13)),
                            const Spacer(),
                            Icon(_showNote ? Icons.expand_less : Icons.expand_more,
                                color: cs.secondary),
                          ],
                        ),
                      ),
                    ),
                    if (_showNote)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(widget.scoring.note,
                            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                      ),
                  ],
                ),
              ),
            ),
            // ---- actions
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(context.tr('cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: outcome.isValid
                          ? () => Navigator.of(context)
                              .pop(DetailedResult(Map<String, int>.of(_v), outcome))
                          : null,
                      child: Text(context.tr('confirm')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
