import 'package:aipin/core/design_system/widgets/app_confirmation_sheet.dart';
import 'package:flutter/material.dart';

abstract final class AppDialog {
  static Future<bool> confirmDestructive(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    return AppConfirmationSheet.show(
      context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      variant: AppConfirmationVariant.destructive,
    );
  }
}
