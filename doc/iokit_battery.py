#!/usr/bin/env python3
"""
通过 IOKit IOHIDManager 直接读取 Compx 8K 鼠标电量。

参考 JZM5BatteryTray.swift 的实现方式：
1. 用 IOHIDManager 匹配 VID/PID
2. 找到 Usage Page 0xFF05 的接口
3. 注册 Input Report 回调
4. 发送 Output Report (rid=0x08, commandId=4)
5. 从 Input Report 回调中解析电量

协议（来自 https://hub.atk.pro/ 逆向）：
- Output Report ID = 0x08
- 命令包 16 字节, [0] = commandId
- GetBatteryLevel = 4
- 响应: [0] = commandId, [5] = batteryLevel, [6] = batteryCharge
"""

import ctypes
import time
import sys
import threading

# 加载框架
IOKIT = ctypes.CDLL("/System/Library/Frameworks/IOKit.framework/IOKit")
CF = ctypes.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")

# 常量
kCFStringEncodingUTF8 = 0x08000100
kCFNumberSInt32Type = 3
kIOHIDOptionsTypeNone = 0
kIOHIDReportTypeOutput = 1

# 获取全局变量
kCFAllocatorDefault = ctypes.c_void_p.in_dll(CF, "kCFAllocatorDefault")
kCFRunLoopDefaultMode = ctypes.c_void_p.in_dll(CF, "kCFRunLoopDefaultMode")

# CF 函数签名
CF.CFStringCreateWithCString.restype = ctypes.c_void_p
CF.CFStringCreateWithCString.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_uint32]

CF.CFNumberCreate.restype = ctypes.c_void_p
CF.CFNumberCreate.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_void_p]

CF.CFDictionaryCreateMutable.restype = ctypes.c_void_p
CF.CFDictionaryCreateMutable.argtypes = [ctypes.c_void_p, ctypes.c_long, ctypes.c_void_p, ctypes.c_void_p]

CF.CFDictionarySetValue.restype = None
CF.CFDictionarySetValue.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]

CF.CFSetGetCount.restype = ctypes.c_long
CF.CFSetGetCount.argtypes = [ctypes.c_void_p]

CF.CFSetGetValues.restype = None
CF.CFSetGetValues.argtypes = [ctypes.c_void_p, ctypes.c_void_p]

CF.CFNumberGetValue.restype = ctypes.c_bool
CF.CFNumberGetValue.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_void_p]

CF.CFNumberGetTypeID.restype = ctypes.c_ulong
CF.CFNumberGetTypeID.argtypes = []

CF.CFGetTypeID.restype = ctypes.c_ulong
CF.CFGetTypeID.argtypes = [ctypes.c_void_p]

CF.CFRelease.restype = None
CF.CFRelease.argtypes = [ctypes.c_void_p]

CF.CFRunLoopGetCurrent.restype = ctypes.c_void_p
CF.CFRunLoopGetCurrent.argtypes = []

CF.CFRunLoopRunInMode.restype = ctypes.c_int32
CF.CFRunLoopRunInMode.argtypes = [ctypes.c_void_p, ctypes.c_double, ctypes.c_bool]

# IOKit 函数签名
IOKIT.IOHIDManagerCreate.restype = ctypes.c_void_p
IOKIT.IOHIDManagerCreate.argtypes = [ctypes.c_void_p, ctypes.c_uint32]

IOKIT.IOHIDManagerOpen.restype = ctypes.c_int
IOKIT.IOHIDManagerOpen.argtypes = [ctypes.c_void_p, ctypes.c_uint32]

IOKIT.IOHIDManagerClose.restype = ctypes.c_int
IOKIT.IOHIDManagerClose.argtypes = [ctypes.c_void_p, ctypes.c_uint32]

IOKIT.IOHIDManagerSetDeviceMatching.restype = None
IOKIT.IOHIDManagerSetDeviceMatching.argtypes = [ctypes.c_void_p, ctypes.c_void_p]

IOKIT.IOHIDManagerCopyDevices.restype = ctypes.c_void_p
IOKIT.IOHIDManagerCopyDevices.argtypes = [ctypes.c_void_p]

IOKIT.IOHIDDeviceOpen.restype = ctypes.c_int
IOKIT.IOHIDDeviceOpen.argtypes = [ctypes.c_void_p, ctypes.c_uint32]

IOKIT.IOHIDDeviceClose.restype = ctypes.c_int
IOKIT.IOHIDDeviceClose.argtypes = [ctypes.c_void_p, ctypes.c_uint32]

IOKIT.IOHIDDeviceSetReport.restype = ctypes.c_int
IOKIT.IOHIDDeviceSetReport.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_int, ctypes.c_char_p, ctypes.c_long]

IOKIT.IOHIDDeviceGetProperty.restype = ctypes.c_void_p
IOKIT.IOHIDDeviceGetProperty.argtypes = [ctypes.c_void_p, ctypes.c_void_p]

IOKIT.IOHIDDeviceRegisterInputReportCallback.restype = None
IOKIT.IOHIDDeviceRegisterInputReportCallback.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_long, ctypes.c_void_p, ctypes.c_void_p]

IOKIT.IOHIDDeviceScheduleWithRunLoop.restype = None
IOKIT.IOHIDDeviceScheduleWithRunLoop.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]

IOKIT.IOHIDDeviceUnscheduleFromRunLoop.restype = None
IOKIT.IOHIDDeviceUnscheduleFromRunLoop.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]

def CFSTR(s):
    return CF.CFStringCreateWithCString(kCFAllocatorDefault, s.encode('utf-8'), kCFStringEncodingUTF8)

kIOHIDVendorIDKey = CFSTR("VendorID")
kIOHIDProductIDKey = CFSTR("ProductID")
kIOHIDPrimaryUsagePageKey = CFSTR("PrimaryUsagePage")
kIOHIDPrimaryUsageKey = CFSTR("PrimaryUsage")

VID = 0x373B
PID = 0x11FE
TARGET_USAGE_PAGE = 0xFF05  # Compx 协议接口: 有 Output Report 0x08 和 Input Report 0x08
OUTPUT_REPORT_ID = 0x08
CMD_GET_BATTERY = 4
CMD_GET_ONLINE = 3  # GetWirelessMouseOnline
CMD_GET_CONFIG = 14  # GetCurrentConfig
CMD_DOWNLOAD_DATA = 1     # DownLoadData (握手/初始化)
CMD_GET_MOUSE_CIDMID = 16  # 0x10 GetMouseCIDMID
CMD_GET_MOUSE_VERSION = 18  # 0x12 GetMouseVersion
CMD_GET_DONGLE_VERSION = 29  # 0x1D GetDongleVersion
REPORT_SIZE = 16
BASE_OFFSET = 5

received_reports = []
callback_lock = threading.Lock()

INPUT_CALLBACK = ctypes.CFUNCTYPE(
    None, ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p,
    ctypes.c_uint32, ctypes.c_uint32, ctypes.c_char_p, ctypes.c_long
)

def input_callback(context, result, sender, report_type, report_id, report, length):
    try:
        if report and length > 0:
            # 用 ctypes.string_at 读取完整数据（c_char_p 遇 \x00 会截断）
            data = ctypes.string_at(report, length)
            with callback_lock:
                received_reports.append({"report_id": report_id, "data": data, "length": length})
            hex_str = " ".join(f"{b:02x}" for b in data)
            # 分类响应: 识别 dongle 本地响应 vs 标准协议帧
            info = classify_response(data)
            tag = "标准协议帧" if info["is_standard"] else "dongle本地响应"
            cs_note = "" if info["checksum_valid"] else f" [checksum不符: 期望0x{info.get('expected_cs',0):02x} 实际0x{info.get('actual_cs',0):02x}]"
            state_note = f" 鼠标={info['mouse_state']}" if info["mouse_state"] != "unknown" else ""
            echo_note = f" 回显='{info['ascii_echo']}'" if info["ascii_echo"] else ""
            print(f"  [CALLBACK] {hex_str}  <- {tag}{cs_note}{state_note}{echo_note}")
    except Exception as e:
        print(f"  [CALLBACK ERROR] {e}")

def hexs(data):
    return " ".join(f"{b:02x}" for b in data)

def calc_checksum(report_id, data_16):
    """计算校验和: 85 - (sum([report_id, ...data[:15]]) & 255)

    注意: 此公式来自网页驱动 JS 源码 (index-O22l5tpG.js:150426),
    仅适用于【发送帧】和【鼠标转发的标准响应帧】。
    IOKit 收到的 dongle 本地响应不使用此公式, [15] 是状态/序号字节。
    """
    total = report_id + sum(data_16[:15])
    return (85 - (total & 255)) & 0xFF

def verify_checksum(rid, raw_16):
    """校验 16 字节响应帧(不含 rid)的 checksum 是否符合标准协议公式。

    返回 (is_valid, expected, actual)。
    IOKit 收到的 dongle 本地响应通常不通过此校验。
    """
    actual = raw_16[15]
    expected = calc_checksum(rid, raw_16)
    return (actual == expected, expected, actual)

def make_cmd(command_id, data=b''):
    """构造 16 字节命令包，自动计算校验和"""
    cmd = bytearray(16)
    cmd[0] = command_id
    for i, b in enumerate(data[:14]):
        cmd[1 + i] = b
    cmd[15] = calc_checksum(OUTPUT_REPORT_ID, cmd)
    return cmd

def pump_runloop(seconds):
    """运行 RunLoop 处理 IOKit 事件, 替代 time.sleep。

    time.sleep 期间 RunLoop 不运行, IOKit Input Report 回调会被积压排队,
    导致回调与发送命令错位(表现为"随机"响应)。用 CFRunLoopRunInMode 让
    回调及时触发。
    """
    deadline = time.time() + seconds
    while time.time() < deadline:
        CF.CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, False)

def classify_response(data):
    """分类 IOKit 收到的响应帧, 识别 dongle 本地响应 vs 标准协议帧。

    返回 dict: {
        is_standard: bool,       # 是否为标准协议帧(checksum 通过)
        is_dongle_local: bool,   # 是否为 dongle 本地响应
        mouse_state: str,        # 'sleep'/'active'/'transition'/'unknown'
        ascii_echo: str,         # [8..9] 的 ASCII 回显(dongle 本地响应)
        checksum_valid: bool,
    }
    """
    if len(data) < 17:
        return {"is_standard": False, "is_dongle_local": True,
                "mouse_state": "unknown", "ascii_echo": "",
                "checksum_valid": False}
    rid = data[0]
    raw = data[1:17]  # 16 bytes, WebHID format
    cs_ok, expected, actual = verify_checksum(rid, raw)

    # dongle 状态标志在 [3..7] (IOKit 偏移, 对应 raw[2..6])
    status_bytes = data[3:8]
    if status_bytes == b'\xff\xff\xff\xff\xff':
        mouse_state = "sleep"
    elif status_bytes == b'\x00\x00\x00\x00\x00':
        mouse_state = "active"
    elif status_bytes[1:] == b'\x00\x00\x00\x00':
        mouse_state = "transition"  # [3]=0x20 等中间态
    else:
        mouse_state = "unknown"

    # [8..9] ASCII 回显(dongle 本地响应特征)
    ascii_echo = ""
    if 0x20 <= data[8] <= 0x7e and 0x20 <= data[9] <= 0x7e:
        ascii_echo = data[8:10].decode('ascii', errors='replace')

    return {
        "is_standard": cs_ok,
        "is_dongle_local": not cs_ok,
        "mouse_state": mouse_state,
        "ascii_echo": ascii_echo,
        "checksum_valid": cs_ok,
        "expected_cs": expected,
        "actual_cs": actual,
    }


def send_and_receive(device, cmd_16, timeout=2.0, retries=3):
    """发送 16 字节命令包并等待匹配的响应。

    复刻网页驱动 transferForResult 的逻辑:
    1. 发送 Output Report (rid=0x08 + 16字节命令)
    2. 运行 RunLoop 等待 Input Report 回调
    3. 匹配响应: data[1]==cmd_16[0] (commandId 回显) 且 checksum 通过

    返回: (raw_16, info) 或 (None, None)
      - raw_16: 16 字节响应(不含 rid), 对应 WebHID 的 raw
      - info: classify_response 的结果

    注意: macOS IOKit 对 0xFF05 接口只能收到 dongle 本地响应,
    checksum 不通过, 此函数会返回 None。这是系统限制, 非脚本 bug。
    如需真实数据, 请用 cdp_battery.py (Chrome WebHID 方案)。
    """
    cmd_id = cmd_16[0]
    last_dongle_raw = None
    last_dongle_info = None
    for attempt in range(retries):
        with callback_lock:
            received_reports.clear()
        buf = bytes([OUTPUT_REPORT_ID]) + bytes(cmd_16)
        IOKIT.IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, OUTPUT_REPORT_ID, buf, len(buf))
        # 运行 RunLoop 等待回调
        deadline = time.time() + timeout
        while time.time() < deadline:
            CF.CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, False)
            with callback_lock:
                reports = list(received_reports)
            # 查找匹配的响应: commandId 回显
            for rpt in reports:
                data = rpt["data"]
                if len(data) >= 17 and data[1] == cmd_id:
                    raw_16 = data[1:17]
                    info = classify_response(data)
                    if info["is_standard"]:
                        return raw_16, info
                    else:
                        # 记录 dongle 本地响应(非标准协议帧)
                        last_dongle_raw = raw_16
                        last_dongle_info = info
    # 如果只收到 dongle 本地响应, 也返回它(但标注非标准)
    if last_dongle_raw:
        return last_dongle_raw, last_dongle_info
    return None, None


def get_device_info(device):
    """获取设备信息 (复刻网页驱动 getMouseCidMid + getDongleVersion)。

    协议 (来自 index-O22l5tpG.js):
      - GetMouseCIDMID (0x10): raw[5]=cid, raw[6]=mid, raw[11..14]=uniqueId
      - GetMouseVersion (0x12): raw[5..6]=version (hex X.YY)
      - GetDongleVersion (0x1D): raw[5..6]=version, 需设 dataValidLen=0, eepromAddress=0
      - DownLoadData (0x01): dataValidLen=8, raw[5..8]=encryptedData(4字节随机),
                              raw[9]=cid, raw[10]=mid, raw[11]=deviceType

    返回 dict: {cid, mid, uniqueId, mouseVersion, dongleVersion, deviceType, connectType}
    """
    info = {}

    # 1. GetMouseCIDMID (0x10)
    cmd = make_cmd(CMD_GET_MOUSE_CIDMID)
    raw, resp_info = send_and_receive(device, cmd)
    if raw and len(raw) >= 15 and resp_info and resp_info["is_standard"]:
        # raw[5]=cid, raw[6]=mid (baseOffset=5)
        info["cid"] = raw[BASE_OFFSET]
        info["mid"] = raw[BASE_OFFSET + 1]
        # uniqueId: raw[11..14] = baseOffset+6..9
        uid_bytes = raw[BASE_OFFSET + 6: BASE_OFFSET + 10]
        info["uniqueId"] = ".".join(f"{b:02x}" for b in uid_bytes)
        print(f"  GetMouseCIDMID: cid=0x{info['cid']:02X} mid=0x{info['mid']:02X} uniqueId={info['uniqueId']}")
    else:
        tag = "dongle本地响应(非标准帧)" if raw else "无响应"
        print(f"  GetMouseCIDMID: 未收到有效响应 ({tag})")
        info["cid"] = info["mid"] = None
        info["uniqueId"] = None

    # 2. GetMouseVersion (0x12)
    cmd = make_cmd(CMD_GET_MOUSE_VERSION)
    raw, resp_info = send_and_receive(device, cmd)
    if raw and len(raw) >= 7 and resp_info and resp_info["is_standard"]:
        # version: [raw[5].toString(16), raw[6].toString(16).padStart(2,'0')].join('.')
        v_major = raw[BASE_OFFSET]
        v_minor = raw[BASE_OFFSET + 1]
        info["mouseVersion"] = f"{v_major:x}.{v_minor:02x}"
        print(f"  GetMouseVersion: {info['mouseVersion']}")
    else:
        tag = "dongle本地响应(非标准帧)" if raw else "无响应"
        print(f"  GetMouseVersion: 未收到有效响应 ({tag})")
        info["mouseVersion"] = None

    # 3. GetDongleVersion (0x1D) - 需设 dataValidLen=0, eepromAddress=0
    cmd = make_cmd(CMD_GET_DONGLE_VERSION)
    cmd[4] = 0  # dataValidLen = 0
    cmd[2] = 0  # eepromAddress low = 0
    cmd[3] = 0  # eepromAddress high = 0
    cmd[15] = calc_checksum(OUTPUT_REPORT_ID, cmd)
    raw, resp_info = send_and_receive(device, cmd)
    if raw and len(raw) >= 7 and resp_info and resp_info["is_standard"]:
        v_major = raw[BASE_OFFSET]
        v_minor = raw[BASE_OFFSET + 1]
        info["dongleVersion"] = f"{v_major:x}.{v_minor:02x}"
        print(f"  GetDongleVersion: {info['dongleVersion']}")
    else:
        tag = "dongle本地响应(非标准帧)" if raw else "无响应"
        print(f"  GetDongleVersion: 未收到有效响应 ({tag})")
        info["dongleVersion"] = None

    # 4. DownLoadData (0x01) - 握手命令, 获取 deviceType/connectType
    import random
    cmd = make_cmd(CMD_DOWNLOAD_DATA)
    cmd[4] = 8  # dataValidLen = 8
    # encryptedData: 4 字节随机 (raw[5..8] = baseOffset..baseOffset+3)
    for i in range(4):
        cmd[BASE_OFFSET + i] = random.randint(0, 255)
    cmd[15] = calc_checksum(OUTPUT_REPORT_ID, cmd)
    raw, resp_info = send_and_receive(device, cmd)
    if raw and len(raw) >= 12 and resp_info and resp_info["is_standard"]:
        # raw[9]=cid (baseOffset+4), raw[10]=mid (baseOffset+5), raw[11]=deviceType (baseOffset+6)
        info["deviceType"] = raw[BASE_OFFSET + 6]
        # deviceType 映射 (来自 JS: O3t 枚举)
        # 0=usbMouse, 1=dongleMouse, 0=dongle
        type_map = {0: "USB鼠标", 1: "无线鼠标(dongle)", 2: "dongle"}
        info["connectType"] = type_map.get(info["deviceType"], f"未知(0x{info['deviceType']:02X})")
        print(f"  DownLoadData: deviceType=0x{info['deviceType']:02X} connectType={info['connectType']}")
    else:
        tag = "dongle本地响应(非标准帧)" if raw else "无响应"
        print(f"  DownLoadData: 未收到有效响应 ({tag})")
        info["deviceType"] = None
        info["connectType"] = None

    return info




def get_number_property(device, key):
    value = IOKIT.IOHIDDeviceGetProperty(device, key)
    if not value:
        return None
    if CF.CFGetTypeID(value) != CF.CFNumberGetTypeID():
        return None
    num = ctypes.c_int(0)
    if CF.CFNumberGetValue(value, kCFNumberSInt32Type, ctypes.byref(num)):
        return num.value
    return None


# ---- Report Descriptor 检查（判断是否暴露标准 HID Battery usage）----
CF.CFDataGetTypeID.restype = ctypes.c_ulong
CF.CFDataGetTypeID.argtypes = []
CF.CFDataGetLength.restype = ctypes.c_long
CF.CFDataGetLength.argtypes = [ctypes.c_void_p]
CF.CFDataGetBytePtr.restype = ctypes.c_char_p
CF.CFDataGetBytePtr.argtypes = [ctypes.c_void_p]

def get_report_descriptor(device):
    """读取设备的 HID Report Descriptor 原始字节"""
    value = IOKIT.IOHIDDeviceGetProperty(device, CFSTR("ReportDescriptor"))
    if not value or CF.CFGetTypeID(value) != CF.CFDataGetTypeID():
        return None
    length = CF.CFDataGetLength(value)
    ptr = CF.CFDataGetBytePtr(value)
    if not ptr or length <= 0:
        return None
    return ctypes.string_at(ptr, length)

def analyze_descriptor(desc):
    """解析 Report Descriptor，查找标准 Battery usage 相关条目"""
    if not desc:
        return None
    result = {"len": len(desc)}
    # 查找标准 HID 电池: Usage Page 0x0084 (Power Device) / 0x0085 (Battery System)
    # Usage 0x40 (Battery Strength)。简单搜索 item 字节模式。
    result["has_battery_page"] = (b"\x06\x84\x00" in desc) or (b"\x06\x85\x00" in desc)
    result["has_battery_strength"] = (b"\x09\x40" in desc) and (b"\x06\x84\x00" in desc or b"\x06\x85\x00" in desc)
    # 搜索所有厂商自定义 Usage Page (0xFF00-0xFFFF)
    # HID item: 0x06 = Usage Page (2 字节, Little-Endian), 0x05 = Usage Page (1 字节)
    result["vendor_pages"] = []
    for i in range(len(desc) - 2):
        if desc[i] == 0x06 and (desc[i + 1] >= 0xFF or desc[i + 2] >= 0xFF):
            page = desc[i + 1] | (desc[i + 2] << 8)
            if page not in result["vendor_pages"]:
                result["vendor_pages"].append(page)
        elif desc[i] == 0x05 and desc[i + 1] >= 0xFF:
            if desc[i + 1] not in result["vendor_pages"]:
                result["vendor_pages"].append(desc[i + 1])
    return result

def main():
    print(f"目标: VID=0x{VID:04X} PID=0x{PID:04X} UsagePage=0x{TARGET_USAGE_PAGE:04X}")

    manager = IOKIT.IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone)
    if not manager:
        print("创建 IOHIDManager 失败")
        return None

    match_dict = CF.CFDictionaryCreateMutable(kCFAllocatorDefault, 0, None, None)
    vid_num = CF.CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, ctypes.byref(ctypes.c_int(VID)))
    pid_num = CF.CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, ctypes.byref(ctypes.c_int(PID)))
    CF.CFDictionarySetValue(match_dict, kIOHIDVendorIDKey, vid_num)
    CF.CFDictionarySetValue(match_dict, kIOHIDProductIDKey, pid_num)
    IOKIT.IOHIDManagerSetDeviceMatching(manager, match_dict)

    result = IOKIT.IOHIDManagerOpen(manager, kIOHIDOptionsTypeNone)
    if result != 0:
        print(f"IOHIDManagerOpen 失败: 0x{result & 0xFFFFFFFF:08X}")
        return None

    devices_cf = IOKIT.IOHIDManagerCopyDevices(manager)
    if not devices_cf:
        print("未找到匹配的设备")
        return None

    count = CF.CFSetGetCount(devices_cf)
    print(f"找到 {count} 个 HID 设备")

    devices_array = (ctypes.c_void_p * count)()
    CF.CFSetGetValues(devices_cf, devices_array)

    target_device = None
    for i in range(count):
        dev = devices_array[i]
        usage_page = get_number_property(dev, kIOHIDPrimaryUsagePageKey)
        usage = get_number_property(dev, kIOHIDPrimaryUsageKey)
        desc = get_report_descriptor(dev)
        info = analyze_descriptor(desc)
        if usage_page is not None:
            line = f"  设备 {i}: UsagePage=0x{usage_page:04X} Usage=0x{usage:04X}"
            if info:
                line += f" | descriptor={info['len']}B"
                if info["has_battery_page"]:
                    line += " | ★含标准Battery Page(0x84/0x85)"
                if info["vendor_pages"]:
                    line += f" | vendor_pages={[hex(p) for p in info['vendor_pages']]}"
            print(line)
            if usage_page == TARGET_USAGE_PAGE:
                target_device = dev
                print(f"  >>> 选定此接口")
        else:
            print(f"  设备 {i}: 无法读取属性")

    if not target_device:
        print("未找到目标接口，尝试任意厂商自定义接口...")
        for i in range(count):
            dev = devices_array[i]
            up = get_number_property(dev, kIOHIDPrimaryUsagePageKey)
            if up and up >= 0xFF00:
                target_device = dev
                print(f"  >>> 回退选择 UsagePage=0x{up:04X}")
                break

    if not target_device:
        return None

    if "--desc-only" in sys.argv:
        print("\n--desc-only 模式：仅检查 Report Descriptor，跳过 HID 查询")
        return None

    result = IOKIT.IOHIDDeviceOpen(target_device, kIOHIDOptionsTypeNone)
    if result != 0:
        print(f"IOHIDDeviceOpen 失败: 0x{result & 0xFFFFFFFF:08X}")
        return None
    print(f"设备已打开：{hex(result)}")

    buffer = (ctypes.c_char * 256)()
    callback_ref = INPUT_CALLBACK(input_callback)
    IOKIT.IOHIDDeviceRegisterInputReportCallback(target_device, buffer, 256, callback_ref, None)

    run_loop = CF.CFRunLoopGetCurrent()
    IOKIT.IOHIDDeviceScheduleWithRunLoop(target_device, run_loop, kCFRunLoopDefaultMode)

    # 先发送初始化命令唤醒鼠标（复刻网页驱动的命令序列）
    # print("发送初始化命令序列（复刻网页驱动）...")
    print("发送初始化命令序列...")
    init_cmds = [
        make_cmd(0x10),  # GetMouseCIDMID
        make_cmd(0x12),  # GetMouseVersion
        make_cmd(0x1D),  # 未知命令
        make_cmd(0x03),  # GetWirelessMouseOnline
        make_cmd(0x04),  # GetBatteryLevel (第一次查询可能唤醒)
        # DownLoadData 命令 - 网页驱动发送的握手命令
        bytearray([0x01, 0x00, 0x00, 0x00, 0x08, 0x4d, 0x24, 0xc0,
                   0x62, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xb1]),
    ]
    for icmd in init_cmds:
        buf = bytes([OUTPUT_REPORT_ID]) + bytes(icmd)
        print(f"  发送: {hexs(icmd)}")
        IOKIT.IOHIDDeviceSetReport(target_device, kIOHIDReportTypeOutput, OUTPUT_REPORT_ID, buf, len(buf))
        # 用 RunLoop 替代 time.sleep, 让 IOKit 回调及时触发, 避免排队错位
        pump_runloop(0.3)
    # 等待初始化响应
    pump_runloop(2)
    with callback_lock:
        received_reports.clear()

    # 获取设备信息 (复刻网页驱动 getMouseCidMid + getDongleVersion + DownLoadData)
    if "--device-info" in sys.argv or "--all" in sys.argv:
        print("\n" + "=" * 50)
        print("获取设备信息 (getDeviceInfo)")
        print("=" * 50)
        dev_info = get_device_info(target_device)
        print("-" * 50)
        print(f"  CID:        0x{dev_info.get('cid', 0):02X}" if dev_info.get("cid") is not None else "  CID:        N/A")
        print(f"  MID:        0x{dev_info.get('mid', 0):02X}" if dev_info.get("mid") is not None else "  MID:        N/A")
        print(f"  UniqueId:   {dev_info.get('uniqueId', 'N/A')}")
        print(f"  鼠标版本:   {dev_info.get('mouseVersion', 'N/A')}")
        print(f"  接收器版本: {dev_info.get('dongleVersion', 'N/A')}")
        print(f"  设备类型:   {dev_info.get('connectType', 'N/A')}")
        print("=" * 50)
        if "--device-info" in sys.argv:
            # 仅获取设备信息模式, 跳过电量查询
            IOKIT.IOHIDDeviceUnscheduleFromRunLoop(target_device, run_loop, kCFRunLoopDefaultMode)
            IOKIT.IOHIDDeviceClose(target_device, kIOHIDOptionsTypeNone)
            return dev_info

    # # 先检查鼠标是否在线
    # print("\n检查鼠标在线状态...")
    # online_cmd = make_cmd(CMD_GET_ONLINE)
    # online_buf = bytes([OUTPUT_REPORT_ID]) + bytes(online_cmd)
    # print(f"  发送: {hexs(online_cmd)}")
    # IOKIT.IOHIDDeviceSetReport(target_device, kIOHIDReportTypeOutput, OUTPUT_REPORT_ID, online_buf, len(online_buf))
    # time.sleep(1)
    # deadline = time.time() + 2
    # while time.time() < deadline:
    #     CF.CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, False)
    # with callback_lock:
    #     if received_reports:
    #         for rpt in received_reports[-1:]:
    #             data = rpt["data"]
    #             print(f"  在线状态响应: {hexs(data)}")
    #     received_reports.clear()

    # 多次查询电量（持续诊断，等待鼠标唤醒）
    # IOKit 数据格式: [0]=reportId(0x08), [1]=commandId, [2]=commandStatus,
    # [3..4]=eepromAddress, [5]=dataValidLen, [6]=batteryLevel, [7]=batteryCharge
    # dataValidLen=0xFF 表示鼠标休眠/无有效数据
    print("\n开始电量查询（请移动/点击鼠标唤醒，最多等待约 2 分钟）...")
    battery_cmd = make_cmd(CMD_GET_BATTERY)
    print(f"  电量查询命令: {hexs(battery_cmd)}")
    found_valid = False
    for i in range(2):
        with callback_lock:
            received_reports.clear()
        cmd_with_rid = bytes([OUTPUT_REPORT_ID]) + bytes(battery_cmd)
        IOKIT.IOHIDDeviceSetReport(target_device, kIOHIDReportTypeOutput, OUTPUT_REPORT_ID, cmd_with_rid, len(cmd_with_rid))
        # 用 RunLoop 替代 time.sleep, 让回调及时触发
        pump_runloop(1)
        deadline = time.time() + 2
        while time.time() < deadline:
            CF.CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, False)
        with callback_lock:
            reports = list(received_reports)
        if not reports:
            print(f"第 {i+1} 次查询：未收到响应")
            continue
        for rpt in reports:
            data = rpt["data"]
            rid = rpt["report_id"]
            info = classify_response(data)
            print(f"第 {i+1} 次响应: rid=0x{rid:02X} len={len(data)} -- {hexs(data)}")
            # 优先判断是否为标准协议帧
            if info["is_dongle_local"]:
                print(f"    -> dongle 本地响应 (非鼠标转发数据, checksum 不符合标准协议公式)")
                print(f"       鼠标状态={info['mouse_state']}, ASCII回显='{info['ascii_echo']}'")
                print(f"       说明: macOS IOKit 对 0xFF05 接口的 Input Report 路由与 WebHID 不同,")
                print(f"             只能收到接收器本地响应, 无法收到鼠标通过 2.4G 转发的真实电量")
            if len(data) <= 5 or data[1] != CMD_GET_BATTERY:
                continue
            data_valid_len = data[5]
            battery_level = data[6]
            battery_charge = data[7]
            if data_valid_len == 0xFF:
                print(f"    -> 鼠标休眠 (dataValidLen=0xFF)，请移动/点击鼠标唤醒")
            elif data_valid_len >= 1 and battery_level <= 100 and info["is_standard"]:
                print(f"    -> 有效数据! dataValidLen={data_valid_len} batteryLevel={battery_level}% batteryCharge={battery_charge}")
                voltage = data[8] | (data[9] << 8) if len(data) > 9 else 0
                print(f"\n{'='*50}")
                print(f"  电量: {battery_level}%")
                print(f"  充电状态: {'充电中' if battery_charge else '未充电'}")
                if voltage:
                    print(f"  电压: {voltage} mV")
                print(f"{'='*50}")
                found_valid = True
            else:
                print(f"    -> 无有效电量 (dataValidLen=0x{data_valid_len:02X}, batteryLevel=0x{battery_level:02X}, batteryCharge=0x{battery_charge:02X})")
                if not info["is_standard"]:
                    print(f"       ⚠️ checksum 不匹配, 此为 dongle 本地响应, 非真实电量数据")
        if found_valid:
            break
    if not found_valid:
        print("\n结论：IOKit 方式无法获取真实电量（macOS 系统限制）")
        print("      IOKit 只能收到 dongle 本地响应, 收不到鼠标通过 2.4G 无线转发的数据")
        print("      如需真实电量, 请使用 cdp_battery.py (Chrome WebHID 方案)")

    IOKIT.IOHIDDeviceUnscheduleFromRunLoop(target_device, run_loop, kCFRunLoopDefaultMode)
    IOKIT.IOHIDDeviceClose(target_device, kIOHIDOptionsTypeNone)
    return None

if __name__ == "__main__":
    main()
