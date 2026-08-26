import 'package:aipin/core/design_system/widgets/app_confirmation_sheet.dart';
import 'package:flutter/material.dart';

abstract final class ResearchConsentSheet {
  static Future<bool> show(BuildContext context) {
    return AppConfirmationSheet.show(
      context,
      title: 'AI 语音研究说明',
      message:
          '这是封闭研究 Beta。所有输入均标记为 research_import，并会发送到临时、公开且未鉴权的服务处理。请勿录制敏感内容。本机录音只有在你确认上传后才会复制到研究空间。',
      confirmLabel: '同意并继续',
      cancelLabel: '暂不使用',
    );
  }
}
