#!/usr/bin/env python3
"""
Merge US IPTV FAST service channels with existing validated playlist.
- Reads existing playlist_valid.m3u
- Parses all M3U files from sources_us/
- Deduplicates by fuzzy channel name matching
- Validates new channel URLs concurrently via aiohttp
- Writes merged result to playlist.m3u
"""

import asyncio
import os
import re
import sys
import time
from pathlib import Path
from collections import defaultdict

import aiohttp

BASE_DIR = Path(__file__).parent
SOURCES_DIR = BASE_DIR / "sources_us"
EXISTING_PLAYLIST = BASE_DIR / "playlist_valid.m3u"
OUTPUT_PLAYLIST = BASE_DIR / "playlist.m3u"

CONCURRENCY = 200
TIMEOUT = 10

# Keywords for sports / news classification
SPORTS_KEYWORDS = [
    'sports', 'nfl', 'nba', 'mlb', 'nhl', 'mls', 'soccer', 'football',
    'basketball', 'baseball', 'hockey', 'boxing', 'wrestling', 'ufc', 'mma',
    'espn', 'fox sports', 'tennis', 'golf', 'racing', 'nascar', 'f1',
    'cricket', 'rugby', 'ncaa', 'stadium', 'athletic', 'olympics',
    'sportsman', 'outdoor', 'fishing', 'hunting',
]

NEWS_KEYWORDS = [
    'news', 'cnn', 'msnbc', 'fox news', 'abc news', 'cbs news', 'nbc news',
    'reuters', 'bloomberg', 'cnbc', 'bbc news', 'al jazeera', 'newsy',
    'weather', 'headline', 'court tv', 'cspan', 'c-span', 'newsmax',
    'newsnation', 'livenow',
]


def normalize_name(name: str) -> str:
    """Normalize channel name for dedup: lowercase, strip whitespace/punctuation."""
    name = name.lower().strip()
    # Remove common suffixes like (720p), (1080p), [FAST], etc.
    name = re.sub(r'\s*[\(\[]\s*\d+p\s*[\)\]]', '', name)
    name = re.sub(r'\s*[\(\[]\s*fast\s*[\)\]]', '', name, flags=re.IGNORECASE)
    # Remove extra whitespace
    name = re.sub(r'\s+', ' ', name)
    return name


def classify_channel(name: str, source_group: str) -> str:
    """Classify a US channel into group-title."""
    combined = (name + " " + source_group).lower()

    for kw in SPORTS_KEYWORDS:
        if kw in combined:
            return "体育"

    for kw in NEWS_KEYWORDS:
        if kw in combined:
            return "新闻"

    return "美国"


def parse_m3u(filepath: Path):
    """Parse an M3U file, yielding (extinf_line, url, channel_name, group_title) tuples."""
    try:
        content = filepath.read_text(encoding='utf-8', errors='replace')
    except Exception as e:
        print(f"  [WARN] Cannot read {filepath}: {e}")
        return

    lines = content.strip().splitlines()
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if line.startswith('#EXTINF:'):
            extinf = line
            # Extract channel name (text after last comma)
            comma_idx = extinf.rfind(',')
            if comma_idx >= 0:
                ch_name = extinf[comma_idx + 1:].strip()
            else:
                ch_name = ""

            # Extract group-title
            grp_match = re.search(r'group-title="([^"]*)"', extinf)
            group = grp_match.group(1) if grp_match else ""

            # Next non-empty, non-comment line is URL
            i += 1
            url = ""
            while i < len(lines):
                candidate = lines[i].strip()
                if candidate and not candidate.startswith('#'):
                    url = candidate
                    break
                i += 1

            if url and ch_name:
                yield extinf, url, ch_name, group
        i += 1


def parse_existing_playlist(filepath: Path):
    """Parse existing playlist, return list of (extinf, url, name, group) and set of normalized names."""
    channels = []
    names = set()

    content = filepath.read_text(encoding='utf-8', errors='replace')
    lines = content.strip().splitlines()

    # Capture header
    header = ""
    if lines and lines[0].startswith('#EXTM3U'):
        header = lines[0]

    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if line.startswith('#EXTINF:'):
            extinf = line
            comma_idx = extinf.rfind(',')
            ch_name = extinf[comma_idx + 1:].strip() if comma_idx >= 0 else ""

            grp_match = re.search(r'group-title="([^"]*)"', extinf)
            group = grp_match.group(1) if grp_match else ""

            i += 1
            url = ""
            while i < len(lines):
                candidate = lines[i].strip()
                if candidate and not candidate.startswith('#'):
                    url = candidate
                    break
                i += 1

            if url and ch_name:
                channels.append((extinf, url, ch_name, group))
                names.add(normalize_name(ch_name))
        i += 1

    return header, channels, names


def derive_service_name(filename: str) -> str:
    """Derive a service prefix from the source filename."""
    mapping = {
        'plex_us': 'Plex',
        'pluto_us': 'Pluto',
        'samsung_us': 'Samsung',
        'roku_us': 'Roku',
        'tubi_all': 'Tubi',
        'xumo_playlist': 'Xumo',
        'xumo_apsattv': 'Xumo',
        'ssungusa': 'Samsung',
        'uslg': 'LG',
        'rok': 'Roku',
        'vizio': 'Vizio',
        'distro': 'DistroTV',
        'localnow': 'LocalNow',
    }
    stem = Path(filename).stem
    return mapping.get(stem, stem)


async def validate_url(session: aiohttp.ClientSession, url: str, sem: asyncio.Semaphore) -> bool:
    """Check if URL is reachable (status < 400)."""
    async with sem:
        try:
            # Try HEAD first
            async with session.head(url, timeout=aiohttp.ClientTimeout(total=TIMEOUT),
                                    allow_redirects=True, ssl=False) as resp:
                if resp.status < 400:
                    return True
        except Exception:
            pass

        try:
            # Fallback to GET with limited read
            async with session.get(url, timeout=aiohttp.ClientTimeout(total=TIMEOUT),
                                   allow_redirects=True, ssl=False) as resp:
                # Read a small chunk to confirm
                await resp.content.read(1024)
                return resp.status < 400
        except Exception:
            return False


async def validate_channels(channels: list) -> list:
    """Validate a list of (extinf, url, name, group) tuples, return valid ones."""
    if not channels:
        return []

    sem = asyncio.Semaphore(CONCURRENCY)
    connector = aiohttp.TCPConnector(limit=CONCURRENCY, force_close=True)

    async with aiohttp.ClientSession(connector=connector,
                                     headers={"User-Agent": "Mozilla/5.0"}) as session:
        tasks = []
        for extinf, url, name, group in channels:
            tasks.append(validate_url(session, url, sem))

        results = await asyncio.gather(*tasks, return_exceptions=True)

    valid = []
    for (extinf, url, name, group), result in zip(channels, results):
        if result is True:
            valid.append((extinf, url, name, group))

    return valid


def build_extinf(name: str, group: str, logo: str = "", tvg_id: str = "") -> str:
    """Build a clean EXTINF line."""
    parts = ['#EXTINF:-1']
    if tvg_id:
        parts.append(f'tvg-id="{tvg_id}"')
    parts.append(f'tvg-name="{name}"')
    if logo:
        parts.append(f'tvg-logo="{logo}"')
    parts.append(f'group-title="{group}"')
    return ' '.join(parts) + f',{name}'


def main():
    print("=" * 70)
    print("US IPTV FAST Channel Merger")
    print("=" * 70)

    # Step 1: Parse existing playlist
    print(f"\n[1] Reading existing playlist: {EXISTING_PLAYLIST}")
    header, existing_channels, existing_names = parse_existing_playlist(EXISTING_PLAYLIST)
    print(f"    Existing channels: {len(existing_channels)}")

    # Step 2: Parse all new source files
    print(f"\n[2] Parsing new source files from {SOURCES_DIR}")
    source_files = sorted(SOURCES_DIR.glob("*.m3u"))
    print(f"    Found {len(source_files)} source files")

    new_candidates = []  # (extinf, url, name, group, source_file)
    source_stats = defaultdict(lambda: {"total": 0, "dedup_skipped": 0, "new": 0})

    for sf in source_files:
        # Skip files that are clearly error pages (< 100 bytes)
        if sf.stat().st_size < 100:
            print(f"    Skipping {sf.name} (too small, likely 404)")
            continue

        service = derive_service_name(sf.name)
        print(f"    Parsing {sf.name} (service: {service})...")

        for extinf, url, ch_name, src_group in parse_m3u(sf):
            source_stats[sf.name]["total"] += 1
            norm = normalize_name(ch_name)

            if norm in existing_names:
                source_stats[sf.name]["dedup_skipped"] += 1
                continue

            # Classify the channel
            group = classify_channel(ch_name, src_group)

            # Extract logo from original extinf
            logo_match = re.search(r'tvg-logo="([^"]*)"', extinf)
            logo = logo_match.group(1) if logo_match else ""

            tvg_id_match = re.search(r'tvg-id="([^"]*)"', extinf)
            tvg_id = tvg_id_match.group(1) if tvg_id_match else ""

            # Build new EXTINF with proper group
            new_extinf = build_extinf(ch_name, group, logo, tvg_id)

            new_candidates.append((new_extinf, url, ch_name, group, sf.name))
            existing_names.add(norm)  # prevent cross-source dupes
            source_stats[sf.name]["new"] += 1

    print(f"\n    Total new candidates (after dedup): {len(new_candidates)}")

    # Print per-source stats
    print("\n    Per-source breakdown:")
    for src, stats in sorted(source_stats.items()):
        print(f"      {src}: {stats['total']} total, {stats['dedup_skipped']} dupes skipped, {stats['new']} new candidates")

    # Step 3: Validate new channels
    print(f"\n[3] Validating {len(new_candidates)} new channel URLs (concurrency={CONCURRENCY}, timeout={TIMEOUT}s)...")
    start = time.time()

    to_validate = [(extinf, url, name, group) for extinf, url, name, group, _ in new_candidates]
    valid_new = asyncio.run(validate_channels(to_validate))

    elapsed = time.time() - start
    print(f"    Validation complete in {elapsed:.1f}s")
    print(f"    Valid new channels: {len(valid_new)} / {len(new_candidates)}")

    # Build set of valid new URLs for per-source counting
    valid_new_urls = {url for _, url, _, _ in valid_new}

    # Per-source valid counts
    source_valid = defaultdict(int)
    for extinf, url, name, group, src in new_candidates:
        if url in valid_new_urls:
            source_valid[src] += 1

    print("\n    Valid channels per source:")
    for src, count in sorted(source_valid.items()):
        print(f"      {src}: {count} valid new channels added")

    # Step 4: Merge and write
    print(f"\n[4] Merging and writing to {OUTPUT_PLAYLIST}")
    all_channels = existing_channels + valid_new

    # Count per group
    group_counts = defaultdict(int)
    for _, _, _, group in all_channels:
        group_counts[group] += 1

    with open(OUTPUT_PLAYLIST, 'w', encoding='utf-8') as f:
        f.write(header + '\n' if header else '#EXTM3U\n')
        for extinf, url, name, group in all_channels:
            f.write(extinf + '\n')
            f.write(url + '\n')

    total = len(all_channels)
    print(f"    Total channels written: {total}")

    # Summary
    print("\n" + "=" * 70)
    print("SUMMARY")
    print("=" * 70)
    print(f"  Existing channels kept:  {len(existing_channels)}")
    print(f"  New channels added:      {len(valid_new)}")
    print(f"  Total channels:          {total}")
    print(f"\n  Channels per group:")
    for group, count in sorted(group_counts.items(), key=lambda x: -x[1]):
        print(f"    {group}: {count}")
    print("=" * 70)


if __name__ == "__main__":
    main()
