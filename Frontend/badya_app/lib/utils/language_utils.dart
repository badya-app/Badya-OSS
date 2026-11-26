
class LanguageUtils {
  static String formatOpenedDate(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return 'Never opened';
    
    try {
      final date = DateTime.parse(isoDate);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        if (date.day == now.day) return 'Opened today';
        return 'Opened yesterday';
      } else if (difference.inDays == 1) {
        return 'Opened yesterday';
      } else if (difference.inDays < 7) {
        return 'Opened ${difference.inDays} days ago';
      } else {
        final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return 'Opened ${months[date.month - 1]} ${date.day.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      return 'Never opened';
    }
  }
}
