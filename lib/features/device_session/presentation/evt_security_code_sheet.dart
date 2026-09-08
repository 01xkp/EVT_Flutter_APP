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
    final bytes = _controller.text.codeUnits;
    return bytes.length == 6 && bytes.every((byte) => byte <= 0xFF);
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
            const SizedBox(height: 20),
            TextField(
              controller: _controller,
              autofocus: true,
              obscureText: _obscureCode,
              enableSuggestions: false,
              autocorrect: false,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.done,
              maxLength: 6,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: '6 字节认证码',
                hintText: '请输入 6 个字符',
                counterText: '',
                errorText: _controller.text.isEmpty || _isComplete
                    ? null
                    : '认证码必须恰好是 6 个原始字节',
                suffixIcon: IconButton(
                  tooltip: _obscureCode ? '显示认证码' : '隐藏认证码',
                  icon: Icon(
                    _obscureCode
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _obscureCode = !_obscureCode),
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
    Navigator.of(context).pop(_controller.text);
  }
}
