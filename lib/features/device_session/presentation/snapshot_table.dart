import 'package:evt_ble_app/features/device_session/domain/device_snapshot.dart';
import 'package:flutter/material.dart';

class SnapshotTable extends StatelessWidget {
  const SnapshotTable({super.key, this.snapshot});

  final DeviceSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('状态', snapshot == null ? '不可验证' : _stateLabel(snapshot!.state)),
      ('电量', snapshot?.batteryPercent == null ? '不可验证' : '${snapshot!.batteryPercent}%'),
      ('充电', snapshot?.isCharging == null ? '不可验证' : (snapshot!.isCharging! ? '充电中' : '未充电')),
      (
        '待机功耗',
        snapshot?.standbyPowerMilliwatts == null
            ? '不可验证'
            : '${snapshot!.standbyPowerMilliwatts} mW',
      ),
    ];
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(child: Text(row.$1, style: Theme.of(context).textTheme.bodyMedium)),
                SizedBox(
                  width: 132,
                  child: Text(
                    row.$2,
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static String _stateLabel(DeviceState state) => switch (state) {
        DeviceState.factoryMode => '产测',
        DeviceState.ship => '运输',
        DeviceState.unbound => '未绑定',
        DeviceState.standby => '待机',
        DeviceState.recording => '录音中',
        DeviceState.privacy => '隐私',
        DeviceState.ota => '升级中',
        DeviceState.safeOff => '安全关机',
        DeviceState.charging => '充电中',
        DeviceState.unknown => '未知',
      };
}
