import 'package:aipin/core/design_system/widgets/app_button.dart';
import 'package:flutter/material.dart';

class EvtSecurityCodeSheet extends StatefulWidget {
  const EvtSecurityCodeSheet({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
  });

  final String title;
  final String message;
  final String confirmLabel;

  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => EvtSecurityCodeSheet(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
      ),
    );
  }

  @override
  State<EvtSecurityCodeSheet> createState() => _EvtSecurityCodeSheetState();
}

class _EvtSecurityCodeSheetState extends State<EvtSecurityCodeSheet> {
  final _controller = TextEditingController();
  var _obscureCode = true;

  bool get _isComplete {
    final value = _controller.text;
    return (value.length == 6 && RegExp(r'^[\x21-\x7E]{6}$').hasMatch(value)) ||
        (value.length == 12 && RegExp(r'^[0-9A-Fa-f]{12}$').hasMatch(value));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(widget.message),
            const SizedBox(height: 8),
            const Text(
              '调试可输入 6 位数字、英文字母或符号（区分大小写，不含空格），例如 123456；也支持 12 位十六进制安全码。',
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _controller,
              autofocus: true,
              obscureText: _obscureCode,
              enableSuggestions: false,
              autocorrect: false,
              textCapitalization: TextCapitalization.none,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.done,
              maxLength: 12,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: '安全码（6 位文本 / 12 位十六进制）',
                hintText: '例如 123456 或 7A31C85E92B4',
                counterText: '',
                errorText: _controller.text.isEmpty || _isComplete
                    ? null
                    : '请输入 6 位数字、英文或符号，或 12 位十六进制字符',
                suffixIcon: SizedBox(
                  width: 64,
                  height: 48,
                  child: TextButton(
                    onPressed: () =>
                        setState(() => _obscureCode = !_obscureCode),
                    child: Text(_obscureCode ? '显示' : '隐藏'),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AppButton.secondary(
                    label: '取消',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton.primary(
                    label: widget.confirmLabel,
                    onPressed: _isComplete ? _submit : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    if (!_isComplete) {
      return;
    }
    // Preserve case for six ASCII characters: each character is one raw byte.
    // Only the twelve-character hex representation can be case-normalized.
    final value = _controller.text;
    Navigator.of(context).pop(value.length == 12 ? value.toUpperCase() : value);
  }
}
