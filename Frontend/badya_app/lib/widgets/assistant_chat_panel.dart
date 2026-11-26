import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:Badya/widgets/custom_selection_toolbar.dart';
import 'dart:ui' as ui;

class AssistantChatPanel extends StatefulWidget {
  final List<Map<String, String>> messages;
  final Function(String) onSendMessage;
  final String? learningLanguage;
  final String? nativeLanguage;
  final Function(String)? onDefinitionRequested;

  const AssistantChatPanel({
    super.key,
    required this.messages,
    required this.onSendMessage,
    this.learningLanguage,
    this.nativeLanguage,
    this.onDefinitionRequested,
  });

  @override
  State<AssistantChatPanel> createState() => _AssistantChatPanelState();
}

class _AssistantChatPanelState extends State<AssistantChatPanel> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String? _selectedText;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleAction(
    BuildContext context,
    String action,
    String text,
    SelectableRegionState state,
  ) {
    state.hideToolbar();
    CustomSelectionToolbar.handleAction(
      context,
      action,
      text,
      learningLanguage: widget.learningLanguage,
      nativeLanguage: widget.nativeLanguage,
      onDefinition: widget.onDefinitionRequested != null
          ? () => widget.onDefinitionRequested!(text)
          : null,
    );
  }

  void _handleSend() {
    if (_controller.text.trim().isNotEmpty) {
      widget.onSendMessage(_controller.text.trim());
      _controller.clear();
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      // Small delay to allow list to update
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && _scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
          decoration: const BoxDecoration(
            color: Color(0xFF1ABC9C),
            borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.white,
                radius: 24,
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/assistant.png',
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Assistant',
                      style: GoogleFonts.merriweather(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Here to help you learn',
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Chat List
        Expanded(
          child: widget.messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.tips_and_updates_outlined,
                        size: 64,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Ask for a tip!',
                        style: GoogleFonts.nunito(
                          fontSize: 18,
                          color: Colors.grey[400],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )
              : SelectionArea(
                  onSelectionChanged: (content) {
                    _selectedText = content?.plainText;
                  },
                  contextMenuBuilder: (context, selectableRegionState) {
                    return CustomSelectionToolbar(
                      anchors: selectableRegionState.contextMenuAnchors,
                      buttonItems: selectableRegionState.contextMenuButtonItems,
                      onHide: () => selectableRegionState.hideToolbar(),
                      showDefinition: widget.onDefinitionRequested != null,
                      onCustomAction: (action) {
                        _handleAction(
                          context,
                          action,
                          _selectedText ?? '',
                          selectableRegionState,
                        );
                      },
                    );
                  },
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(20),
                    itemCount: widget.messages.length,
                    itemBuilder: (context, index) {
                      final message = widget.messages[index];
                      final isUser = message['role'] == 'user';

                      return Align(
                        alignment: isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(16),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                          ),
                          decoration: BoxDecoration(
                            color: isUser
                                ? Color(0xFF1ABC9C).withValues(alpha: 0.1)
                                : Theme.of(context).cardTheme.color,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(20),
                              topRight: const Radius.circular(20),
                              bottomLeft: isUser
                                  ? const Radius.circular(20)
                                  : const Radius.circular(4),
                              bottomRight: isUser
                                  ? const Radius.circular(4)
                                  : const Radius.circular(20),
                            ),
                            border: isUser
                                ? Border.all(
                                    color: Color(
                                      0xFF1ABC9C,
                                    ).withValues(alpha: 0.2),
                                  )
                                : null,
                            boxShadow: [
                              if (!isUser)
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!isUser) ...[
                                const Icon(
                                  Icons.lightbulb_rounded,
                                  color: Color(0xFFFFD93D),
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                              ],

                              Flexible(
                                child: MarkdownBody(
                                  data: message['content']!,
                                  styleSheet: MarkdownStyleSheet(
                                    p: GoogleFonts.nunito(
                                      fontSize: 16,
                                      color: Theme.of(
                                        context,
                                      ).textTheme.bodyLarge?.color,
                                      height: 1.4,
                                    ),
                                  ),
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

        // Input Area
        Padding(
          padding: const EdgeInsets.all(16),
          child: SafeArea(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Color(0xFF2D2D2D).withValues(alpha: 0.6)
                        : Colors.white.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.white.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          maxLength: 1000,
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          style: GoogleFonts.nunito(
                            fontSize: 15,
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Ask assistant...',
                            counterText: "",
                            hintStyle: GoogleFonts.nunito(
                              color: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.color,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            fillColor: Colors.transparent,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 6, left: 6),
                        child: Container(
                          width: 35,
                          height: 35,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF1ABC9C), Color(0xFF16A085)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: const Icon(
                              Icons.send_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            padding: EdgeInsets.zero,
                            onPressed: _handleSend,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
