#!/usr/bin/env python3
"""并发验证 M3U 播放列表中的所有频道源，过滤掉无效链接。"""

import re
import sys
import time
import asyncio
import aiohttp
from pathlib import Path
from collections import defaultdict

INPUT_FILE = "playlist.m3u"
OUTPUT_FILE = "playlist_valid.m3u"
TIMEOUT = 8  # 秒
MAX_CONCURRENT = 200  # 最大并发数


def parse_m3u(filepath):
    """解析 M3U 文件，返回频道列表。"""
    channels = []
    with open(filepath, "r", encoding="utf-8") as f:
        lines = f.readlines()

    header = lines[0].strip() if lines and lines[0].startswith("#EXTM3U") else "#EXTM3U"
    i = 1 if lines[0].startswith("#EXTM3U") else 0

    while i < len(lines):
        line = lines[i].strip()
        if line.startswith("#EXTINF:"):
            extinf = line
            i += 1
            while i < len(lines) and lines[i].strip().startswith("#"):
                extinf += "\n" + lines[i].strip()
                i += 1
            if i < len(lines):
                url = lines[i].strip()
                if url and not url.startswith("#"):
                    # 提取频道名和分组
                    name_match = re.search(r',(.+)$', extinf.split('\n')[0])
                    group_match = re.search(r'group-title="([^"]*)"', extinf)
                    name = name_match.group(1).strip() if name_match else "Unknown"
                    group = group_match.group(1) if group_match else "其他"
                    channels.append({
                        "extinf": extinf,
                        "url": url,
                        "name": name,
                        "group": group,
                    })
        i += 1

    return header, channels


async def check_url(session, channel, semaphore):
    """检查单个 URL 是否有效。"""
    async with semaphore:
        url = channel["url"]
        try:
            async with session.head(url, timeout=aiohttp.ClientTimeout(total=TIMEOUT), allow_redirects=True, ssl=False) as resp:
                if resp.status < 400:
                    return channel, True
            # HEAD 不行试 GET
            async with session.get(url, timeout=aiohttp.ClientTimeout(total=TIMEOUT), allow_redirects=True, ssl=False) as resp:
                # 只读少量数据验证
                await resp.content.read(1024)
                return channel, resp.status < 400
        except Exception:
            return channel, False


async def main():
    header, channels = parse_m3u(INPUT_FILE)
    total = len(channels)
    print(f"共 {total} 个频道，开始并发验证（并发数: {MAX_CONCURRENT}, 超时: {TIMEOUT}s）...\n")

    semaphore = asyncio.Semaphore(MAX_CONCURRENT)
    connector = aiohttp.TCPConnector(limit=MAX_CONCURRENT, ttl_dns_cache=300)

    valid = []
    invalid = 0
    checked = 0
    start_time = time.time()

    async with aiohttp.ClientSession(connector=connector, headers={"User-Agent": "Mozilla/5.0"}) as session:
        tasks = [check_url(session, ch, semaphore) for ch in channels]

        for coro in asyncio.as_completed(tasks):
            channel, is_valid = await coro
            checked += 1
            if is_valid:
                valid.append(channel)
            else:
                invalid += 1

            if checked % 200 == 0 or checked == total:
                elapsed = time.time() - start_time
                print(f"  进度: {checked}/{total} | 有效: {len(valid)} | 无效: {invalid} | 耗时: {elapsed:.1f}s")

    # 按分组统计
    groups = defaultdict(list)
    for ch in valid:
        groups[ch["group"]].append(ch)

    # 写入输出文件
    group_order = ["央视", "卫视", "地方台", "港澳台", "美国", "英国", "日本", "韩国", "体育", "新闻", "欧洲", "东南亚", "其他"]
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        f.write(header + "\n")
        for g in group_order:
            for ch in groups.get(g, []):
                f.write(ch["extinf"] + "\n")
                f.write(ch["url"] + "\n")
        # 写入不在预定义分组中的
        for g, chs in groups.items():
            if g not in group_order:
                for ch in chs:
                    f.write(ch["extinf"] + "\n")
                    f.write(ch["url"] + "\n")

    elapsed = time.time() - start_time
    print(f"\n{'='*50}")
    print(f"验证完成！耗时 {elapsed:.1f}s")
    print(f"总计: {total} | 有效: {len(valid)} | 无效: {invalid}")
    print(f"有效率: {len(valid)/total*100:.1f}%")
    print(f"\n各分组有效频道数:")
    for g in group_order:
        count = len(groups.get(g, []))
        if count > 0:
            print(f"  {g}: {count}")
    for g in sorted(groups.keys()):
        if g not in group_order:
            print(f"  {g}: {len(groups[g])}")
    print(f"\n已保存到 {OUTPUT_FILE}")


if __name__ == "__main__":
    asyncio.run(main())
