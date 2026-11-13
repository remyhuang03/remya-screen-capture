part of 'image_editor.dart';

class _FontPicker extends StatefulWidget {
  const _FontPicker({required this.selected});

  static const _genericFonts = {
    'sans-serif': 'Sans',
    'serif': 'Serif',
    'monospace': 'Monospace',
  };

  final String selected;

  static String label(String family) => _genericFonts[family] ?? family;

  @override
  State<_FontPicker> createState() => _FontPickerState();
}

class _FontPickerState extends State<_FontPicker> {
  late final _systemFonts = _loadSystemFonts();
  String _query = '';

  Future<List<String>> _loadSystemFonts() async {
    final result = await Process.run('fc-list', [
      '--format',
      r'%{[]family{%{family}\n}}',
    ]);
    if (result.exitCode != 0) throw StateError('fc-list failed');
    final families = {
      for (final line in (result.stdout as String).split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    };
    return families.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Font'),
    content: SizedBox(
      width: 380,
      height: 380,
      child: Column(
        spacing: 8,
        children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Search fonts'),
            onChanged: (value) => setState(() {
              _query = value.trim().toLowerCase();
            }),
          ),
          Expanded(
            child: FutureBuilder<List<String>>(
              future: _systemFonts,
              builder: (context, snapshot) {
                if (snapshot.connectionState != .done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final options =
                    {
                      widget.selected,
                      ..._FontPicker._genericFonts.keys,
                      ...?snapshot.data,
                    }.where((family) {
                      return _FontPicker.label(family)
                          .toLowerCase()
                          .contains(_query);
                    }).toList();
                if (options.isEmpty && !snapshot.hasError) {
                  return const Center(child: Text('No matching fonts'));
                }
                return ListView.builder(
                  itemCount: options.length + (snapshot.hasError ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == options.length) {
                      return const ListTile(
                        title: Text('System fonts could not be loaded'),
                      );
                    }
                    final family = options[index];
                    return ListTile(
                      title: Text(_FontPicker.label(family)),
                      selected: family == widget.selected,
                      onTap: () => Navigator.pop(context, family),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  );
}
