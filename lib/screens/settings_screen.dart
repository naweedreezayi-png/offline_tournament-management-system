import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_strings.dart';
import '../providers/settings_provider.dart';
import '../utils/zoom_route.dart';
import 'about_screen.dart';
import 'ai_insights_screen.dart';
import 'backup_screen.dart';
import 'recycle_bin_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionCard(
            child: SwitchListTile(
              value: settings.isDark,
              onChanged: (v) => context.read<SettingsProvider>().toggleDarkMode(v),
              title: Text(context.tr('darkMode')),
              secondary: Icon(settings.isDark ? Icons.dark_mode : Icons.light_mode),
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                leading: const Icon(Icons.language),
                title: Text(context.tr('language')),
                subtitle: Text(
                  _kSupportedLanguages
                      .firstWhere((l) => l.code == settings.languageCode)
                      .nativeName,
                ),
                childrenPadding: EdgeInsets.zero,
                children: [
                  RadioGroup<String>(
                    groupValue: settings.languageCode,
                    onChanged: (v) {
                      if (v != null) context.read<SettingsProvider>().setLanguage(v);
                    },
                    child: Column(
                      children: [
                        for (final lang in _kSupportedLanguages)
                          RadioListTile<String>(
                            value: lang.code,
                            title: Text(lang.nativeName),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            child: ListTile(
              leading: const Icon(Icons.psychology),
              title: Text(context.tr('aiInsights')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context)
                  .push(ZoomRoute(page: const AiInsightsScreen())),
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            child: ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(context.tr('recycleBin')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context)
                  .push(ZoomRoute(page: const RecycleBinScreen())),
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            child: ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: Text(context.tr('backupRestore')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context)
                  .push(ZoomRoute(page: const BackupScreen())),
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(context.tr('aboutUs')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context)
                  .push(ZoomRoute(page: const AboutScreen())),
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageOption {
  final String code;
  final String nativeName;
  const _LanguageOption(this.code, this.nativeName);
}

const _kSupportedLanguages = [
  _LanguageOption('fa', 'دری / فارسی'),
  _LanguageOption('en', 'English'),
  _LanguageOption('es', 'Español'),
  _LanguageOption('fr', 'Français'),
  _LanguageOption('ar', 'العربية'),
  _LanguageOption('ps', 'پښتو'),
  _LanguageOption('ru', 'Русский'),
  _LanguageOption('hi', 'हिन्दी'),
  _LanguageOption('zh', '中文'),
];

class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: child,
    );
  }
}
