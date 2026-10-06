import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../theme/theme_style.dart';
import 'unified_media_import_dialog.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';

/// 统一的增强工具栏组件
///
/// 整合了两个原有工具栏的优点：
/// - 使用官方组件确保稳定性
/// - 保留自定义功能的完整性
/// - 优化大文件处理，防止OOM
/// - 统一媒体导入逻辑
class UnifiedQuillToolbar extends StatefulWidget {
  final quill.QuillController controller;
  final void Function(String filePath)? onMediaImported;

  const UnifiedQuillToolbar({
    super.key,
    required this.controller,
    this.onMediaImported,
  });

  @override
  State<UnifiedQuillToolbar> createState() => _UnifiedQuillToolbarState();
}

class _UnifiedQuillToolbarState extends State<UnifiedQuillToolbar> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 定制版：按设置里自定义的分组顺序渲染工具栏
    late final List<String> order;
    try {
      order = context.read<SettingsService>().editorToolbarGroupOrder;
    } catch (_) {
      order = SettingsService.defaultToolbarOrder;
    }

    final List<Widget> children = <Widget>[];
    for (final String id in order) {
      final List<Widget> group = _groupById(id);
      if (group.isEmpty) continue;
      if (children.isNotEmpty) children.add(_buildDivider());
      children.addAll(group);
    }

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: children),
      ),
    );
  }

  /// 组 id → 该组的按钮列表
  List<Widget> _groupById(String id) {
    switch (id) {
      case 'history':
        return _buildHistoryGroup();
      case 'basic':
        return _buildBasicFormatGroup();
      case 'header':
        return _buildHeaderGroup();
      case 'font':
        return _buildFontGroup();
      case 'color':
        return _buildColorGroup();
      case 'alignment':
        return _buildAlignmentGroup();
      case 'list':
        return _buildListGroup();
      case 'quote':
        return _buildQuoteAndCodeGroup();
      case 'link':
        return _buildLinkGroup();
      case 'media':
        return _buildMediaGroup(context);
      case 'misc':
        return _buildMiscGroup();
      default:
        return const <Widget>[];
    }
  }

  List<Widget> _buildHistoryGroup() {
    return [
      quill.QuillToolbarHistoryButton(
        controller: widget.controller,
        isUndo: true,
        options: const quill.QuillToolbarHistoryButtonOptions(),
      ),
      quill.QuillToolbarHistoryButton(
        controller: widget.controller,
        isUndo: false,
        options: const quill.QuillToolbarHistoryButtonOptions(),
      ),
    ];
  }

  List<Widget> _buildBasicFormatGroup() {
    return [
      quill.QuillToolbarToggleStyleButton(
        controller: widget.controller,
        attribute: quill.Attribute.bold,
        options: const quill.QuillToolbarToggleStyleButtonOptions(),
      ),
      quill.QuillToolbarToggleStyleButton(
        controller: widget.controller,
        attribute: quill.Attribute.italic,
        options: const quill.QuillToolbarToggleStyleButtonOptions(),
      ),
      quill.QuillToolbarToggleStyleButton(
        controller: widget.controller,
        attribute: quill.Attribute.underline,
        options: const quill.QuillToolbarToggleStyleButtonOptions(),
      ),
      quill.QuillToolbarToggleStyleButton(
        controller: widget.controller,
        attribute: quill.Attribute.strikeThrough,
        options: const quill.QuillToolbarToggleStyleButtonOptions(),
      ),
    ];
  }

  List<Widget> _buildHeaderGroup() {
    return [
      quill.QuillToolbarSelectHeaderStyleDropdownButton(
        controller: widget.controller,
        options:
            const quill.QuillToolbarSelectHeaderStyleDropdownButtonOptions(),
      ),
    ];
  }

  List<Widget> _buildFontGroup() {
    return [
      quill.QuillToolbarFontSizeButton(
        controller: widget.controller,
        options: const quill.QuillToolbarFontSizeButtonOptions(),
      ),
      quill.QuillToolbarFontFamilyButton(
        controller: widget.controller,
        options: const quill.QuillToolbarFontFamilyButtonOptions(),
      ),
    ];
  }

  List<Widget> _buildColorGroup() {
    return [
      quill.QuillToolbarColorButton(
        controller: widget.controller,
        isBackground: false,
        options: const quill.QuillToolbarColorButtonOptions(),
      ),
      quill.QuillToolbarColorButton(
        controller: widget.controller,
        isBackground: true,
        options: const quill.QuillToolbarColorButtonOptions(),
      ),
    ];
  }

  List<Widget> _buildAlignmentGroup() {
    return [
      quill.QuillToolbarSelectAlignmentButton(controller: widget.controller),
    ];
  }

  List<Widget> _buildListGroup() {
    return [
      quill.QuillToolbarToggleStyleButton(
        controller: widget.controller,
        attribute: quill.Attribute.ol,
        options: const quill.QuillToolbarToggleStyleButtonOptions(),
      ),
      quill.QuillToolbarToggleStyleButton(
        controller: widget.controller,
        attribute: quill.Attribute.ul,
        options: const quill.QuillToolbarToggleStyleButtonOptions(),
      ),
      quill.QuillToolbarIndentButton(
        controller: widget.controller,
        isIncrease: false,
        options: const quill.QuillToolbarIndentButtonOptions(),
      ),
      quill.QuillToolbarIndentButton(
        controller: widget.controller,
        isIncrease: true,
        options: const quill.QuillToolbarIndentButtonOptions(),
      ),
    ];
  }

  List<Widget> _buildQuoteAndCodeGroup() {
    return [
      quill.QuillToolbarToggleStyleButton(
        controller: widget.controller,
        attribute: quill.Attribute.blockQuote,
        options: const quill.QuillToolbarToggleStyleButtonOptions(),
      ),
      quill.QuillToolbarToggleStyleButton(
        controller: widget.controller,
        attribute: quill.Attribute.codeBlock,
        options: const quill.QuillToolbarToggleStyleButtonOptions(),
      ),
    ];
  }

  List<Widget> _buildLinkGroup() {
    return [
      quill.QuillToolbarLinkStyleButton(
        controller: widget.controller,
        options: const quill.QuillToolbarLinkStyleButtonOptions(),
      ),
    ];
  }

  List<Widget> _buildMediaGroup(BuildContext context) {
    return [
      _buildMediaButton(
        icon: Icons.image,
        tooltip: AppLocalizations.of(context).insertImage,
        onPressed: () => _showUnifiedMediaDialog('image'),
      ),
      _buildMediaButton(
        icon: Icons.videocam,
        tooltip: AppLocalizations.of(context).insertVideo,
        onPressed: () => _showUnifiedMediaDialog('video'),
      ),
      _buildMediaButton(
        icon: Icons.audiotrack,
        tooltip: AppLocalizations.of(context).insertAudio,
        onPressed: () => _showUnifiedMediaDialog('audio'),
      ),
    ];
  }

  List<Widget> _buildMiscGroup() {
    return [
      quill.QuillToolbarClearFormatButton(
        controller: widget.controller,
        options: const quill.QuillToolbarClearFormatButtonOptions(),
      ),
      quill.QuillToolbarSearchButton(
        controller: widget.controller,
        options: const quill.QuillToolbarSearchButtonOptions(),
      ),
    ];
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Theme.of(
        context,
      ).colorScheme.outlineVariant.withValues(alpha: 0.5),
    );
  }

  Widget _buildMediaButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);
    final buttonRadius = AppShapeTokens.of(context).buttonRadius;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          label: tooltip,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(buttonRadius),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(buttonRadius),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(buttonRadius),
                ),
                child: Icon(icon, size: 18, color: theme.colorScheme.onSurface),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 显示统一的媒体导入对话框
  void _showUnifiedMediaDialog(String mediaType) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => UnifiedMediaImportDialog(
        mediaType: mediaType,
        onMediaImported: (String filePath) {
          _insertMediaIntoEditor(filePath, mediaType);
          // 将导入的媒体回传给上层（如编辑页）以便会话级追踪
          widget.onMediaImported?.call(filePath);
        },
      ),
    );
  }

  /// 将媒体文件插入到编辑器中
  void _insertMediaIntoEditor(String filePath, String mediaType) {
    try {
      final index = widget.controller.selection.baseOffset;
      final length = widget.controller.selection.extentOffset - index;

      // 根据媒体类型创建不同的嵌入块
      switch (mediaType) {
        case 'image':
          widget.controller.replaceText(
            index,
            length,
            quill.BlockEmbed.image(filePath),
            null,
          );
          break;
        case 'video':
          widget.controller.replaceText(
            index,
            length,
            quill.BlockEmbed.video(filePath),
            null,
          );
          break;
        case 'audio':
          // 创建自定义音频嵌入块
          final audioEmbed = quill.CustomBlockEmbed('audio', filePath);
          widget.controller.replaceText(index, length, audioEmbed, null);
          break;
      }

      // 移动光标到插入内容之后
      widget.controller.updateSelection(
        TextSelection.collapsed(offset: index + 1),
        quill.ChangeSource.local,
      );
    } catch (e) {
      debugPrint('插入媒体文件失败: $e');
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.insertMediaFailed(
                _getMediaTypeName(context, mediaType),
                e.toString(),
              ),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  String _getMediaTypeName(BuildContext context, String type) {
    final l10n = AppLocalizations.of(context);
    switch (type) {
      case 'image':
        return l10n.mediaTypeImage;
      case 'video':
        return l10n.mediaTypeVideo;
      case 'audio':
        return l10n.mediaTypeAudio;
      default:
        return l10n.mediaTypeMedia;
    }
  }
}

/// 兼容性别名，保持向后兼容
class FullScreenToolbar extends UnifiedQuillToolbar {
  const FullScreenToolbar({super.key, required super.controller});
}
