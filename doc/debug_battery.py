#!/usr/bin/env python3
"""
调试版：尝试多种方式读取 Compx 鼠标的 HID 响应。
"""

import hid
import time
import sys
import ctypes

VID = 0x373B
PID = 0x11FE
OUTPUT_REPORT_ID = 0x08

def hexs(data):
    return " ".join(f"{b:02x}" for b in data)

def main():
    devices = hid.enumerate(VID, PID)
    print(f"找到 {len(devices)} 个 HID 接口:")
    for d in devices:
        print(f"  UsagePage=0x{d['usage_page']:04X} Usage=0x{d['usage']:04X} path={d['path'][:50]}")

    # 尝试所有厂商自定义接口
    vendor_ifaces = [d for d in devices if d["usage_page"] >= 0xFF00]

    for iface in vendor_ifaces:
        print(f"\n{'='*60}")
        print(f"测试接口: UsagePage=0x{iface['usage_page']:04X}")
        print(f"{'='*60}")

        try:
            dev = hid.Device(path=iface["path"])
            dev.nonblocking = True
            print(f"  打开成功: {dev.manufacturer} / {dev.product}")
        except Exception as e:
            print(f"  打开失败: {e}")
            continue

        try:
            # 尝试1: 发送电量查询命令 (commandId=4)
            cmd = bytearray(16)
            cmd[0] = 4  # GetBatteryLevel
            buf = bytes([OUTPUT_REPORT_ID]) + bytes(cmd)
            print(f"  发送 cmd(4): {hexs(cmd)}")
            dev.write(buf)

            # 读取响应
            for attempt in range(20):
                try:
                    data = dev.read(256, timeout_ms=500)
                    if data:
                        print(f"  [read] 收到: {hexs(data[:20])} (len={len(data)})")
                        if data[0] == 4 and len(data) > 6:
                            print(f"  >>> 电量: {data[5]}%, 充电: {data[6]}")
                except:
                    pass

            # 尝试2: 发送初始化命令后再查询
            print(f"  --- 尝试初始化序列 ---")
            init_cmds = [
                bytearray([0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                           0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3d]),
                bytearray([0x12, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                           0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3b]),
            ]
            for icmd in init_cmds:
                buf = bytes([OUTPUT_REPORT_ID]) + bytes(icmd)
                print(f"  发送 init: {hexs(icmd)}")
                dev.write(buf)
                time.sleep(0.2)
                # 读取初始化响应
                for _ in range(5):
                    try:
                        data = dev.read(256, timeout_ms=200)
                        if data:
                            print(f"  [init resp] {hexs(data[:20])} (len={len(data)})")
                    except:
                        pass

            # 再次发送电量查询
            cmd = bytearray(16)
            cmd[0] = 4
            buf = bytes([OUTPUT_REPORT_ID]) + bytes(cmd)
            print(f"  发送 cmd(4): {hexs(cmd)}")
            dev.write(buf)

            for attempt in range(20):
                try:
                    data = dev.read(256, timeout_ms=500)
                    if data:
                        print(f"  [read] 收到: {hexs(data[:20])} (len={len(data)})")
                        if data[0] == 4 and len(data) > 6:
                            print(f"  >>> 电量: {data[5]}%, 充电: {data[6]}")
                except:
                    pass

            # 尝试3: 用 get_input_report 主动读取
            print(f"  --- 尝试 get_input_report ---")
            for rid in [0x10, 0x08, 0x02, 0x05, 0x09, 0x0b]:
                try:
                    report = dev.get_input_report(rid, 64)
                    if report:
                        print(f"  [get_input_report rid=0x{rid:02X}] {hexs(report[:20])} (len={len(report)})")
                except Exception as e:
                    print(f"  [get_input_report rid=0x{rid:02X}] 失败: {e}")

            # 尝试4: 用 get_feature_report
            print(f"  --- 尝试 get_feature_report ---")
            for rid in [0x06, 0x08, 0x09]:
                try:
                    report = dev.get_feature_report(rid, 64)
                    if report:
                        print(f"  [get_feature_report rid=0x{rid:02X}] {hexs(report[:20])} (len={len(report)})")
                except Exception as e:
                    print(f"  [get_feature_report rid=0x{rid:02X}] 失败: {e}")

        except Exception as e:
            print(f"  错误: {e}")
        finally:
            dev.close()

if __name__ == "__main__":
    main()
