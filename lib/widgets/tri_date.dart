import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import '../utils/calendars.dart';

/// A date shown in all three calendars: Gregorian (with the time), Shamsi and Hijri (Qamari).
class TriDate extends StatelessWidget {
  final DateTime date;
  final bool withTime;
  final double fontSize;
  final TextAlign align;
  const TriDate({super.key, required this.date, this.withTime = true, this.fontSize = 11, this.align = TextAlign.start});

  static String line1(DateTime d, {bool withTime = true}) =>
      '${Calendars.numeric(CalKind.gregorian, d)}${withTime ? '  ${Calendars.time(d)}' : ''}';

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: fontSize, color: mutedText(context));
    return Column(
      crossAxisAlignment: align == TextAlign.center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${line1(date, withTime: withTime)}  ${context.tr('calGregorian')}', style: style, textAlign: align),
        Text(
            '${Calendars.numeric(CalKind.shamsi, date)} ${context.tr('calShamsi')}  ·  '
            '${Calendars.numeric(CalKind.hijri, date)} ${context.tr('calHijri')}',
            style: style,
            textAlign: align),
      ],
    );
  }
}

/// Date (and optional time) picker that works in the Shamsi, Hijri or Gregorian calendar.
/// Returns the chosen date as a Gregorian [DateTime], or null when cancelled.
/// Cleared means: the caller receives [TriDatePickerResult.cleared].
class TriDatePickerResult {
  final DateTime? value;
  final bool cleared;
  const TriDatePickerResult(this.value, {this.cleared = false});
}

Future<TriDatePickerResult?> showTriDatePicker(BuildContext context, {DateTime? initial}) {
  return showDialog<TriDatePickerResult>(
    context: context,
    builder: (_) => _TriDateDialog(initial: initial ?? DateTime.now()),
  );
}

class _TriDateDialog extends StatefulWidget {
  final DateTime initial;
  const _TriDateDialog({required this.initial});

  @override
  State<_TriDateDialog> createState() => _TriDateDialogState();
}

class _TriDateDialogState extends State<_TriDateDialog> {
  late CalKind _kind;
  late int _y, _m, _d;
  late TimeOfDay _time;

  @override
  void initState() {
    super.initState();
    final lang = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    _kind = (lang == 'fa' || lang == 'ps') ? CalKind.shamsi : CalKind.gregorian;
    _time = TimeOfDay(hour: widget.initial.hour, minute: widget.initial.minute);
    _load(widget.initial);
  }

  void _load(DateTime g) {
    final (y, m, d) = Calendars.parts(_kind, g);
    _y = y;
    _m = m;
    _d = d;
  }

  DateTime get _gregorian => Calendars.toGregorian(_kind, _y, _m, _d);

  void _switch(CalKind k) {
    final g = _gregorian; // keep the same day while the calendar changes
    setState(() {
      _kind = k;
      _load(g);
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.read<SettingsProvider>().languageCode;
    final days = Calendars.daysInMonth(_kind, _y, _m);
    if (_d > days) _d = days;
    final g = _gregorian;
    final years = [for (var y = _y - 6; y <= _y + 6; y++) y];
    String label(CalKind k) =>
        context.tr(k == CalKind.shamsi ? 'calShamsi' : (k == CalKind.hijri ? 'calHijri' : 'calGregorian'));

    return AlertDialog(
      title: Text(context.tr('pickDate')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 6, children: [
            for (final k in CalKind.values)
              ChoiceChip(label: Text(label(k)), selected: _kind == k, onSelected: (_) => _switch(k)),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<int>(
                value: _d,
                isExpanded: true,
                decoration: InputDecoration(labelText: context.tr('day')),
                items: [for (var i = 1; i <= days; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                onChanged: (v) => setState(() => _d = v ?? _d),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 5,
              child: DropdownButtonFormField<int>(
                value: _m,
                isExpanded: true,
                decoration: InputDecoration(labelText: context.tr('month')),
                items: [
                  for (var i = 1; i <= 12; i++)
                    DropdownMenuItem(value: i, child: Text(Calendars.monthName(_kind, i, lang), overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _m = v ?? _m),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 4,
              child: DropdownButtonFormField<int>(
                value: _y,
                isExpanded: true,
                decoration: InputDecoration(labelText: context.tr('year')),
                items: [for (final y in years) DropdownMenuItem(value: y, child: Text('$y'))],
                onChanged: (v) => setState(() => _y = v ?? _y),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.schedule_rounded),
            label: Text('${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}'),
            onPressed: () async {
              final t = await showTimePicker(context: context, initialTime: _time);
              if (t != null) setState(() => _time = t);
            },
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TriDate(date: DateTime(g.year, g.month, g.day, _time.hour, _time.minute), fontSize: 12),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, const TriDatePickerResult(null, cleared: true)),
            child: Text(context.tr('clearDate'))),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('cancel'))),
        FilledButton(
          onPressed: () => Navigator.pop(
              context, TriDatePickerResult(DateTime(g.year, g.month, g.day, _time.hour, _time.minute))),
          child: Text(context.tr('confirm')),
        ),
      ],
    );
  }
}
