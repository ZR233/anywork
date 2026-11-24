import 'package:anywork/src/features/conversation/workspace/conversation_sidebar_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConversationSidebarState', () {
    test('new pending plan opens in expanded mode by default', () {
      final state = ConversationSidebarState<String>();

      state.observePlan(identity: 'interaction:1', pending: true);

      expect(state.isOpen, isTrue);
      expect(state.activeKind, ConversationSidebarPanelKind.plan);
      expect(
        state.layoutModeFor(
          ConversationSidebarPanelKind.plan,
          defaultMode: ConversationSidebarLayoutMode.expanded,
        ),
        ConversationSidebarLayoutMode.expanded,
      );
    });

    test('repeated observation preserves user split, switch, and collapse', () {
      final state = ConversationSidebarState<String>()
        ..observePlan(identity: 'interaction:1', pending: true)
        ..toggleLayoutMode(
          ConversationSidebarPanelKind.plan,
          defaultMode: ConversationSidebarLayoutMode.expanded,
        );
      expect(
        state.layoutModeFor(
          ConversationSidebarPanelKind.plan,
          defaultMode: ConversationSidebarLayoutMode.expanded,
        ),
        ConversationSidebarLayoutMode.split,
      );

      state.observePlan(identity: 'interaction:1', pending: true);
      expect(state.isOpen, isTrue);
      expect(
        state.layoutModeFor(
          ConversationSidebarPanelKind.plan,
          defaultMode: ConversationSidebarLayoutMode.expanded,
        ),
        ConversationSidebarLayoutMode.split,
      );

      state
        ..openPanel(ConversationSidebarPanelKind.workflow)
        ..observePlan(identity: 'interaction:1', pending: true);
      expect(state.activeKind, ConversationSidebarPanelKind.workflow);

      state
        ..collapse()
        ..observePlan(identity: 'interaction:1', pending: true);
      expect(state.isOpen, isFalse);

      // New pending interaction restores expanded default.
      state.observePlan(identity: 'interaction:2', pending: true);
      expect(state.isOpen, isTrue);
      expect(state.activeKind, ConversationSidebarPanelKind.plan);
      expect(
        state.layoutModeFor(
          ConversationSidebarPanelKind.plan,
          defaultMode: ConversationSidebarLayoutMode.expanded,
        ),
        ConversationSidebarLayoutMode.expanded,
      );
    });

    test(
      'read-only plan transition closes pending view and uses split default',
      () {
        final state = ConversationSidebarState<String>()
          ..observePlan(identity: 'interaction:1', pending: true);
        expect(state.isOpen, isTrue);

        state.observePlan(identity: 'plan:2', pending: false);
        expect(state.isOpen, isFalse);
        expect(state.activeKind, ConversationSidebarPanelKind.plan);

        state.openPanel(
          ConversationSidebarPanelKind.plan,
          defaultMode: ConversationSidebarLayoutMode.split,
        );
        expect(state.isOpen, isTrue);
        expect(
          state.layoutModeFor(ConversationSidebarPanelKind.plan),
          ConversationSidebarLayoutMode.split,
        );

        state.observePlan(identity: null, pending: false);
        expect(state.isOpen, isFalse);
        expect(state.activeKind, isNull);
      },
    );

    test(
      'openFile and closeFile restore previous active panel when available',
      () {
        final state = ConversationSidebarState<String>()
          ..openPanel(ConversationSidebarPanelKind.workflow)
          ..openFile('README.md');

        expect(state.isOpen, isTrue);
        expect(state.activeKind, ConversationSidebarPanelKind.file);
        expect(state.file, 'README.md');

        state.closeFile(
          remainingAvailable: const [
            ConversationSidebarPanelKind.workflow,
            ConversationSidebarPanelKind.todo,
          ],
        );
        expect(state.file, isNull);
        expect(state.isOpen, isTrue);
        expect(state.activeKind, ConversationSidebarPanelKind.workflow);

        state
          ..openFile('DESIGN.md')
          ..closeFile(
            remainingAvailable: const [ConversationSidebarPanelKind.todo],
          );
        expect(state.isOpen, isFalse);
        expect(state.activeKind, isNull);
      },
    );

    test(
      'toggleSidebar remembers last panel or falls back to first available',
      () {
        final state = ConversationSidebarState<String>();

        state.toggleSidebar(
          availableOrder: const [
            ConversationSidebarPanelKind.workflow,
            ConversationSidebarPanelKind.todo,
          ],
        );
        expect(state.isOpen, isTrue);
        expect(state.activeKind, ConversationSidebarPanelKind.workflow);

        state.openPanel(ConversationSidebarPanelKind.todo);
        state.toggleSidebar(
          availableOrder: const [
            ConversationSidebarPanelKind.workflow,
            ConversationSidebarPanelKind.todo,
          ],
        );
        expect(state.isOpen, isFalse);

        state.toggleSidebar(
          availableOrder: const [
            ConversationSidebarPanelKind.workflow,
            ConversationSidebarPanelKind.todo,
          ],
        );
        expect(state.isOpen, isTrue);
        expect(state.activeKind, ConversationSidebarPanelKind.todo);

        state
          ..collapse()
          ..toggleSidebar(
            availableOrder: const [ConversationSidebarPanelKind.workflow],
          );
        expect(state.isOpen, isTrue);
        expect(state.activeKind, ConversationSidebarPanelKind.workflow);
      },
    );

    test('reconcileAvailable closes sidebar when active panel disappears', () {
      final state = ConversationSidebarState<String>()
        ..openPanel(ConversationSidebarPanelKind.todo);

      state.reconcileAvailable(const {ConversationSidebarPanelKind.workflow});

      expect(state.isOpen, isFalse);
      expect(state.activeKind, isNull);
    });
  });
}
