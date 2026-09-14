import 'package:flutter/material.dart';

class MarkdownEditingController extends TextEditingController {
  static const _codeSurface = Color(0xFF21142F);
  static const _codeText = Color(0xFFF0E8F6);
  static const _codeKeyword = Color(0xFF71C7EC);
  static const _codeString = Color(0xFFF2B880);
  static const _codeNumber = Color(0xFFC7A4FF);
  static const _codeComment = Color(0xFF91B98C);
  static const _codeFunction = Color(0xFFE6C27A);
  static const _codeType = Color(0xFFB69CFF);
  static const _codePunctuation = Color(0xFFBDB0CA);

  MarkdownEditingController({
    super.text,
    this.onLinkTap,
    this.onImageTap,
    this.imageHeightLines = 5,
  }) : assert(imageHeightLines > 0, 'imageHeightLines must be positive') {
    _sourceText = super.text;
    // Add virtual newlines for image spacing on initial text
    _updateTextWithNewlines();
  }

  /// Called when a link is tapped. Receives the URL as a string.
  final void Function(String url)? onLinkTap;

  /// Called when an image is tapped. Receives the URL as a string.
  final void Function(String url)? onImageTap;

  /// The height of inline images in lines of text.
  /// The actual height is calculated as: fontSize * imageHeightLines.
  /// Defaults to 5 lines.
  final int imageHeightLines;

  /// Stores link ranges for offset-based tap detection.
  /// Each entry contains (start, end, url).
  final List<({int start, int end, String url})> _linkRanges = [];

  /// The currently focused line number (0-indexed).
  /// When set, syntax markers are hidden on all other lines.
  int? _focusedLine;

  /// The source text without virtual newlines
  String _sourceText = '';

  /// Flag to prevent recursive text updates
  bool _isUpdatingText = false;

  int? get focusedLine => _focusedLine;

  /// Set the focused line and update text to inject/remove newlines
  set focusedLine(int? value) {
    if (_focusedLine != value) {
      _focusedLine = value;
      _updateTextWithNewlines();
      notifyListeners();
    }
  }

  void updateFocusedLineFromSelection() {
    if (selection.isValid && selection.baseOffset >= 0) {
      // Ensure _sourceText is up-to-date (defensive measure)
      if (_sourceText.isEmpty && super.text.isNotEmpty) {
        _sourceText = _removeVirtualNewlines(super.text);
      }
      // Map display offset to source offset first, then calculate line number from source text
      final sourceOffset = _displayToSourceOffset(
        selection.baseOffset,
        super.text,
      );
      focusedLine = _getLineNumber(sourceOffset, _sourceText);
    }
  }

  /// Looks up the URL at the given character offset.
  /// Returns null if no link exists at that offset.
  String? getLinkUrlAtOffset(int offset) {
    for (final range in _linkRanges) {
      if (offset >= range.start && offset < range.end) {
        return range.url;
      }
    }
    return null;
  }

  /// Maps a display text offset to a source text offset.
  /// Virtual newline markers in display text are skipped when counting source offset.
  int _displayToSourceOffset(int displayOffset, String displayText) {
    int sourceOffset = 0;

    for (int i = 0; i < displayOffset && i < displayText.length; i++) {
      if (displayText.startsWith(_virtualNewlineMarker, i)) {
        // Virtual newline marker - skip in source, advance past both chars
        i += _virtualNewlineMarker.length - 1;
      } else {
        sourceOffset++;
      }
    }

    return sourceOffset;
  }

  int _getLineNumber(int offset, String text) {
    int line = 0;
    for (int i = 0; i < offset && i < text.length; i++) {
      if (text[i] == '\n') {
        line++;
      }
    }
    return line;
  }

  (int start, int end) _getLineRange(int lineNumber, String text) {
    int currentLine = 0;
    int lineStart = 0;

    for (int i = 0; i < text.length; i++) {
      if (currentLine == lineNumber) {
        int lineEnd = i;
        while (lineEnd < text.length && text[lineEnd] != '\n') {
          lineEnd++;
        }
        return (lineStart, lineEnd);
      }
      if (text[i] == '\n') {
        currentLine++;
        lineStart = i + 1;
      }
    }

    if (currentLine == lineNumber) {
      return (lineStart, text.length);
    }

    return (0, 0);
  }

  /// Builds an image widget for rendering inline images.
  Widget _buildImageWidget(String url, String altText, TextStyle style) {
    final fontSize = style.fontSize?.toDouble() ?? 16.0;

    return GestureDetector(
      onTap: onImageTap != null ? () => onImageTap!(url) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: SizedBox(
          height: fontSize * imageHeightLines * (style.height ?? 1.2),
          child: _buildImageWithSource(url, altText),
        ),
      ),
    );
  }

  /// Builds the appropriate image source based on URL scheme.
  Widget _buildImageWithSource(String url, String altText) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return Image.network(
        url,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _buildImageError(altText),
      );
    } else if (url.startsWith('asset://')) {
      return Image.asset(
        url.replaceFirst('asset://', ''),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _buildImageError(altText),
      );
    } else {
      // Unknown scheme - show error placeholder directly
      return _buildImageError(
        altText.isNotEmpty ? altText : 'Unsupported URL: $url',
      );
    }
  }

  /// Builds an error placeholder when image fails to load.
  Widget _buildImageError(String altText) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        altText.isNotEmpty ? altText : 'Image not found',
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
    );
  }

  // ============================================================
  // NEWLINE INJECTION FOR IMAGE SPACING
  // ============================================================

  /// Pattern to match image syntax (with full groups for parsing)
  static final _imagePattern = RegExp(r'(!\[)([^\]]*)(\]\()([^)]+)(\))');

  /// Pattern to match our virtual newlines (marked with special comment)
  /// We use zero-width space + newline to mark virtual newlines
  static const _virtualNewlineMarker = '\u200B\n';

  /// Update the actual text to include newlines around unfocused images
  void _updateTextWithNewlines() {
    if (_isUpdatingText) return;
    _isUpdatingText = true;

    try {
      _updateTextWithNewlinesInternal();
    } finally {
      _isUpdatingText = false;
    }
  }

  /// Keeps the editable buffer as the original Markdown source.
  ///
  /// Earlier versions injected zero-width markers and real newlines around
  /// image previews. That made the TextField's buffer differ from the note
  /// source, which caused IME edits and cursor moves to replay removed text.
  /// Image previews already have their own WidgetSpan height, so the source
  /// buffer never needs synthetic characters.
  void _updateTextWithNewlinesInternal() {
    final cleanText = _removeVirtualNewlines(super.text);
    _sourceText = cleanText;
    if (super.text == cleanText) return;
    final oldSelection = selection;
    super.value = super.value.copyWith(
      text: cleanText,
      selection: TextSelection(
        baseOffset: oldSelection.baseOffset.clamp(0, cleanText.length),
        extentOffset: oldSelection.extentOffset.clamp(0, cleanText.length),
        affinity: oldSelection.affinity,
      ),
      composing: TextRange.empty,
    );
  }

  /// Remove virtual newlines from text
  String _removeVirtualNewlines(String text) {
    return text.replaceAll(_virtualNewlineMarker, '');
  }

  /// Override text setter so externally loaded notes retain exact source text.
  @override
  set text(String value) {
    if (_isUpdatingText) {
      super.text = value;
      return;
    }
    final cleanValue = _removeVirtualNewlines(value);
    _isUpdatingText = true;
    try {
      _sourceText = cleanValue;
      super.value = TextEditingValue(
        text: cleanValue,
        selection: TextSelection.collapsed(offset: cleanValue.length),
      );
    } finally {
      _isUpdatingText = false;
    }
  }

  /// Override value setter to handle paste operations
  /// Flutter's TextField sets controller.value directly when pasting,
  /// bypassing the text setter. This ensures _sourceText stays synchronized.
  @override
  set value(TextEditingValue newValue) {
    if (_isUpdatingText) {
      super.value = newValue;
      return;
    }

    // Check if text has actually changed (selection-only changes should pass through)
    if (newValue.text == super.text) {
      // Selection-only change - pass through without processing
      super.value = newValue;
      return;
    }

    // Text has changed - clean virtual newlines and update source text.
    final previousSource = _removeVirtualNewlines(super.text);
    var cleanText = _removeVirtualNewlines(newValue.text);

    // Map selection from display coordinates (in newValue.text) to source coordinates
    // This is critical because newValue.selection is relative to newValue.text which
    // contains virtual newlines, but we're about to set cleanText which has none.
    var mappedSourceBase = _displayToSourceOffset(
      newValue.selection.baseOffset,
      newValue.text,
    );
    var mappedSourceExtent = _displayToSourceOffset(
      newValue.selection.extentOffset,
      newValue.text,
    );

    final continuation = _numberedListContinuation(
      previousSource,
      cleanText,
      mappedSourceExtent,
    );
    if (continuation != null) {
      cleanText = continuation.text;
      mappedSourceBase = continuation.selectionOffset;
      mappedSourceExtent = continuation.selectionOffset;
    }
    _sourceText = cleanText;

    // Update with cleaned text AND mapped selection (source coordinates)
    _isUpdatingText = true;
    try {
      final sourceSelection = TextSelection(
        baseOffset: mappedSourceBase.clamp(0, cleanText.length),
        extentOffset: mappedSourceExtent.clamp(0, cleanText.length),
        affinity: newValue.selection.affinity,
      );
      super.value = newValue.copyWith(
        text: cleanText,
        selection: sourceSelection,
      );
      // Keep the backing TextField value as exact Markdown source. Rendering
      // is handled in buildTextSpan and must not rewrite the edit buffer.
      _updateTextWithNewlinesInternal();
    } finally {
      _isUpdatingText = false;
    }
  }

  /// Get the source text (without virtual newlines)
  String get sourceText => _sourceText;

  ({String text, int selectionOffset})? _numberedListContinuation(
    String previousSource,
    String updatedSource,
    int selectionOffset,
  ) {
    // Only react to one Enter keypress, never to a pasted multi-line block.
    if (updatedSource.length != previousSource.length + 1 ||
        selectionOffset <= 0 ||
        selectionOffset > updatedSource.length ||
        updatedSource[selectionOffset - 1] != '\n') {
      return null;
    }
    final withoutNewline =
        updatedSource.substring(0, selectionOffset - 1) +
        updatedSource.substring(selectionOffset);
    if (withoutNewline != previousSource) return null;

    final previousLineStart =
        updatedSource.lastIndexOf('\n', selectionOffset - 2) + 1;
    final previousLine = updatedSource.substring(
      previousLineStart,
      selectionOffset - 1,
    );
    final match = RegExp(r'^([ \t]*)(\d+)\.\s+\S').firstMatch(previousLine);
    if (match == null) return null;

    final prefix = '${match.group(1)}${int.parse(match.group(2)!) + 1}. ';
    return (
      text:
          updatedSource.substring(0, selectionOffset) +
          prefix +
          updatedSource.substring(selectionOffset),
      selectionOffset: selectionOffset + prefix.length,
    );
  }

  List<InlineSpan> _buildCodeSpans(
    String code,
    TextStyle style,
    String language,
  ) {
    final keywords = switch (language) {
      'dart' =>
        r'abstract|as|async|await|bool|break|case|catch|class|const|continue|default|do|double|else|enum|extends|false|final|finally|for|if|implements|import|in|int|is|late|new|null|on|return|static|String|super|switch|this|throw|true|try|var|void|while|with',
      'js' || 'javascript' || 'ts' || 'typescript' =>
        r'async|await|break|case|catch|class|const|continue|default|else|export|false|finally|for|from|function|if|import|in|let|new|null|return|switch|this|throw|true|try|typeof|var|while',
      'python' || 'py' =>
        r'and|as|async|await|break|class|continue|def|elif|else|except|False|finally|for|from|if|import|in|is|lambda|None|not|or|pass|return|True|try|while|with|yield',
      'json' => r'null|false|true',
      _ =>
        r'abstract|async|await|class|const|false|final|for|function|if|import|let|null|return|true|var|void|while',
    };
    final keywordPattern = RegExp('^(?:$keywords)\$');
    final tokenPattern = RegExp(
      "//[^\\n]*|#[^\\n]*|\"(?:\\\\.|[^\"])*\"|'(?:\\\\.|[^'])*'|\\b(?:$keywords)\\b|\\b\\d+(?:\\.\\d+)?\\b|\\b[A-Za-z_]\\w*(?=\\s*\\()|\\b[A-Z][A-Za-z0-9_]*\\b|[(){}\\[\\],.;:=+*/<>!-]+",
    );
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final match in tokenPattern.allMatches(code)) {
      if (match.start > offset) {
        spans.add(
          TextSpan(text: code.substring(offset, match.start), style: style),
        );
      }
      final token = match.group(0)!;
      final isFunction = RegExp(r'^\s*\(').hasMatch(code.substring(match.end));
      final tokenStyle = token.startsWith('//') || token.startsWith('#')
          ? style.copyWith(color: _codeComment)
          : token.startsWith('"') || token.startsWith("'")
          ? style.copyWith(color: _codeString)
          : RegExp(r'^\d').hasMatch(token)
          ? style.copyWith(color: _codeNumber)
          : keywordPattern.hasMatch(token)
          ? style.copyWith(color: _codeKeyword, fontWeight: FontWeight.w600)
          : RegExp(r'^[(){}\[\],.;:=+*/<>!-]+$').hasMatch(token)
          ? style.copyWith(color: _codePunctuation)
          : isFunction
          ? style.copyWith(color: _codeFunction, fontWeight: FontWeight.w600)
          : RegExp(r'^[A-Z]').hasMatch(token)
          ? style.copyWith(color: _codeType)
          : style.copyWith(color: _codeFunction, fontWeight: FontWeight.w600);
      spans.add(TextSpan(text: token, style: tokenStyle));
      offset = match.end;
    }
    if (offset < code.length) {
      spans.add(TextSpan(text: code.substring(offset), style: style));
    }
    return spans;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // Clear link ranges on each rebuild
    _linkRanges.clear();
    style ??= const TextStyle();
    return _parseMarkdown(text, style, context);
  }

  TextSpan _parseMarkdown(
    String displayText,
    TextStyle defaultStyle,
    BuildContext context,
  ) {
    final List<InlineSpan> spans = [];
    final colors = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    final codeSurface = light ? const Color(0xffe7e1ed) : _codeSurface;
    final codeText = light ? const Color(0xff211a2d) : _codeText;
    final inlineCodeSurface = light
        ? const Color(0xffd7cfe2)
        : Colors.grey.shade200.withValues(alpha: .5);

    // Calculate focused line range in SOURCE text coordinates
    // This is critical because _focusedLine is tracked in source coordinates,
    // and virtual newlines in displayText would cause offset mismatches
    (int start, int end)? focusedLineRangeSource;
    if (_focusedLine != null) {
      focusedLineRangeSource = _getLineRange(_focusedLine!, _sourceText);
    }

    // Pattern definitions
    final patterns = <_MarkdownPattern>[
      // Escaped Markdown markers render as literal text. Give these the
      // highest priority so a later inline matcher cannot consume them.
      _MarkdownPattern(
        RegExp(r'\\([\\`*_~\[\](){}#+.!-])'),
        (match) => const TextStyle(),
        type: _PatternType.escape,
        priority: 20,
      ),
      // Fenced code must be matched before inline code. While the cursor is
      // anywhere in the block, keep both fences visible so typing never jumps
      // between hidden syntax and rendered content.
      _MarkdownPattern(
        RegExp(
          r'(^[ \t]*(?:```|~~~)[^\n]*\n?)([\s\S]*?)(^[ \t]*(?:```|~~~)[ \t]*$)',
          multiLine: true,
        ),
        (match) => TextStyle(
          fontFamily: 'monospace',
          backgroundColor: codeSurface,
          color: codeText,
        ),
        type: _PatternType.fencedCode,
        priority: 10,
      ),
      // Headers: show # only on focused line
      _MarkdownPattern(RegExp(r'^(#{1,6}\s+)(.*)$', multiLine: true), (match) {
        final headingLevel = match.group(1)!.trim().length;
        final fontSizes = [28.0, 24.0, 20.0, 18.0, 16.0, 14.0];
        final fontSize = fontSizes[headingLevel.clamp(1, 6) - 1];
        return TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: fontSize,
          color: Colors.blueAccent,
        );
      }, type: _PatternType.header),
      // Blockquote: keep the marker while editing, render a quote rail otherwise.
      _MarkdownPattern(
        RegExp(r'^(>\s?)(.*(?:\n>\s?.*)*)', multiLine: true),
        (match) => const TextStyle(),
        type: _PatternType.blockquote,
      ),
      // GitHub-flavored task lists: - [ ] todo / - [x] done.
      _MarkdownPattern(
        RegExp(r'^([ \t]*)([*+-])([ \t]+)(\[[ xX]\])([ \t]+)', multiLine: true),
        (match) => const TextStyle(fontWeight: FontWeight.w500),
        type: _PatternType.taskList,
        priority: 5,
      ),
      // Unordered List
      _MarkdownPattern(
        RegExp(r'^([ \t]*)([*+-])([ \t]+)', multiLine: true),
        (match) => const TextStyle(fontWeight: FontWeight.w500),
        type: _PatternType.list,
      ),
      // Ordered List
      _MarkdownPattern(
        RegExp(r'^([ \t]*)(\d+\.)([ \t]+)', multiLine: true),
        (match) => const TextStyle(fontWeight: FontWeight.w500),
        type: _PatternType.list,
      ),
      // Bold **text**
      _MarkdownPattern(
        RegExp(r'(\*\*)(.+?)(\*\*)'),
        (match) => const TextStyle(fontWeight: FontWeight.bold),
        type: _PatternType.inline,
      ),
      // Bold __text__
      _MarkdownPattern(
        RegExp(r'(__)(.+?)(__)'),
        (match) => const TextStyle(fontWeight: FontWeight.bold),
        type: _PatternType.inline,
      ),
      // Italic *text*
      _MarkdownPattern(
        RegExp(r'(\*)(.+?)(\*)'),
        (match) => const TextStyle(fontStyle: FontStyle.italic),
        type: _PatternType.inline,
      ),
      // Italic _text_
      _MarkdownPattern(
        RegExp(r'(_)(.+?)(_)'),
        (match) => const TextStyle(fontStyle: FontStyle.italic),
        type: _PatternType.inline,
      ),
      // Strikethrough ~~text~~
      _MarkdownPattern(
        RegExp(r'(~~)(.+?)(~~)'),
        (match) => const TextStyle(decoration: TextDecoration.lineThrough),
        type: _PatternType.inline,
      ),
      // Inline code `text`
      _MarkdownPattern(
        RegExp(r'(?<!`)(`)(?!`)([^`\n]+)(`)(?!`)'),
        (match) => TextStyle(
          fontFamily: 'monospace',
          backgroundColor: inlineCodeSurface,
          color: colors.onSurface,
          fontWeight: FontWeight.w600,
        ),
        type: _PatternType.inline,
      ),
      // Links [text](url)
      _MarkdownPattern(
        RegExp(r'(\[)([^\]]+)(\]\()([^\)]+)(\))'),
        (match) => const TextStyle(
          color: Colors.blue,
          decoration: TextDecoration.underline,
        ),
        type: _PatternType.link,
      ),
      // Images ![alt text](url)
      _MarkdownPattern(
        _imagePattern,
        (match) => const TextStyle(),
        type: _PatternType.image,
      ),
      // Thematic break
      _MarkdownPattern(
        RegExp(
          r'^ {0,3}((\*[ \t]*){3,}|(-[ \t]*){3,}|(_[ \t]*){3,})$',
          multiLine: true,
        ),
        (match) => const TextStyle(color: Colors.grey),
        type: _PatternType.thematicBreak,
        priority: 1,
      ),
      // Virtual newline pattern (to hide markers)
      _MarkdownPattern(
        RegExp(r'\u200B'),
        (match) => TextStyle(fontSize: 0, color: Colors.transparent),
        type: _PatternType.virtualNewline,
        priority: 10,
      ),
    ];

    // Collect all matches
    List<_MatchRange> ranges = [];

    for (final pattern in patterns) {
      for (final match in pattern.exp.allMatches(displayText)) {
        // Convert display position to source position for accurate line comparison
        final matchStartSource = _displayToSourceOffset(
          match.start,
          displayText,
        );
        final matchEndSource = _displayToSourceOffset(match.end, displayText);
        final isOnFocusedLine =
            focusedLineRangeSource != null &&
            (pattern.type == _PatternType.blockquote ||
                    pattern.type == _PatternType.fencedCode
                ? matchStartSource < focusedLineRangeSource.$2 &&
                      matchEndSource >= focusedLineRangeSource.$1
                : matchStartSource >= focusedLineRangeSource.$1 &&
                      matchStartSource < focusedLineRangeSource.$2);

        final rangeStyle = pattern.styleBuilder(match);
        final List<InlineSpan> matchSpans = [];

        // TextStyle to start with (merging default + pattern style)
        final combinedStyle = defaultStyle.merge(rangeStyle);
        // Style for hidden syntax (zero size)
        final hiddenStyle = combinedStyle.copyWith(fontSize: 0.0);

        if (pattern.type == _PatternType.virtualNewline) {
          // Hide zero-width markers with zero-size text
          matchSpans.add(TextSpan(text: match.group(0), style: hiddenStyle));
        } else if (pattern.type == _PatternType.escape) {
          // Hide only the escape slash; leave the escaped punctuation visible.
          matchSpans.add(TextSpan(text: '\\', style: hiddenStyle));
          matchSpans.add(TextSpan(text: match.group(1), style: combinedStyle));
        } else if (pattern.type == _PatternType.fencedCode) {
          final openingFence = match.group(1)!;
          final content = match.group(2)!;
          final closingFence = match.group(3)!;
          final language =
              RegExp(
                r'(?:```|~~~)\s*([\w+-]+)',
              ).firstMatch(openingFence)?.group(1)?.toLowerCase() ??
              '';
          matchSpans.add(
            TextSpan(
              text: openingFence,
              style: isOnFocusedLine ? combinedStyle : hiddenStyle,
            ),
          );
          matchSpans.addAll(_buildCodeSpans(content, combinedStyle, language));
          matchSpans.add(
            TextSpan(
              text: closingFence,
              style: isOnFocusedLine ? combinedStyle : hiddenStyle,
            ),
          );
        } else if (pattern.type == _PatternType.blockquote) {
          // Group 1: marker, Group 2: quoted content.
          final marker = match.group(1)!;
          final rawContent = match.group(2)!;
          final renderedContent = rawContent.replaceAll(
            RegExp(r'\n>\s?'),
            '\n',
          );
          if (isOnFocusedLine) {
            matchSpans.add(TextSpan(text: marker, style: combinedStyle));
            matchSpans.add(TextSpan(text: rawContent, style: combinedStyle));
          } else {
            final quoteRail = defaultStyle.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            );
            matchSpans.add(TextSpan(text: '▌ ', style: quoteRail));
            matchSpans.add(
              TextSpan(
                text: renderedContent.replaceAll('\n', '\n▌ '),
                style: combinedStyle.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            );
          }
        } else if (pattern.type == _PatternType.header) {
          // Group 1: Syntax (e.g. "# "), Group 2: Content
          final syntax = match.group(1)!;
          final content = match.group(2)!;

          matchSpans.add(
            TextSpan(
              text: syntax,
              style: isOnFocusedLine ? combinedStyle : hiddenStyle,
            ),
          );
          matchSpans.add(TextSpan(text: content, style: combinedStyle));
        } else if (pattern.type == _PatternType.taskList) {
          final indent = match.group(1)!;
          final bullet = match.group(2)!;
          final spacing = match.group(3)!;
          final state = match.group(4)!;
          final trailingSpace = match.group(5)!;
          matchSpans.add(TextSpan(text: indent, style: defaultStyle));
          if (isOnFocusedLine) {
            matchSpans.add(
              TextSpan(
                text: '$bullet$spacing$state$trailingSpace',
                style: combinedStyle.copyWith(color: Colors.blueAccent),
              ),
            );
          } else {
            final checked = state.toLowerCase() == '[x]';
            final sourceMarker = '$bullet$spacing$state$trailingSpace';
            // `☑` falls back to Android's emoji font while `☐` does not,
            // making checked tasks visibly larger. `☒` is a monochrome text
            // glyph with the same metrics as the empty ballot box.
            final renderedMarker = checked ? '☒ ' : '☐ ';
            matchSpans.add(
              TextSpan(
                text: renderedMarker,
                style: combinedStyle.copyWith(
                  color: checked ? Colors.greenAccent : Colors.blueAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
            matchSpans.add(
              TextSpan(
                // Keep the rendered span exactly as long as the underlying
                // Markdown marker. The previous code emitted both the visual
                // checkbox and the full hidden marker, which shifted the rest
                // of the line and made the following space behave like a wrap.
                text: '\u200B' * (sourceMarker.length - renderedMarker.length),
                style: hiddenStyle,
              ),
            );
          }
        } else if (pattern.type == _PatternType.list) {
          // Group 1: Leading indent, Group 2: Bullet/Number, Group 3: Space
          final indent = match.group(1)!;
          final bulletOrNumber = match.group(2)!;
          final space = match.group(3)!;

          matchSpans.add(TextSpan(text: indent, style: defaultStyle));

          if (isOnFocusedLine) {
            matchSpans.add(
              TextSpan(
                text: bulletOrNumber + space,
                style: combinedStyle.copyWith(color: Colors.blueAccent),
              ),
            );
          } else {
            final replacement = RegExp(r'^\d+\.$').hasMatch(bulletOrNumber)
                ? bulletOrNumber
                : '•';
            matchSpans.add(
              TextSpan(
                text: replacement + space,
                style: combinedStyle.copyWith(fontWeight: FontWeight.bold),
              ),
            );
          }
        } else if (pattern.type == _PatternType.thematicBreak) {
          if (isOnFocusedLine) {
            matchSpans.add(
              TextSpan(
                text: match.group(0),
                style: combinedStyle.copyWith(color: Colors.grey),
              ),
            );
          } else {
            final lineLength = match.group(0)!.length;
            final lineChars = '─' * lineLength;
            matchSpans.add(
              TextSpan(
                text: lineChars,
                style: combinedStyle.copyWith(
                  color: Colors.grey,
                  letterSpacing: 0,
                ),
              ),
            );
          }
        } else if (pattern.type == _PatternType.link) {
          // Groups: 1=[, 2=text, 3=](, 4=url, 5=)
          final bracket = match.group(1)!;
          final linkText = match.group(2)!;
          final middle = match.group(3)!;
          final url = match.group(4)!;
          final closeParen = match.group(5)!;

          final linkStyle = combinedStyle;

          // Store the link range for offset-based tap detection
          final linkTextStart = match.start + bracket.length;
          final linkTextEnd = linkTextStart + linkText.length;
          _linkRanges.add((start: linkTextStart, end: linkTextEnd, url: url));

          if (isOnFocusedLine) {
            matchSpans.add(TextSpan(text: bracket, style: linkStyle));
            matchSpans.add(TextSpan(text: linkText, style: linkStyle));
            matchSpans.add(TextSpan(text: middle, style: linkStyle));
            matchSpans.add(
              TextSpan(
                text: url,
                style: linkStyle.copyWith(color: Colors.blue.shade300),
              ),
            );
            matchSpans.add(TextSpan(text: closeParen, style: linkStyle));
          } else {
            matchSpans.add(TextSpan(text: bracket, style: hiddenStyle));
            matchSpans.add(TextSpan(text: linkText, style: linkStyle));
            matchSpans.add(TextSpan(text: middle, style: hiddenStyle));
            matchSpans.add(TextSpan(text: url, style: hiddenStyle));
            matchSpans.add(TextSpan(text: closeParen, style: hiddenStyle));
          }
        } else if (pattern.type == _PatternType.image) {
          // Groups: 1=![, 2=alt text, 3=](, 4=url, 5=)
          final openingMarker = match.group(1)!;
          final altText = match.group(2)!;
          final bridge = match.group(3)!;
          final url = match.group(4)!;
          final closeParen = match.group(5)!;
          final int syntaxLength = match.group(0)!.length;

          if (isOnFocusedLine) {
            // On focused line: show full raw syntax for editing
            matchSpans.add(TextSpan(text: openingMarker, style: combinedStyle));
            matchSpans.add(TextSpan(text: altText, style: combinedStyle));
            matchSpans.add(TextSpan(text: bridge, style: combinedStyle));
            matchSpans.add(
              TextSpan(
                text: url,
                style: combinedStyle.copyWith(color: Colors.blue.shade300),
              ),
            );
            matchSpans.add(TextSpan(text: closeParen, style: combinedStyle));
          } else {
            // On unfocused line: hide all syntax and show image widget
            // The newlines for spacing are already in the text

            matchSpans.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: _buildImageWidget(url, altText, combinedStyle),
              ),
            );

            // Fill remaining character positions with zero-width spaces (hidden)
            // WidgetSpan occupies 1 position, so we need (syntaxLength - 1) more
            final int zwspCount = syntaxLength - 1;
            if (zwspCount > 0) {
              matchSpans.add(
                TextSpan(text: '\u200B' * zwspCount, style: hiddenStyle),
              );
            }
          }
        } else if (pattern.type == _PatternType.inline) {
          if (match.groupCount >= 3) {
            final prefix = match.group(1)!;
            final content = match.group(2)!;
            final suffix = match.group(3)!;

            matchSpans.add(
              TextSpan(
                text: prefix,
                style: isOnFocusedLine ? combinedStyle : hiddenStyle,
              ),
            );
            matchSpans.add(TextSpan(text: content, style: combinedStyle));
            matchSpans.add(
              TextSpan(
                text: suffix,
                style: isOnFocusedLine ? combinedStyle : hiddenStyle,
              ),
            );
          } else {
            matchSpans.add(
              TextSpan(text: match.group(0), style: combinedStyle),
            );
          }
        }

        ranges.add(
          _MatchRange(match.start, match.end, matchSpans, pattern.priority),
        );
      }
    }

    // Sort by start position, then by priority (higher first), then by length
    ranges.sort((a, b) {
      final startCompare = a.start.compareTo(b.start);
      if (startCompare != 0) return startCompare;
      final priorityCompare = b.priority.compareTo(a.priority);
      if (priorityCompare != 0) return priorityCompare;
      final lengthCompare = b.end.compareTo(a.end);
      return lengthCompare;
    });

    // Remove overlapping ranges (keep higher priority)
    List<_MatchRange> filteredRanges = [];
    int lastEnd = 0;
    for (final range in ranges) {
      if (range.start >= lastEnd) {
        filteredRanges.add(range);
        lastEnd = range.end;
      }
    }

    // Build final spans
    int textCursor = 0;

    for (final range in filteredRanges) {
      if (range.start > textCursor) {
        spans.add(
          TextSpan(
            text: displayText.substring(textCursor, range.start),
            style: defaultStyle,
          ),
        );
      }

      spans.addAll(range.spans);
      textCursor = range.end;
    }

    // Add remaining text
    if (textCursor < displayText.length) {
      spans.add(
        TextSpan(text: displayText.substring(textCursor), style: defaultStyle),
      );
    }

    return TextSpan(style: defaultStyle, children: spans);
  }
}

enum _PatternType {
  header,
  blockquote,
  taskList,
  list,
  inline,
  link,
  thematicBreak,
  image,
  virtualNewline,
  fencedCode,
  escape,
}

class _MarkdownPattern {
  final RegExp exp;
  final TextStyle Function(Match match) styleBuilder;
  final _PatternType type;
  final int priority;

  _MarkdownPattern(
    this.exp,
    this.styleBuilder, {
    this.type = _PatternType.inline,
    this.priority = 0,
  });
}

class _MatchRange {
  final int start;
  final int end;
  final List<InlineSpan> spans;
  final int priority;

  _MatchRange(this.start, this.end, this.spans, this.priority);
}
