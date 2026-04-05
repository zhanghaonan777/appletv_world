#!/usr/bin/env python3
"""
Merge multiple IPTV M3U sources into a single deduplicated playlist
organized by channel groups for Apple TV (iPlayTV).
"""

import os
import re
import glob
from collections import OrderedDict

SOURCES_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sources")
OUTPUT_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "playlist.m3u")

# EPG source
EPG_URL = "https://live.fanmingming.cn/e.xml"

# Group ordering
GROUP_ORDER = [
    "央视", "卫视", "地方台", "港澳台",
    "美国", "英国", "日本", "韩国",
    "体育", "新闻", "欧洲", "东南亚", "其他"
]


def parse_m3u(filepath, source_tag=None):
    """Parse an M3U file and return list of channel dicts."""
    channels = []
    try:
        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()
    except Exception as e:
        print(f"  Warning: Could not read {filepath}: {e}")
        return channels

    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if line.startswith("#EXTINF:"):
            # Parse EXTINF line
            extinf = line
            # Find the URL (next non-empty, non-comment line)
            url = None
            j = i + 1
            while j < len(lines):
                next_line = lines[j].strip()
                if next_line and not next_line.startswith("#"):
                    url = next_line
                    break
                elif next_line.startswith("#EXTINF:"):
                    break  # next entry, no URL for current
                j += 1

            if url:
                ch = parse_extinf(extinf, url)
                if ch:
                    ch["source"] = source_tag or os.path.basename(filepath)
                    channels.append(ch)
                i = j + 1
                continue
        i += 1

    return channels


def parse_extinf(extinf_line, url):
    """Parse an #EXTINF line into a channel dict."""
    ch = {
        "tvg_id": "",
        "tvg_name": "",
        "tvg_logo": "",
        "group_title": "",
        "name": "",
        "url": "",
    }

    # Extract attributes
    tvg_id = re.search(r'tvg-id="([^"]*)"', extinf_line)
    tvg_name = re.search(r'tvg-name="([^"]*)"', extinf_line)
    tvg_logo = re.search(r'tvg-logo="([^"]*)"', extinf_line)
    group_title = re.search(r'group-title="([^"]*)"', extinf_line)

    if tvg_id:
        ch["tvg_id"] = tvg_id.group(1).strip()
    if tvg_name:
        ch["tvg_name"] = tvg_name.group(1).strip()
    if tvg_logo:
        ch["tvg_logo"] = tvg_logo.group(1).strip()
    if group_title:
        ch["group_title"] = group_title.group(1).strip()

    # Extract channel name (after the last comma in the EXTINF line)
    name_match = re.search(r',\s*(.+)$', extinf_line)
    if name_match:
        ch["name"] = name_match.group(1).strip()
    else:
        return None

    ch["url"] = url.strip()

    # Skip empty names or URLs
    if not ch["name"] or not ch["url"]:
        return None

    return ch


def metadata_score(ch):
    """Score a channel entry by how much metadata it has (higher = better)."""
    score = 0
    if ch["tvg_logo"]:
        score += 10
    if ch["tvg_id"]:
        score += 5
    if ch["tvg_name"]:
        score += 3
    if ch["group_title"]:
        score += 2
    # Prefer non-IPv6 URLs slightly (more compatible)
    if "[" not in ch["url"]:
        score += 1
    return score


def normalize_name(name):
    """Normalize channel name for dedup comparison."""
    n = name.strip().upper()
    # Remove common suffixes/prefixes
    n = re.sub(r'\s*(高清|超清|标清|HD|FHD|4K|8K|SDR|HDR|HEVC|H\.?265|H\.?264|SD|Ⓢ|Ⓖ)\s*', '', n)
    # Normalize CCTV formats
    n = re.sub(r'CCTV[-\s]*(\d+).*', r'CCTV\1', n)
    # Remove spaces and dashes for comparison
    n = re.sub(r'[\s\-_]+', '', n)
    return n


def classify_channel(ch):
    """Classify a channel into one of our target groups."""
    name = ch["name"]
    orig_group = ch["group_title"]
    name_upper = name.upper()

    # --- Chinese channels ---
    # CCTV channels -> 央视
    if re.search(r'CCTV|中央|央视|CGTN|CETV|中国教育', name_upper):
        return "央视"

    # Provincial satellite -> 卫视
    if re.search(r'卫视', name):
        return "卫视"

    # Check original group for Chinese groupings
    if orig_group in ("央视频道", "央视", "CCTV"):
        return "央视"
    if orig_group in ("卫视频道", "卫视"):
        return "卫视"

    # Hong Kong / Macau / Taiwan
    hk_tw_patterns = (
        r'凤凰|翡翠|明珠|TVB|ViuTV|香港|澳门|澳視|RTHK|港台|有线|'
        r'台视|中视|华视|民视|东森|TVBS|三立|纬来|中天|壹电视|'
        r'年代|非凡|FOX体育|公视|大爱|八大|寰宇|龙华|靖天|'
        r'Taiwan|Hong.?Kong|Macau|HBO.?Asia|星卫'
    )
    if re.search(hk_tw_patterns, name, re.IGNORECASE):
        return "港澳台"
    if orig_group in ("港澳台", "香港", "澳门", "台湾") or \
       re.search(r'Hong Kong|Taiwan|Macau|HK|TW', orig_group, re.IGNORECASE):
        return "港澳台"

    # Local Chinese channels
    cn_local_patterns = (
        r'北京|天津|河北|山西|内蒙古|辽宁|吉林|黑龙江|上海|江苏|浙江|'
        r'安徽|福建|江西|山东|河南|湖北|湖南|广东|广西|海南|重庆|'
        r'四川|贵州|云南|西藏|陕西|甘肃|青海|宁夏|新疆|深圳|厦门|'
        r'大连|宁波|青岛|杭州|南京|武汉|成都|广州|长沙|济南|'
        r'BRTV|BTV|STV|都市|影视|生活|新闻综合|文艺|少儿|'
        r'地方|珠江|经济|南方|岭南|金鹰'
    )
    if re.search(cn_local_patterns, name):
        return "地方台"
    if orig_group in ("地方台", "地方频道", "其他频道", "数字频道") or \
       re.search(r'4K频道|数字|地方|Local', orig_group):
        return "地方台"

    # --- Sports ---
    sport_patterns = (
        r'sport|ESPN|NBA|NFL|MLB|NHL|足球|体育|'
        r'五星体育|CCTV.?5|广东体育|劲爆|F1|'
        r'beIN|Sky.?Sport|Fox.?Sport|BT.?Sport|DAZN|Eurosport|'
        r'Tennis|Golf|Cricket|Rugby|Wrestling|Boxing|UFC|'
        r'Racing|Olympic|Eleven|Star.?Sport'
    )
    if re.search(sport_patterns, name, re.IGNORECASE):
        return "体育"
    if re.search(r'sport', orig_group, re.IGNORECASE):
        return "体育"

    # --- News ---
    news_patterns = (
        r'News|CNN|BBC|MSNBC|Fox.?News|Al.?Jazeera|新闻|'
        r'NHK.?World|Euronews|France.?24|DW|RT|Sky.?News|'
        r'ABC.?News|CBS.?News|NBC.?News|Bloomberg|CNBC|'
        r'新华|CNA|TRT.?World|WION|NDTV|Arirang'
    )
    if re.search(news_patterns, name, re.IGNORECASE):
        return "新闻"
    if re.search(r'news|新闻', orig_group, re.IGNORECASE):
        return "新闻"

    # --- Country-based classification ---
    # US
    us_patterns = (
        r'\bABC\b|\bCBS\b|\bNBC\b|\bFOX\b|\bPBS\b|\bHBO\b|\bShowtime\b|'
        r'\bAMC\b|\bTBS\b|\bTNT\b|\bUSA\b|\bCW\b|\bBET\b|\bMTV\b|'
        r'\bNickelodeon\b|\bCartoon.?Network\b|\bDisney\b|\bNatGeo\b|'
        r'\bDiscovery\b|\bHistory\b|\bA&E\b|\bLifetime\b|\bHGTV\b|'
        r'\bFood.?Network\b|\bComedy.?Central\b|\bFreeform\b|'
        r'\bBravo\b|\bE!\b|\bSyfy\b|\bTLC\b|\bFX\b'
    )
    if re.search(us_patterns, name, re.IGNORECASE):
        return "美国"
    if orig_group in ("USA", "United States") or \
       re.search(r'United States|USA|America', orig_group, re.IGNORECASE):
        return "美国"

    # UK
    uk_patterns = (
        r'\bBBC\b(?!.*Arabic|.*Persian|.*Bangla|.*Hindi|.*Urdu)|\bITV\b|\bChannel\s*[45]\b|'
        r'\bSky\b(?!.*Arabia|.*Sport)|\bDave\b|\bE4\b'
    )
    if re.search(uk_patterns, name, re.IGNORECASE):
        return "英国"
    if orig_group in ("UK", "United Kingdom") or \
       re.search(r'United Kingdom|UK\b', orig_group, re.IGNORECASE):
        return "英国"

    # Japan
    jp_patterns = r'NHK|日本|テレビ|フジ|TBS.?JP|TV.?Tokyo|TV.?Asahi|Nippon|Fuji|Japan'
    if re.search(jp_patterns, name, re.IGNORECASE):
        return "日本"
    if re.search(r'Japan', orig_group, re.IGNORECASE):
        return "日本"

    # Korea
    kr_patterns = r'KBS|MBC|SBS|JTBC|YTN|MBN|TV조선|채널A|韩国|Korea|한국|아리랑'
    if re.search(kr_patterns, name, re.IGNORECASE):
        return "韩国"
    if re.search(r'Korea|South Korea', orig_group, re.IGNORECASE):
        return "韩国"

    # European
    eu_patterns = (
        r'\bARD\b|\bZDF\b|\bRTL\b|\bSAT\.?1\b|\bProSieben\b|\bTF1\b|'
        r'\bFrance\s*[2345]\b|\bM6\b|\bRAI\b|\bMediaset\b|\bCanale\b|'
        r'\bAntena\b|\bTVE\b|\bLa\s*[12]\b|\bNPO\b|\bSVT\b|\bNRK\b|'
        r'\bDR[12]\b|\bYLE\b|\bRTP\b|\bTVP\b|\bPolsat\b|\bORF\b|'
        r'\bSRF\b|\bVRT\b|\bRTBF\b'
    )
    if re.search(eu_patterns, name, re.IGNORECASE):
        return "欧洲"
    eu_countries = (
        r'Germany|France|Italy|Spain|Netherlands|Sweden|Norway|Denmark|'
        r'Finland|Portugal|Poland|Austria|Switzerland|Belgium|Ireland|'
        r'Greece|Czech|Romania|Hungary|Bulgaria|Croatia|Serbia|'
        r'Albania|Bosnia|North Macedonia|Slovenia|Slovakia|Lithuania|'
        r'Latvia|Estonia|Luxembourg|Iceland|Malta|Cyprus|'
        r'Deutschland|Francia|Italia|Espana|Europa'
    )
    if re.search(eu_countries, orig_group, re.IGNORECASE):
        return "欧洲"

    # Southeast Asia
    sea_patterns = (
        r'Thailand|Thai|ไทย|Vietnam|Viet|VTV|HTV|泰国|越南|'
        r'Philippines|GMA|ABS-CBN|菲律宾|Malaysia|Astro|RTM|马来|'
        r'Singapore|Channel.?NewsAsia|新加坡|Indonesia|TVRI|RCTI|SCTV|印尼|'
        r'Myanmar|Cambodia|Laos|缅甸|柬埔寨|老挝'
    )
    if re.search(sea_patterns, name, re.IGNORECASE):
        return "东南亚"
    if re.search(r'Thailand|Vietnam|Philippines|Malaysia|Singapore|Indonesia|Myanmar|Cambodia|Laos|Southeast', orig_group, re.IGNORECASE):
        return "东南亚"

    # Fallback: check source file for country hints
    source = ch.get("source", "")
    source_group_map = {
        "iptv_us.m3u": "美国",
        "iptv_gb.m3u": "英国",
        "iptv_jp.m3u": "日本",
        "iptv_kr.m3u": "韩国",
        "iptv_hk.m3u": "港澳台",
        "iptv_tw.m3u": "港澳台",
        "iptv_cn.m3u": "地方台",
        "iptv_sports.m3u": "体育",
        "iptv_news.m3u": "新闻",
        "iptv_th.m3u": "东南亚",
        "iptv_vn.m3u": "东南亚",
        "iptv_ph.m3u": "东南亚",
        "iptv_my.m3u": "东南亚",
        "iptv_sg.m3u": "东南亚",
        "iptv_id.m3u": "东南亚",
        "iptv_de.m3u": "欧洲",
        "iptv_fr.m3u": "欧洲",
        "iptv_it.m3u": "欧洲",
        "iptv_es.m3u": "欧洲",
        "iptv_nl.m3u": "欧洲",
        "iptv_se.m3u": "欧洲",
        "iptv_no.m3u": "欧洲",
        "iptv_dk.m3u": "欧洲",
        "iptv_fi.m3u": "欧洲",
        "iptv_pt.m3u": "欧洲",
        "iptv_pl.m3u": "欧洲",
    }
    if source in source_group_map:
        return source_group_map[source]

    # Check freetv group-title which uses country names
    freetv_group_map = {
        "Albania": "欧洲", "Andorra": "欧洲", "Argentina": "其他",
        "Australia": "其他", "Austria": "欧洲", "Belarus": "欧洲",
        "Belgium": "欧洲", "Bolivia": "其他", "Bosnia Herzegovina": "欧洲",
        "Brazil": "其他", "Bulgaria": "欧洲", "Canada": "美国",
        "Chile": "其他", "China": "地方台", "Colombia": "其他",
        "Costa Rica": "其他", "Croatia": "欧洲", "Cyprus": "欧洲",
        "Czech Republic": "欧洲", "Denmark": "欧洲", "Dominican Republic": "其他",
        "Ecuador": "其他", "El Salvador": "其他", "Estonia": "欧洲",
        "Finland": "欧洲", "France": "欧洲", "Germany": "欧洲",
        "Greece": "欧洲", "Guatemala": "其他", "Honduras": "其他",
        "Hong Kong": "港澳台", "Hungary": "欧洲", "Iceland": "欧洲",
        "India": "其他", "Indonesia": "东南亚", "Ireland": "欧洲",
        "Israel": "其他", "Italy": "欧洲", "Japan": "日本",
        "Kosovo": "欧洲", "Latvia": "欧洲", "Lithuania": "欧洲",
        "Luxembourg": "欧洲", "Macau": "港澳台", "Malaysia": "东南亚",
        "Malta": "欧洲", "Mexico": "其他", "Moldova": "欧洲",
        "Mongolia": "其他", "Montenegro": "欧洲", "Morocco": "其他",
        "Netherlands": "欧洲", "New Zealand": "其他", "Nicaragua": "其他",
        "North Macedonia": "欧洲", "Norway": "欧洲", "Pakistan": "其他",
        "Panama": "其他", "Paraguay": "其他", "Peru": "其他",
        "Philippines": "东南亚", "Poland": "欧洲", "Portugal": "欧洲",
        "Romania": "欧洲", "Russia": "欧洲", "Serbia": "欧洲",
        "Singapore": "东南亚", "Slovakia": "欧洲", "Slovenia": "欧洲",
        "South Korea": "韩国", "Spain": "欧洲", "Sweden": "欧洲",
        "Switzerland": "欧洲", "Taiwan": "港澳台", "Thailand": "东南亚",
        "Turkey": "其他", "Ukraine": "欧洲", "United Kingdom": "英国",
        "United States": "美国", "Uruguay": "其他", "Venezuela": "其他",
        "Vietnam": "东南亚",
    }
    if orig_group in freetv_group_map:
        return freetv_group_map[orig_group]

    return "其他"


def main():
    print("=" * 60)
    print("IPTV Playlist Merger for Apple TV (iPlayTV)")
    print("=" * 60)

    # Find all M3U files
    m3u_files = sorted(
        glob.glob(os.path.join(SOURCES_DIR, "*.m3u")) +
        glob.glob(os.path.join(SOURCES_DIR, "*.m3u8"))
    )

    print(f"\nFound {len(m3u_files)} source files:")
    all_channels = []
    for f in m3u_files:
        fname = os.path.basename(f)
        channels = parse_m3u(f, source_tag=fname)
        print(f"  {fname}: {len(channels)} channels")
        all_channels.append((fname, channels))

    total_raw = sum(len(ch) for _, ch in all_channels)
    print(f"\nTotal raw channels: {total_raw}")

    # Deduplicate: group by normalized name, keep best metadata
    dedup = {}  # normalized_name -> best channel
    for source_name, channels in all_channels:
        for ch in channels:
            key = normalize_name(ch["name"])
            if not key:
                continue
            if key in dedup:
                existing = dedup[key]
                if metadata_score(ch) > metadata_score(existing):
                    dedup[key] = ch
            else:
                dedup[key] = ch

    print(f"After deduplication: {len(dedup)} unique channels")

    # Classify all channels
    groups = OrderedDict()
    for g in GROUP_ORDER:
        groups[g] = []

    for key, ch in dedup.items():
        group = classify_channel(ch)
        ch["assigned_group"] = group
        groups[group].append(ch)

    # Sort channels within each group
    for g in groups:
        groups[g].sort(key=lambda c: c["name"])

    # Print summary
    print("\n" + "=" * 60)
    print("CHANNEL SUMMARY BY GROUP")
    print("=" * 60)
    total = 0
    for g in GROUP_ORDER:
        count = len(groups[g])
        total += count
        print(f"  {g:8s} : {count:5d} channels")
    print(f"  {'TOTAL':8s} : {total:5d} channels")
    print("=" * 60)

    # Write output M3U
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        f.write(f'#EXTM3U x-tvg-url="{EPG_URL}"\n')

        for group_name in GROUP_ORDER:
            channels = groups[group_name]
            if not channels:
                continue
            for ch in channels:
                attrs = f'#EXTINF:-1'
                if ch["tvg_id"]:
                    attrs += f' tvg-id="{ch["tvg_id"]}"'
                if ch["tvg_name"]:
                    attrs += f' tvg-name="{ch["tvg_name"]}"'
                if ch["tvg_logo"]:
                    attrs += f' tvg-logo="{ch["tvg_logo"]}"'
                attrs += f' group-title="{group_name}"'
                attrs += f',{ch["name"]}\n'
                f.write(attrs)
                f.write(ch["url"] + "\n")

    print(f"\nPlaylist written to: {OUTPUT_FILE}")
    print(f"File size: {os.path.getsize(OUTPUT_FILE) / 1024:.1f} KB")


if __name__ == "__main__":
    main()
