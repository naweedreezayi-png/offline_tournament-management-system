import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';

// ---------------------------------------------------------------------
// Replace these with your real store listing / links once published.
// ---------------------------------------------------------------------
const String kAppVersion = '4.0.0';
const String kPlayStorePackageId = 'com.naweedrezayi.tournamentmaster';
const String kWebsiteUrl = 'https://naweed-portfolio.vercel.app/en';
const String kGithubUrl = 'https://github.com/naweedreezayi-png';
const String kSupportEmail = 'support@tournamentmaster.app';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _rateApp() => _open('https://play.google.com/store/apps/details?id=$kPlayStorePackageId');

  void _shareApp() async {
    const text = 'Tournament Master — professional tournament management app.\n'
        'https://play.google.com/store/apps/details?id=$kPlayStorePackageId';
    await Clipboard.setData(const ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('linkCopiedMsg'))),
      );
    }
  }

  void _contactDeveloper() => _open('mailto:$kSupportEmail?subject=Tournament%20Master%20Feedback');

  void _checkForUpdates() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.tr('checkUpdatesTitle')),
        content: Text(context.tr('checkUpdatesBody')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('confirm'))),
        ],
      ),
    );
  }

  void _showLegalDialog(String title, String body) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(body)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('confirm'))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 260,
                backgroundColor: AppColors.primary,
                iconTheme: const IconThemeData(color: Colors.white),
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: const BoxDecoration(gradient: AppTheme.primaryGradient),
                    child: SafeArea(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const AppLogo(size: 84),
                          const SizedBox(height: 14),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(context.tr('appName'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                          ),
                          const SizedBox(height: 4),
                          Text('${context.tr('aboutVersionLabel')} $kAppVersion',
                              style: const TextStyle(color: Colors.white70, fontSize: 13)),
                          const SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              context.tr('aboutTagline'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      children: [
                        _ActionChip(icon: Icons.star_rounded, label: context.tr('actionRateApp'), color: const Color(0xFFF59E0B), onTap: _rateApp),
                        _ActionChip(icon: Icons.share_rounded, label: context.tr('actionShareApp'), color: const Color(0xFF0E8F8F), onTap: _shareApp),
                        _ActionChip(icon: Icons.public_rounded, label: context.tr('actionWebsite'), color: const Color(0xFF0B8A63), onTap: () => _open(kWebsiteUrl)),
                        _ActionChip(icon: Icons.code_rounded, label: context.tr('actionGithub'), color: const Color(0xFF047857), onTap: () => _open(kGithubUrl)),
                        _ActionChip(icon: Icons.email_rounded, label: context.tr('actionContact'), color: const Color(0xFFB45309), onTap: _contactDeveloper),
                        _ActionChip(icon: Icons.system_update_rounded, label: context.tr('actionUpdates'), color: const Color(0xFF0F766E), onTap: _checkForUpdates),
                      ],
                    ),
                    const SizedBox(height: 20),

                    _InfoCard(
                      icon: Icons.info_outline_rounded,
                      iconColor: AppColors.primary,
                      title: context.tr('aboutSectionTitle'),
                      child: Text(context.tr('aboutBody'), style: const TextStyle(height: 1.5)),
                    ),

                    _InfoCard(
                      icon: Icons.new_releases_rounded,
                      iconColor: const Color(0xFFF59E0B),
                      title: context.tr('aboutNewTitle'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _FeatureRow(context.tr('featureRaces')),
                          _FeatureRow(context.tr('featureChessKurash')),
                          _FeatureRow(context.tr('featureRoles')),
                          _FeatureRow(context.tr('featureLiveCompetitions')),
                        ],
                      ),
                    ),

                    _InfoCard(
                      icon: Icons.auto_awesome_rounded,
                      iconColor: const Color(0xFFF59E0B),
                      title: context.tr('featuresSectionTitle'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _FeatureRow(context.tr('featureLeagueMgmt')),
                          _FeatureRow(context.tr('featureKnockoutMgmt')),
                          _FeatureRow(context.tr('featureGroupStage')),
                          _FeatureRow(context.tr('featureAutoScheduling')),
                          _FeatureRow(context.tr('featureLiveStandings')),
                          _FeatureRow(context.tr('featureBrackets')),
                          _FeatureRow(context.tr('featureTeamLogos')),
                          _FeatureRow(context.tr('featureSportsCategories')),
                          _FeatureRow(context.tr('featurePasswordProtect')),
                          _FeatureRow(context.tr('featureSearchFilter')),
                          _FeatureRow(context.tr('featureDarkLight')),
                          _FeatureRow(context.tr('featureMultiLang')),
                          _FeatureRow(context.tr('featureSqlite')),
                          _FeatureRow(context.tr('featureFastUI')),
                          _FeatureRow(context.tr('featureSecureStorage')),
                        ],
                      ),
                    ),

                    _InfoCard(
                      icon: Icons.flag_rounded,
                      iconColor: const Color(0xFF0E8F8F),
                      title: context.tr('missionSectionTitle'),
                      child: Text(context.tr('missionBody'), style: const TextStyle(height: 1.5)),
                    ),

                    _InfoCard(
                      icon: Icons.person_rounded,
                      iconColor: const Color(0xFFB45309),
                      title: context.tr('developerSectionTitle'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Naweed Rezayi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 4),
                          Text(context.tr('developerRole1')),
                          Text(context.tr('developerRole2')),
                          Text(context.tr('developerRole3')),
                          Text(context.tr('developerCountry')),
                        ],
                      ),
                    ),

                    _InfoCard(
                      icon: Icons.build_rounded,
                      iconColor: const Color(0xFF0B8A63),
                      title: context.tr('technologiesSectionTitle'),
                      child: const Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _TechChip('Flutter'),
                          _TechChip('Dart'),
                          _TechChip('SQLite'),
                          _TechChip('Provider'),
                          _TechChip('Material Design 3'),
                        ],
                      ),
                    ),

                    _InfoCard(
                      icon: Icons.contact_mail_rounded,
                      iconColor: const Color(0xFF8E44AD),
                      title: context.tr('actionContact'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ContactRow(icon: Icons.email_outlined, label: kSupportEmail, onTap: _contactDeveloper),
                          _ContactRow(icon: Icons.public, label: kWebsiteUrl, onTap: () => _open(kWebsiteUrl)),
                          _ContactRow(icon: Icons.code, label: kGithubUrl, onTap: () => _open(kGithubUrl)),
                        ],
                      ),
                    ),

                    _InfoCard(
                      icon: Icons.favorite_rounded,
                      iconColor: const Color(0xFFFF6B6B),
                      title: context.tr('supportUsSectionTitle'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(context.tr('supportUsIntro'), style: const TextStyle(height: 1.5)),
                          const SizedBox(height: 8),
                          _SupportRow(icon: Icons.star_rounded, label: context.tr('supportRateOurApp'), onTap: _rateApp),
                          _SupportRow(icon: Icons.share_rounded, label: context.tr('supportShareWithFriends'), onTap: _shareApp),
                          _SupportRow(icon: Icons.chat_bubble_outline_rounded, label: context.tr('supportSendFeedback'), onTap: _contactDeveloper),
                          _SupportRow(icon: Icons.bug_report_outlined, label: context.tr('supportReportBugs'), onTap: _contactDeveloper),
                        ],
                      ),
                    ),

                    _InfoCard(
                      icon: Icons.gavel_rounded,
                      iconColor: const Color(0xFF7F8C8D),
                      title: context.tr('legalSectionTitle'),
                      child: Column(
                        children: [
                          _LegalRow(
                            label: context.tr('privacyPolicyTitle'),
                            onTap: () => _showLegalDialog(context.tr('privacyPolicyTitle'), context.tr('privacyPolicyBody')),
                          ),
                          _LegalRow(
                            label: context.tr('termsTitle'),
                            onTap: () => _showLegalDialog(context.tr('termsTitle'), context.tr('termsBody')),
                          ),
                          _LegalRow(
                            label: context.tr('openSourceLicenses'),
                            onTap: () => showLicensePage(
                              context: context,
                              applicationName: 'Intelligent Multi-Sport Tournament Management System',
                              applicationVersion: kAppVersion,
                              applicationIcon: const Padding(
                                padding: EdgeInsets.all(8),
                                child: AppLogo(size: 48),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    _InfoCard(
                      icon: Icons.smartphone_rounded,
                      iconColor: AppColors.primary,
                      title: context.tr('appInfoSectionTitle'),
                      child: Column(
                        children: [
                          _KeyValueRow(context.tr('appInfoAppName'), 'Intelligent Multi-Sport Tournament Management System'),
                          _KeyValueRow(context.tr('appInfoCurrentVersion'), kAppVersion),
                          _KeyValueRow(context.tr('developerSectionTitle'), 'Naweed Rezayi'),
                          _KeyValueRow(context.tr('appInfoPlatform'), 'Android'),
                          _KeyValueRow(context.tr('appInfoBuiltWith'), 'Flutter'),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        context.tr('copyrightNotice'),
                        style: TextStyle(fontSize: 12, color: mutedText(context)),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionChip({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget child;
  const _InfoCard({required this.icon, required this.iconColor, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final String text;
  const _FeatureRow(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF0E8F8F)),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _TechChip extends StatelessWidget {
  final String label;
  const _TechChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ContactRow({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: mutedText(context)),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          ],
        ),
      ),
    );
  }
}

class _SupportRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SupportRow({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _LegalRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _LegalRow({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(fontSize: 14)),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  final String label;
  final String value;
  const _KeyValueRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: mutedText(context), fontSize: 13))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}
