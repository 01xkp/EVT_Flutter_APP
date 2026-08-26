import 'package:aipin/core/design_system/widgets/app_confirmation_sheet.dart';
import 'package:flutter/material.dart';

abstract final class ResearchUploadConfirmationSheet {
  static Future<bool> show(BuildContext context) {
    return AppConfirmationSheet.show(
      context,
      title: '使用 AI 转写和总结？',
      message: '将复制本机录音并上传至临时研究服务处理。原本机录音不会被移动或删除，请勿上传敏感内容。',
      cancelLabel: '暂不处理',
      confirmLabel: '开始处理',
    );
  }
}
