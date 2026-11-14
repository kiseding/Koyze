import 'package:flutter/material.dart';

/// 弹层里滚动区统一使用的物理：不分平台，一律不给橡皮筋。
///
/// 弹层本身已经跟着手指走了，如果里面的列表再用 iOS 的
/// [BouncingScrollPhysics]，同一段手指位移会被消费两次：内容先被拉长一段，
/// 松手时再用弹簧模拟缩回去。两段运动叠在一起，读起来就是「弹簧」。
///
/// 换成 [ClampingScrollPhysics] 后内容不再拉伸，到顶后多余的下拉以
/// `OverscrollNotification` 的形式冒出来，由弹层的拖拽逻辑转成面板位移，
/// 松手直接收尾，没有回弹段。弹层内容本身不需要「拉不到还弹一下」的反馈。
class SheetScrollBehavior extends MaterialScrollBehavior {
  const SheetScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();
}
