import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/connectivity_service.dart';

class ChatSheet extends StatefulWidget {
  const ChatSheet({super.key});

  @override
  State<ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<ChatSheet> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Clear unread count when chat is opened
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ConnectivityService>(context, listen: false).clearUnreadChatCount();
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final connService = Provider.of<ConnectivityService>(context, listen: false);
    connService.sendChatMessage(text);
    _controller.clear();
    
    // Auto-scroll after a short frame delay so the list has time to build the new message
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  @override
  Widget build(BuildContext context) {
    final connService = Provider.of<ConnectivityService>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final backgroundColor = isDark ? const Color(0xFF161B26) : Colors.white;
    final borderColor = isDark ? const Color(0xFF1F2937) : const Color(0xFFE5E7EB);
    final textColor = isDark ? Colors.white : const Color(0xFF111827);
    final bubbleMeColor = const Color(0xFF8A2387);
    final bubbleMeTextColor = Colors.white;
    final bubblePeerColor = isDark ? const Color(0xFF2D3748) : const Color(0xFFF3F4F6);
    final bubblePeerTextColor = isDark ? Colors.white : const Color(0xFF1F2937);

    // Keep keyboard overlay from blocking bottom sheet
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    // Trigger auto-scroll on new incoming message while open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (connService.unreadChatCount > 0) {
        connService.clearUnreadChatCount();
      }
      _scrollToBottom();
    });

    return Container(
      margin: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: 12 + bottomInset,
        top: 80, // Safe top margin
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: isDark ? const Color(0xFF00F2FE) : const Color(0xFF8A2387),
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Chat mit ${connService.connectedPeer?.name ?? "Gegner"}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: isDark ? Colors.white60 : Colors.black54,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1),

          // Messages View
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 350),
              child: connService.chatMessages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 40,
                            color: isDark ? Colors.white10 : Colors.black12,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Sende eine Nachricht,\num den Chat zu starten!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white30 : Colors.black38,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: connService.chatMessages.length,
                      itemBuilder: (context, index) {
                        final msg = connService.chatMessages[index];
                        final isMe = msg.isMe;

                        return Align(
                          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.7,
                            ),
                            decoration: BoxDecoration(
                              color: isMe ? bubbleMeColor : bubblePeerColor,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16),
                                topRight: const Radius.circular(16),
                                bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
                                bottomRight: isMe ? Radius.zero : const Radius.circular(16),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!isMe)
                                  Text(
                                    msg.senderName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                      color: isDark ? Colors.white70 : Colors.black54,
                                    ),
                                  ),
                                if (!isMe) const SizedBox(height: 2),
                                Text(
                                  msg.text,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    color: isMe ? bubbleMeTextColor : bubblePeerTextColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
          const Divider(height: 1, thickness: 1),
          
          // Quick emoji reactions row
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                '👍', '❤️', '😂', '🔥', '👏', '😮', '😢', '🎮', '🎉', '👑', '🤔', '💯'
              ].map((emoji) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    onTap: () {
                      connService.sendChatMessage(emoji);
                      Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Text(
                        emoji,
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          
          const Divider(height: 1, thickness: 1),

          // Message Input Field
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 12, top: 8, bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                    style: TextStyle(fontSize: 14, color: textColor),
                    decoration: InputDecoration(
                      hintText: 'Nachricht schreiben...',
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white30 : Colors.black38,
                      ),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send_rounded),
                  color: isDark ? const Color(0xFF00F2FE) : const Color(0xFF8A2387),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
