import 'package:flutter/material.dart';
import '../data/api_client.dart';
import '../l10n/app_strings.dart';
import '../models/sport.dart';
import '../models/tournament.dart';
import '../providers/settings_provider.dart';
import '../providers/tournament_provider.dart';
import '../utils/name_check.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../utils/zoom_route.dart';
import '../widgets/gradient_button.dart';
import 'team_setup_screen.dart';

class CreateTournamentScreen extends StatefulWidget {
  const CreateTournamentScreen({super.key});

  @override
  State<CreateTournamentScreen> createState() => _CreateTournamentScreenState();
}

class _CreateTournamentScreenState extends State<CreateTournamentScreen> {
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  TournamentType _type = TournamentType.league;

  /// Race sports (dash, swimming...) start once and finish once: no league/knockout.
  bool get _isRace => Sports.byId(_sport).isRace;
  bool _hasGroupStage = false;
  SeedingMode _seedingMode = SeedingMode.random;
  String _sport = ApiClient.instance.isReferee ? (ApiClient.instance.sport ?? 'football') : 'football';
  List<SportType> get _allowedSports => ApiClient.instance.isReferee
      ? Sports.all.where((s) => s.id == ApiClient.instance.sport).toList()
      : Sports.all;
  bool _protectWithPassword = false;
  bool _twoLegged = false;

  bool get _canProceed => _nameController.text.trim().isNotEmpty;

  bool _nameTaken(BuildContext context) => NameCheck.isTaken(
      _nameController.text,
      context.read<TournamentProvider>().activeTournaments.map((t) => t.name));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('newTournament'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(context.tr('tournamentName'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                errorText: _nameController.text.trim().isNotEmpty && _nameTaken(context)
                    ? context.tr('dupTourField')
                    : null,
                hintText: context.tr('tournamentName'),
                filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 26),
            Text(context.tr('selectSport'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _allowedSports.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final sport = _allowedSports[index];
                  final selected = sport.id == _sport;
                  final dark = Theme.of(context).brightness == Brightness.dark;
                  final tone = sport.tone(dark);
                  final langCode = context.watch<SettingsProvider>().languageCode;
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => setState(() => _sport = sport.id),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 78,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selected
                            ? sport.color
                            : (dark ? sport.color.withValues(alpha: 0.30) : Colors.white.withValues(alpha: 0.92)),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: tone.withValues(alpha: selected ? 1 : 0.6), width: 1.2),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(sport.icon, color: selected ? Colors.white : tone, size: 26),
                          const SizedBox(height: 4),
                          Text(sport.label(langCode),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: selected ? Colors.white : (dark ? Colors.white : AppColors.lightText),
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (!_isRace) ...[
            const SizedBox(height: 26),
            Text(context.tr('tournamentType'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _TypeCard(
                    title: context.tr('league'),
                    desc: context.tr('leagueDesc'),
                    icon: Icons.table_chart_rounded,
                    selected: _type == TournamentType.league,
                    onTap: () => setState(() => _type = TournamentType.league),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TypeCard(
                    title: context.tr('knockout'),
                    desc: context.tr('knockoutDesc'),
                    icon: Icons.account_tree_rounded,
                    selected: _type == TournamentType.knockout,
                    onTap: () => setState(() => _type = TournamentType.knockout),
                  ),
                ),
              ],
            ),
            if (_type == TournamentType.knockout) ...[
              const SizedBox(height: 26),
              Text(context.tr('knockoutStructure'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              _OptionTile(
                title: context.tr('groupsThenKnockout'),
                selected: _hasGroupStage == true,
                onTap: () => setState(() => _hasGroupStage = true),
              ),
              _OptionTile(
                title: context.tr('directKnockout'),
                selected: _hasGroupStage == false,
                onTap: () => setState(() => _hasGroupStage = false),
              ),
            ],
            const SizedBox(height: 26),
            Text(context.tr('matchFormat'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _TypeCard(
                    title: context.tr('singleMatch'),
                    desc: context.tr('singleMatchDesc'),
                    icon: Icons.sports_score_rounded,
                    selected: !_twoLegged,
                    onTap: () => setState(() => _twoLegged = false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TypeCard(
                    title: context.tr('homeAway'),
                    desc: context.tr('homeAwayDesc'),
                    icon: Icons.sync_alt_rounded,
                    selected: _twoLegged,
                    onTap: () => setState(() => _twoLegged = true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            Text(context.tr('seedingMode'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            _OptionTile(
              title: context.tr('manualSeed'),
              selected: _seedingMode == SeedingMode.manual,
              onTap: () => setState(() => _seedingMode = SeedingMode.manual),
            ),
            _OptionTile(
              title: context.tr('randomSeed'),
              selected: _seedingMode == SeedingMode.random,
              onTap: () => setState(() => _seedingMode = SeedingMode.random),
            ),
            _OptionTile(
              title: context.tr('balancedSeed'),
              selected: _seedingMode == SeedingMode.balanced,
              onTap: () => setState(() => _seedingMode = SeedingMode.balanced),
            ),
            ] else ...[
              const SizedBox(height: 26),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.flag_rounded, color: Theme.of(context).colorScheme.secondary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${context.tr('raceTypeLabel')}\n${context.tr('raceNote')}',
                        style: const TextStyle(height: 1.45, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 26),
            _OptionTile(
              title: context.tr('passwordProtect'),
              selected: _protectWithPassword,
              onTap: () => setState(() => _protectWithPassword = !_protectWithPassword),
            ),
            if (_protectWithPassword) ...[
              const SizedBox(height: 6),
              TextField(
                controller: _passwordController,
                obscureText: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: context.tr('password'),
                  prefixIcon: const Icon(Icons.lock_outline),
                  filled: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                ),
              ),
            ],
            const SizedBox(height: 34),
            GradientButton(
              label: context.tr('next'),
              icon: Icons.arrow_forward_rounded,
              onPressed: _canProceed &&
                      (!_protectWithPassword || _passwordController.text.trim().isNotEmpty)
                  ? () {
                      if (_nameTaken(context)) {
                        NameCheck.showDuplicateTournamentDialog(
                            context, _nameController.text.trim());
                        return;
                      }
                      Navigator.of(context).push(ZoomRoute(
                        page: TeamSetupScreen(
                          tournamentName: _nameController.text.trim(),
                          type: _isRace ? TournamentType.race : _type,
                          hasGroupStage: _isRace ? false : _hasGroupStage,
                          seedingMode: _isRace ? SeedingMode.manual : _seedingMode,
                          sport: _sport,
                          twoLegged: _isRace ? false : _twoLegged,
                          password: _protectWithPassword
                              ? _passwordController.text.trim()
                              : null,
                        ),
                      ));
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  final String title;
  final String desc;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TypeCard({
    required this.title,
    required this.desc,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: selected ? AppTheme.primaryGradient : null,
          color: selected ? null : Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? Colors.transparent : Colors.grey.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: selected ? Colors.white : Theme.of(context).colorScheme.primary),
            const SizedBox(height: 10),
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: selected ? Colors.white : null)),
            const SizedBox(height: 4),
            Text(desc,
                style: TextStyle(
                    fontSize: 11,
                    color: selected ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _OptionTile({required this.title, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.12)
                : Theme.of(context).cardTheme.color,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.primary : Colors.grey.withValues(alpha: 0.2),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? AppColors.primary : Colors.grey,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(title,
                      style: TextStyle(
                          fontWeight: selected ? FontWeight.w600 : FontWeight.normal))),
            ],
          ),
        ),
      ),
    );
  }
}
