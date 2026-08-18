#!/usr/bin/env python3
"""
用 hidapi 阻塞模式读取 Compx 鼠标电量。
尝试在单独线程中持续读取 Input Report。
"""

import hid
import time
import sys
import threading

VID = 0x373B
PID = 0x11FE
OUTPUT_REPORT_ID = 0x08
CMD_GET_BATTERY = 4
REPORT_SIZE = 16
BASE_OFFSET = 5

def hexs(data):
    return " ".join(f"{b:02x}" for b in data)

received_data = []
data_lock = threading.Lock()

def reader_thread(dev, duration):
    """在单独线程中持续读取 Input Report"""
    deadline = time.time() + duration
    while time.time() < deadline:
        try:
            data = dev.read(256, timeout_ms=500)
            if data:
                with data_lock:
                    received_data.append(bytes(data))
                print(f"  [READER] 收到: {hexs(data[:20])} (len={len(data)})")
        except Exception as e:
            pass

def main():
    devices = hid.enumerate(VID, PID)
    vendor_ifaces = [d for d in devices if d["usage_page"] >= 0xFF00]

    if not vendor_ifaces:
        print("未找到厂商自定义接口")
        return

    for iface in vendor_ifaces:
        print(f"\n{'='*60}")
        print(f"测试接口: UsagePage=0x{iface['usage_page']:04X}")
        print(f"{'='*60}")

        try:
            dev = hid.Device(path=iface["path"])
            # 不设置非阻塞，使用阻塞模式
            print(f"  打开成功: {dev.manufacturer} / {dev.product}")
        except Exception as e:
            print(f"  打开失败: {e}")
            continue

        try:
            # 启动读取线程
            reader = threading.Thread(target=reader_thread, args=(dev, 15), daemon=True)
            reader.start()

            # 发送初始化命令
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
                time.sleep(0.3)

            # 发送电量查询命令
            cmd = bytearray(REPORT_SIZE)
            cmd[0] = CMD_GET_BATTERY
            buf = bytes([OUTPUT_REPORT_ID]) + bytes(cmd)
            print(f"  发送 cmd(4): {hexs(cmd)}")
            dev.write(buf)

            # 等待读取线程完成
            reader.join(timeout=15)

            # 分析结果
            with data_lock:
                if received_data:
                    print(f"\n  总共收到 {len(received_data)} 个报告")
                    for i, data in enumerate(received_data):
                        print(f"  [{i}] {hexs(data[:20])}")
                        # 查找电量值 50
                        for offset, b in enumerate(data):
                            if b == 50:
                                print(f"    >>> byte[{offset}]=50 (可能是电量!)")
                            if b == 4 and offset == 0:
                                print(f"    >>> byte[0]=4 (可能是 GetBatteryLevel 响应)")
                else:
                    print("  未收到任何数据")

            # 清空 for next interface
            with data_lock:
                received_data.clear()

        except Exception as e:
            print(f"  错误: {e}")
        finally:
            dev.close()

if __name__ == "__main__":
    main()
