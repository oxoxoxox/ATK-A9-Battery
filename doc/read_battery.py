#!/usr/bin/env python3
"""
读取 Compx 8K 无线鼠标 (VID 0x373b / PID 0x11fe) 的电量。

协议分析（来自 https://hub.atk.pro/ 网页驱动逆向）：
- Output Report ID = 0x08
- 命令包 16 字节，[0] = commandId
- GetBatteryLevel 命令的 commandId = 4 (MZt.GetBatteryLevel)
- 响应通过 Input Report 返回，[0] = commandId (匹配请求)
- 电量解析: batteryLevel = raw[5] (baseOffset=5)
- 充电状态: batteryCharge = raw[6] (baseOffset+1)
- 电压: batteryVoltage = raw.getUint16(7) (baseOffset+2)

Usage:
  source .venv/bin/activate
  DYLD_LIBRARY_PATH=/opt/homebrew/lib python3 read_battery.py
"""

import hid
import time
import sys

VID = 0x373B
PID = 0x11FE
OUTPUT_REPORT_ID = 0x08
CMD_GET_BATTERY_LEVEL = 4  # MZt.GetBatteryLevel
REPORT_SIZE = 16  # wZt.SIZE = 16
BASE_OFFSET = 5   # wZt.baseOffset = 5


def hexs(data):
    return " ".join(f"{b:02x}" for b in data)


def find_vendor_interface():
    """找到厂商自定义 Usage Page 0xFF05 的接口"""
    devices = hid.enumerate(VID, PID)
    for d in devices:
        if d["usage_page"] == 0xFF05:
            return d
    # 如果找不到 0xFF05，找任意厂商自定义接口
    for d in devices:
        if d["usage_page"] >= 0xFF00:
            return d
    return None


def read_battery():
    iface = find_vendor_interface()
    if not iface:
        print("未找到 Compx 鼠标的厂商自定义 HID 接口！")
        print("请确认鼠标接收器已插入且处于 2.4G 模式。")
        return None

    print(f"使用接口: UsagePage=0x{iface['usage_page']:04X} Usage=0x{iface['usage']:04X}")

    try:
        dev = hid.Device(path=iface["path"])
    except Exception as e:
        print(f"打开设备失败: {e}")
        print("提示: 请关闭网页驱动 (https://hub.atk.pro/) 后重试，浏览器可能占用了 HID 接口。")
        return None

    print(f"设备已打开: {dev.manufacturer} / {dev.product}")
    dev.nonblocking = True  # 设置非阻塞模式

    try:
        # 先发送初始化命令（网页驱动在连接时发送的命令）
        # commandId=16 (GetMouseCIDMID), payload 最后字节是校验和
        init_cmds = [
            bytearray([0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                       0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3d]),
            bytearray([0x12, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                       0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3b]),
        ]
        for cmd in init_cmds:
            buf = bytes([OUTPUT_REPORT_ID]) + bytes(cmd)
            print(f"发送初始化命令: rid=0x{OUTPUT_REPORT_ID:02X} data={hexs(cmd)}")
            dev.write(buf)
            time.sleep(0.1)

        # 构造电量查询命令
        # 16 字节，[0] = commandId = 4 (GetBatteryLevel)
        cmd = bytearray(REPORT_SIZE)
        cmd[0] = CMD_GET_BATTERY_LEVEL
        # 其余字节为 0

        # hidapi 要求 report_id 作为第一字节（如果 report_id != 0）
        buf = bytes([OUTPUT_REPORT_ID]) + bytes(cmd)
        print(f"发送查询命令: rid=0x{OUTPUT_REPORT_ID:02X} data={hexs(cmd)}")
        dev.write(buf)

        # 等待 Input Report 响应
        print("等待响应...")
        deadline = time.time() + 10
        while time.time() < deadline:
            try:
                data = dev.read(256, timeout_ms=1000)
                if data:
                    print(f"收到响应: {hexs(data[:16])} (len={len(data)})")
                    # 解析电量
                    # Input Report 的 [0] 可能是 report_id 或 commandId
                    # 根据 handleInputReport: e.getUint8(0) = requestCode
                    # 如果 [0] == 0，是特殊报告；否则 [0] 匹配请求的 commandId
                    if data[0] == CMD_GET_BATTERY_LEVEL:
                        # 响应匹配电量查询命令
                        if len(data) > BASE_OFFSET:
                            battery_level = data[BASE_OFFSET]
                            battery_charge = data[BASE_OFFSET + 1]
                            # batteryVoltage = getUint16(baseOffset+2)
                            if len(data) > BASE_OFFSET + 3:
                                voltage = data[BASE_OFFSET + 2] | (data[BASE_OFFSET + 3] << 8)
                            else:
                                voltage = 0

                            print(f"\n{'='*50}")
                            print(f"  电量: {battery_level}%")
                            print(f"  充电状态: {'充电中' if battery_charge else '未充电'}")
                            if voltage:
                                print(f"  电压: {voltage} mV")
                            print(f"{'='*50}")
                            return {
                                "level": battery_level,
                                "charging": bool(battery_charge),
                                "voltage": voltage,
                            }
                        else:
                            print(f"响应数据太短: {hexs(data)}")
                    else:
                        print(f"  [其他报告] rid=0x{data[0]:02X} {hexs(data[:16])}")
                        # 可能是其他主动报告，继续等待
            except Exception as e:
                pass

        print("超时：10 秒内未收到电量响应。")
        print("提示: 可能需要先发送初始化命令，或关闭网页驱动后重试。")
        return None
    finally:
        dev.close()


if __name__ == "__main__":
    result = read_battery()
    if result:
        sys.exit(0)
    else:
        sys.exit(1)
