import '../../models/chat_models.dart';

/// Normalizes a session so legacy linear message lists get explicit tree links.
void normalizeSession(ChatSession session) {
  if (session.messages.isEmpty) {
    session.rootMessageId = null;
    return;
  }
  if (session.rootMessageId == null) {
    session.rootMessageId = session.messages.first.id;
    for (var i = 0; i < session.messages.length; i++) {
      final msg = session.messages[i];
      msg.parentId = i == 0 ? null : session.messages[i - 1].id;
      msg.selectedChildId =
          i + 1 < session.messages.length ? session.messages[i + 1].id : null;
    }
  }
}

/// Walks from [session.rootMessageId] following `selectedChildId` to produce
/// the currently visible linear conversation path.
List<ChatMessage> getVisibleMessages(ChatSession session) {
  normalizeSession(session);
  if (session.rootMessageId == null) return const [];

  final byId = <String, ChatMessage>{
    for (final m in session.messages) m.id: m,
  };

  final path = <ChatMessage>[];
  String? currentId = session.rootMessageId;
  while (currentId != null) {
    final msg = byId.remove(currentId);
    if (msg == null) break;
    path.add(msg);
    currentId = msg.selectedChildId;
  }
  return path;
}

/// Groups sibling messages by `parentId` to power `< 1 / N >` version switchers.
Map<String, MessageVersionInfo> buildMessageVersions(ChatSession session) {
  normalizeSession(session);
  final childrenByParent = <String?, List<String>>{};
  for (final m in session.messages) {
    childrenByParent.putIfAbsent(m.parentId, () => []).add(m.id);
  }
  final versions = <String, MessageVersionInfo>{};
  for (final ids in childrenByParent.values) {
    for (var i = 0; i < ids.length; i++) {
      versions[ids[i]] = MessageVersionInfo(ids: ids, index: i);
    }
  }
  return versions;
}

/// Appends a new chain of [newMessages] under [parentId] and switches active selection to it.
void appendBranch(
  ChatSession session,
  String? parentId,
  List<ChatMessage> newMessages,
) {
  if (newMessages.isEmpty) return;
  normalizeSession(session);

  for (var i = 0; i < newMessages.length; i++) {
    final msg = newMessages[i];
    msg.parentId = i == 0 ? parentId : newMessages[i - 1].id;
    msg.selectedChildId =
        i + 1 < newMessages.length ? newMessages[i + 1].id : null;
  }

  if (parentId == null) {
    session.rootMessageId = newMessages.first.id;
  } else {
    for (final m in session.messages) {
      if (m.id == parentId) {
        m.selectedChildId = newMessages.first.id;
        break;
      }
    }
  }

  session.messages.addAll(newMessages);
}

/// Switches the active branch to sibling [messageId] if its parent is on the visible path.
bool selectVersion(ChatSession session, String messageId) {
  normalizeSession(session);
  ChatMessage? target;
  for (final m in session.messages) {
    if (m.id == messageId) {
      target = m;
      break;
    }
  }
  if (target == null) return false;

  if (target.parentId == null) {
    if (session.rootMessageId == target.id) return false;
    session.rootMessageId = target.id;
    return true;
  }

  final visibleIds = getVisibleMessages(session).map((m) => m.id).toSet();
  if (!visibleIds.contains(target.parentId)) return false;

  for (final m in session.messages) {
    if (m.id == target.parentId) {
      if (m.selectedChildId == target.id) return false;
      m.selectedChildId = target.id;
      return true;
    }
  }
  return false;
}
