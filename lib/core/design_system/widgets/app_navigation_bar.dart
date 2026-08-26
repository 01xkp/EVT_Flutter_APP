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
    return NavigationBar(
      selectedIndex: selected.index,
      onDestinationSelected: (index) =>
          onSelected(AppDestination.values[index]),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: '首页',
        ),
        NavigationDestination(
          icon: Icon(Icons.mic_none_outlined),
          selectedIcon: Icon(Icons.mic),
          label: '录音',
        ),
        NavigationDestination(
          icon: Icon(Icons.folder_open_outlined),
          selectedIcon: Icon(Icons.folder_open),
          label: '记录',
        ),
      ],
    );
  }
}
