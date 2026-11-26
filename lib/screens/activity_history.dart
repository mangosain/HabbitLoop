import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../core/palette.dart';
import '../widgets/common.dart';
import '../widgets/shared_element.dart';

class ActivityHistoryPage extends StatefulWidget {
  const ActivityHistoryPage({super.key, required this.uid});
  final String uid;
  @override
  State<ActivityHistoryPage> createState() => _ActivityHistoryPageState();
}

class _ActivityHistoryPageState extends State<ActivityHistoryPage> {
  late var _activity = _watchActivity();
  final _dateFormat = DateFormat('d MMM\nHH:mm');

  Stream<QuerySnapshot<Map<String, dynamic>>> _watchActivity() =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .collection('activity')
          .orderBy('at', descending: true)
          .limit(100)
          .snapshots();

  @override
  void didUpdateWidget(ActivityHistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) _activity = _watchActivity();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Row(
        children: [
          SharedIcon(
            tag: activityHeroTag,
            icon: Icons.history_rounded,
            child: Icon(Icons.history_rounded),
          ),
          SizedBox(width: 8),
          Text(
            'Activity history',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    ),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      key: ValueKey(widget.uid),
      stream: _activity,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return Center(
            child: Text('Unable to load history: ${snapshot.error}'),
          );
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final events = snapshot.data!.docs;
        if (events.isEmpty) {
          return const EmptyMessage(
            title: 'No activity yet',
            subtitle: 'Completion changes will appear here.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(18),
          itemCount: events.length,
          separatorBuilder: (_, i) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final e = events[i].data();
            final timestamp = e['at'] as Timestamp?;
            final date = timestamp?.toDate();
            final state = e['to'] as String? ?? 'pending';
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: state == 'completed'
                    ? AppPalette.mint
                    : AppPalette.peach,
                child: Icon(
                  state == 'completed'
                      ? Icons.check_rounded
                      : state == 'skipped'
                      ? Icons.remove_rounded
                      : Icons.undo_rounded,
                  color: AppPalette.deepGreen,
                ),
              ),
              title: Text(
                'Task ${e['taskId']} · $state',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                'Scheduled: ${e['date']} · previously ${e['from']}',
              ),
              trailing: date == null
                  ? null
                  : Text(
                      _dateFormat.format(date),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: AppPalette.muted,
                        fontSize: 11,
                      ),
                    ),
            );
          },
        );
      },
    ),
  );
}
