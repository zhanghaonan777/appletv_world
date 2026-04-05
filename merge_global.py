#!/usr/bin/env python3
"""
Download international IPTV sources, validate concurrently, deduplicate,
and merge with the existing playlist.m3u.
"""

import asyncio
import os
import re
import subprocess
import sys
import time
import urllib.request
import ssl
from collections import OrderedDict

try:
    import aiohttp
except ImportError:
    sys.exit("aiohttp is required: pip install aiohttp")

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SOURCES_DIR = os.path.join(BASE_DIR, "sources_global")
EXISTING_PLAYLIST = os.path.join(BASE_DIR, "playlist.m3u")
OUTPUT_FILE = os.path.join(BASE_DIR, "playlist.m3u")
EPG_URL = "https://live.fanmingming.cn/e.xml"

CONCURRENCY = 300
VALIDATE_TIMEOUT = 8

# ── Sources ──────────────────────────────────────────────────────────

COUNTRY_CODES = [
    "de", "fr", "it", "es", "nl", "tr", "ru", "pl", "se", "no", "dk", "fi",
    "in", "th", "vn", "ph", "my", "id", "pk", "sa", "eg", "br", "mx", "ca",
    "au", "ar", "co", "pt", "gr", "ro", "ua", "ae", "iq", "za", "ng", "ke",
    "bd", "sg", "nz",
]

IPTV_ORG_COUNTRY = {
    code: f"https://iptv-org.github.io/iptv/countries/{code}.m3u"
    for code in COUNTRY_CODES
}

IPTV_ORG_CATEGORY = {
    f"cat_{name}": f"https://iptv-org.github.io/iptv/categories/{name}.m3u"
    for name in ["entertainment", "music", "kids", "movies", "lifestyle"]
}

BUDDY_CHEW = {
    "buddy_plutotv": "https://raw.githubusercontent.com/BuddyChewChew/app-m3u-generator/main/playlists/plutotv_all.m3u",
    "buddy_plex": "https://raw.githubusercontent.com/BuddyChewChew/app-m3u-generator/main/playlists/plex_all.m3u",
    "buddy_samsung": "https://raw.githubusercontent.com/BuddyChewChew/app-m3u-generator/main/playlists/samsungtvplus_all.m3u",
    "buddy_roku": "https://raw.githubusercontent.com/BuddyChewChew/app-m3u-generator/main/playlists/roku_all.m3u",
}

APSATTV = {
    "apsattv_lg": "https://www.apsattv.com/lg.m3u",
    "apsattv_vidaa": "https://www.apsattv.com/vidaa.m3u",
    "apsattv_tcl": "https://www.apsattv.com/tclplus.m3u",
    "apsattv_sports": "https://www.apsattv.com/freelivesports.m3u",
    "apsattv_rakuten": "https://www.apsattv.com/rakuten-jp.m3u",
}

REGIONAL = {
    "regional_de": "https://raw.githubusercontent.com/josxha/german-tv-m3u/main/german-tv.m3u",
    "regional_ru": "https://raw.githubusercontent.com/smolnp/IPTVru/refs/heads/gh-pages/IPTVru.m3u",
    "regional_my": "https://raw.githubusercontent.com/haqem/iptv-malaysia/main/playlist.m3u",
}

ALL_SOURCES = {}
ALL_SOURCES.update(IPTV_ORG_COUNTRY)
ALL_SOURCES.update(IPTV_ORG_CATEGORY)
ALL_SOURCES.update(BUDDY_CHEW)
ALL_SOURCES.update(APSATTV)
ALL_SOURCES.update(REGIONAL)

# ── Group definitions ────────────────────────────────────────────────

GROUP_ORDER = [
    "央视", "卫视", "地方台", "港澳台",
    "美国", "加拿大", "英国", "德国", "法国", "意大利", "西班牙", "荷兰",
    "北欧", "波兰", "俄罗斯", "土耳其", "葡萄牙", "希腊", "罗马尼亚", "乌克兰",
    "日本", "韩国", "南亚", "东南亚", "中东", "拉美", "澳新", "非洲",
    "体育", "新闻", "娱乐", "音乐", "少儿", "电影", "生活", "其他",
]

# Country code → group
COUNTRY_GROUP = {
    "de": "德国", "fr": "法国", "it": "意大利", "es": "西班牙", "nl": "荷兰",
    "tr": "土耳其", "ru": "俄罗斯", "pl": "波兰",
    "se": "北欧", "no": "北欧", "dk": "北欧", "fi": "北欧",
    "in": "南亚", "pk": "南亚", "bd": "南亚",
    "th": "东南亚", "vn": "东南亚", "ph": "东南亚", "my": "东南亚",
    "id": "东南亚", "sg": "东南亚",
    "sa": "中东", "eg": "中东", "ae": "中东", "iq": "中东",
    "br": "拉美", "ar": "拉美", "co": "拉美", "mx": "拉美",
    "ca": "加拿大",
    "au": "澳新", "nz": "澳新",
    "pt": "葡萄牙", "gr": "希腊", "ro": "罗马尼亚", "ua": "乌克兰",
    "za": "非洲", "ng": "非洲", "ke": "非洲",
}

CATEGORY_GROUP = {
    "cat_entertainment": "娱乐",
    "cat_music": "音乐",
    "cat_kids": "少儿",
    "cat_movies": "电影",
    "cat_lifestyle": "生活",
}

# ── Helpers ───────────────────────────────────────────────────────────

def download_source(tag, url, dest_dir):
    """Download a single M3U source. Returns (tag, filepath) or (tag, None).
    Tries urllib first, then falls back to curl for SSL issues."""
    filepath = os.path.join(dest_dir, f"{tag}.m3u")
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=30, context=ctx) as resp:
            data = resp.read()
        with open(filepath, "wb") as f:
            f.write(data)
        return tag, filepath
    except Exception:
        pass
    # Fallback: use curl
    try:
        result = subprocess.run(
            ["curl", "-fsSL", "-k", "--max-time", "30",
             "-H", "User-Agent: Mozilla/5.0", "-o", filepath, url],
            capture_output=True, timeout=35,
        )
        if result.returncode == 0 and os.path.exists(filepath) and os.path.getsize(filepath) > 100:
            return tag, filepath
    except Exception:
        pass
    print(f"  [SKIP] {tag}: download failed")
    return tag, None


def parse_extinf(extinf_line, url):
    ch = {
        "tvg_id": "",
        "tvg_name": "",
        "tvg_logo": "",
        "group_title": "",
        "name": "",
        "url": "",
    }
    m = re.search(r'tvg-id="([^"]*)"', extinf_line)
    if m:
        ch["tvg_id"] = m.group(1).strip()
    m = re.search(r'tvg-name="([^"]*)"', extinf_line)
    if m:
        ch["tvg_name"] = m.group(1).strip()
    m = re.search(r'tvg-logo="([^"]*)"', extinf_line)
    if m:
        ch["tvg_logo"] = m.group(1).strip()
    m = re.search(r'group-title="([^"]*)"', extinf_line)
    if m:
        ch["group_title"] = m.group(1).strip()
    name_match = re.search(r',\s*(.+)$', extinf_line)
    if name_match:
        ch["name"] = name_match.group(1).strip()
    else:
        return None
    ch["url"] = url.strip()
    if not ch["name"] or not ch["url"]:
        return None
    return ch


def parse_m3u(filepath, source_tag=None):
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
            extinf = line
            url = None
            j = i + 1
            while j < len(lines):
                next_line = lines[j].strip()
                if next_line and not next_line.startswith("#"):
                    url = next_line
                    break
                elif next_line.startswith("#EXTINF:"):
                    break
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


def normalize_name(name):
    n = name.strip().lower()
    n = re.sub(
        r'\s*(高清|超清|标清|hd|fhd|4k|8k|sdr|hdr|hevc|h\.?265|h\.?264|sd|ⓢ|ⓖ|ⓨ)\s*',
        '', n, flags=re.IGNORECASE,
    )
    n = re.sub(r'cctv[-\s]*(\d+).*', r'cctv\1', n)
    n = re.sub(r'[\s\-_\(\)\[\]]+', '', n)
    return n


def metadata_score(ch):
    score = 0
    if ch["tvg_logo"]:
        score += 10
    if ch["tvg_id"]:
        score += 5
    if ch["tvg_name"]:
        score += 3
    if ch["group_title"]:
        score += 2
    if "[" not in ch["url"]:
        score += 1
    return score


def classify_channel(ch, source_tag=""):
    """Classify a channel into a group based on name, original group, and source tag."""
    name = ch["name"]
    orig_group = ch["group_title"]
    name_upper = name.upper()

    # ── Chinese channels ──
    if re.search(r'CCTV|中央|央视|CGTN|CETV|中国教育', name_upper):
        return "央视"
    if re.search(r'卫视', name):
        return "卫视"
    if orig_group in ("央视频道", "央视", "CCTV"):
        return "央视"
    if orig_group in ("卫视频道", "卫视"):
        return "卫视"

    # Hong Kong / Macau / Taiwan
    hk_tw = (
        r'凤凰|翡翠|明珠|TVB|ViuTV|香港|澳门|澳視|RTHK|港台|有线|'
        r'台视|中视|华视|民视|东森|TVBS|三立|纬来|中天|壹电视|'
        r'年代|非凡|公视|大爱|八大|寰宇|龙华|靖天|Taiwan|Hong.?Kong|Macau|HBO.?Asia|星卫'
    )
    if re.search(hk_tw, name, re.IGNORECASE):
        return "港澳台"
    if orig_group in ("港澳台", "香港", "澳门", "台湾") or \
       re.search(r'Hong Kong|Taiwan|Macau|HK|TW', orig_group, re.IGNORECASE):
        return "港澳台"

    # Local Chinese
    cn_local = (
        r'北京|天津|河北|山西|内蒙古|辽宁|吉林|黑龙江|上海|江苏|浙江|'
        r'安徽|福建|江西|山东|河南|湖北|湖南|广东|广西|海南|重庆|'
        r'四川|贵州|云南|西藏|陕西|甘肃|青海|宁夏|新疆|深圳|厦门|'
        r'大连|宁波|青岛|杭州|南京|武汉|成都|广州|长沙|济南|'
        r'BRTV|BTV|STV|都市|影视|生活频道|新闻综合|文艺|'
        r'珠江|经济|南方|岭南|金鹰'
    )
    if re.search(cn_local, name):
        return "地方台"
    if orig_group in ("地方台", "地方频道", "其他频道", "数字频道") or \
       re.search(r'4K频道|数字|地方|Local', orig_group):
        return "地方台"

    # ── Sports ──
    sport_pat = (
        r'sport|ESPN|NBA|NFL|MLB|NHL|足球|体育|'
        r'五星体育|CCTV.?5|广东体育|劲爆|F1|'
        r'beIN|Sky.?Sport|Fox.?Sport|BT.?Sport|DAZN|Eurosport|'
        r'Tennis|Golf|Cricket|Rugby|Wrestling|Boxing|UFC|'
        r'Racing|Olympic|Eleven|Star.?Sport'
    )
    if re.search(sport_pat, name, re.IGNORECASE):
        return "体育"
    if re.search(r'sport', orig_group, re.IGNORECASE):
        return "体育"

    # ── News ──
    news_pat = (
        r'News|CNN|MSNBC|Fox.?News|Al.?Jazeera|新闻|'
        r'NHK.?World|Euronews|France.?24|DW.?News|Sky.?News|'
        r'ABC.?News|CBS.?News|NBC.?News|Bloomberg|CNBC|'
        r'新华|CNA|TRT.?World|WION|NDTV|Arirang'
    )
    if re.search(news_pat, name, re.IGNORECASE):
        return "新闻"
    if re.search(r'news|新闻', orig_group, re.IGNORECASE):
        return "新闻"

    # ── Category-based from source tag ──
    if source_tag in CATEGORY_GROUP:
        return CATEGORY_GROUP[source_tag]
    # Check orig_group for category hints
    cat_map = {
        "Entertainment": "娱乐", "Music": "音乐", "Kids": "少儿",
        "Movies": "电影", "Lifestyle": "生活",
    }
    for kw, grp in cat_map.items():
        if kw.lower() in orig_group.lower():
            return grp

    # ── Country-specific patterns ──
    # US
    us_pat = (
        r'\bABC\b|\bCBS\b|\bNBC\b|\bFOX\b|\bPBS\b|\bHBO\b|\bShowtime\b|'
        r'\bAMC\b|\bTBS\b|\bTNT\b|\bUSA\b|\bCW\b|\bBET\b|\bMTV\b|'
        r'\bNickelodeon\b|\bCartoon.?Network\b|\bDisney\b|\bNatGeo\b|'
        r'\bDiscovery\b|\bHistory\b|\bA&E\b|\bLifetime\b|\bHGTV\b|'
        r'\bFood.?Network\b|\bComedy.?Central\b|\bFreeform\b|'
        r'\bBravo\b|\bE!\b|\bSyfy\b|\bTLC\b|\bFX\b'
    )
    if re.search(us_pat, name, re.IGNORECASE):
        return "美国"
    if re.search(r'United States|USA|America', orig_group, re.IGNORECASE):
        return "美国"

    # UK (BBC without regional qualifiers)
    uk_pat = (
        r'\bBBC\b(?!.*Arabic|.*Persian|.*Bangla|.*Hindi|.*Urdu)|\bITV\b|'
        r'\bChannel\s*[45]\b|\bSky\b(?!.*Arabia|.*Sport)|\bDave\b|\bE4\b'
    )
    if re.search(uk_pat, name, re.IGNORECASE):
        return "英国"
    if re.search(r'United Kingdom|UK\b', orig_group, re.IGNORECASE):
        return "英国"

    # Germany
    de_pat = r'\bARD\b|\bZDF\b|\bRTL\b|\bSAT\.?1\b|\bProSieben\b|\bWDR\b|\bNDR\b|\bMDR\b|\bBR\b|\bSWR\b|\bHR\b'
    if re.search(de_pat, name, re.IGNORECASE):
        return "德国"
    if re.search(r'Germany|Deutschland', orig_group, re.IGNORECASE):
        return "德国"

    # France
    fr_pat = r'\bTF1\b|\bFrance\s*[2345]\b|\bM6\b|\bArte\b|\bBFM\b|\bCanalPlus\b|\bCanal\+\b'
    if re.search(fr_pat, name, re.IGNORECASE):
        return "法国"
    if re.search(r'\bFrance\b|Francia', orig_group, re.IGNORECASE):
        return "法国"

    # Italy
    it_pat = r'\bRAI\b|\bMediaset\b|\bCanale\s*5\b|\bItalia\b|\bLa7\b|\bRete\s*4\b'
    if re.search(it_pat, name, re.IGNORECASE):
        return "意大利"
    if re.search(r'\bItaly\b|\bItalia\b', orig_group, re.IGNORECASE):
        return "意大利"

    # Spain
    es_pat = r'\bAntena\s*3\b|\bTVE\b|\bLa\s*[12]\b|\bTelecinco\b|\bCuatro\b|\bLa\s*Sexta\b'
    if re.search(es_pat, name, re.IGNORECASE):
        return "西班牙"
    if re.search(r'\bSpain\b|\bEspa', orig_group, re.IGNORECASE):
        return "西班牙"

    # Netherlands
    nl_pat = r'\bNPO\b|\bRTL\s*[4578]\b|\bSBS\s*[69]\b|\bVeronica\b|\bNET\s*5\b'
    if re.search(nl_pat, name, re.IGNORECASE):
        return "荷兰"
    if re.search(r'Netherlands|Holland', orig_group, re.IGNORECASE):
        return "荷兰"

    # Nordic
    nordic_pat = r'\bSVT\b|\bNRK\b|\bDR[12]\b|\bYLE\b|\bTV\s*2\b.*(?:Norge|Denmark)'
    if re.search(nordic_pat, name, re.IGNORECASE):
        return "北欧"
    if re.search(r'Sweden|Norway|Denmark|Finland|Nordic', orig_group, re.IGNORECASE):
        return "北欧"

    # Poland
    if re.search(r'\bTVP\b|\bPolsat\b|\bTVN\b', name, re.IGNORECASE):
        return "波兰"
    if re.search(r'Poland|Polska', orig_group, re.IGNORECASE):
        return "波兰"

    # Russia
    if re.search(r'\bПервый\b|\bРоссия\b|\bНТВ\b|\bРЕН\b|\bОТР\b|\bТНТ\b|\bСТС\b|Channel\s*One\s*Russia', name, re.IGNORECASE):
        return "俄罗斯"
    if re.search(r'Russia|Россия', orig_group, re.IGNORECASE):
        return "俄罗斯"

    # Turkey
    if re.search(r'\bTRT\b|\bATV\b|\bShow\s*TV\b|\bStar\s*TV\b|\bKanal\s*D\b|\bFox\s*TR\b|\bTV8\b', name, re.IGNORECASE):
        return "土耳其"
    if re.search(r'Turkey|Türk', orig_group, re.IGNORECASE):
        return "土耳其"

    # Portugal
    if re.search(r'\bRTP\b|\bSIC\b|\bTVI\b', name, re.IGNORECASE):
        return "葡萄牙"
    if re.search(r'Portugal', orig_group, re.IGNORECASE):
        return "葡萄牙"

    # Greece
    if re.search(r'\bERT\b|\bSKAI\b|\bANT1\b|\bMEGA\b.*(?:Greece|GR)', name, re.IGNORECASE):
        return "希腊"
    if re.search(r'Greece|Ελλάδα', orig_group, re.IGNORECASE):
        return "希腊"

    # Romania
    if re.search(r'\bPRO\s*TV\b|\bAntena\s*[13]\b|\bRomania\b|\bDigi\b.*RO', name, re.IGNORECASE):
        return "罗马尼亚"
    if re.search(r'Romania', orig_group, re.IGNORECASE):
        return "罗马尼亚"

    # Ukraine
    if re.search(r'\b1\+1\b|\bInter\b.*UA|\bICTV\b|\bUkraine\b|\bSTB\b.*UA', name, re.IGNORECASE):
        return "乌克兰"
    if re.search(r'Ukraine|Україна', orig_group, re.IGNORECASE):
        return "乌克兰"

    # Japan
    if re.search(r'NHK|日本|テレビ|フジ|TBS.?JP|TV.?Tokyo|TV.?Asahi|Nippon|Fuji|Japan', name, re.IGNORECASE):
        return "日本"
    if re.search(r'Japan', orig_group, re.IGNORECASE):
        return "日本"

    # Korea
    if re.search(r'KBS|MBC|SBS|JTBC|YTN|MBN|TV조선|채널A|韩国|Korea|한국|아리랑', name, re.IGNORECASE):
        return "韩国"
    if re.search(r'Korea', orig_group, re.IGNORECASE):
        return "韩国"

    # South Asia
    if re.search(r'Zee|Star\s*Plus|Colors|Sony.*India|NDTV|DD\s*National|PTV|GEO|ARY|Hum\s*TV|BTV|NTV.*Bangla', name, re.IGNORECASE):
        return "南亚"
    if re.search(r'India|Pakistan|Bangladesh|Sri Lanka|Nepal', orig_group, re.IGNORECASE):
        return "南亚"

    # Southeast Asia
    sea_pat = (
        r'Thailand|Thai|ไทย|Vietnam|Viet|VTV|HTV|泰国|越南|'
        r'Philippines|GMA|ABS-CBN|菲律宾|Malaysia|Astro|RTM|马来|'
        r'Singapore|Channel.?NewsAsia|新加坡|Indonesia|TVRI|RCTI|SCTV|印尼|'
        r'Myanmar|Cambodia|Laos|缅甸|柬埔寨|老挝'
    )
    if re.search(sea_pat, name, re.IGNORECASE):
        return "东南亚"
    if re.search(r'Thailand|Vietnam|Philippines|Malaysia|Singapore|Indonesia|Myanmar|Cambodia|Laos|Southeast', orig_group, re.IGNORECASE):
        return "东南亚"

    # Middle East
    if re.search(r'Al\s*Jazeera|MBC\b.*Arab|\bAl\b.*TV|Saudi|Dubai|Abu\s*Dhabi|Rotana', name, re.IGNORECASE):
        return "中东"
    if re.search(r'Saudi|Egypt|Arab|Iraq|Kuwait|Qatar|Oman|Bahrain|Jordan|Lebanon|Syria|Palestine|Yemen|Libya|Tunisia|Algeria|Morocco|Middle East', orig_group, re.IGNORECASE):
        return "中东"

    # Latin America
    if re.search(r'Globo|Record|Band|Televisa|TV\s*Azteca|Caracol|RCN.*Colombia|TeleSUR|Canal\s*13.*Arg', name, re.IGNORECASE):
        return "拉美"
    if re.search(r'Brazil|Mexico|Argentina|Colombia|Chile|Peru|Venezuela|Latin|América|Latina', orig_group, re.IGNORECASE):
        return "拉美"

    # Canada
    if re.search(r'\bCBC\b|\bCTV\b|\bGlobal\s*TV\b|\bTSN\b.*CA|\bSportsnet\b', name, re.IGNORECASE):
        return "加拿大"
    if re.search(r'Canada', orig_group, re.IGNORECASE):
        return "加拿大"

    # Australia / NZ
    if re.search(r'\bABC\b.*(?:AU|Australia)|\bSBS\b.*AU|\bSeven\b|\bNine\b.*AU|\bTVNZ\b', name, re.IGNORECASE):
        return "澳新"
    if re.search(r'Australia|New Zealand', orig_group, re.IGNORECASE):
        return "澳新"

    # Africa
    if re.search(r'SABC|eNCA|DStv|SuperSport|NTA|KTN|Citizen\s*TV.*KE|KBC', name, re.IGNORECASE):
        return "非洲"
    if re.search(r'South Africa|Nigeria|Kenya|Ghana|Tanzania|Uganda|Africa', orig_group, re.IGNORECASE):
        return "非洲"

    # ── Source-tag fallback (country code from filename) ──
    if source_tag in COUNTRY_GROUP:
        return COUNTRY_GROUP[source_tag]
    # Regional specialists
    regional_map = {
        "regional_de": "德国", "regional_ru": "俄罗斯", "regional_my": "东南亚",
    }
    if source_tag in regional_map:
        return regional_map[source_tag]
    # FAST services – try to fall back to other patterns, else 其他
    # buddy / apsattv sources often have group-title with country names already handled above

    return "其他"


# ── Download step ────────────────────────────────────────────────────

def download_all():
    os.makedirs(SOURCES_DIR, exist_ok=True)
    downloaded = {}
    total = len(ALL_SOURCES)
    print(f"\nDownloading {total} sources...")
    for i, (tag, url) in enumerate(ALL_SOURCES.items(), 1):
        print(f"  [{i}/{total}] {tag}...", end=" ", flush=True)
        tag_out, path = download_source(tag, url, SOURCES_DIR)
        if path:
            size_kb = os.path.getsize(path) / 1024
            print(f"OK ({size_kb:.0f} KB)")
            downloaded[tag_out] = path
        # (skip message already printed by download_source on failure)
    print(f"\nDownloaded {len(downloaded)}/{total} sources successfully.")
    return downloaded


# ── Validation step ──────────────────────────────────────────────────

async def validate_url(session, url, sem):
    """Try HEAD then GET to check if URL is reachable."""
    async with sem:
        try:
            async with session.head(url, timeout=aiohttp.ClientTimeout(total=VALIDATE_TIMEOUT),
                                     allow_redirects=True, ssl=False) as resp:
                if resp.status < 400:
                    return True
        except Exception:
            pass
        try:
            async with session.get(url, timeout=aiohttp.ClientTimeout(total=VALIDATE_TIMEOUT),
                                    allow_redirects=True, ssl=False) as resp:
                if resp.status < 400:
                    await resp.content.read(1024)
                    return True
        except Exception:
            pass
    return False


async def validate_channels(channels):
    """Validate a list of channels concurrently. Returns list of valid ones."""
    if not channels:
        return []
    sem = asyncio.Semaphore(CONCURRENCY)
    connector = aiohttp.TCPConnector(limit=CONCURRENCY, ttl_dns_cache=300, ssl=False)
    async with aiohttp.ClientSession(connector=connector,
                                      headers={"User-Agent": "Mozilla/5.0"}) as session:
        tasks = [validate_url(session, ch["url"], sem) for ch in channels]
        results = await asyncio.gather(*tasks)
    valid = [ch for ch, ok in zip(channels, results) if ok]
    return valid


# ── Main pipeline ────────────────────────────────────────────────────

async def main():
    t0 = time.time()
    print("=" * 60)
    print("Global IPTV Merger — Download, Validate & Merge")
    print("=" * 60)

    # ── Step 1: Load existing playlist ──
    print(f"\nLoading existing playlist: {EXISTING_PLAYLIST}")
    existing_channels = parse_m3u(EXISTING_PLAYLIST, source_tag="existing")
    print(f"  Existing channels: {len(existing_channels)}")

    # Build set of existing normalized names + URLs for dedup
    existing_keys = set()
    existing_urls = set()
    for ch in existing_channels:
        existing_keys.add(normalize_name(ch["name"]))
        existing_urls.add(ch["url"])

    # ── Step 2: Download sources ──
    downloaded = download_all()

    # ── Step 3: Parse new sources ──
    print("\nParsing downloaded sources...")
    new_channels_by_source = {}
    for tag, path in downloaded.items():
        chs = parse_m3u(path, source_tag=tag)
        if chs:
            new_channels_by_source[tag] = chs
            print(f"  {tag}: {len(chs)} channels")

    total_new_raw = sum(len(v) for v in new_channels_by_source.values())
    print(f"Total new raw channels: {total_new_raw}")

    # ── Step 4: Classify new channels ──
    print("\nClassifying new channels...")
    new_all = []
    for tag, chs in new_channels_by_source.items():
        for ch in chs:
            # Check source group-title for Sport/News override
            og = ch["group_title"]
            if re.search(r'sport', og, re.IGNORECASE):
                ch["_forced_group"] = "体育"
            elif re.search(r'news', og, re.IGNORECASE):
                ch["_forced_group"] = "新闻"
            ch["_source_tag"] = tag
            new_all.append(ch)

    # ── Step 5: Deduplicate among new channels ──
    print("Deduplicating new channels...")
    new_dedup = {}
    for ch in new_all:
        nkey = normalize_name(ch["name"])
        if not nkey:
            continue
        if nkey in new_dedup:
            if metadata_score(ch) > metadata_score(new_dedup[nkey]):
                new_dedup[nkey] = ch
        else:
            new_dedup[nkey] = ch

    print(f"  Unique new channels after internal dedup: {len(new_dedup)}")

    # Remove channels that already exist in existing playlist
    truly_new = {}
    for nkey, ch in new_dedup.items():
        if nkey not in existing_keys and ch["url"] not in existing_urls:
            truly_new[nkey] = ch

    print(f"  Truly new channels (not in existing playlist): {len(truly_new)}")

    # ── Step 6: Validate new channels only ──
    to_validate = list(truly_new.values())
    print(f"\nValidating {len(to_validate)} new channels (concurrency={CONCURRENCY}, timeout={VALIDATE_TIMEOUT}s)...")
    vt0 = time.time()
    valid_new = await validate_channels(to_validate)
    vt1 = time.time()
    print(f"  Validation done in {vt1 - vt0:.1f}s")
    print(f"  Valid new channels: {len(valid_new)} / {len(to_validate)}")

    # ── Step 7: Merge existing + validated new ──
    print("\nMerging...")
    # Start with existing channels, preserving their groups
    merged = OrderedDict()
    for g in GROUP_ORDER:
        merged[g] = []

    # Add existing channels with their current group
    for ch in existing_channels:
        group = ch["group_title"]
        if group not in merged:
            group = "其他"
        merged[group].append(ch)

    # Add validated new channels with classified groups
    added_count = 0
    for ch in valid_new:
        forced = ch.pop("_forced_group", None)
        source_tag = ch.pop("_source_tag", "")
        if forced:
            group = forced
        else:
            group = classify_channel(ch, source_tag=source_tag)
        if group not in merged:
            group = "其他"
        ch["assigned_group"] = group
        merged[group].append(ch)
        added_count += 1

    # Sort within each group
    for g in merged:
        merged[g].sort(key=lambda c: c["name"])

    # ── Step 8: Write output ──
    print(f"\nWriting merged playlist to {OUTPUT_FILE}...")
    total_written = 0
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        f.write(f'#EXTM3U x-tvg-url="{EPG_URL}"\n')
        for group_name in GROUP_ORDER:
            channels = merged.get(group_name, [])
            for ch in channels:
                attrs = '#EXTINF:-1'
                if ch.get("tvg_id") or ch.get("tvg_id", "") != "":
                    tid = ch.get("tvg_id", "")
                    if tid:
                        attrs += f' tvg-id="{tid}"'
                tn = ch.get("tvg_name", "")
                if tn:
                    attrs += f' tvg-name="{tn}"'
                tl = ch.get("tvg_logo", "")
                if tl:
                    attrs += f' tvg-logo="{tl}"'
                attrs += f' group-title="{group_name}"'
                attrs += f',{ch["name"]}\n'
                f.write(attrs)
                f.write(ch["url"] + "\n")
                total_written += 1

    # ── Step 9: Statistics ──
    t1 = time.time()
    print("\n" + "=" * 60)
    print("MERGE STATISTICS")
    print("=" * 60)
    print(f"{'Group':<12} {'Count':>6}")
    print("-" * 20)
    for g in GROUP_ORDER:
        count = len(merged.get(g, []))
        if count > 0:
            print(f"  {g:<10} {count:>6}")
    print("-" * 20)
    print(f"  {'TOTAL':<10} {total_written:>6}")
    print(f"\n  Existing channels kept: {len(existing_channels)}")
    print(f"  New channels added:     {added_count}")
    print(f"  Total in playlist:      {total_written}")
    print(f"  File size:              {os.path.getsize(OUTPUT_FILE) / 1024:.1f} KB")
    print(f"  Elapsed time:           {t1 - t0:.1f}s")
    print("=" * 60)


if __name__ == "__main__":
    asyncio.run(main())
