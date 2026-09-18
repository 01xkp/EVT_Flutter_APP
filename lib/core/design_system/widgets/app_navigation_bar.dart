import 'package:aipin/app/app_destination.dart';
import 'package:flutter/material.dart';

class AppNavigationBar extends StatelessWidget {
  const AppNavigationBar({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final AppDestination selected;
  final ValueChanged<AppDestination> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              for (final destination in AppDestination.values)
                Expanded(
                  child: Semantics(
                    selected: selected == destination,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        foregroundColor: selected == destination
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.secondary,
                        backgroundColor: selected == destination
                            ? colorScheme.primaryContainer
                            : null,
                      ),
                      onPressed: () => onSelected(destination),
                      child: Text(
                        destination == AppDestination.home ? '首页' : '检查记录',
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
