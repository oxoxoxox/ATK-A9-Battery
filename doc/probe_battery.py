#!/usr/bin/env python3
"""
探测 Compx 8K 无线鼠标 (VID 0x373b / PID 0x11fe) 的电量 HID 报文。

策略：
1. 枚举所有 HID 接口，重点关照厂商自定义 Usage Page (0xFF02~0xFF06)。
2. 对有 Output Report 的接口，尝试发送网页驱动抓到的查询命令 (reportId=0x08)。
3. 对所有接口监听 Input Report，捕获主动广播的电量数据。
"""

import hid
import time
import struct
import sys

VID = 0x373B
PID = 0x11FE

def hexs(data):
    return " ".join(f"{b:02x}" for b in data)

def enumerate_interfaces():
    """枚举 VID/PID 匹配的所有 HID 接口"""
    print("=" * 70)
    print(f"枚举设备 VID=0x{VID:04X} PID=0x{PID:04X}")
    print("=" * 70)
    devices = hid.enumerate(VID, PID)
    interfaces = []
    for d in devices:
        info = {
            "path": d["path"],
            "usage_page": d["usage_page"],
            "usage": d["usage"],
            "interface": d.get("interface_number", -1),
            "product": d["product_string"],
            "release": d["release_number"],
        }
        interfaces.append(info)
        print(f"  UsagePage=0x{info['usage_page']:04X} Usage=0x{info['usage']:04X} "
              f"iface={info['interface']} path={info['path'][:60]}...")
    return interfaces

def try_open_and_listen(path, usage_page, usage, duration=5):
    """打开接口，发送查询命令并监听 Input Report"""
    print(f"\n--- 尝试接口 UsagePage=0x{usage_page:04X} Usage=0x{usage:04X} ---")
    try:
        dev = hid.Device(path=path)
        print(f"  打开成功: {dev.manufacturer} / {dev.product}")
    except Exception as e:
        print(f"  打开失败: {e}")
        return None

    reports = []

    # 尝试发送网页驱动抓到的查询命令 (Output Report ID=0x08)
    # 网页驱动发送的 payload: 0x10,0x00,...,0x3D 和 0x12,0x00,...,0x3B
    query_cmds = [
        (0x08, bytes([0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3D])),
        (0x08, bytes([0x12, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3B])),
    ]

    for rid, payload in query_cmds:
        try:
            # hidapi 要求 report_id 作为第一字节（如果 report_id != 0）
            buf = bytes([rid]) + payload
            dev.write(buf)
            print(f"  发送 Output Report rid=0x{rid:02X}: {hexs(payload)} -> OK")
        except Exception as e:
            print(f"  发送失败 (rid=0x{rid:02X}): {e}")

    # 监听 Input Report
    print(f"  监听 Input Report ({duration}秒)...")
    deadline = time.time() + duration
    while time.time() < deadline:
        try:
            data = dev.read(256, timeout_ms=500)
            if data:
                rid = data[0] if len(data) > 0 else 0
                print(f"  [IN] rid=0x{rid:02X} len={len(data)} {hexs(data[:32])}")
                reports.append({"rid": rid, "data": bytes(data)})
        except Exception as e:
            pass

    try:
        dev.close()
    except:
        pass
    return reports

def main():
    interfaces = enumerate_interfaces()
    if not interfaces:
        print("未找到设备！请确认鼠标接收器已插入。")
        return

    # 优先测试厂商自定义 Usage Page
    vendor_pages = [i for i in interfaces if i["usage_page"] >= 0xFF00]
    standard = [i for i in interfaces if i["usage_page"] < 0xFF00]

    print(f"\n厂商自定义接口: {len(vendor_pages)} 个")
    print(f"标准接口: {len(standard)} 个")

    all_reports = []
    for iface in vendor_pages:
        reports = try_open_and_listen(iface["path"], iface["usage_page"], iface["usage"], duration=5)
        if reports:
            all_reports.extend(reports)

    # 如果厂商接口没有响应，也试试标准接口
    if not all_reports:
        print("\n厂商接口无响应，尝试标准接口...")
        for iface in standard:
            reports = try_open_and_listen(iface["path"], iface["usage_page"], iface["usage"], duration=3)
            if reports:
                all_reports.extend(reports)

    print("\n" + "=" * 70)
    print(f"总计捕获 {len(all_reports)} 个 Input Report")
    print("=" * 70)
    for i, r in enumerate(all_reports):
        data = r["data"]
        print(f"  [{i}] rid=0x{r['rid']:02X} {hexs(data[:32])}")
        # 尝试在数据中寻找 50 (0x32) 这个已知电量值
        for offset, b in enumerate(data):
            if b == 50:
                print(f"       ^^^ byte[{offset}]=50 (0x32) 可能是电量!")

if __name__ == "__main__":
    main()
