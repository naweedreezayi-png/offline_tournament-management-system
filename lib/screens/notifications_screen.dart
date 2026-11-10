import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../providers/notification_center.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    NotificationCenter.instance.markRead();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: NotificationCenter.instance,
      builder: (context, _) {
        final items = NotificationCenter.instance.items;
        return Scaffold(
          appBar: AppBar(
            title: Text(context.tr('notifTitle')),
            actions: [
              if (items.isNotEmpty)
                TextButton(
                    onPressed: NotificationCenter.instance.clear,
                    child: Text(context.tr('notifClear'))),
            ],
          ),
          body: items.isEmpty
              ? Center(child: Text(context.tr('notifEmpty')))
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) => ListTile(
                    leading: const Icon(Icons.notifications_active_outlined),
                    title: Text(context.tr(items[i].text)),
                    subtitle: Text(items[i].time.toString().split('.').first),
                  ),
                ),
        );
      },
    );
  }
}
