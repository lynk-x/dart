import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynk_x/presentation/features/forum/models/forum_model.dart';
import 'package:lynk_x/presentation/features/forum/widgets/message_list_keys.dart';

/// Counts how many times each message's widget state was created — a stand-in for the real
/// bubble's expensive state (link previews, loaded images, selection).
final _created = <String, int>{};

class _Probe extends StatefulWidget {
  final String id;
  const _Probe(this.id);
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    _created[widget.id] = (_created[widget.id] ?? 0) + 1;
  }

  @override
  Widget build(BuildContext context) => SizedBox(height: 40, child: Text(widget.id));
}

ChatMessage _msg(String id) => ChatMessage(
      id: id,
      sender: 'Sender',
      userId: 'u',
      message: 'hello $id',
      createdAt: DateTime(2026, 1, 1),
      isMe: false,
      type: MessageType.chat,
    );

/// A reversed list like the forum's: newest message at index 0. [messages] is read at build time.
Widget _list(List<ChatMessage> messages, {required bool useHelpers}) {
  return MaterialApp(
    home: Scaffold(
      body: CustomScrollView(
        reverse: true,
        slivers: [
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = _Probe(messages[index].id);
                return useHelpers ? keyedMessageItem(messages[index], item) : item;
              },
              findChildIndexCallback:
                  useHelpers ? messageChildIndexFinder(messages) : null,
              childCount: messages.length,
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  setUp(_created.clear);

  Future<void> insertNewestMessage(WidgetTester tester, {required bool useHelpers}) async {
    final messages = [_msg('c'), _msg('b'), _msg('a')]; // newest first
    await tester.pumpWidget(_list(messages, useHelpers: useHelpers));
    expect(_created, {'a': 1, 'b': 1, 'c': 1});

    // A new message arrives and lands at index 0, shifting every existing item by one.
    await tester.pumpWidget(_list([_msg('d'), ...messages], useHelpers: useHelpers));
  }

  testWidgets('existing bubbles keep their state when a new message arrives', (tester) async {
    await insertNewestMessage(tester, useHelpers: true);
    expect(_created['a'], 1, reason: 'a must be moved, not rebuilt');
    expect(_created['b'], 1);
    expect(_created['c'], 1);
    expect(_created['d'], 1);
  });

  testWidgets('control: without the helpers every bubble is rebuilt (the old behaviour)', (tester) async {
    await insertNewestMessage(tester, useHelpers: false);
    // Matched by position, the elements at shifted indices are different messages, so their
    // state is recreated. This documents what the helpers prevent.
    expect(_created.values.any((n) => n > 1), isTrue);
  });

  test('messageChildIndexFinder maps keys to current indices and ignores foreign keys', () {
    final find = messageChildIndexFinder([_msg('x'), _msg('y')]);
    expect(find(const ValueKey<String>('x')), 0);
    expect(find(const ValueKey<String>('y')), 1);
    expect(find(const ValueKey<String>('gone')), isNull);
    expect(find(const ValueKey<int>(7)), isNull);
  });
}
