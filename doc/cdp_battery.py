#!/usr/bin/env python3
"""
通过 Chrome DevTools Protocol (CDP) 在网页驱动中执行 HID 命令，获取鼠标电量。

原理：
1. Chrome 以远程调试模式运行
2. Python 通过 CDP 连接到 Chrome
3. 在 hub.atk.pro 页面中执行 JavaScript，直接调用 WebHID API 获取电量
4. 解析响应并输出电量

使用方法：
1. 先关闭所有 Chrome 窗口
2. 运行本脚本（它会自动启动 Chrome）
3. 或手动启动: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --remote-debugging-port=9222
"""

import json
import subprocess
import sys
import time
import os
import urllib.request

# CDP WebSocket 客户端
try:
    import websocket
except ImportError:
    print("需要安装 websocket-client: pip install websocket-client")
    sys.exit(1)

CHROME_PATH = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
CDP_PORT = 9222
HUB_URL = "https://hub.atk.pro/#/"

def ensure_chrome_running():
    """确保 Chrome 以远程调试模式运行"""
    try:
        req = urllib.request.urlopen(f"http://127.0.0.1:{CDP_PORT}/json/version", timeout=2)
        data = json.loads(req.read())
        print(f"Chrome 已在运行 (CDP端口 {CDP_PORT})")
        return True
    except:
        print(f"启动 Chrome (远程调试端口 {CDP_PORT})...")
        subprocess.Popen([
            CHROME_PATH,
            f"--remote-debugging-port={CDP_PORT}",
            "--remote-allow-origins=*",
            "--user-data-dir=/tmp/chrome-cdp-profile",
            "--no-first-run",
            "--no-default-browser-check",
            HUB_URL
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(15):
            time.sleep(1)
            try:
                req = urllib.request.urlopen(f"http://127.0.0.1:{CDP_PORT}/json/version", timeout=2)
                print("Chrome 已启动")
                return True
            except:
                continue
        print("Chrome 启动超时")
        return False

def find_hub_tab():
    """找到 hub.atk.pro 的标签页"""
    req = urllib.request.urlopen(f"http://127.0.0.1:{CDP_PORT}/json", timeout=5)
    tabs = json.loads(req.read())
    for tab in tabs:
        if "hub.atk.pro" in tab.get("url", ""):
            return tab
    # 如果没找到，返回第一个页面类型的标签
    for tab in tabs:
        if tab.get("type") == "page":
            return tab
    return None

def execute_js(ws_url, js_code):
    """通过 CDP WebSocket 执行 JavaScript"""
    ws = websocket.create_connection(ws_url, timeout=15)
    try:
        # 执行 JavaScript
        msg = {
            "id": 1,
            "method": "Runtime.evaluate",
            "params": {
                "expression": js_code,
                "awaitPromise": True,
                "returnByValue": True,
            }
        }
        ws.send(json.dumps(msg))
        resp = json.loads(ws.recv())
        if "result" in resp and "result" in resp["result"]:
            return resp["result"]["result"].get("value")
        elif "result" in resp and "exceptionDetails" in resp["result"]:
            return {"error": resp["result"]["exceptionDetails"].get("text", "unknown")}
        return resp
    finally:
        ws.close()

def get_battery():
    """获取鼠标电量"""
    if not ensure_chrome_running():
        return None

    tab = find_hub_tab()
    if not tab:
        print("未找到 hub.atk.pro 标签页")
        return None

    ws_url = tab["webSocketDebuggerUrl"]
    print(f"使用标签页: {tab.get('url', 'unknown')}")

    # JavaScript 代码：通过 WebHID 获取电量
    js_code = """
(async () => {
    const hex = data => {
        const arr = data instanceof ArrayBuffer ? new Uint8Array(data) : new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
        return [...arr].map(v => v.toString(16).padStart(2, "0")).join(" ");
    };

    // 获取已授权的设备
    let devices = await navigator.hid.getDevices();
    if (devices.length === 0) {
        // 请求设备授权
        devices = await navigator.hid.requestDevice({ filters: [{ vendorId: 0x373b }] });
    }

    if (devices.length === 0) {
        return { error: "未找到设备" };
    }

    // 找到包含厂商自定义 Usage Page 的设备
    const target = devices.find(d => d.collections.some(c => c.usagePage >= 0xFF00));
    if (!target) {
        return { error: "未找到厂商自定义接口", devices: devices.map(d => d.productName) };
    }

    // 打开设备
    if (!target.opened) {
        await target.open();
    }

    // 监听 inputreport
    return new Promise((resolve) => {
        const reports = [];
        target.addEventListener("inputreport", event => {
            const data = new Uint8Array(event.data.buffer, event.data.byteOffset, event.data.byteLength);
            reports.push({ rid: event.reportId, data: hex(data), len: data.length });

            // 检查是否是电量响应 (commandId=4 在 data[0])
            if (data[0] === 4 && data[4] > 0 && data[5] <= 100) {
                target.removeEventListener("inputreport", arguments.callee);
                resolve({
                    success: true,
                    batteryLevel: data[5],
                    batteryCharge: data[6],
                    voltage: data[7] | (data[8] << 8),
                    raw: hex(data),
                    allReports: reports
                });
            }
        });

        // 发送初始化命令
        const initCmds = [
            new Uint8Array([0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3d]),
            new Uint8Array([0x12, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3b]),
            new Uint8Array([0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x4a]),
        ];

        (async () => {
            for (const cmd of initCmds) {
                await target.sendReport(0x08, cmd);
                await new Promise(r => setTimeout(r, 200));
            }

            // 发送电量查询命令
            const batteryCmd = new Uint8Array([0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x49]);
            await target.sendReport(0x08, batteryCmd);

            // 等待响应
            setTimeout(() => {
                resolve({
                    error: "超时未收到电量响应",
                    reports: reports,
                    deviceOpened: target.opened
                });
            }, 8000);
        })();
    });
})()
"""

    result = execute_js(ws_url, js_code)
    return result

def main():
    print("=" * 60)
    print("  Compx 8K 无线鼠标电量读取 (通过 Chrome WebHID)")
    print("  VID=0x373B PID=0x11FE")
    print("=" * 60)

    result = get_battery()
    print(f"\n结果: {json.dumps(result, indent=2, ensure_ascii=False)}")

    # 即使脚本返回 timeout，也检查 reports 中是否有电量响应
    if result and result.get("success"):
        print(f"\n{'='*50}")
        print(f"  电量: {result['batteryLevel']}%")
        print(f"  充电状态: {'充电中' if result['batteryCharge'] else '未充电'}")
        if result.get("voltage"):
            print(f"  电压: {result['voltage']} mV")
        print(f"  原始数据: {result['raw']}")
        print(f"{'='*50}")
        return 0
    elif result and result.get("reports"):
        # 从 reports 中查找电量响应
        for rpt in result["reports"]:
            hex_data = rpt.get("data", rpt.get("hex", ""))
            bytes_list = hex_data.split()
            if len(bytes_list) > 5 and bytes_list[0] == "04" and int(bytes_list[4], 16) > 0:
                level = int(bytes_list[5], 16)
                charge = int(bytes_list[6], 16) if len(bytes_list) > 6 else 0
                if level <= 100:
                    print(f"\n{'='*50}")
                    print(f"  电量: {level}%")
                    print(f"  充电状态: {'充电中' if charge else '未充电'}")
                    print(f"  原始数据: {hex_data}")
                    print(f"{'='*50}")
                    return 0
        print("\n未能从响应中解析电量")
        return 1

if __name__ == "__main__":
    sys.exit(main())
