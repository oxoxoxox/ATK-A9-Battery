# ATK A9 Ultra Max三模 电量

让 macOS 电池小组件和 [AirBattery](https://github.com/lihaoyun6/AirBattery) 显示 ATK A9 Ultra Max三模 的 2.4G 模式电量。

程序直接读取接收器的私有 HID 电量报告，每 10 秒更新一次电量和充电状态。菜单栏显示的内容可以在“设置”中选择：只显示鼠标图标；只显示电量数值和闪电；鼠标图标加电量数值和闪电（默认）；鼠标图标加电量数值。点击图标弹出悬浮面板，查看电量环、连接状态、输入监控授权、开机启动和 AirBattery 同步状态，并可打开设置、立即刷新、打开日志文件夹、查看关于页面或退出；右键图标则打开系统风格的快捷菜单。它不会修改 AirBattery，也不会写入 AirBattery 的容器目录。

![macOS 电池小组件显示 ATK A9 Ultra Max三模 电量](assets/macos-battery-widgets.png)

## 下载与启动

1. 从 Releases 下载 `MouseBatteryBridge-<版本号>.dmg`（或 `MouseBatteryBridge.app.zip`），打开后把应用拖到“应用程序”。自行打包 DMG 见下文“从源码构建”。
2. 本项目没有 Apple Developer ID 签名和公证。若 macOS 提示应用已损坏或无法验证开发者，只移除本应用的下载隔离属性：

   ```bash
   sudo xattr -dr com.apple.quarantine /Applications/MouseBatteryBridge.app
   ```

3. 启动应用，点击菜单栏鼠标图标打开面板，在“输入监控”一行点击“去授权”（右键菜单中也有“输入监控授权…”），再到“系统设置 → 隐私与安全性 → 输入监控”允许“MouseBatteryBridge for ATK A9 Ultra Max三模”。授权后重新启动应用。

不要使用 `spctl --master-disable` 全局关闭 Gatekeeper。

## AirBattery Nearcast

AirBattery 不是必需的；macOS 电池小组件可由本程序独立更新。需要同步到 AirBattery 时：

1. 在 AirBattery 设置中开启 Nearcast。
2. 在终端运行一次下面的命令，把 AirBattery 的 Nearcast 群组 ID 写入本程序自己的偏好设置（Bundle ID 以 `Info.plist` 的 `CFBundleIdentifier` = `local.atka9.MouseBatteryBridge` 为准）：

   ```bash
   defaults write local.atka9.MouseBatteryBridge nearcastGroupID \
     "$(defaults read com.lihaoyun6.AirBattery ncGroupID)"
   ```

3. 重新启动 `MouseBatteryBridge.app`，并在 macOS 询问时允许其访问本地网络。

群组 ID 不会写入应用包或上传到网络。AirBattery 重置群组 ID、重新安装或换 Mac 后，需要重新执行上述命令。

## 注意事项

- 仅适配 ATK A9 Ultra Max三模 的 2.4G 接收器 `VID 0x373B / PID 0x11FE`，不适用于蓝牙模式或其他型号。
- 鼠标必须已与接收器配对；网页驱动运行时可能占用 HID 接口，测试前请关闭相关页面。
- 应用需要“输入监控”权限读取 HID 报告；Nearcast 还需要“本地网络”权限。
- 应用启动时立即查询一次，5 秒后若仍无读数再查一次，之后每 10 秒查询。读取失败时保留上一次有效电量，不会发布假 `0%`。
- 应用退出后，macOS 电源项会消失；AirBattery 会收到离线状态，但其界面或小组件可能要等下一次时间线刷新才消失。
- 系统电池小组件的刷新由 macOS 调度，显示可能比真实电量晚一个刷新周期。
- 系统电源项使用 macOS 的非公开 IOKit 接口，未来系统版本可能改变行为。
- 仅支持 Apple Silicon（arm64），不支持 Intel Mac。

## 从源码构建

需要 macOS 13 或更高版本及 Xcode Command Line Tools：

```bash
./build.sh
open dist/MouseBatteryBridge.app
```

需要安装包时运行 `./dmg.sh`，它会先执行 `build.sh`，再生成 `dist/MouseBatteryBridge-<版本号>.dmg`（版本号取自 `Info.plist`，内含应用和“应用程序”快捷方式）。

无硬件的协议断言可用 `./test.sh` 单独运行（编译 codec、电量服务与面板状态模型，不编译 UI 窗口和系统发布器）。

构建脚本默认使用 ad-hoc 签名，不需要开发者证书。产物位于 `dist/MouseBatteryBridge.app`。如果本机有开发证书，建议用稳定身份构建，避免每次重新编译后都要重新授予输入监控权限：

```bash
CODE_SIGN_IDENTITY="Apple Development: 你的证书名称" ./build.sh
CODE_SIGN_IDENTITY="Apple Development: 你的证书名称" ./dmg.sh
```

## 代码结构

```
Sources/
  Battery/    # 电量值对象、设备身份、Provider 协议、轮询服务
  HID/        # VID/PID/Usage 匹配、IOKit 打开/发送/等待
  Devices/    # 每只鼠标一个 Provider（ATK A9 用 CompxCodec 解析私有协议）
  Publishers/ # 系统电源项（IOPS）与 AirBattery Nearcast
  Settings/   # 菜单栏显示模式与 UserDefaults 持久化
  UI/         # 菜单栏图标与百分比、悬浮面板（SwiftUI）、设置与关于窗口、状态模型
  App/        # 生命周期、定时器（后台查询）、权限与开机启动动作、接线
Tests/        # 无硬件的 CompxCodec 断言
```

## 适配其他鼠标

加一只同类鼠标只需新增 Provider，不必改菜单栏、电源项和 Nearcast：

1. 新建 `Sources/Devices/<Vendor>/<Name>Provider.swift`，实现 `BatteryProvider`。
2. 若协议是 Compx 同类（Output `0x08` + 16 字节 command），复用 `CompxCodec`，只换 `HIDMatch` 和 `DeviceIdentity`。
3. 若只是字节布局不同但仍是 Output + Input Report，新建 `*Codec.swift`，继续用 `HIDSession`。
4. 若改为 Feature Report / 广播 / BLE，不要改 `HIDSession`，在 Provider 内自己取电。
5. 在 `DeviceCatalog.makeProviders()` 追加实例。数组顺序 = 匹配优先级；同一时间只服务第一只匹配成功的鼠标。
6. `./test.sh`（有 codec 测试时）和 `./build.sh`。

最小骨架：

```swift
final class OtherMouseProvider: BatteryProvider {
    let identity = DeviceIdentity(
        displayName: "...",
        appName: "MouseBatteryBridge",
        accessoryIdentifier: "...",
        deviceType: "Mouse",
        receiverVendorID: 0x0000,
        accessoryProductID: 0x0000
    )
    let queryInterval: TimeInterval = 10
    let timeout: TimeInterval = 3

    func readBattery() throws -> BatteryReading {
        try HIDSession.withDevice(match, displayName: identity.displayName) { connection in
            try connection.sendOutput(reportID: ..., bytes: ...)
            return try connection.awaitInput(timeout: timeout) { reportID, bytes in
                // parse → BatteryReading?
                nil
            }
        }
    }
}
```

然后：`DeviceCatalog.makeProviders() -> [ATKA9Provider(), OtherMouseProvider()]`。

### 从网页驱动快速抓 HID 报文

HAR 不会记录 WebHID 的 USB 收发内容，只会保存网页、接口请求和 JavaScript 文件。HAR 适合搜索协议实现；要拿到真实报文，最快的方法是在 Chrome/Edge 的网页驱动页面打开开发者工具，在 Console 运行下面的拦截代码，然后点击网页里的“连接”或“刷新设备”：

```javascript
const toBytes = data => data instanceof ArrayBuffer
  ? new Uint8Array(data)
  : new Uint8Array(data.buffer, data.byteOffset, data.byteLength);

const hex = data => [...toBytes(data)]
  .map(value => value.toString(16).padStart(2, "0"))
  .join(" ");

const originalSendReport = HIDDevice.prototype.sendReport;
HIDDevice.prototype.sendReport = function (reportId, data) {
  console.log("HID OUT", this.productName, `reportId=0x${reportId.toString(16)}`, hex(data));
  return originalSendReport.call(this, reportId, data);
};

const originalSendFeature = HIDDevice.prototype.sendFeatureReport;
HIDDevice.prototype.sendFeatureReport = function (reportId, data) {
  console.log("HID FEATURE OUT", this.productName, `reportId=0x${reportId.toString(16)}`, hex(data));
  return originalSendFeature.call(this, reportId, data);
};

const originalReceiveFeature = HIDDevice.prototype.receiveFeatureReport;
HIDDevice.prototype.receiveFeatureReport = async function (reportId) {
  const data = await originalReceiveFeature.call(this, reportId);
  console.log("HID FEATURE IN", this.productName, `reportId=0x${reportId.toString(16)}`, hex(data));
  return data;
};

for (const device of await navigator.hid.getDevices()) {
  console.log("HID DEVICE", {
    productName: device.productName,
    vendorId: `0x${device.vendorId.toString(16)}`,
    productId: `0x${device.productId.toString(16)}`,
    collections: device.collections
  });

  device.addEventListener("inputreport", event => {
    console.log(
      "HID IN",
      device.productName,
      `reportId=0x${event.reportId.toString(16)}`,
      hex(event.data)
    );
  });
}
```

先在网页中授权一次设备，再执行代码。如果网页在执行拦截代码之前已经缓存了 `sendReport` 函数，可在 DevTools 的 Sources 中搜索这些关键词并打断点：

```text
navigator.hid
requestDevice
sendReport
sendFeatureReport
receiveFeatureReport
inputreport
battery
charge
power
isCharging
```

每次操作至少记录以下内容：

- 接收器的 VID/PID、产品名。
- `device.collections` 中的 Usage Page、Usage。
- Output/Feature Report ID、Payload 长度和完整查询字节。
- Input Report ID、Payload 长度和完整响应字节。
- 网页解析电量和充电状态的代码。

WebHID 的 `event.reportId` 是单独参数，`event.data` 通常不包含 Report ID；IOKit 某些设备会把 Report ID 同时放在缓冲区第 0 字节。`CompxCodec.parseBattery` 兼容这两种输入布局。

### 快速找到电量字节和充电位

不要只抓一份回包。保持电量基本不变，分别采集“未插线”和“正在充电”的响应；再采集两个不同电量百分比的响应。把已经去掉 Report ID 的十六进制 Payload 粘贴到下面的脚本：

```python
before = bytes.fromhex("06 00 ...")
after  = bytes.fromhex("06 00 ...")

if len(before) != len(after):
    raise SystemExit(f"长度不同：{len(before)} != {len(after)}")

for offset, (old, new) in enumerate(zip(before, after)):
    if old != new:
        print(
            f"byte[{offset}] 0x{old:02X} -> 0x{new:02X} "
            f"xor=0x{old ^ new:02X}"
        )
```

判断方法：

- 插线前后只有某一位稳定翻转，这一位通常是充电状态。比如 XOR 为 `0x80`，说明最高位可能是充电位。
- 随电量变化而变化、数值接近 `0–100` 的低位通常是电量。
- 每次查询都变化的字段可能是序号、时间或校验值，不要直接当成电量。
- 最后一个变化字节经常是校验和。先在网页脚本里搜索求和、XOR、CRC 等计算。
- 至少重复三轮插线/拔线，避免把配置档位、回报率变化误认为充电状态。

（历史模板）京东京造 JZM5 的结果是：

```text
payload[19] & 0x7F       = 电量百分比
(payload[19] & 0x80) != 0 = 正在充电
```

也就是同一个字节的低 7 位保存电量，最高位保存充电状态。ATK A9 的对应布局见 `CompxCodec.parseBattery`：`payload[5]` 电量、`payload[6]` 充电标志。

### 确认 macOS 的 HID 接口

网页看到的 Collection 不一定等于 macOS 枚举出的主 Usage。先用十进制 VID/PID 查看候选接口（例：历史模板 JZM5 `VID 0x362D / PID 0xD107`）：

```bash
hidutil list --matching '{"VendorID":13869,"ProductID":53511}'
```

十六进制转十进制可用：

```bash
printf '%d\n' 0x373B
printf '%d\n' 0x11FE
```

把枚举出的 `PrimaryUsagePage` 和 `PrimaryUsage` 写入 `HIDMatch`。如果存在多个接口，优先测试厂商自定义 Usage Page，不要向普通鼠标移动或键盘输入接口发送私有命令。

### 填入适配区并验证

1. 新建 `Sources/Devices/<Vendor>/<Name>Provider.swift`，填入 VID/PID、Usage、Report ID 与 `DeviceIdentity`。
2. 在 codec 的组包函数中复刻网页发送的完整报告。注意 IOKit 对部分设备要求缓冲区第 0 字节包含 Report ID。
3. 在解析函数中先验证响应类型和命令字，再解析电量及充电位。
4. 关闭网页驱动，避免浏览器同时占用接口。
5. 执行 `./build.sh`，运行 `dist/MouseBatteryBridge.app`。
6. 分别测试未充电、充电中和电量变化，确认系统组件与 AirBattery 一致。

如果新设备使用 Feature Report、加密会话、动态校验或主动广播而不是“Output + Interrupt-IN”，需要在 Provider 内自己实现取电；这些行为无法只靠更换字节偏移完成。

## 工作原理

ATK A9：程序在接收器的 `Usage Page 0xFF05 / Usage 0x00` 接口发送 Output Report `0x08`（16 字节命令，首字节为命令 ID，末字节校验和 = `85 - sum & 255`），从 Input Report `0x08` 的 `payload[5]`/`payload[6]` 解析电量和充电状态。随后将结果发布为 macOS Accessory Power Source，并可选通过 AirBattery Nearcast 在本机同步。

## Contributors

- LANMIN-X
- OpenAI Codex：协助协议分析、macOS 桥接实现与文档整理

## 许可证

本项目采用 [MIT License](LICENSE)。
