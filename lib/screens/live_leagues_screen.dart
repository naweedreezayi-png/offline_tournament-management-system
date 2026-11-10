import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_strings.dart';
import '../live/football_data_service.dart';
import '../live/live_models.dart';
import '../theme/app_theme.dart';
import '../utils/zoom_route.dart';
import 'live_league_detail_screen.dart';

/// Real-world competitions: fixtures, results, tables and AI predictions.
class LiveLeaguesScreen extends StatefulWidget {
  const LiveLeaguesScreen({super.key});

  @override
  State<LiveLeaguesScreen> createState() => _LiveLeaguesScreenState();
}

class _LiveLeaguesScreenState extends State<LiveLeaguesScreen> {
  final _controller = TextEditingController();
  String _token = '';
  bool _loaded = false;
  bool _editingKey = false;
  // null = idle, 'checking', 'bad', 'net'
  String? _status;

  @override
  void initState() {
    super.initState();
    FootballDataService.instance.getToken().then((t) {
      if (!mounted) return;
      setState(() {
        _token = t;
        _controller.text = t;
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    try {
      final d = await Clipboard.getData('text/plain');
      final t = d?.text?.trim();
      if (t != null && t.isNotEmpty && mounted) {
        setState(() {
          _controller.text = t;
          _status = null;
        });
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    final t = _controller.text.trim();
    if (t.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _status = 'checking');
    String? result; // null = valid
    try {
      await FootballDataService.instance.validateToken(t);
    } on LiveException catch (e) {
      if (e.type == LiveErrorType.badKey) {
        result = 'bad';
      } else if (e.type == LiveErrorType.network) {
        result = 'net'; // can't verify offline: keep the key anyway
      }
      // rate-limit / restricted / other: the key itself was accepted
    } catch (_) {
      result = 'net';
    }
    if (!mounted) return;
    if (result == 'bad') {
      setState(() => _status = 'bad');
      return;
    }
    await FootballDataService.instance.saveToken(t);
    if (!mounted) return;
    setState(() {
      _token = t;
      _editingKey = false;
      _status = result; // null or 'net'
    });
    if (result == 'net') {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.tr('liveKeyUnverified'))));
    }
  }

  Future<void> _openRegister() async {
    try {
      await launchUrl(Uri.parse('https://www.football-data.org/client/register'),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final needKey = _loaded && (_token.isEmpty || _editingKey);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('liveLeagues')),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(context.tr('liveIntro'),
                    style: TextStyle(color: mutedText(context), fontSize: 13)),
                const SizedBox(height: 12),
                if (needKey) _keyCard(context) else _connectedCard(context),
                _sectionTitle(context, Icons.sports_soccer, context.tr('liveSecFootball')),
                for (final c in kLiveCompetitions) _competitionTile(context, c),
                const SizedBox(height: 10),
                _sectionTitle(context, Icons.sports_cricket, context.tr('liveSecOther')),
                for (final c in kOtherSportCompetitions) _competitionTile(context, c),
                Container(
                  margin: const EdgeInsets.only(top: 4, bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.info_outline, size: 18, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(context.tr('liveNoApiSports'),
                          style: const TextStyle(fontSize: 12.5)),
                    ),
                  ]),
                ),
                const SizedBox(height: 8),
                Text(context.tr('liveDisclaimer'),
                    style: TextStyle(color: mutedText(context), fontSize: 11)),
                const SizedBox(height: 4),
                Text(context.tr('liveDataBy'),
                    style: TextStyle(color: mutedText(context), fontSize: 11)),
              ],
            ),
    );
  }

  Widget _sectionTitle(BuildContext context, IconData icon, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Row(children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ]),
      );

  IconData _iconFor(LiveCompetition c) {
    if (c.region == 'world') return Icons.public;
    switch (c.sport) {
      case 'cricket':
        return Icons.sports_cricket;
      case 'basketball':
        return Icons.sports_basketball;
      case 'volleyball':
        return Icons.sports_volleyball;
      default:
        return Icons.sports_soccer;
    }
  }

  Widget _competitionTile(BuildContext context, LiveCompetition c) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            child: Icon(c.isCup ? Icons.emoji_events_rounded : _iconFor(c), color: AppColors.primary),
          ),
          title: Text(c.name),
          subtitle: Row(children: [
            Container(
              margin: const EdgeInsets.only(top: 3),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: (c.isCup ? AppColors.cyanDeep : AppColors.primary).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(context.tr(c.isCup ? 'liveKindCup' : 'liveKindLeague'),
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: c.isCup ? AppColors.cyanDeep : AppColors.primary)),
            ),
            if (!c.isFootballData) ...[
              const SizedBox(width: 8),
              Flexible(
                  child: Text(context.tr('liveNoKeyNeeded'),
                      overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))),
            ],
          ]),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context)
              .push(ZoomRoute(page: LiveLeagueDetailScreen(competition: c))),
        ),
      );

  Widget _connectedCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        const Icon(Icons.check_circle_rounded, color: AppColors.success),
        const SizedBox(width: 10),
        Expanded(
          child: Text(context.tr('liveConnected'),
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        TextButton(
          onPressed: () => setState(() {
            _editingKey = true;
            _status = null;
          }),
          child: Text(context.tr('liveChangeKey')),
        ),
      ]),
    );
  }

  Widget _keyCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('liveKeyTitle'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 6),
          Text(context.tr('liveKeySteps'), style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _openRegister,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(context.tr('liveGetKey')),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _controller,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) {
              if (_status != null) setState(() => _status = null);
            },
            decoration: InputDecoration(
              suffixIcon: IconButton(
                icon: const Icon(Icons.content_paste_rounded),
                tooltip: context.tr('livePaste'),
                onPressed: _paste,
              ),
              hintText: context.tr('liveKeyHint'),
              filled: true,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          if (_status == 'bad')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                const Icon(Icons.error_outline, size: 16, color: AppColors.danger),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(context.tr('liveErrBadKey'),
                      style: const TextStyle(fontSize: 12, color: AppColors.danger)),
                ),
              ]),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _status == 'checking' ? null : _save,
                  icon: _status == 'checking'
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.verified_outlined, size: 18),
                  label: Text(_status == 'checking'
                      ? context.tr('liveChecking')
                      : context.tr('liveSave')),
                ),
              ),
              if (_editingKey) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() {
                    _editingKey = false;
                    _controller.text = _token;
                  }),
                  child: Text(context.tr('cancel')),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
