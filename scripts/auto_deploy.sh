#!/usr/bin/env bash
# CF 全球边缘节点 一键自动部署(通用 Agent 版)
# 用户唯一要做的事:在弹出的浏览器里登录 Cloudflare 并点"Allow"(含验证码/2FA)。
# 其余全部由本脚本完成。所有密钥/订阅只写进 $WORK(包外目录),绝不写进本仓库。
# 可选环境变量:NAME(默认 edge-node) DOMAIN(已在CF激活的域名的子域,如 edge-node.<YOUR_DOMAIN>)
#               REGION(优选地区国家码,如 US/JP/SG/HK,默认不筛) PREFERRED(1=写入优选IP,默认1)
set -euo pipefail
PKG="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK:-$HOME/cf-edge-work}"; NAME="${NAME:-edge-node}"; DOMAIN="${DOMAIN:-}"
REGION="${REGION:-}"; PREFERRED="${PREFERRED:-1}"
PIN=66f1c51c4ecee058b959104cb0517e073cdb1213
SHA=1e84d11af0544654bf56a06fa833e77184a57193288a9ffccf62c031a9fb7d65
WR="npx -y wrangler@4"
mkdir -p "$WORK"; chmod 700 "$WORK"; cd "$WORK"
say(){ printf '\n== %s\n' "$*"; }

say "1/9 下载并校验上游 edgetunnel(钉版 $PIN)"
[ -f _worker.js ] || curl -fsSL -o _worker.js "https://raw.githubusercontent.com/cmliu/edgetunnel/$PIN/_worker.js"
echo "$SHA  _worker.js" | sha256sum -c - || { echo "校验失败,停止。不要部署来路不明的代码。"; exit 1; }

say "2/9 登录 Cloudflare(只需用户在浏览器点登录/Allow)"
$WR whoami 2>/dev/null | grep -qi "associated with the email\|Account ID" || $WR login
$WR whoami >/dev/null

say "3/9 起名(撞名自动加数字,绝不覆盖已有 Worker)"
base="$NAME"; i=1
while $WR deployments list --name "$NAME" >/dev/null 2>&1; do i=$((i+1)); NAME="$base$i"; done
echo "Worker 名: $NAME"

say "4/9 建 KV"
KVID=$($WR kv namespace create "$NAME-kv" 2>&1 | grep -oE '[0-9a-f]{32}' | head -1)
[ -n "$KVID" ] || { echo "KV 创建失败"; exit 1; }

say "5/9 自动生成 UUID 与面板密码(只存本机 $WORK/SECRETS.local.json)"
[ -f SECRETS.local.json ] || python3 - <<'PY'
import json,uuid,secrets,os
json.dump({"ADMIN":secrets.token_urlsafe(18),"UUID":str(uuid.uuid4())},open("SECRETS.local.json","w"))
os.chmod("SECRETS.local.json",0o600)
PY

write_toml(){ cat > wrangler.toml <<T
name = "$NAME"
main = "_worker.js"
compatibility_date = "2026-10-08"
compatibility_flags = ["nodejs_compat"]
workers_dev = true
keep_vars = true
[[kv_namespaces]]
binding = "KV"
id = "$KVID"
T
[ -n "${1:-}" ] && printf '[vars]\nHOST = "%s"\n' "$1" >> wrangler.toml
[ -n "$DOMAIN" ] && printf '[[routes]]\npattern = "%s"\ncustom_domain = true\n' "$DOMAIN" >> wrangler.toml
true; }

say "6/9 部署(先部署拿到地址,再写 HOST 重新部署)"
write_toml ""
OUT=$($WR deploy 2>&1 | tee deploy.log)
WD=$(echo "$OUT" | grep -oE "https://$NAME\.[a-z0-9-]+\.workers\.dev" | head -1 | sed 's#https://##')
HOST="${DOMAIN:-$WD}"; [ -n "$HOST" ] || { echo "没拿到地址,看 deploy.log"; exit 1; }
write_toml "$HOST"; $WR deploy >>deploy.log 2>&1
$WR secret bulk SECRETS.local.json >>deploy.log 2>&1
echo "HOST=$HOST"

say "7/9 自验:面板与订阅"
sleep 8
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
ok=[]; ctx=ssl.create_default_context()
for ip,p,lab in cand[:40]:
    try:
        with socket.create_connection((ip,p),timeout=4) as s, ctx.wrap_socket(s,server_hostname="www.cloudflare.com"):
            ok.append(f"{ip}:{p}#{lab}")
    except Exception: pass
    if len(ok)>=10: break
print("\n".join(ok))
PY
if [ -s ADD.txt ]; then
  $WR kv key put --namespace-id "$KVID" ADD.txt --path ADD.txt --remote >/dev/null
  $WR kv key get --namespace-id "$KVID" config.json --remote > config.json
  python3 - <<'PY'
import json
c=json.load(open("config.json")); c["优选订阅生成"]["本地IP库"]["随机IP"]=False
json.dump(c,open("config.json","w"),ensure_ascii=False)
PY
  $WR kv key put --namespace-id "$KVID" config.json --path config.json --remote >/dev/null
  echo "已写入 $(wc -l < ADD.txt) 个优选IP(本机探活;不等于用户运营商实测)"
else echo "没筛到可用优选IP,保持默认随机模式(能用,但节点会变)"; fi
fi

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
