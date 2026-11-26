import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:Badya/utils/ui_utils.dart';
import 'package:Badya/services/import_service.dart';

class SectionIndexDrawerContent extends StatefulWidget {
  final List<Map<String, dynamic>> sections;
  final List<Map<String, dynamic>> allImports;
  final Function(String, int) onReorder;
  final VoidCallback onCreateSection;
  final Function(Map<String, dynamic>) onRenameSection;
  final Function(Map<String, dynamic>) onDeleteSection;
  final Function(int) onTapSection;

  const SectionIndexDrawerContent({
    super.key,
    required this.sections,
    required this.allImports,
    required this.onReorder,
    required this.onCreateSection,
    required this.onRenameSection,
    required this.onDeleteSection,
    required this.onTapSection,
  });

  @override
  State<SectionIndexDrawerContent> createState() => _SectionIndexDrawerContentState();
}

class _SectionIndexDrawerContentState extends State<SectionIndexDrawerContent> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final filteredSections = widget.sections.where((s) => 
      s['title'].toString().toLowerCase().contains(_searchQuery.toLowerCase())
    ).toList();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121212) : theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.08),
            blurRadius: 40,
            offset: const Offset(10, 0),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Library',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : const Color(0xFF1A1C1E),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ),
                ],
              ),
            ),

            // Search Bar + Add Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (v) => setState(() => _searchQuery = v),
                        decoration: InputDecoration(
                          hintText: 'Search sections',
                          hintStyle: GoogleFonts.nunito(
                            color: isDark ? Colors.white38 : Colors.black38,
                            fontSize: 14,
                          ),
                          prefixIcon: Icon(
                            Icons.search_rounded, 
                            size: 18, 
                            color: isDark ? Colors.white54 : const Color(0xFF4ECDC4)
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Material(
                    color: Color(0xFF4ECDC4).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        widget.onCreateSection();
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: const Icon(
                          Icons.create_new_folder_rounded,
                          color: Color(0xFF4ECDC4),
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // List
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: filteredSections.length,
                proxyDecorator: (child, index, animation) {
                  return AnimatedBuilder(
                    animation: animation,
                    builder: (context, child) {
                      return Material(
                        elevation: 0,
                        color: Colors.transparent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        clipBehavior: Clip.antiAlias,
                        child: child,
                      );
                    },
                    child: child,
                  );
                },
                onReorder: (oldIndex, newIndex) {
                  if (oldIndex < newIndex) newIndex -= 1;
                  widget.onReorder(filteredSections[oldIndex]['id'], newIndex);
                },
                itemBuilder: (context, index) {
                  final section = filteredSections[index];
                  final sectionId = section['id'];
                    final bool isDefaultSection = ImportService.isDefaultSectionId(sectionId?.toString()) ||
                                                 (index == 0 && section['title'] == 'My Imports');
                     final count = widget.allImports.where((imp) {
                      final String? sId = imp['section_id'];
                      if (isDefaultSection) {
                        return sId == null ||
                            sId == '' ||
                            sId == 'null' ||
                            ImportService.isDefaultSectionId(sId) ||
                            !widget.sections.any((s) => s['id'] == sId);
                      }
                      return sId == sectionId;
                    }).length;

                  final List<Color> folderColors = [
                    const Color(0xFF4ECDC4),
                    const Color(0xFFFF6B6B),
                    const Color(0xFF4A90E2),
                    const Color(0xFF9B51E0),
                    const Color(0xFFF2994A),
                    const Color(0xFF27AE60),
                  ];
                  final Color folderColor = folderColors[index % folderColors.length];

                  return Container(
                    key: Key(sectionId),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        onTap: () {
                          final realIndex = widget.sections.indexOf(section);
                          widget.onTapSection(realIndex);
                        },
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: folderColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(Icons.folder_rounded, color: folderColor, size: 24),
                        ),
                        title: Text(
                          section['title'],
                          style: GoogleFonts.nunito(
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                            color: isDark ? Colors.white : const Color(0xFF1A1C1E),
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '$count items • Modified ${UiUtils.formatTimeAgo(section['last_updated'])}',
                            style: GoogleFonts.nunito(
                              fontSize: 13,
                              color: isDark ? Colors.white38 : Colors.black45,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        trailing: isDefaultSection 
                          ? null 
                          : PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'rename') {
                                  widget.onRenameSection(section);
                                } else if (value == 'delete') {
                                  widget.onDeleteSection(section);
                                }
                              },
                              icon: const Icon(Icons.more_vert_rounded, color: Colors.grey),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'rename',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit_rounded, size: 20, color: isDark ? Colors.white70 : Colors.black54),
                                      const SizedBox(width: 12),
                                      Text('Rename', style: GoogleFonts.raleway(fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.redAccent),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Delete', 
                                        style: GoogleFonts.raleway(
                                          fontWeight: FontWeight.w600,
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
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
}
