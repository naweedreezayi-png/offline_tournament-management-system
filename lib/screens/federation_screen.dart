import 'package:flutter/material.dart';
import '../data/api_client.dart';
import '../l10n/app_strings.dart';
import '../models/sport.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import '../utils/calendars.dart';
import '../widgets/tri_date.dart';
import 'package:provider/provider.dart';

enum _T { text, integer, number, date, sport, choice }

class _F {
  final String key; // column name on the server
  final String label; // l10n key
  final _T type;
  final bool required;
  final List<String> choices;
  final String? initial;
  const _F(this.key, this.label, this.type, {this.required = false, this.choices = const [], this.initial});
}

class _Res {
  final String id; // path on the server
  final String title; // l10n key
  final IconData icon;
  final String main; // field shown as the row title
  final List<_F> fields;
  final bool adminOnly;
  const _Res(this.id, this.title, this.icon, this.main, this.fields, {this.adminOnly = false});
}

const _resources = <_Res>[
  _Res('players', 'fedPlayers', Icons.sports_handball_outlined, 'full_name', [
    _F('full_name', 'fedName', _T.text, required: true),
    _F('sport', 'fedSport', _T.sport, required: true),
    _F('team', 'fedTeam', _T.text),
    _F('birth_date', 'fedBirth', _T.date),
    _F('gender', 'fedGender', _T.choice, choices: ['male', 'female']),
  ]),
  _Res('referees', 'fedReferees', Icons.sports_outlined, 'full_name', [
    _F('full_name', 'fedName', _T.text, required: true),
    _F('sport', 'fedSport', _T.sport, required: true),
    _F('license_no', 'fedLicense', _T.text),
    _F('level', 'fedLevel', _T.text),
  ]),
  _Res('venues', 'fedVenues', Icons.stadium_outlined, 'name', [
    _F('name', 'fedName', _T.text, required: true),
    _F('city', 'fedCity', _T.text),
    _F('capacity', 'fedCapacity', _T.integer),
  ]),
  _Res('finance', 'fedFinance', Icons.account_balance_wallet_outlined, 'category', [
    _F('kind', 'fedKind', _T.choice, required: true, choices: ['income', 'expense'], initial: 'income'),
    _F('category', 'fedCategory', _T.text, required: true),
    _F('amount', 'fedAmount', _T.number, required: true),
    _F('currency', 'fedCurrency', _T.text, initial: 'AFN'),
    _F('note', 'fedNote', _T.text),
    _F('entry_date', 'fedDate', _T.date),
  ], adminOnly: true),
];

/// Players, referees, venues and finance of the federation.
/// Everyone signed in can read (finance: administrator only); only the administrator can change.
class FederationScreen extends StatelessWidget {
  const FederationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isAdmin = ApiClient.instance.isAdmin;
    final list = [for (final r in _resources) if (!r.adminOnly || isAdmin) r];
    return DefaultTabController(
      length: list.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('federationTitle')),
          bottom: TabBar(isScrollable: true, tabs: [
            for (final r in list) Tab(icon: Icon(r.icon, size: 18), text: context.tr(r.title)),
          ]),
        ),
        body: TabBarView(children: [for (final r in list) _ResourceTab(res: r, canEdit: isAdmin)]),
      ),
    );
  }
}

class _ResourceTab extends StatefulWidget {
  final _Res res;
  final bool canEdit;
  const _ResourceTab({required this.res, required this.canEdit});

  @override
  State<_ResourceTab> createState() => _ResourceTabState();
}

class _ResourceTabState extends State<_ResourceTab> with AutomaticKeepAliveClientMixin {
  late Future<List<Map<String, dynamic>>> _future;
  String? _sport; // filter for players / referees

  @override
  bool get wantKeepAlive => true;

  bool get _hasSport => widget.res.fields.any((f) => f.type == _T.sport);

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _future = ApiClient.instance.fedList(widget.res.id, sport: _sport);

  void _reload() => setState(_load);

  String _show(Map<String, dynamic> row, _F f, String lang) {
    final v = row[f.key];
    if (v == null) return '';
    if (f.type == _T.sport) return Sports.byId('$v').label(lang);
    if (f.type == _T.date) {
      final d = DateTime.tryParse('$v');
      return d == null ? '$v' : Calendars.numeric(CalKind.shamsi, d) + '  ·  ' + Calendars.numeric(CalKind.gregorian, d);
    }
    if (f.type == _T.choice) return context.tr('fed_$v');
    return '$v';
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EditDialog(res: widget.res, row: row),
    );
    if (saved == true) _reload();
  }

  Future<void> _remove(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(context.tr('confirmDelete').split('?').first),
        content: Text('${row[widget.res.main]}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(context.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(context.tr('delete'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiClient.instance.fedDelete(widget.res.id, '${row['id']}');
      _reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final lang = context.watch<SettingsProvider>().languageCode;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: widget.canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: Text(context.tr('fedAdd')))
          : null,
      body: Column(children: [
        if (_hasSport)
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(context.tr('allTournaments')),
                    selected: _sport == null,
                    onSelected: (_) => setState(() {
                      _sport = null;
                      _load();
                    }),
                  ),
                ),
                for (final s in Sports.all)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: Icon(s.icon, size: 15, color: s.color),
                      label: Text(s.label(lang)),
                      selected: _sport == s.id,
                      onSelected: (_) => setState(() {
                        _sport = s.id;
                        _load();
                      }),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text('${snap.error}', textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                              onPressed: _reload,
                              icon: const Icon(Icons.refresh),
                              label: Text(context.tr('liveRefresh'))),
                        ])));
              }
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final rows = snap.data!;
              if (rows.isEmpty) {
                return Center(child: Text(context.tr('fedEmpty'), style: TextStyle(color: mutedText(context))));
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final row = rows[i];
                  final main = widget.res.fields.firstWhere((f) => f.key == widget.res.main);
                  final lines = [
                    for (final f in widget.res.fields)
                      if (f.key != widget.res.main && _show(row, f, lang).isNotEmpty)
                        '${context.tr(f.label)}: ${_show(row, f, lang)}',
                  ];
                  final income = row['kind'] == 'income';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                        child: Icon(
                            widget.res.id == 'finance'
                                ? (income ? Icons.south_west_rounded : Icons.north_east_rounded)
                                : widget.res.icon,
                            color: widget.res.id == 'finance'
                                ? (income ? AppColors.success : AppColors.danger)
                                : AppColors.primary),
                      ),
                      title: Text(_show(row, main, lang), maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: lines.isEmpty ? null : Text(lines.join('\n'), style: const TextStyle(fontSize: 12)),
                      isThreeLine: lines.length > 1,
                      trailing: widget.canEdit
                          ? Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(row)),
                              IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _remove(row)),
                            ])
                          : null,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _EditDialog extends StatefulWidget {
  final _Res res;
  final Map<String, dynamic>? row;
  const _EditDialog({required this.res, this.row});

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  final Map<String, TextEditingController> _c = {};
  final Map<String, String?> _pick = {};
  final Map<String, DateTime?> _dates = {};
  String _error = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    for (final f in widget.res.fields) {
      final v = widget.row?[f.key] ?? f.initial;
      switch (f.type) {
        case _T.sport:
        case _T.choice:
          _pick[f.key] = v?.toString();
        case _T.date:
          _dates[f.key] = v == null ? null : DateTime.tryParse('$v');
        default:
          _c[f.key] = TextEditingController(text: v == null ? '' : '$v');
      }
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    final body = <String, dynamic>{};
    for (final f in widget.res.fields) {
      dynamic v;
      switch (f.type) {
        case _T.sport:
        case _T.choice:
          v = _pick[f.key];
        case _T.date:
          v = _dates[f.key] == null ? null : _iso(_dates[f.key]!);
        case _T.integer:
          v = int.tryParse(_c[f.key]!.text.trim());
        case _T.number:
          v = _c[f.key]!.text.trim().replaceAll(',', '.');
        case _T.text:
          v = _c[f.key]!.text.trim();
      }
      if (f.required && (v == null || '$v'.isEmpty)) {
        setState(() => _error = '${context.tr(f.label)}: ${context.tr('fedRequired')}');
        return;
      }
      if (v != null && '$v'.isNotEmpty) body[f.key] = v;
      if (widget.row != null && (v == null || '$v'.isEmpty)) body[f.key] = null; // clear on edit
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await ApiClient.instance.fedSave(widget.res.id, body, id: widget.row?['id'] as String?);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.read<SettingsProvider>().languageCode;
    return AlertDialog(
      title: Text(context.tr(widget.res.title)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final f in widget.res.fields) ...[
              _field(context, f, lang),
              const SizedBox(height: 12),
            ],
            if (_error.isNotEmpty)
              Text(_error, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: Text(context.tr('cancel'))),
        FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(context.tr('saveShort'))),
      ],
    );
  }

  Widget _field(BuildContext context, _F f, String lang) {
    final label = context.tr(f.label) + (f.required ? ' *' : '');
    switch (f.type) {
      case _T.sport:
        return DropdownButtonFormField<String>(
          initialValue: _pick[f.key],
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [for (final s in Sports.all) DropdownMenuItem(value: s.id, child: Text(s.label(lang)))],
          onChanged: (v) => setState(() => _pick[f.key] = v),
        );
      case _T.choice:
        return DropdownButtonFormField<String>(
          initialValue: _pick[f.key],
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [for (final c in f.choices) DropdownMenuItem(value: c, child: Text(context.tr('fed_$c')))],
          onChanged: (v) => setState(() => _pick[f.key] = v),
        );
      case _T.date:
        final d = _dates[f.key];
        return InkWell(
          onTap: () async {
            final r = await showTriDatePicker(context, initial: d);
            if (r == null) return;
            setState(() => _dates[f.key] = r.cleared ? null : r.value);
          },
          child: InputDecorator(
            decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.event_rounded)),
            child: d == null ? Text(context.tr('noDate'), style: TextStyle(color: mutedText(context))) : TriDate(date: d, withTime: false, fontSize: 12),
          ),
        );
      default:
        return TextField(
          controller: _c[f.key],
          keyboardType: f.type == _T.integer
              ? TextInputType.number
              : f.type == _T.number
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
          decoration: InputDecoration(labelText: label),
        );
    }
  }
}
