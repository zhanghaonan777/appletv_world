#!/usr/bin/env python3
"""将大播放列表拆分为按地区的小文件 + 生成精简版。"""

import re
import os
from collections import defaultdict

INPUT = "playlist.m3u"
OUTPUT_DIR = "by_region"
LITE_FILE = "playlist_lite.m3u"

# 精简版每个分组的频道数上限
LITE_LIMITS = {
    "央视": 6, "卫视": 4, "地方台": 20, "港澳台": 14,
    "美国": 80, "加拿大": 15, "英国": 30, "德国": 30,
    "法国": 20, "意大利": 20, "西班牙": 20, "荷兰": 5,
    "北欧": 20, "波兰": 3, "俄罗斯": 20, "土耳其": 7,
    "葡萄牙": 7, "希腊": 2, "罗马尼亚": 10, "乌克兰": 5,
    "日本": 12, "韩国": 20, "南亚": 30, "东南亚": 20,
    "中东": 15, "拉美": 25, "澳新": 3, "非洲": 10,
    "体育": 30, "新闻": 40, "娱乐": 20, "音乐": 15,
    "少儿": 10, "电影": 15, "生活": 10, "其他": 20,
}

# 地区合并文件映射
REGION_FILES = {
    "china": ["央视", "卫视", "卫视频道", "地方台", "港澳台"],
    "us_canada": ["美国", "加拿大"],
    "europe": ["英国", "德国", "法国", "意大利", "西班牙", "荷兰", "北欧",
               "波兰", "俄罗斯", "土耳其", "葡萄牙", "希腊", "罗马尼亚", "乌克兰",
               "United Kingdom", "Sweden", "France"],
    "asia": ["日本", "韩国", "南亚", "东南亚", "中东"],
    "americas": ["拉美"],
    "oceania_africa": ["澳新", "非洲"],
    "sports": ["体育"],
    "news": ["新闻", "News"],
    "entertainment": ["娱乐", "音乐", "少儿", "电影", "生活",
                       "Entertainment", "Movies", "Kids", "Lifestyle", "Culture", "Cooking"],
}


def parse_m3u(filepath):
    channels = defaultdict(list)
    with open(filepath, "r", encoding="utf-8") as f:
        lines = f.readlines()

    header = lines[0].strip() if lines[0].startswith("#EXTM3U") else "#EXTM3U"
    i = 1

    while i < len(lines):
        line = lines[i].strip()
        if line.startswith("#EXTINF:"):
            extinf = line
            i += 1
            while i < len(lines) and lines[i].strip().startswith("#"):
                i += 1
            if i < len(lines):
                url = lines[i].strip()
                if url and not url.startswith("#"):
                    group_match = re.search(r'group-title="([^"]*)"', extinf)
                    group = group_match.group(1) if group_match else "其他"
                    channels[group].append((extinf, url))
        i += 1

    return header, channels


def write_m3u(filepath, header, channel_list):
    with open(filepath, "w", encoding="utf-8") as f:
        f.write(header + "\n")
        for extinf, url in channel_list:
            f.write(extinf + "\n")
            f.write(url + "\n")


def main():
    header, channels = parse_m3u(INPUT)
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    total_groups = sum(len(v) for v in channels.values())
    print(f"原始播放列表: {total_groups} 个频道, {len(channels)} 个分组\n")

    # 1. 按地区生成分文件
    print("=== 地区分文件 ===")
    for filename, groups in REGION_FILES.items():
        region_channels = []
        for g in groups:
            region_channels.extend(channels.get(g, []))
        if region_channels:
            path = os.path.join(OUTPUT_DIR, f"{filename}.m3u")
            write_m3u(path, header, region_channels)
            print(f"  {filename}.m3u: {len(region_channels)} 个频道")

    # 写入未归类的
    all_assigned = set()
    for groups in REGION_FILES.values():
        all_assigned.update(groups)
    other_channels = []
    for g, chs in channels.items():
        if g not in all_assigned:
            other_channels.extend(chs)
    if other_channels:
        path = os.path.join(OUTPUT_DIR, "other.m3u")
        write_m3u(path, header, other_channels)
        print(f"  other.m3u: {len(other_channels)} 个频道")

    # 2. 生成精简版
    print(f"\n=== 精简版 ({LITE_FILE}) ===")
    lite_channels = []
    for group in LITE_LIMITS:
        limit = LITE_LIMITS[group]
        available = channels.get(group, [])
        selected = available[:limit]
        if selected:
            lite_channels.extend(selected)
            print(f"  {group}: {len(selected)}/{len(available)}")

    # 添加未在 LITE_LIMITS 中的小分组
    for g, chs in channels.items():
        if g not in LITE_LIMITS and len(chs) <= 5:
            lite_channels.extend(chs)

    write_m3u(LITE_FILE, header, lite_channels)
    print(f"\n精简版总计: {len(lite_channels)} 个频道")
    print(f"已保存到 {LITE_FILE}")

    # 3. 全量版保留
    print(f"\n全量版: {total_groups} 个频道 (playlist.m3u)")
    print(f"地区分文件目录: {OUTPUT_DIR}/")


if __name__ == "__main__":
    main()
