import 'package:Badya/services/user_preferences_service.dart';
import 'package:Badya/services/vocab_review_service.dart';
import 'package:Badya/utils/language_service.dart';
import 'package:Badya/utils/ui_utils.dart';
import 'package:Badya/widgets/definition_dialog.dart';
import 'package:Badya/widgets/translation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

class CustomSelectionToolbar extends StatelessWidget {
  final TextSelectionToolbarAnchors anchors;
  final List<ContextMenuButtonItem> buttonItems;
  final VoidCallback onHide;
  final Function(String action) onCustomAction;
  final bool showDefinition;

  const CustomSelectionToolbar({
    super.key,
    required this.anchors,
    required this.buttonItems,
    required this.onHide,
    required this.onCustomAction,
    this.showDefinition = true,
  });

  static Future<void> handleAction(
    BuildContext context,
    String action,
    String text, {
    VoidCallback? onDefinition,
    String? learningLanguage,
    String? nativeLanguage,
  }) async {
    final languageService = LanguageService();

    if (action == 'Translate') {
      if (context.mounted) {
        TranslationDialog.show(
          context,
          text,
          sourceLanguage: learningLanguage,
          targetLanguage: nativeLanguage,
        );
      }
    } else if (action == 'Strange Word') {
      final vocabService = VocabReviewService();
      final prefs = UserPreferencesService();
      final lang = learningLanguage ?? await prefs.getCurrentLanguage();
      await vocabService.addWord(word: text, language: lang);
      if (context.mounted) {
        UiUtils.showTopNotification(
          context,
          'Saved to Strange words for $lang: '
          '"${text.length > 20 ? '${text.substring(0, 20)}...' : text}"',
          type: NotificationType.success,
          icon: Icons.add_card_rounded,
        );
      }
    } else if (action == 'Speak') {
      await languageService.speak(text, learningLang: learningLanguage);
    } else if (action == 'Definition') {
      if (onDefinition != null) {
        onDefinition();
      } else {
        if (context.mounted) {
          DefinitionDialog.show(
            context,
            text,
            sourceLanguage: learningLanguage,
            targetLanguage: nativeLanguage,
          );
        }
      }
    } else {
      if (context.mounted) {
        UiUtils.showTopNotification(
          context,
          '$action: "${text.length > 20 ? '${text.substring(0, 20)}...' : text}"',
          type: NotificationType.info,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomSingleChildLayout(
      delegate: _ToolbarLayoutDelegate(anchors.primaryAnchor),
      child: Material(
        color: Colors.transparent,
        child: _ToolbarContent(
          buttonItems: buttonItems,
          onHide: onHide,
          onCustomAction: onCustomAction,
          showDefinition: showDefinition,
        ),
      ),
    );
  }
}

class _ToolbarContent extends StatefulWidget {
  final List<ContextMenuButtonItem> buttonItems;
  final VoidCallback onHide;
  final Function(String action) onCustomAction;
  final bool showDefinition;

  const _ToolbarContent({
    required this.buttonItems,
    required this.onHide,
    required this.onCustomAction,
    required this.showDefinition,
  });

  @override
  State<_ToolbarContent> createState() => _ToolbarContentState();
}

class _ToolbarContentState extends State<_ToolbarContent> {
  bool _showMore = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: _showMore ? 220 : 300,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (_showMore)
                IconButton(
                  onPressed: () => setState(() => _showMore = false),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                )
              else
                const SizedBox(width: 32),
              InkWell(
                onTap: widget.onHide,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(16),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: Colors.grey,
                  ),
                ),
              ),
            ],
          ),

          // Content
          if (!_showMore)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSvgOption('assets/images/addcard.svg', 'Add', () {
                    widget.onCustomAction('Strange Word');
                  }),
                  _buildOption(Icons.volume_up_rounded, 'Speak', () {
                    widget.onCustomAction('Speak');
                  }),
                  if (widget.showDefinition)
                    _buildOption(Icons.menu_book_rounded, 'Define', () {
                      widget.onCustomAction('Definition');
                    }),
                  _buildOption(Icons.translate_rounded, 'Translate', () {
                    widget.onCustomAction('Translate');
                  }),
                  _buildActionButton(Icons.more_vert_rounded, 'More', () {
                    setState(() => _showMore = true);
                  }),
                ],
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 250),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                itemCount: widget.buttonItems.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = widget.buttonItems[index];
                  final label = AdaptiveTextSelectionToolbar.getButtonLabel(
                    context,
                    item,
                  );
                  final icon = _getIconForButtonType(item.type);

                  return ListTile(
                    visualDensity: VisualDensity.compact,
                    leading: icon != null ? Icon(icon, size: 18) : null,
                    title: Text(
                      label,
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () {
                      item.onPressed?.call();
                      widget.onHide();
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  IconData? _getIconForButtonType(ContextMenuButtonType type) {
    switch (type) {
      case ContextMenuButtonType.copy:
        return Icons.copy_rounded;
      case ContextMenuButtonType.selectAll:
        return Icons.select_all_rounded;
      case ContextMenuButtonType.paste:
        return Icons.paste_rounded;
      case ContextMenuButtonType.cut:
        return Icons.cut_rounded;
      case ContextMenuButtonType.searchWeb:
        return Icons.search_rounded;
      case ContextMenuButtonType.share:
        return Icons.share_rounded;
      default:
        return null;
    }
  }

  Widget _buildSvgOption(String svgAsset, String label, VoidCallback onTap) {
    final theme = Theme.of(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              svgAsset,
              width: 18,
              height: 18,
              colorFilter: ColorFilter.mode(
                theme.iconTheme.color ?? Colors.black,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(IconData icon, String label, VoidCallback onTap) {
    final theme = Theme.of(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: theme.iconTheme.color, size: 18),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onTap) {
    final theme = Theme.of(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: theme.iconTheme.color, size: 18),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarLayoutDelegate extends SingleChildLayoutDelegate {
  final Offset anchor;

  _ToolbarLayoutDelegate(this.anchor);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return constraints.loosen();
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double x = anchor.dx - childSize.width / 2;
    double y = anchor.dy - childSize.height - 16;

    if (x < 10) x = 10;
    if (x + childSize.width > size.width - 10) {
      x = size.width - childSize.width - 10;
    }
    if (y < 10) {
      y = anchor.dy + 16;
    }

    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_ToolbarLayoutDelegate oldDelegate) {
    return anchor != oldDelegate.anchor;
  }
}
