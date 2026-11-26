import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:Badya/services/import_service.dart';

class MoveDialogContent extends StatefulWidget {
  final List<dynamic> sections;
  final List<dynamic> allImports;

  const MoveDialogContent({
    super.key,
    required this.sections,
    required this.allImports,
  });

  @override
  State<MoveDialogContent> createState() => _MoveDialogContentState();
}

class _MoveDialogContentState extends State<MoveDialogContent> {
  String _query = '';
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final filtered = widget.sections.where((s) => 
      s['title'].toString().toLowerCase().contains(_query.toLowerCase())
    ).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          onChanged: (v) => setState(() => _query = v),
          style: GoogleFonts.nunito(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Colors.black87,
          ),
          decoration: InputDecoration(
            hintText: 'Search sections...',
            hintStyle: GoogleFonts.nunito(
              color: isDark ? Colors.white38 : Colors.black38,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            prefixIcon: Icon(
              Icons.search_rounded, 
              size: 22, 
              color: isDark ? Colors.white54 : Colors.black45,
            ),
            filled: true,
            fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white.withValues(alpha: 0.8),
            contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFF4ECDC4), width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 8),
        
        // List
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxHeight: 350),
            child: ListView(
              shrinkWrap: true,
              children: [
                // Create New Option
                if (_query.isEmpty) ...[
                  ListTile(
                    onTap: () => Navigator.pop(context, 'CREATE_NEW'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    horizontalTitleGap: 16,
                    leading: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: isDark ? Color(0xFFE67E5A).withValues(alpha: 0.15) : const Color(0xFFFFF1EB),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.add_rounded, color: Color(0xFFE67E5A), size: 28),
                    ),
                    title: Text(
                      'New Section',
                      style: GoogleFonts.nunito(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: isDark ? Colors.white : const Color(0xFF1A1C1E),
                      ),
                    ),
                    subtitle: Text(
                      'Create a folder for this item',
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white38 : Colors.black45,
                      ),
                    ),
                  ),
                  Divider(
                    indent: 16, 
                    endIndent: 16, 
                    height: 24, 
                    thickness: 0.5,
                    color: isDark ? Colors.white10 : Colors.black12,
                  ),
                ],
                
                // Filtered Sections
                ...filtered.map((section) {
                  final sectionId = section['id'];
                  final index = widget.sections.indexOf(section);
                  final count = widget.allImports.where((imp) {
                    final String? sId = imp['section_id'];
                    if (ImportService.isDefaultSectionId(sectionId?.toString())) {
                      return sId == null ||
                          sId == '' ||
                          sId == 'null' ||
                          ImportService.isDefaultSectionId(sId) ||
                          !widget.sections.any((s) => s['id'] == sId);
                    }
                    return sId == sectionId;
                  }).length;

                  // Soft color palettes matching the reference, adjusted for dark mode
                  final List<Map<String, Color>> palette = [
                    {'bg': const Color(0xFF4A90E2), 'icon': const Color(0xFF4A90E2)}, // Blue
                    {'bg': const Color(0xFF9B51E0), 'icon': const Color(0xFF9B51E0)}, // Purple
                    {'bg': const Color(0xFFF2994A), 'icon': const Color(0xFFF2994A)}, // Orange
                    {'bg': const Color(0xFF4ECDC4), 'icon': const Color(0xFF4ECDC4)}, // Green/Teal
                  ];
                  final colors = palette[index % palette.length];

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      onTap: () => Navigator.pop(context, sectionId),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      horizontalTitleGap: 16,
                      leading: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: colors['bg']!.withValues(alpha: isDark ? 0.15 : 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(Icons.folder_open_rounded, color: colors['icon'], size: 26),
                      ),
                      title: Text(
                        section['title'],
                        style: GoogleFonts.nunito(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          color: isDark ? Colors.white : const Color(0xFF1A1C1E),
                        ),
                      ),
                      subtitle: Text(
                        '$count items',
                        style: GoogleFonts.nunito(
                          fontSize: 13,
                          color: isDark ? Colors.white54 : Colors.black45,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
