#!/usr/bin/env bash
# CF 全球边缘节点 一键自动部署(通用 Agent 版)
# 用户唯一要做的事:在弹出的浏览器里登录 Cloudflare 并点"Allow"(含验证码/2FA)。
# 其余全部由本脚本完成。所有密钥/订阅只写进 $WORK(包外目录),绝不写进本仓库。
# 可选环境变量:NAME(默认 edge-node) DOMAIN(已在CF激活的域名的子域,如 edge-node.<YOUR_DOMAIN>)
#               REGION(优选地区国家码,如 US/JP/SG/HK,默认不筛) PREFERRED(1=写入优选IP,默认1)
# v4:          HEAL(1=开启 Cron 自愈,默认1) HEAL_CRON(默认 "*/20 * * * *")
#               UPGRADE=1 + NAME=<已有Worker名>:原地升级老节点(同 Worker/同 KV/同 UUID → 订阅链接不变)
set -euo pipefail
PKG="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK:-$HOME/cf-edge-work}"; NAME="${NAME:-edge-node}"; DOMAIN="${DOMAIN:-}"
REGION="${REGION:-}"; PREFERRED="${PREFERRED:-1}"
HEAL="${HEAL:-1}"; HEAL_CRON="${HEAL_CRON:-*/20 * * * *}"; UPGRADE="${UPGRADE:-0}"
PIN=66f1c51c4ecee058b959104cb0517e073cdb1213
SHA=1e84d11af0544654bf56a06fa833e77184a57193288a9ffccf62c031a9fb7d65
WR="npx -y wrangler@4"
mkdir -p "$WORK"; chmod 700 "$WORK"; cd "$WORK"
say(){ printf '\n== %s\n' "$*"; }
# 账号 API 帮助函数(用 wrangler 的登录态拿 token;不打印 token)
acct_id(){ $WR whoami 2>/dev/null | grep -oE '[0-9a-f]{32}' | head -1; }
cf_api(){ local tok; tok=$($WR auth token 2>/dev/null | tail -1); curl -fsS -X "$1" -H "Authorization: Bearer $tok" "https://api.cloudflare.com/client/v4/accounts/${ACCT:=$(acct_id)}$2"; }
# 不依赖 `wrangler deployments list --name`(各版本参数不一致):直接查脚本是否存在
worker_exists(){ cf_api GET "/workers/scripts/$1/settings" >/dev/null 2>&1; }

say "1/9 下载并校验上游 edgetunnel(钉版 $PIN)"
[ -f _worker.js ] || curl -fsSL -o _worker.js "https://raw.githubusercontent.com/KUAILESHANGWEI/edge-skill/main/vendor/edgetunnel/_worker.js"
echo "$SHA  _worker.js" | sha256sum -c - || { echo "校验失败,停止。不要部署来路不明的代码。"; exit 1; }

say "2/9 登录 Cloudflare(只需用户在浏览器点登录/Allow)"
$WR whoami 2>/dev/null | grep -qi "associated with the email\|Account ID" || $WR login
$WR whoami >/dev/null

say "3/9 起名(撞名自动加数字,绝不覆盖已有 Worker)"
if [ "$UPGRADE" = "1" ]; then
  worker_exists "$NAME" || { echo "UPGRADE=1 但找不到 Worker $NAME,停止"; exit 1; }
  echo "升级模式:沿用已有 Worker(不改名、不换 UUID)"
  say "3b/9 升级前备份(回滚用):脚本 + KV 关键键 → $WORK/backup-$NAME-$(date +%Y%m%d%H%M%S)"
  BK="$WORK/backup-$NAME-$(date +%Y%m%d%H%M%S)"; mkdir -p "$BK"; chmod 700 "$BK"
  cf_api GET "/workers/scripts/$NAME/content/v2" > "$BK/script.multipart" || { echo "脚本备份失败,停止(不在没有回滚点时升级)"; exit 1; }
  cf_api GET "/workers/scripts/$NAME/settings" > "$BK/settings.json" || true
  cf_api GET "/workers/scripts/$NAME/schedules" > "$BK/schedules.json" || true
  [ -s "$BK/script.multipart" ] || { echo "脚本备份为空,停止"; exit 1; }
  echo "备份完成: $BK(回滚:Dashboard → Worker → 部署 → 回滚到上一个版本,或用 settings.json 里的 KV id 恢复 ADD.txt)"
else
  base="$NAME"; i=1
  while worker_exists "$NAME"; do i=$((i+1)); NAME="$base$i"; done
fi
echo "Worker 名: $NAME"

say "4/9 建 KV(已存在同名则复用,幂等;升级模式用线上 Worker 实际绑定的 KV)"
KVID=""
if [ "$UPGRADE" = "1" ]; then
  KVID=$(cf_api GET "/workers/scripts/$NAME/settings" | python3 -c 'import sys,json
b=json.load(sys.stdin)["result"]["bindings"]; k=[x["namespace_id"] for x in b if x.get("type")=="kv_namespace" and x.get("name")=="KV"]
print(k[0] if len(k)==1 else "")')
  [ -n "$KVID" ] || { echo "升级模式:线上 Worker 没有名为 KV 的 KV 绑定,停止(不新建空 KV)"; exit 1; }
  echo "沿用线上 KV: $KVID"
fi
[ -n "$KVID" ] || KVID=$($WR kv namespace list 2>/dev/null | python3 -c 'import sys,json
try: L=json.load(sys.stdin)
except Exception: L=[]
print(next((x["id"] for x in L if x.get("title")==sys.argv[1]),""))' "$NAME-kv" || true)
[ -n "$KVID" ] || KVID=$($WR kv namespace create "$NAME-kv" 2>&1 | grep -oE '[0-9a-f]{32}' | head -1)
[ -n "$KVID" ] || { echo "KV 创建失败"; exit 1; }

say "5/9 自动生成 UUID 与面板密码(只存本机 $WORK/SECRETS.local.json)"
if [ "$UPGRADE" = "1" ] && [ ! -f SECRETS.local.json ]; then
  echo "升级模式:本机没有 SECRETS.local.json → 不生成新 UUID、不改密钥(线上 UUID 保持原样,订阅不变)"; KEEP_SECRETS=1; fi
[ -n "${KEEP_SECRETS:-}" ] || [ -f SECRETS.local.json ] || python3 - <<'PY'
import json,uuid,secrets,os
json.dump({"ADMIN":secrets.token_urlsafe(18),"UUID":str(uuid.uuid4())},open("SECRETS.local.json","w"))
os.chmod("SECRETS.local.json",0o600)
PY

MAIN=_worker.js
if [ "$HEAL" = "1" ]; then cp "$PKG/templates/heal_entry.js" heal_entry.js; MAIN=heal_entry.js; fi
write_toml(){ cat > wrangler.toml <<T
name = "$NAME"
main = "$MAIN"
compatibility_date = "2026-10-08"
compatibility_flags = ["nodejs_compat"]
workers_dev = true
keep_vars = true
[[kv_namespaces]]
binding = "KV"
id = "$KVID"
T
[ -n "${1:-}" ] && printf '[vars]\nHOST = "%s"\n' "$1" >> wrangler.toml
[ -n "$REGION" ] && [ -n "${1:-}" ] && printf 'HEAL_REGION = "%s"\n' "$REGION" >> wrangler.toml
[ "$HEAL" = "1" ] && printf '[triggers]\ncrons = ["%s"]\n' "$HEAL_CRON" >> wrangler.toml
[ -n "$DOMAIN" ] && printf '[[routes]]\npattern = "%s"\ncustom_domain = true\n' "$DOMAIN" >> wrangler.toml
true; }

say "6/9 部署(先部署拿到地址,再写 HOST 重新部署)"
write_toml ""
OUT=$($WR deploy 2>&1 | tee deploy.log)
WD=$(echo "$OUT" | grep -oE "https://$NAME\.[a-z0-9-]+\.workers\.dev" | head -1 | sed 's#https://##')
HOST="${DOMAIN:-$WD}"; [ -n "$HOST" ] || { echo "没拿到地址,看 deploy.log"; exit 1; }
write_toml "$HOST"; $WR deploy >>deploy.log 2>&1
[ -n "${KEEP_SECRETS:-}" ] || $WR secret bulk SECRETS.local.json >>deploy.log 2>&1
echo "HOST=$HOST"

if [ -n "${KEEP_SECRETS:-}" ]; then
  echo "升级完成:订阅链接与之前完全相同(HOST+UUID 未变),小火箭里点「更新订阅」即可。单节点链接用户才需重扫。"
  PREFERRED_ONLY=1; fi
say "7/9 自验:面板与订阅"
sleep 8
if [ -z "${PREFERRED_ONLY:-}" ]; then
code=$(curl -s -o /dev/null -w '%{http_code}' "https://$HOST/login" || true)
echo "/login -> $code"
if [ "$code" != "200" ]; then
  echo "面板不是200。若是1101/500:按 SKILL.md 排障表,删掉这个新建的 Worker 后重建,并改用 Dashboard 加 ADMIN/UUID 密钥。停止。"; exit 2; fi
TOKEN=$(python3 - "$HOST" <<'PY'
import json,sys,hashlib
u=json.load(open("SECRETS.local.json"))["UUID"].lower(); h=sys.argv[1]
m=lambda s:hashlib.md5(s.encode()).hexdigest()
print(m(m(h+u)[7:27]))
PY
)
SUB="https://$HOST/sub?token=$TOKEN"; echo "$SUB" > sub-url.txt; chmod 600 sub-url.txt
curl -s -A v2rayN "$SUB" -o sub.b64
python3 - "$HOST" <<'PY'
import base64,sys,json
d=base64.b64decode(open("sub.b64").read().strip()).decode()
u=json.load(open("SECRETS.local.json"))["UUID"].lower()
L=[l for l in d.splitlines() if l.startswith("vless://")]
assert L and u in d and sys.argv[1] in d, "订阅解码不对:UUID/HOST 不匹配"
print("订阅OK,节点数",len(L))
PY
fi

if [ "$PREFERRED" = "1" ]; then
say "8/9 优选IP:拉社区清单→按地区筛→TLS探活→冻结≤10个写入KV"
python3 - "$REGION" <<'PY' > ADD.txt || true
import sys,re,socket,ssl,urllib.request
reg=sys.argv[1].upper()
src=["https://raw.githubusercontent.com/LancelotRar/best-cf-ips/main/best-cf-ip-scanned-top20.txt",
     "https://raw.githubusercontent.com/joname1/BestCFip/main/ipv4.txt"]
cand=[]
for s in src:
    try: t=urllib.request.urlopen(s,timeout=15).read().decode("utf-8","ignore")
    except Exception: continue
    for line in t.splitlines():
        m=re.match(r"\s*(\d+\.\d+\.\d+\.\d+)(?::(\d+))?(?:#(.*))?",line)
        if not m: continue
        lab=(m.group(3) or "CF").strip()
        if reg and reg not in lab.upper(): continue
        cand.append((m.group(1),int(m.group(2) or 443),lab))
    if cand: break
open("POOL.txt","w").write("\n".join(f"{i}:{p}#{l}" for i,p,l in cand[:200]))
ok=[]; ctx=ssl.create_default_context()
for ip,p,lab in cand[:40]:
    try:
        with socket.create_connection((ip,p),timeout=4) as s, ctx.wrap_socket(s,server_hostname="www.cloudflare.com"):
            ok.append(f"{ip}:{p}#{lab}")
    except Exception: pass
    if len(ok)>=10: break
print("\n".join(ok))
PY
# v4.1:候选池优先放"可测"的第三方反代IP —— 用 SNI=HOST 做 TLS 握手,证书确是本节点的才收
: > POOL.relay.txt
# v4.2 CF_ONLY=1(默认):不用第三方反代IP。反代运营者能看到你的源IP、目标和流量时间;想要更多可测节点再设 CF_ONLY=0
[ "${CF_ONLY:-1}" = "0" ] && python3 - "$HOST" <<'PY2' > POOL.relay.txt || true
import sys,re,subprocess,urllib.request,concurrent.futures as cf
host=sys.argv[1]; L=[]
for s in ["https://raw.githubusercontent.com/cmliu/WorkerVless2sub/main/addressesapi.txt",
          "https://raw.githubusercontent.com/ymyuuu/IPDB/main/bestproxy.txt",
          "https://raw.githubusercontent.com/ymyuuu/IPDB/main/proxy.txt"]:
    try: t=urllib.request.urlopen(s,timeout=15).read().decode("utf-8","ignore")
    except Exception: continue
    for l in t.splitlines()[:80]:
        m=re.match(r"\s*(\d+\.\d+\.\d+\.\d+)(?::(\d+))?(?:#(.*))?",l)
        if m: L.append((m[1],int(m[2] or 443),(m[3] or "PROXY").strip()))
def ok(e):
    try:
        o=subprocess.run(["timeout","6","openssl","s_client","-connect",f"{e[0]}:{e[1]}","-servername",host],input="",capture_output=True,text=True).stdout
        return e if host.split(".",1)[-1] in o else None
    except Exception: return None
with cf.ThreadPoolExecutor(20) as x: R=[e for e in x.map(ok,L) if e]
print("\n".join(f"{i}:{p}#{l}" for i,p,l in R[:100]))
PY2
if [ -s POOL.relay.txt ]; then cat POOL.relay.txt POOL.txt 2>/dev/null > POOL.new && mv POOL.new POOL.txt; echo "候选池:$(wc -l < POOL.relay.txt) 个已验证反代IP + CF官方兜底"; fi
# v4.2:混合端口。给前 3 个 CF 官方 IP 各加一个 2053/8443/2083 变体(CF 免费版支持的 HTTPS 端口;域名条目在非 443 端口实测不通,只加 IP)
if [ -s ADD.txt ] && [ "${MIX_PORTS:-1}" = "1" ]; then
  python3 - <<'PY2'
import re
L=[l for l in open("ADD.txt").read().splitlines() if l.strip()]
ips=[l.split(":")[0] for l in L if re.match(r"\d+\.\d+\.\d+\.\d+:443#",l)][:3]
extra=[f"{ip}:{p}#CF-{p}" for ip,p in zip(ips,[2053,8443,2083])]
open("ADD.txt","w").write("\n".join(L+extra))
PY2
fi
# v4.2:用户已置顶(PINNED.txt 非空)时,升级不覆盖 ADD.txt —— 置顶条目是在用户真实网络里验证过的
PINNED_NOW=$($WR kv key get --namespace-id "$KVID" PINNED.txt --remote 2>/dev/null | grep -c ':' || true)
if [ "${PINNED_NOW:-0}" -gt 0 ] && [ "$UPGRADE" = "1" ]; then echo "检测到 $PINNED_NOW 条置顶节点,保留现有 ADD.txt"; : > ADD.txt; fi
if [ -s ADD.txt ]; then
  $WR kv key put --namespace-id "$KVID" ADD.txt --path ADD.txt --remote >/dev/null
  [ -s POOL.txt ] && $WR kv key put --namespace-id "$KVID" POOL.txt --path POOL.txt --remote >/dev/null
  echo "已写入 $(wc -l < ADD.txt) 个优选IP(本机探活;不等于用户运营商实测)"
else echo "没筛到可用优选IP,保持默认随机模式(能用,但节点会变)"; fi
# 配置调优(0-RTT/分片/固定IP库)不论是否写 ADD.txt 都做
$WR kv key get --namespace-id "$KVID" config.json --remote > config.json
python3 - <<'PY'
import json
c=json.load(open("config.json")); c["优选订阅生成"]["本地IP库"]["随机IP"]=False
import os
if os.environ.get("CN_TUNE","1")=="1":   # v4.2 默认:上游原生选项 0-RTT(path 带 ?ed=2560) + 小火箭 TLS 分片;中国移动 5G 实测必需
  c["启用0RTT"]=True; c["TLS分片"]="Shadowrocket"
json.dump(c,open("config.json","w"),ensure_ascii=False)
PY
$WR kv key put --namespace-id "$KVID" config.json --path config.json --remote >/dev/null
fi

[ "$HEAL" = "1" ] && echo "自愈已开:Cron \"$HEAL_CRON\" 每次探测 ADD.txt,坏的从 POOL.txt 补。查看: https://$HOST/heal-status?key=<你的UUID>"
[ -n "${PREFERRED_ONLY:-}" ] && exit 0
say "9/9 生成订阅二维码并解码校验"
[ -x .venv/bin/python ] || { python3 -m venv .venv && .venv/bin/pip -q install "qrcode[pil]" opencv-python-headless; }
SUB_URL="$SUB" .venv/bin/python "$PKG/templates/make_sub_qr.py" --output "$WORK/cf-subscription-qr.png"
cat <<R

完成。交付物(都在 $WORK,属于凭据,别公开):
  订阅链接: $WORK/sub-url.txt
  二维码:   $WORK/cf-subscription-qr.png
  面板:     https://$HOST/admin  (密码在 SECRETS.local.json 的 ADMIN)
$( [ -z "$DOMAIN" ] && echo "  注意: 用的是 workers.dev。大陆网络常见全部节点握手超时;超时就给我一个已在CF激活的域名,我绑子域名重发。")
R
