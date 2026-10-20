import 'package:gpt_markdown/gpt_markdown.dart'
    show kGptMarkdownFontPackage, kGptMarkdownMonoFontFamily;

/// Package-qualified family shared by code surfaces; missing glyphs use the
/// platform fallback instead of requiring a separately installed font.
const studioCodeFontFamily =
    'packages/$kGptMarkdownFontPackage/$kGptMarkdownMonoFontFamily';
