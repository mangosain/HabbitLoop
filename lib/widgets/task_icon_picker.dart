import 'package:material_ui/material_ui.dart';

import 'task_icons.dart';
import 'shared_element.dart';

class TaskIconPicker extends StatefulWidget {
  const TaskIconPicker({
    super.key,
    required this.selectedId,
    this.previewIcon,
    this.iconHeroTag,
  });

  final String? selectedId;
  final IconData? previewIcon;
  final Object? iconHeroTag;

  @override
  State<TaskIconPicker> createState() => _TaskIconPickerState();
}

class _TaskIconPickerState extends State<TaskIconPicker> {
  final _scroll = ScrollController();
  late List<TaskIconOption> _results = searchTaskIcons('');

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _search(String query) {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() => _results = searchTaskIcons(query));
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: SizedBox(
      width: 520,
      height: 570,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 2),
            child: Row(
              children: [
                if (widget.iconHeroTag case final tag?)
                  SharedIcon(
                    tag: tag,
                    icon: widget.previewIcon!,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 9),
                      child: Icon(widget.previewIcon),
                    ),
                  ),
                Expanded(
                  child: Text(
                    'Task icon',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close icon picker',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: _search,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                labelText: 'Search icons',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.auto_awesome_rounded),
            title: const Text('Automatic'),
            selected: widget.selectedId == null,
            trailing: widget.selectedId == null
                ? const Icon(Icons.check_rounded)
                : null,
            onTap: () => Navigator.pop(context, 'auto'),
          ),
          Expanded(
            child: _results.isEmpty
                ? const Center(child: Text('No matching icons'))
                : GridView.builder(
                    controller: _scroll,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 108,
                          mainAxisExtent: 78,
                          crossAxisSpacing: 4,
                          mainAxisSpacing: 4,
                        ),
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final option = _results[index];
                      return Semantics(
                        selected: widget.selectedId == option.id,
                        child: TextButton(
                          onPressed: () => Navigator.pop(context, option.id),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.all(4),
                            backgroundColor: widget.selectedId == option.id
                                ? Theme.of(context)
                                      .colorScheme
                                      .secondaryContainer
                                : null,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(option.icon, size: 24),
                              const SizedBox(height: 3),
                              Text(
                                option.label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}
