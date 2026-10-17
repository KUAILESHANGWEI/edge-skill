---
name: cf-global-edge-node
description: "Use when someone wants to build their own Cloudflare global edge node / CF-based proxy node from scratch, deploy an edgetunnel-style Worker or Pages node, configure KV preferred IPs (ADD.txt), produce a real subscription URL and scannable subscription QR code, import it into Shadowrocket, Clash, sing-box or v2rayN, or troubleshoot a CF node that connects but has no traffic, wrong region, or dead preferred IPs."
---

# CF Global Edge Node (Workers/Pages + KV Preferred IPs)

Build a personal Cloudflare edge node: a single-file Worker (edgetunnel, `_worker.js`) on Cloudflare Workers or Pages, backed by a KV namespace storing config and a preferred-IP list (`ADD.txt`). Clients import the generated subscription and connect to Cloudflare edge entry IPs. Exit is Cloudflare Workers egress, not a residential exit and not a VPS.

Goal state: the operator ends with (1) an admin panel URL they can log into, (2) a real subscription URL built exactly as the code builds it, (3) a scannable QR code image of that subscription URL, (4) at least one client that connected end-to-end. If any operator input below is missing, stop at the gate and ask. Do not invent accounts, domains, passwords, UUIDs, tokens, or results.

## 0. Pre-flight gate (STOP and ask if anything is missing)

Collect every item before touching Cloudflare. If an item is missing, output the missing list and stop. Do not proceed on assumptions, and never log into an account the operator did not explicitly hand over in this session.

| # | Operator input | Accepted forms | If missing |
|---|---|---|---|
| 1 | Cloudflare login method | "dashboard" (operator logs in in their browser and confirms) OR "api" (operator provides a scoped API token and account ID for Wrangler in this session) | STOP and ask which method |
| 2 | Worker name | e.g. `edge-node` (lowercase letters, digits, hyphens) | STOP and ask |
| 3 | Public hostname decision | (a) custom subdomain on an active Cloudflare zone, placeholder `node.<YOUR_DOMAIN>`, or (b) explicit decision to start on `workers.dev`: `https://<WORKER_NAME>.<YOUR_SUBDOMAIN>.workers.dev` (account subdomain must be supplied) | STOP and ask which |
| 4 | `ADMIN` password | Operator-chosen strong unique password, supplied in session, never stored in this package | STOP and ask operator to choose one |
| 5 | UUID choice | "generate for me" (run `uuidgen`, show it once, treat as secret) or operator-supplied valid UUIDv4 | STOP and ask |
| 6 | Client target | Shadowrocket / Clash / sing-box / v2rayN (pick at least one for the first test) | Ask; default suggestion is Shadowrocket only if operator confirms |

Gate rule: after listing what is present and missing, wait. Work allowed before the gate passes is non-mutating preparation only: downloading and checksum-verifying `_worker.js` (Section 2), generating a UUID if the operator asked, and the Parallel preheat in Section 2A (fetch preferred-IP community list, pre-probe default-region candidates). Never deploy, bind a domain, write KV, or register anything before the gate passes and, for domain registration, before the operator's explicit final say at the 确认点.

Route-priority rule (fastest first, details in Sections 3.4 and 6): **A** domain zone already Active on Cloudflare -> bind Worker Custom Domain by API/Wrangler, minutes, no NS wait. **B** domain at another registrar/DNSHE where the operator can edit DNS -> deploy via Pages + external CNAME subdomain, skipping whole-zone NS activation (apex/root excluded). **C** new/moved domain via NS change to Cloudflare -> slowest, wait for zone Active (15-min / 2-hour rule in Section 9). Always try A before B before C when facts allow; never present C's waiting as the only route when A or B is available.


## 0A. Beginner wizard (default mode for non-technical operators)

If the operator is non-technical, do NOT hand them Section 6 to execute. Run this dialogue instead: one question at a time, plain language, wait for the answer, validate format, then YOU do the work (API/Wrangler/dashboard actions available to you). The operator should only need to: register or log in, paste back a few values, pick a region, and scan a QR code at the end. Never ask the operator to "deploy", edit code, or run commands.

Mandatory-or-optional facts to state in plain Chinese at the start (verified 2026-10-17):

- "Cloudflare 账号:必须要。这是整套东西的地基,没有账号就没有 Worker 和 KV,搭不了。注册免费。"
- "域名:不必须,但有就优先用。你已经有绑在 Cloudflare 上的域名,我们就优先绑一个新子域名当正式地址;没有域名也可以先用 Cloudflare 免费送的 workers.dev 地址部署,但要先说清:workers.dev 在中国大陆网络上常见整批节点在 TLS/WS 握手阶段超时(面板和订阅在浏览器里能打开不代表节点能连),这时不要承诺能用,按排障步骤绑自定义域名再重发订阅。"
- No-domain route (Branch D, see below): if the operator has no domain, offer the free-domain onboarding at [DNSHE](https://my.dnshe.com/clientarea.php?language=chinese&autolang=1) as one option — free domains there exist in different terms: some are 1-year (renew free within 180 days before expiry), some are 10-year. 该站有不同年限，优先选10年期；若只有1年期，老实告知续期规则：到期前180天内免费续 (以站点当期规则为准; never promise a term you have not seen on the live site in this session; verify on live site, labels/terms may change). Agent-driven model: the deploying Agent opens ITS OWN cloud/browser environment and performs the Cloudflare and DNSHE registration flows itself (navigates, fills forms, searches domain availability, submits, changes nameservers, binds the Worker Custom Domain, polls DNS activation) — the operator does NOT do these steps in their own browser. The operator's only jobs are the 确认点 pauses in D2/D3: (1) authorize/confirm login state when the Agent presents a login/session that needs them (e.g. approve a Google sign-in prompt, confirm '已登录'), (2) complete human-only checks the Agent cannot do (captcha/人机验证, 2FA/OTP), and (3) explicit confirm before final registration of the exact domain ('好，注册 <DOMAIN>'). Never require buying anything, and never promise the free route is available today unless you verified it on the live site in this session.

Wizard speed rules (do not renumber the 6 steps):
- Parallel preheat (Section 2A): while the operator is answering W1-W7, run the background preparation in Section 2A so deployment starts instantly after the gate. Tell the operator once, in plain Chinese: "你答题这会儿，我后台先把程序和优选清单准备好，这样不耽误时间。" Do not let preheat delay a question, and never use a preheat result as a delivered node without Section 7/9 verification and the operator's region final say (Section 0B).
- Fast route first: when you reach route choice, check A (zone already Active on Cloudflare) before B (Pages + external CNAME) before C (NS move, slowest). See Sections 3.4/6. This is a backend choice you make from account facts, not an extra wizard step.

Wizard steps (ask exactly one at a time; scripts in Chinese you can copy):

Before W1, you MUST send the operator ONE heads-up card first, as a single message, before asking anything else. Use this card verbatim (fill nothing in):

```text
先花30秒看完, 然后我们一步一步来:
一共6步, 每步我只问一句, 你回一句就行, 部署的活我来做, 不用你动手。
必需: 一个免费的 Cloudflare 账号。没有的话先用邮箱注册, 有的话登录就行。
不必需: 域名。有绑在 Cloudflare 上的域名优先用它当正式地址; 没有就先用 workers.dev 免费地址, 但大陆网络下它常见整批节点超时, 能部署不等于手机一定能连, 到时绑域名重发订阅再测。
你要准备: 能注册或登录的邮箱, 想一个面板密码, 选一个想要的国家或地区, 最后用手机客户端扫码。
全程你只做四件事: 1) 注册或登录, 2) 回数字或贴回我需要的值, 3) 选国家或地区, 4) 最后扫码验收。
预计耗时: 通常几分钟到十几分钟, 这是估计, 主要取决于注册、登录验证和你的回复速度, 不保证固定时间。
说明: 我只能尽量把入口偏向你选的国家或地区, 不能承诺任意国家的IP, 最后以实测出口为准, 你点头才算定。
```

Progress prefix rule (mandatory): every wizard question must start with "第X/6步". Mapping is fixed: W1 = 第1/6步, W2 = 第2/6步, W3 = 第3/6步, W4 = 第4/6步, W6 = 第5/6步, W7 (region, Section 0B) = 第6/6步(选地区). W5 UUID is NOT a step and gets no number: it is an auto-generated item, mentioned only as a note inside 第5/6步 before the client question (see W5 below). Follow-up questions inside the same W item keep the same prefix. Work you execute after the wizard (deploy, verify, QR) is not numbered as a wizard step.

Compact 3-step summary variant: if the operator says "太长" or "简单点", you may compress the presentation into three dialogue beats: (1) CF账号好了吗 + 用免费地址还是域名, (2) 密码 + 客户端 + 想要的国家, (3) 扫码验收. This compression is presentation only: inside each beat you must still ask, wait for, and validate every gate item in Sections 0, 0A and 0B in order (login method, route and any hostname value, Worker name confirmation, ADMIN length, UUID auto-generation notice, client target, region choice and operator acceptance). Never skip a question, a format check, or the region acceptance loop just because the beats are grouped. If an answer is missing or invalid, stay in that beat and ask again with the same 第X/6步 prefix.


- W1 Account. Ask: "第1/6步: 你有 Cloudflare 账号吗?没有的话,打开 dash.cloudflare.com 注册一个(邮箱+密码就行,免费),注册好回我一句 好了 。" Wait. If they have one: "第1/6步: 好,你先在浏览器登录 dash.cloudflare.com,登录好回我 好了 。" You cannot click their browser for them unless a logged-in connector/tool is already available in session; if an API token / MCP connector is already authorized for their account in this session, say so and use it, otherwise ask them to either (a) confirm the browser is logged in and tell you, for dashboard-guided steps, or (b) create a scoped API token (Workers/KV edit, this account only) and paste it. Validate: token paste must not be echoed back in full by you; store it only as a credential, never in files that ship.
- W2 Route choice. Ask: "第2/6步: 用哪种地址?你有已经绑在 Cloudflare 上的域名就回 2(优先,正式地址用你的子域名);没有域名但想先零成本部署回 1(免费地址,形如 edge-node.你的账号.workers.dev,但大陆网络下常见整批节点握手超时,我不能先承诺手机能连);没域名、又想要个正式域名回 3,我带你走免费域名子分支(第2/6步的子分支 D1-D4,不占新步数)。回 1、2 或 3。" If 2, ask for the root domain only, validate it is a plausible hostname and (when you have account access) that an active zone with that name exists; then this is Route A (Section 3.4): pick a fresh subdomain together (suggest `edge-node.<ROOT>`, check no DNS record and no Worker domain already uses it; if conflict, suggest `edge-node2`, never overwrite) and bind by API/Wrangler Custom Domain, no NS wait. If their domain is NOT on Cloudflare but they can edit DNS where it is registered, choose Route B instead (Pages + external CNAME subdomain, Section 3.4): explain in plain Chinese it is faster because it skips moving the whole domain, apex/root cannot be used, and a conflicting record means picking another subdomain name, never overwriting. If 1, the hostname is decided after W3: `https://<WORKER_NAME>.<ACCOUNT_SUBDOMAIN>.workers.dev`; ask for nothing more, and record that the workers.dev timeout risk was stated to the operator before delivery. If 3, run Branch D below (D1-D4, all still prefixed 第2/6步) BEFORE deploying — inside D4 try Route B first, Route C only if B is impossible — then continue to W3 with the resulting hostname.
- W3 Worker name. Auto-suggest, do not make them invent: "第3/6步: 我给这个空间起名叫 edge-node,可以吗?想要别的名字回我一个小写英文名。" Validate: lowercase letters/digits/hyphens only, and (with account access) not already taken; on conflict append a digit and re-confirm. Never reuse an existing Worker name.
- W4 ADMIN password. Ask: "第4/6步: 给管理面板想一个密码:至少 12 位,别用你其他地方用过的。现在发我,我只存进本机密钥文件和 Cloudflare 密钥里,不会写进教程或仓库。" Validate length >= 12 (reject shorter, ask again). Never echo it back in full, never put it in chat summaries or delivered documents.
- W5 UUID. Not a step, do not count or number it. As a note inside 第5/6步, before the W6 client question, say: "顺带说明(不算一步): 节点编号(UUID)我自动生成,你不用管。" Generate a fresh UUIDv4 yourself and treat it as a secret like the password.
- W6 Client. After the W5 note, ask: "第5/6步: 你最后用什么上网?小火箭 Shadowrocket / Clash / sing-box / v2rayN,回名字就行,不确定就回 小火箭。" This only chooses the first test format; the subscription itself is the same.
- W7 Region choice. This is 第6/6步(选地区). Run Section 0B and do not skip it; its R1 question and R4 decision prompt carry the 第6/6步(选地区) prefix.
- Then execute Sections 2, 6, 7, 9, 10 yourself. At the end deliver only: admin URL, subscription URL, QR image, and the region verification result from W7. If any step fails twice, stop and report the exact screen/error in plain Chinese instead of improvising fixes on live resources.


### Branch D: no-domain onboarding (第2/6步的子分支 D1-D4, inserted before deploy)

Use only when W2 = 3. This branch does NOT renumber the 6 wizard steps: every question in D1-D4 keeps the "第2/6步" prefix. Placeholders only: the resulting domain is written `<DOMAIN>` everywhere in docs/files; never record the operator's real domain in this package.

- D1 选路 (ask): "第2/6步(D1): 你主要在大陆网络用吗?不在大陆用可以跳过域名、直接用 workers.dev;在大陆用又想要稳,建议走免费域名路线,我带你注册一个再绑到 Cloudflare。你选:回 A 跳过域名用免费地址,回 B 走免费域名。" If A, return to W2 route 1. If B, continue to D2.
- D2 注册 (Agent 云端浏览器全程操作,用户只过确认点): YOU (the deploying Agent) open YOUR OWN cloud/browser environment and perform the registration flows yourself on Cloudflare (dash.cloudflare.com) and on [DNSHE 免费域名](https://my.dnshe.com/clientarea.php?language=chinese&autolang=1) (该站有不同年限，优先选10年期；若只有1年期，老实告知续期规则：到期前180天内免费续; 以站点当期规则为准, never promise a term not seen on the live site; verify on live site, labels/terms may change) — including Google sign-in for Cloudflare signup/login and for DNSHE if the live site offers it. You navigate, fill forms, search domain availability, submit, change nameservers, bind the Worker Custom Domain, poll DNS activation, set HOST, and re-issue subscription/QR — the operator does NOT do these steps in their own browser, and you report progress after each background step. 确认点 rule (mandatory): at each 确认点 you STOP, tell the operator exactly what to confirm in plain Chinese (prefixed 第2/6步), wait for them, then continue automatically. The operator's only jobs are: (1) authorize/confirm login state when you present a login/session that needs them (e.g. approve a Google sign-in prompt, confirm '已登录'); (2) complete human-only checks you cannot do: captcha/人机验证, 2FA/OTP; (3) the D3 explicit confirm before final registration of the exact domain. Safe-login rule (mandatory): passwords and OTP/2FA codes must NEVER be typed into the chat transcript, and you must NEVER ask for, receive, or relay a Google/Cloudflare/DNSHE password, OTP, or 2FA code in chat — credentials go only into the browser's own login fields / the secure credential prompt the host provides. You must not bypass captcha, must not bulk-register, and must respect site terms. If your environment has NO browser tool at all, say so honestly and fall back to guiding the operator step-by-step — do not pretend you browsed.
- D3 选域名 (Agent 操作,用户只确认准确域名): look for / prefer a 10-year term option when the live site offers a choice (该站有不同年限，优先选10年期); if only a 1-year term is available for that name, tell the operator plainly before the 确认点: 若只有1年期，老实告知续期规则：到期前180天内免费续 — never present a 1-year registration as 10 years. In your own cloud/browser session you search and shortlist available names/suffixes; show the exact candidate domain in full and ask "第2/6步(D3): 就注册这个域名 `<DOMAIN>` 吗?确认回:好，注册 <DOMAIN>" — this is a 确认点: STOP and wait. Registration/submit happens ONLY after the operator explicitly replies "好，注册 <DOMAIN>" (or an unambiguous equivalent) for that exact domain name, and then YOU submit it in your cloud browser (the operator does not submit it in their own browser). One domain only, no bulk registering, respect DNSHE's current terms. If at submit time the site presents a human-only check (captcha/人机验证, 2FA/OTP, or a final confirm only a human may click), treat it as a 确认点: pause, tell the operator exactly what to complete in the session you presented, wait, then continue automatically. Record the confirmed name as `<DOMAIN>` in all package/docs output.
- D4 接入 (you do this after D3, in your own cloud/browser or authorized API session — operator does not do this): try routes fastest-first (Section 3.4). **Route B first when DNS can be edited at DNSHE:** deploy the Pages variant, add a custom domain for a subdomain such as `edge-node.<DOMAIN>` in Pages, then at DNSHE add CNAME `edge-node` -> `<PROJECT>.pages.dev` (verify labels on live site). This skips whole-zone NS activation. Apex/root (`<DOMAIN>` itself) is excluded. Before adding any record, check for a conflicting DNS record; on conflict pick another subdomain name (e.g. `edge-node2`), never overwrite or delete an existing record. **Route C only if B is impossible** (e.g. DNS editing/CNAME not allowed): in Cloudflare use "Add a site" for `<DOMAIN>`, note the 2 nameservers Cloudflare assigns, then at DNSHE change NS to those two (verify on live site), and wait until the zone shows Active. Before waiting on NS, check the zone setup wizard actually finished (plan selected / setup step complete; check zone meta/step/wizard completion where visible — Cloudflare may not start provisioning until then). Poll zone status every 15 minutes (not every minute); if still `initializing`/`pending` after 2 hours, STOP and report, suggest deleting the zone and re-doing "Add a site", and tell the operator this is Cloudflare-side waiting they cannot speed up by staring at it. Never bind a domain or issue a QR before the chosen route is actually live/Active. On the live route: set `HOST` to that canonical hostname, then issue subscription + QR (Section 6, Sections 9-10). Fallback honesty rule: if DNS edit/NS change is not allowed on the free plan, the site blocks it, or activation never completes, STOP and tell the operator the options plainly — use any registrar domain they can point at Cloudflare, or accept the workers.dev mainland-timeout risk — and ask which way to go. Never fake success.
- Domain-asset note (say it once, in D4): "这个域名是你的资产,不是我的。DNSHE 和 Cloudflare 两个账号的登录方式你自己收好,我不保存、也不会在以后向你要密码;域名到期/续期规则以 DNSHE 当期规则为准,你留意一下。" Add, with the actual term seen on the live site: 该站有不同年限，优先选10年期；若只有1年期，老实告知续期规则：到期前180天内免费续 — state which term `<DOMAIN>` actually got, never a term you did not see.

## 0B. Region choice: the operator decides (mandatory step)

Honesty rule (say this verbatim in substance): "优选IP可以把入口尽量偏向你选的国家/地区,但不能保证、更不能承诺任意国家的住宅IP。最后出口是哪儿,以实测出口IP的归属地为准;我测出来告诉你,你说行才算定,你说不行我们就换一个再测。"

Step R1 Ask (multi-select allowed for up to 3 regions): "第6/6步(选地区): 你想要哪个国家/地区的出口?常见:美国、日本、新加坡、韩国、香港、台湾、英国、德国。也可以回你想的其它国家,或回 多个:美国,日本 这样最多选三个。"
Step R2 Source candidates for each requested region using Section 7 rules (curated lists you can re-test, or the code random generator as fallback). Never silently substitute a different region's candidates when the list is empty: tell the operator "这个地区我暂时没找到能测的入口,要么换地区,要么先用随机入口试", and let them choose.
Step R3 Test each candidate: (a) Section 7 TCP/TLS probe; (b) end-to-end exit verification, in this order of preference: (i) if you can run a local VLESS client (for example xray-core) on your box, build a one-node client config from the candidate URI, route a request through it to an IP-geolocation lookup, and record actual exit country/city and colo; (ii) otherwise ask the operator to import the single candidate node on their phone, open an IP-lookup page, and paste back the country/city shown. Record requested region vs actual exit country/city per candidate. A candidate whose actual exit disagrees with the request is "未命中", not a success to be relabelled.
Step R4 Operator decides, loop: report "第6/6步(选地区): 你选的是 X,实测出口是 Y(城市 Z)。1) 就用这个 2) 换下一个候选再测 3) 换个国家。回数字。" Loop back to R3 or R1 until the operator accepts. Never end the build on an unaccepted region mismatch.
Step R5 Write only accepted candidates into ADD.txt (Section 7 write path), set the node label to the ACTUAL verified exit region, re-fetch the subscription, and record in the Final Delivery Checklist: requested region(s), accepted candidate label(s), actual exit country/city per candidate, verification method (local client or phone), and date. The default random-IP mode has no region choice at all: if the operator cares about region, random mode is only a pipeline smoke test, never the delivery.


## 1. Evidence base (verified 2026-10-17, re-verify before reuse)

- Local verified file `/workspace/_worker.js` is byte-identical to upstream main on 2026-10-17: SHA-256 `1e84d11af0544654bf56a06fa833e77184a57193288a9ffccf62c031a9fb7d65`, size 5,142,235 bytes, header line 1 `const Version = '2026-10-08 22:23:27';`. Upstream repo https://github.com/cmliu/edgetunnel (GPL-2.0), pinned commit `66f1c51c4ecee058b959104cb0517e073cdb1213`. Line numbers below refer to this pinned file; if a newer file is used, re-locate each function before trusting line hints.
- Code facts used below, with line hints: env/UUID derivation L30-37; quick-sub redirect L87-90; login and admin routes L91-111, L208-299; subscription route and token L304-315; per-client format dispatch L332-347; local subscription generation from KV `ADD.txt` L356-361; VLESS URI template L452-456 and placeholder replacement L470-486; external subscription conversion L457-467; admin KV write endpoints L220-287; default config and KV auto-init in function `读取config_JSON` L5598-5845 (defaults L5600-5700, auto-create `config.json` L5702-5706, `tg.json` L5799-5804, `cf.json` L5814-5819); transport/path defaults function `获取传输协议配置` L4794-4815; double-MD5 function `MD5MD5` L5403-5415; random preferred IP generation L5878-5908.
- Cloudflare platform facts checked 2026-10-17 in official docs: Workers Free 100,000 requests/day then error 1027, reset midnight UTC (https://developers.cloudflare.com/workers/platform/limits/); KV Free 100,000 reads/day, 1,000 writes/day to different keys, 1 GB/account (https://developers.cloudflare.com/kv/platform/limits/); Worker Custom Domain requires an active Cloudflare zone (https://developers.cloudflare.com/workers/configuration/routing/custom-domains/). Re-check before quoting.
- Fast-route docs: Worker Custom Domains (API/Wrangler binding on an already-Active zone creates DNS + certificate automatically) https://developers.cloudflare.com/workers/configuration/routing/custom-domains/ ; Pages custom domains, including external-CNAME setup for a subdomain when DNS is hosted elsewhere (apex requires zone handling, so apex/root is excluded from Route B) https://developers.cloudflare.com/pages/configuration/custom-domains/ .
- Community preferred-IP sources (third-party, runtime-reference only, no licence stated, may die or change without notice — never vendor/copy their data files into this package, never treat as guaranteed): primary scanned top-20, country-labelled, updated about every 6 hours https://raw.githubusercontent.com/LancelotRar/best-cf-ips/main/best-cf-ip-scanned-top20.txt ; fallbacks https://raw.githubusercontent.com/joname1/BestCFip/main/ipv4.txt and domain-lite https://raw.githubusercontent.com/LancelotRar/best-cf-domains/main/best-cf-domain-lite.txt . See the two-stage rule in Section 7.

## 2. Get _worker.js (version-locked, checksum-verified)

Version-lock rule (resolves the earlier contradiction): the pinned commit below is the only canonical source for this skill. Downloading floating `main` or "latest release" is NOT equivalent and must not be mixed with these instructions or templates. If upstream has moved on, either use the pin exactly, or redo the evidence pass in Section 1 for the new file before deploying.

```bash
curl -L -o _worker.js https://raw.githubusercontent.com/cmliu/edgetunnel/66f1c51c4ecee058b959104cb0517e073cdb1213/_worker.js
sha256sum _worker.js
# expected: 1e84d11af0544654bf56a06fa833e77184a57193288a9ffccf62c031a9fb7d65
head -n 1 _worker.js
# expected: const Version = '2026-10-08 22:23:27';
wc -c _worker.js
# expected: 5142235
```

If hash, version header, or size differ: STOP. Do not deploy. Report the three observed values and ask whether to re-verify a new upstream version. Never use re-uploaded copies from file-sharing sites; a tampered Worker can steal traffic and credentials. `templates/wrangler.toml.example` sets `compatibility_date = "2026-10-08"` only to match this pinned build's era; it is not a version guarantee, the hash above is.

## 2A. Parallel preheat (while the operator answers, non-mutating)

Start these in the background as soon as the wizard starts, without blocking the next question:
1. Download and SHA-verify the pinned `_worker.js` (Section 2).
2. Fetch the primary community preferred-IP top list (Section 7 source list; fallbacks if it fails) and cache it outside the package (runtime data only, never committed/vendored).
3. Pre-probe a small default-region candidate set (TCP/TLS with SNI = the eventual canonical `<HOST>` once known; before HOST is known, probe TCP/TLS reachability only and re-probe with real SNI later).

Rules: preheat never deploys, never writes KV, never binds a domain, never registers anything, and never skips Section 0/0B gates. Agent-machine probe results are not the operator's carrier results: label them pre-checks, then still do Section 7/9 verification and let the operator make the final region call. CloudflareSpeedTest is only a fallback for small samples when lists/probes are insufficient: `CloudflareSpeedTest -n 200 -dn 10` scale, never a full default scan, and never present agent-machine speed ranks as the user's phone result.

## 3. Variables, HOST vs Custom Domain, first-build defaults

### 3.1 What each thing actually is (code-verified)

- Custom Domain / workers.dev hostname = how requests reach the Worker. It is the `url.hostname` of the incoming request.
- `HOST` env = node hostname(s) written into generated nodes. Code: `hosts` = parsed `env.HOST` list if set, else `[url.hostname]`; `host = hosts[0]` (L36-37). On every config load, `config_JSON.HOSTS` is overwritten from `env.HOST` (L5725) and the subscription generator shuffles HOSTS and substitutes them into node URIs (L470-483). `HOST` does not create DNS and does not attach a domain to the Worker.
- First-build rule: set `HOST` to exactly the public hostname from gate item 3 (custom subdomain, or the full workers.dev hostname). A HOST that does not resolve to this Worker breaks TLS SNI/host matching in generated nodes (consequence of L36-37 plus the URI template in Section 5; treat any other combination as advanced multi-host setup).
- Canonical-host preference (field lesson, 2026-10-17): if the operator has any usable domain on an active Cloudflare zone, prefer/bind a Custom Domain (placeholder `node.example.com`) and use it as canonical `HOST`/SNI. `workers.dev` (placeholder `https://<WORKER_NAME>.<account>.workers.dev`) is enough to deploy and the panel/subscription can open in a browser, but as node `host`/`sni` on mainland China networks it commonly/likely causes ALL nodes to timeout at the TLS/WS handshake — swapping in preferred entry IPs does not fix it, because the entry IP changes while SNI/host stays `workers.dev`. If the operator has no domain, proceed on `workers.dev` but set that expectation up front and do not promise phone connectivity; the fix path is the troubleshooting row in Section 9. Changing the canonical host changes the token (Section 4), so the fix invalidates the old subscription URL and QR and all three must be re-issued.
- `UUID`: if `env.UUID` is a valid UUIDv4 it is used lowercased; otherwise the Worker derives a UUID-shaped value from `MD5MD5(ADMIN + KEY)` (L30-35). Pin an explicit generated UUID for a first build so changing the password does not silently rotate every node.
- Subscription token uses `host`, i.e. `HOST` first entry or the request hostname (Section 4). Visiting the same Worker under a different hostname yields a different token and different node hostnames. Pick one canonical hostname and use it everywhere.

### 3.2 Variable table (placeholders only)

| Variable | First build | Placeholder / value | Purpose (code) |
|---|---|---|---|
| `ADMIN` | Required, as secret | `<STRONG_ADMIN_PASSWORD>` | Panel login; also seeds derived UUID if `UUID` unset (L30, L91-106) |
| `UUID` | Recommended, as secret | `<UUID>` from `uuidgen` | Fixed node UUIDv4 (L34-35) |
| `KEY` | Optional, as secret | `<QUICK_SUB_KEY>` | Visiting `/<KEY>` 302-redirects to the full subscription URL (L87-90). Also feeds derived UUID and login cookie hash (L31-32, L94). Set it if you want the short quick-sub path |
| `HOST` | Recommended, plain var | `<YOUR_DOMAIN>` (the gate-3 hostname) | Node hostname list, see 3.1 |
| `PATH` | Leave unset | default `/` (L5730-5731, default config L5605) | WebSocket path prefix in node URIs |
| `PROXYIP` | LEAVE UNSET on first build | - | If unset, code uses an automatic per-colo reverse proxy with fallback enabled (L44-49). If set, a random entry from the list is used and automatic fallback is disabled, so one dead entry can break nodes |
| `BEST_SUB` | LEAVE UNSET on first build (default empty) | - | Only flags this Worker as a public preferred-subscription generator when a request arrives with placeholder host `example.com` and the code placeholder UUID `00000000-0000-4000-8000-000000000000` (L305, verbatim from code; this value is a public code placeholder, never a real credential, never use it as your UUID). Not needed for a private node. Never send the operator's real UUID/HOST to any public subscription generator/converter, and never use public generators to build the delivered subscription |
| `GO2SOCKS5` | LEAVE UNSET on first build | - | Appends domains to the built-in SOCKS5 whitelist (L52-54). Advanced chain-proxy feature |

This table is authoritative and matches `templates/env.example` and `templates/wrangler.toml.example`. Any conflict between skill and templates is a bug; stop and report it.

### 3.4 Route priority: fastest binding first (A > B > C)

Choose the first route whose facts are true; do not default to the slowest.

| Route | When it applies | How | Speed / wait | Hard limits |
|---|---|---|---|---|
| **A. Worker Custom Domain on an already-Active CF zone** | Domain zone already shows Active on this Cloudflare account | Bind `node.<YOUR_DOMAIN>` as a Worker Custom Domain via Cloudflare API (`PUT /client/v4/accounts/{account_id}/workers/domains` with `zone_id`, `hostname`, `service`) or Wrangler `custom_domain`; Cloudflare creates the DNS record and certificate automatically. Doc: https://developers.cloudflare.com/workers/configuration/routing/custom-domains/ | Minutes, **no NS/zone-activation wait** | Zone must already be Active; check for conflicting DNS/Worker-domain use first, pick another subdomain on conflict, never overwrite |
| **B. Pages + external CNAME subdomain** | Domain is at DNSHE/another registrar and the operator can edit its DNS, but the zone is not on Cloudflare | Deploy the Pages variant (Section 6 alternative), set the custom domain in Pages for a subdomain such as `edge-node.<YOUR_DOMAIN>`, then at the external DNS add CNAME `edge-node` -> `<PROJECT>.pages.dev`. Doc: https://developers.cloudflare.com/pages/configuration/custom-domains/ | Minutes to DNS propagation; **skips whole-zone NS activation** | Subdomain only — apex/root domain excluded. Before adding, check no conflicting DNS record exists; on conflict pick another subdomain name, never overwrite/delete an existing record |
| **C. NS move to Cloudflare (existing Branch D route)** | New domain, or operator explicitly wants the whole zone on Cloudflare, and A/B are impossible | "Add a site", change NS at the registrar to Cloudflare's pair, wait for Active, then Route A binding | Slowest: minutes to hours, sometimes longer | **Before waiting on NS:** confirm the zone setup wizard is actually finished on the Cloudflare side (plan selected / setup step complete — check zone meta/step/wizard state where visible; provisioning may not start until that is done). Only then poll every 15 min; if >2h still `initializing`/`pending`, stop & report and suggest delete zone + re-"Add a site". Never bind domain or issue QR before Active |

For all routes: after binding is live, set canonical `HOST` to that hostname and re-issue subscription + QR (host change changes the token).

OAuth/API cross-reference: some Cloudflare domain APIs reject OAuth-derived tokens (field-observed for Workers domain binding, e.g. `/workers/domains`-style endpoints). If an API/Wrangler Custom Domain bind fails with an auth/scope error on an OAuth token, do not loop on the API — fall back to Dashboard Settings -> Domains & Routes binding for Route A. The browser-upload -> OAuth/API/CLI fallback in Section 6 (Pages) and this dashboard-binding fallback are complementary, not contradictory.

### 3.3 Secrets hygiene

- Dashboard (preferred for this large ~5 MB Worker): add `ADMIN`, `UUID`, `KEY` with the secret/encrypt type if offered, not as plain text. Setting secrets in Dashboard triggers a clean redeploy and is the default first-build path in Section 6.
- Wrangler: never put real `ADMIN`/`UUID`/`KEY` values in `wrangler.toml` `[vars]` (that file gets committed). Keep `[vars]` for non-secret values only such as `HOST`. `templates/wrangler.toml.example` therefore contains only non-secret placeholders plus a warning comment; it has no secret lines at all (that is deliberate).
- Large-Worker secret failure mode (field-observed, not a universal law): in one field deployment, `wrangler secret put` for secrets the code reads (`ADMIN`/`UUID`) on the ~5 MB Worker was followed by persistent 500 / error 1101 on all paths, while Dashboard-added secrets worked. This does **not** prove CLI/API secret-put always corrupts large Workers — earlier API/raw-multipart deploys in this project succeeded — so treat it as a known failure mode + fix, not a ban. If you do use CLI/API secret-put: verify immediately (`/login` and `/sub` return expected 200s, Section 9). If persistent 1101/500 starts right after a secret change and re-uploading the checksum-verified code does not fix it, stop patching that Worker: delete-and-recreate **only the newly created Worker for this build**, re-upload the verified code, then add secrets via Dashboard (Section 9, 1101 row).
- A Cloudflare API token for Wrangler must be scoped to Workers/KV edit on the one account, supplied by the operator at the gate, and revoked after use. Never use a Global API Key, never paste any credential into chat logs, articles, screenshots, or this package.

## 4. Subscription URL and panel (exactly as code implements)

Panel (L91-111, L208-299):

- Login page: `https://<HOST>/login` (POST field `password` = `ADMIN`; success sets an `auth` cookie, HttpOnly, 24 h).
- Admin panel: `https://<HOST>/admin` (redirects to `/login` without a valid cookie). The subscription response also advertises this as `Profile-web-page-url` (L323).
- Useful authenticated admin endpoints: GET `/admin/config.json`, POST `/admin/config.json`, GET/POST `/admin/ADD.txt` (case-sensitive path for POST, L277-293), GET `/admin/log.json`, GET `/admin/getCloudflareUsage`, GET `/admin/check`, GET `/admin/getADDAPI`, POST `/admin/init` (reset config). Do not expose the cookie.

Subscription URL (L304-315):

```text
https://<HOST>/sub?token=<TOKEN>
```

- `TOKEN = MD5MD5(host + userID)` where `host` is Section 3.1's canonical host and `userID` is the effective UUID (L305). The panel stores the same value as `config.优选订阅生成.TOKEN` (L5635, L5797).
- `MD5MD5(text)` (L5403-5415) is a double MD5: take MD5 hex of the text, take characters 7..26 (slice(7,27), 20 chars) of that hex, MD5 that substring, output lowercase hex.
- Do not hand-compute the token as your first choice. Copy the subscription URL from the panel, or read `TOKEN` from `/admin/config.json` after first login. Hand-compute only to cross-check, with Python `hashlib.md5` implementing the two steps above, and compare full strings. If they differ, you used the wrong host or UUID; fix the input, not the code.
- Quick-sub alternative (only if `KEY` was set): `https://<HOST>/<KEY>` returns 302 to `/sub?token=<TOKEN>` (L87-90). The `<KEY>` path itself is a credential.
- Per-client formats, as dispatched in code (L332-347): no target and a non-browser client = `mixed`; `?target=clash` or a Clash/Mihomo user agent = `clash`; `?target=singbox` or sing-box UA = `singbox`; also `surge`, `quanx`, `loon` targets. Non-`mixed` formats are produced by an external subscription-converter backend configured in `config.订阅转换配置.SUBAPI` (L457-467), with `clash` and `singbox` outputs post-patched locally and content types set to YAML / JSON (L488-494). If the converter backend is down, non-mixed requests fail while `mixed` still works; troubleshoot `mixed` first.
- v2rayN and Shadowrocket are not named targets in this dispatch (Shadowrocket appears in code only as a TLS-fragment option, L353). Both consume the `mixed` subscription: when the client UA is not Mozilla, or `b64`/`base64` is in the query, the `mixed` body is standard `btoa` base64 (standard alphabet, with padding; not base64url) of the plain node list (L486). A browser (Mozilla UA) receives plain text instead, which is a common source of "my subscription is not base64" confusion.

## 5. Node URI format (one complete placeholder example)

Default config (L5600-5624): protocol `vless`, transport `ws`, path `/`, fingerprint `chrome`, ALPN empty, ECH off, TLS fragment off, random path off, 0-RTT off. The subscription builder emits (template L454, then placeholder UUID and `example.com` are replaced with the real UUID and shuffled HOSTS at L470-483):

```text
vless://<UUID>@<ENTRY_HOST_OR_IP>:443?security=tls&type=ws&host=<HOST>&fp=chrome&sni=<HOST>&path=%2F&encryption=none&alpn=#<NODE_LABEL>
```

Fully concrete documentation-only instantiation (copy-paste-checkable, will NOT connect: UUID is the code placeholder from L454, domain is RFC 2606 example, entry IP is RFC 5737 TEST-NET-1):

```text
vless://00000000-0000-4000-8000-000000000000@192.0.2.10:443?security=tls&type=ws&host=node.example.com&fp=chrome&sni=node.example.com&path=%2F&encryption=none&alpn=#EXAMPLE-01
```

A parser check on this string must yield: scheme vless, port 443, security=tls, type=ws, host=sni=node.example.com, path=/ after URL-decoding %2F, encryption=none, fp=chrome, fragment EXAMPLE-01. If your generated real node does not parse the same way (with your real UUID/host/entry), stop and compare against the template before touching the client.

Param notes, all from the template: query order is `security`, `type`, `host`, `fp`, `sni`, `path`, `encryption`, `alpn`; `path` is `encodeURIComponent` of the node path (`/` becomes `%2F`); `alpn` is present but empty under defaults because default ALPN is the empty string (L5606, L454), while the panel single-node LINK omits `alpn` (L5796), so a one-character difference there is expected and not an error; the fragment is `encodeURIComponent` of the `ADD.txt` remark label. Protocol variants the same builder can emit when config changes: `trojan` (forced for Surge unless protocol is `ss`, L350) and `ss` with a v2ray-plugin URI (L443-451). First build stays on `vless` + `ws`.

Base64 verification step (mandatory after fetching a `mixed` subscription as a client would):

```bash
curl -s -A "v2rayN" "https://<HOST>/sub?token=<TOKEN>" -o sub.txt
python3 -c "import base64; d=base64.b64decode(open('sub.txt').read().strip()); print(d.decode()[:500]); print('lines:', len([l for l in d.decode().splitlines() if l.strip()]))"
```

Expect: decoded text starts with `vless://`, contains your UUID and canonical host, line count equals the node count you expect. Standard `b64decode` succeeding also confirms the encoding variant; if decode fails with padding errors, you probably fetched the Mozilla plain-text variant, so re-fetch with a client user agent or add `&b64=1` handling exactly as L486 does (query flag `b64` or `base64`).

## 6. Deploy: Workers dashboard (recommended first build)

Precondition: Section 0 gate passed. Placeholders below are replaced with operator values in the dashboard only, never written into this package.

1. Section 2 download and checksum pass on the operator machine or this box.
2. Dashboard -> Workers & Pages -> Create -> Worker, name `<WORKER_NAME>`, deploy the starter so the service exists.
3. Worker -> Edit code: replace all code with the verified `_worker.js`, Deploy. A truncated paste shows up later as error 1101; file size in the editor should correspond to 5,142,235 bytes.
4. Settings -> Variables and Secrets: secrets `ADMIN`, `UUID`, `KEY` (if used) — add them here in Dashboard by default for this ~5 MB Worker (clean redeploy; see Section 3.3 field-observed CLI-secret failure mode); plain var `HOST` = gate-3 hostname. Leave `PROXYIP`, `BEST_SUB`, `GO2SOCKS5`, `PATH` unset. Deploy if prompted, then immediately verify `/login` + `/sub` (Section 9) before proceeding.
5. Storage & Databases -> KV -> Create namespace (e.g. `edge-node-kv`). Worker -> Settings -> Bindings -> Add -> KV Namespace: variable name exactly `KV` (case-sensitive), select the namespace, Deploy.
6. Hostname — apply Route priority A > B > C (Section 3.4): **A** if the zone is already Active, bind Worker Custom Domain `node.<YOUR_DOMAIN>` (dashboard Settings -> Domains & Routes, or API `PUT /client/v4/accounts/{account_id}/workers/domains` with `zone_id`/`hostname`/`service`, or Wrangler `custom_domain`), wait until the domain (not the zone) is Active — minutes, no NS wait — and use it as canonical `HOST`. **B** if the domain is external but DNS-editable, switch this build to the Pages variant (see Alternative: Pages), set the Pages custom domain for the subdomain, add the external CNAME to `<PROJECT>.pages.dev`, check conflicts first (another subdomain name on conflict, never overwrite), apex excluded. **C** NS move only when A/B are impossible: wait for zone Active under the 15-min/2-hour rule (Section 9) before any binding or QR. For workers.dev, confirm the URL `https://<WORKER_NAME>.<YOUR_SUBDOMAIN>.workers.dev` answers, but treat that only as "deployed", not as "nodes will connect on mainland networks" (Section 3.1 warning). One canonical hostname only for the first build (Section 3.1).
7. First login: open `https://<HOST>/login`, sign in with `ADMIN`, land on `/admin`. This first authenticated load (and the first subscription fetch) triggers config initialisation (Section 8). Fetch GET `/admin/config.json` and record: UUID matches gate value, HOST/HOSTS match canonical hostname, TOKEN present (this is your Section 4 token, do not publish it).
8. Preferred IPs: use the two-stage ADD.txt flow in Section 7 before sharing anything. Stage 1 may ship fast only when labelled exactly as the community-source automatic-list version (未逐个实测); Stage 2 (same session) freezes <=10 region-intersected, probed IPs and is the normal delivery. Default random mode generates 16 random Cloudflare-CIDR entries per subscription fetch, so node lists differ between fetches until a curated/frozen `ADD.txt` is saved. The operator still chooses the region and gives the final say (Section 0B) — stage speed never overrides that.
9. Get the subscription URL (Section 4) from the panel, run the base64 verification (Section 5), then Sections 9-10 for client import and QR delivery.

### Alternative: Wrangler CLI

```bash
cp templates/wrangler.toml.example wrangler.toml   # fill name, KV id, HOST; keep secrets out
npx wrangler deploy
npx wrangler secret put ADMIN
npx wrangler secret put UUID
npx wrangler secret put KEY    # only if quick-sub is wanted
```

Create the KV namespace first (`npx wrangler kv namespace create edge-node-kv`) and paste its id into the `[[kv_namespaces]]` block with binding `KV`. Then continue at dashboard step 6.

> CLI secret caution (Section 3.3): `wrangler secret put` above is a fallback, not the preferred path for the ~5 MB Worker. If you use it, verify `/login` and `/sub` immediately; on persistent 1101/500 after the secret change that re-upload does not fix, delete-and-recreate only this newly created Worker and add secrets via Dashboard. Some domain-binding APIs also reject OAuth tokens — use Dashboard binding then (Section 3.4 cross-reference).

### Alternative: Pages

Fork https://github.com/cmliu/edgetunnel, Dashboard -> Pages -> Connect to Git, add env `ADMIN` at setup, deploy, then Settings -> Bindings -> KV namespace with variable name `KV`, redeploy so the binding takes effect, optionally add the custom domain. Note: this tracks the fork's branch, not the Section 2 pin; for a version-locked build prefer Workers with the pinned file. Continue at dashboard step 7.

Pages upload lesson (field-verified): browser drag-upload of `_worker.js` may stall — the drag area may expose no usable file input to automation, so clicks/drag do nothing. Do not fight the UI: if browser upload is stuck >10 minutes, switch the file-transfer step to API/CLI: create a scoped temporary API token (Cloudflare Pages: Edit only, nothing broader), run `npx wrangler pages deploy` for `<PROJECT>`, then delete/revoke that temporary token immediately after the deploy succeeds. The browser session keeps doing what it is good at — login, variables/secrets, KV binding, and custom-domain binding — only the stalled upload moves to CLI. Never keep, reuse, or log the temporary token (Section 3.3).

Asset-ownership check (also Section 9): the hostname you asked for as `<PROJECT>.pages.dev` may already be taken by someone else; Cloudflare then assigns your project a suffixed hostname (like `<PROJECT>-xxx.pages.dev`). A `200` on the unsuffixed name may be someone else's project, not yours. Always read back the actual assigned `pages.dev` hostname from your own project settings and confirm it belongs to this deployment before using it as a CNAME target, setting `HOST`, or reporting any success.

## 7. Preferred IPs and ADD.txt (sourcing, liveness, only then write)

Format, one entry per line (builder parsing L363-394, URI generation L404-456):

```text
<ENTRY_IP_OR_DOMAIN>:<PORT>#<REGION LABEL>
```

Port defaults to 443 if omitted (L413-418). Entries whose address part does not match the builder's address pattern are silently skipped (L419-422), so a malformed line means a missing node, not an error.

Sourcing, in order of preference for a first build:

1. Start with the code default: `config.优选订阅生成.本地IP库.随机IP = true`, 16 random entries from Cloudflare CIDR lists fetched at runtime (L5627-5631, L5878-5908, ports from 443/2053/2083/2087/2096/8443 at L5890). Zero sourcing work, proves the pipeline, but entries are random and rotate.
2. Curated list: switch `本地IP库.随机IP` to `false` in the panel config, then the builder reads KV `ADD.txt` (L359-361). Source candidates only from lists you can re-test (your own measurements, or a public preferred-IP project whose update time you can see). A region label is a claim; see the colo check in Section 9 before believing it.
3. Residential-entry lists: same handling, plus verify the entry is not hosting/datacenter via an IP-intelligence lookup before calling it residential. An earlier audit estimate found only about 60-70% of upstream residential-marked entries were actually residential; re-test your own list. Entry geography never changes the exit: exit stays Cloudflare Workers egress. **Never promise a residential exit/IP**; this setup's exit is Cloudflare Workers egress.
4. Two-stage community ADD.txt (the fast path, mandatory wording): edgetunnel natively fetches `https://` lines placed in `ADD.txt`, so a community list can be referenced at runtime instead of hand-copying IPs.
   - **Stage 1 — fast subscription (minutes):** `ADD.txt` may contain exactly ONE line = a community preferred-IP API/list URL whose candidates are filtered/intersected with the operator's chosen region (Section 0B). Primary: `https://raw.githubusercontent.com/LancelotRar/best-cf-ips/main/best-cf-ip-scanned-top20.txt` (country-labelled, updated about every 6 hours). Fallbacks if the primary is unreachable/empty: `https://raw.githubusercontent.com/joname1/BestCFip/main/ipv4.txt` or domain-lite `https://raw.githubusercontent.com/LancelotRar/best-cf-domains/main/best-cf-domain-lite.txt`. Before writing, validate the endpoint first via `/admin/getADDAPI` when that admin endpoint is available in this build, and by fetching the URL yourself. Delivery wording for Stage 1 must be exactly in substance: 「社区源自动列表版（未逐个实测）」 — never call it verified/tested.
   - **Stage 2 — freeze (same session, before calling the build finished):** pull the list yourself, intersect with the operator's chosen region, run the TCP/TLS probe below with `SNI=<canonical HOST>` for each candidate, end-to-end verify where possible, then freeze **<=10 explicit IPs** into `ADD.txt` as `IP:443#<REGION LABEL>` lines, removing the live URL line so delivery no longer depends on a public list. Delivery wording now: 「已冻结实测版」 with requested vs actual exit recorded (Section 0B R5). If Stage 2 cannot be completed, keep the Stage 1 label and say so — do not upgrade the wording.
   - Third-party source limits: these community lists have no licence stated, may die/change/be wrong, and are **runtime-reference only — never vendor/copy their data files into this package/repo/zip**. Keep `BEST_SUB` empty by default, and never send the operator's UUID/HOST/token to public subscription generators or converters.

Liveness check BEFORE writing ADD.txt (all three, per candidate):

1. TCP/TLS probe from a machine on a network similar to the end user's:

```bash
python3 - << "PY"
import socket, ssl
candidates = [("<ENTRY_HOST_OR_IP>", 443)]  # replace with real candidates at run time
ctx = ssl.create_default_context()
for host, port in candidates:
    try:
        with socket.create_connection((host, port), timeout=5) as s:
            with ctx.wrap_socket(s, server_hostname="<HOST>") as tls:
                print(host, port, "OK", tls.version())
    except Exception as e:
        print(host, port, "FAIL", e)
PY
```

2. Write only passing lines to `ADD.txt`, save through the panel (POST `/admin/ADD.txt`) or KV editor. No Worker redeploy is needed for an ADD.txt-only change.
3. Re-fetch the subscription, base64-verify (Section 5), and connect-test each new node in the client (Section 9). A TCP-open entry can still be a wrong-region or dead forward; only the end-to-end test counts. Drop failures instead of retrying them into the list.

Anti-dump rule (mandatory): the frozen delivery must be probed server-side first (steps 1-3 above) before any QR is handed over as 「已冻结实测版」. The only exception is Stage 1's single community-URL `ADD.txt`, which may be handed over fast only when labelled 「社区源自动列表版（未逐个实测）」 and followed by Stage 2 freezing in the same session. Never ship only 1 direct-only node, and never ship an unverified preferred-IP batch and ask the operator to "test each one" as the primary debugging method. The operator's phone test is the final acceptance check (Section 9), not your liveness probe; if you could not run the server-side probes, say so explicitly and label the batch unverified instead of presenting it as done. CloudflareSpeedTest, if used at all, is fallback-only small-sample (`-n 200 -dn 10`), never a default full scan, and agent-machine results do not equal the operator's carrier — say so.

Sandbox probing lesson (field-verified, strengthens the agent-machine != carrier rule above): the Agent's own sandbox/CI egress may sit behind a transparent proxy / TLS MITM. Symptoms that mean the probe environment is lying, not that the IPs are dead: raw-socket TLS fails uniformly (e.g. wrong-version errors), `CONNECT` probes present a MITM/self-signed chain (you are handshaking with the proxy, not the candidate edge), and an SNI probe using the final custom hostname fails with `handshake_failure` before that custom domain is live (normal — the edge has no certificate for it yet, not a dead IP). Rule: if all probes fail suspiciously uniformly, re-probe from a clean egress (e.g. the operator's VPS in/near the target `<REGION>`) using a guaranteed Cloudflare SNI such as `www.cloudflare.com` to validate that the candidate is a live Cloudflare edge accepting TLS on 443; do the SNI-specific check with the canonical `<HOST>` only after the custom domain is live. Agent-sandbox results do not equal the operator's carrier/network (see also Section 9) — label any batch probed only from a suspect sandbox as unverified.

Never publish a working `ADD.txt` together with your subscription URL; together they hand out your node.

## 8. KV keys: what the code auto-creates (and what it does not)

Verified in `读取config_JSON` and the admin routes:

| KV key | Auto-created? | Evidence |
|---|---|---|
| `config.json` | Yes, on first config load (first `/admin` or `/sub` hit) if missing or on reset; written with defaults, then `HOST`, `HOSTS`, `UUID`, `TOKEN` are filled in | L5702-5706, L5723-5726, L5797 |
| `tg.json` | Yes, initialised to null BotToken/ChatID on first config load if missing | L5799-5804 |
| `cf.json` | Yes, initialised to null credential fields on first config load if missing | L5814-5819 |
| `ADD.txt` | NO. Created only when an operator saves custom IPs via POST `/admin/ADD.txt`. Reads fall back to random generation when it is absent | L277-280 (write), L291-292 and L359-361 (fallback) |
| `log.json` | Written by the request-logging path when logging is enabled; not part of first-build checks | `admin/log.json` read L112-114; treat initial absence as normal |

Practical consequence: an empty KV after deploy is expected. Do not pre-create `config.json`, `cf.json`, or `tg.json` by hand; do create `ADD.txt` only via the panel save so its format stays exactly what the builder reads.

## 9. Verification (all six before delivery)

Deployer self-verification before handing over the QR (mandatory, do not outsource to the operator): subscription fetches as a client would, the Section 5 decode shows the expected UUID / canonical host / `sni` / `path`, panel login works, and you have attempted every TLS/WS handshake check available to you server-side (Section 7 probes; a local VLESS client check per Section 0B R3 when available). Only after that may you ask the operator for one phone acceptance test. Shipping unverified nodes and asking the operator to try them one by one is a delivery failure, not a test plan.

Minimal control-group debugging (use before guessing): when a build returns 500/1101, vary **one** factor at a time and record the result — e.g. no-secret vs with-secret, Dashboard-added secret vs CLI-added secret, trivial small Worker vs the full ~5 MB file, fresh Worker name vs the stuck name. The combination that flips the result is the lead; changing three things at once proves nothing.

1. Panel: `https://<HOST>/admin` loads after login; `/admin/config.json` shows your UUID, canonical HOST/HOSTS, and TOKEN.
2. Subscription: Section 5 base64 check passes; node count and labels match `ADD.txt` line count (or 16 random entries if still on random mode); every URI matches the Section 5 shape.
3. End-to-end: client connected through one node, open an IP-lookup page; exit shows Cloudflare network addresses. Any source claiming a residential exit from this setup is wrong. Strongest evidence (explicit client-trace standard): when the Agent has a real client tool (e.g. xray or the operator's client), run it end-to-end through one node and capture `https://www.cloudflare.com/cdn-cgi/trace` showing `colo=` / `loc=` for that node — a client trace `colo` is the strongest region evidence. If no such real-client trace was run, label the region claim unverified; a subscription decode or a `200` alone does not prove the exit region.
4. Region: with the client connected, open `https://www.cloudflare.com/cdn-cgi/trace` and compare `colo=` with the `ADD.txt` label for that entry; relabel or drop mismatches. Note: trace shows the colo you exit through, so test one entry at a time. Prefer the Agent-run real-client (e.g. xray) trace `colo`/`loc` as the final region proof (item 3); a phone-only check is acceptance, and anything without a client trace is labelled unverified. Asset-ownership check before any success claim (Pages builds): confirm the actual assigned `<PROJECT>.pages.dev` hostname (which may carry a suffix like `-xxx` when the plain name was taken) belongs to this deployment — a first `200` on the unsuffixed name may be someone else's project (Section 6, Alternative: Pages). Sandbox-probe cross-reference: uniform probe failures from the Agent sandbox may be transparent-proxy/TLS-MITM artefacts; re-probe from a clean egress before declaring IPs dead (Section 7).
5. Quota: Dashboard -> Workers -> `<WORKER_NAME>` -> Metrics shows requests counting and headroom under 100,000/day on Free.
6. QR decode: Section 10 decode check prints the exact subscription URL. A QR that encodes a single node or a truncated URL fails delivery.

Troubleshooting quick table:

| Symptom | Likely cause | Fix |
|---|---|---|
| 1027 | Free 100k/day cap (Section 1 docs) | Wait for UTC midnight reset, find the looping client, or upgrade Workers Paid. Never multi-account to evade caps |
| 1101 | Truncated or edited `_worker.js` paste; OR (verified in the 2026-10-17 live test) a Worker first created by a `wrangler deploy` bundled upload stayed at 1101 across later raw re-uploads, while the identical raw script ran immediately under a fresh Worker name and after delete-and-recreate; OR (separate field report, one deployment) persistent 1101/500 began immediately after CLI `wrangler secret put` of code-read secrets (`ADMIN`/`UUID`) on the ~5 MB Worker and Dashboard-added secrets on a clean redeploy worked — presented as a field-observed failure mode, not a proven universal law, and not contradicting earlier successful API/raw-multipart deploys | Re-paste the checksum-verified file and check Workers Logs; use minimal control-group debugging (above): no-secret vs secret, small vs large, fresh name vs stuck name. If a brand-new test Worker still 1101s on every path while a trivial hello Worker works, delete that NEW Worker (only one you created for this build) and recreate it by raw multipart upload (main_module `_worker.js`, content type `application/javascript+module`, compatibility_flags `nodejs_compat`), then re-enable its workers.dev subdomain. If the breakage followed a CLI/API secret change and re-upload does not fix it, delete-and-recreate only that newly created Worker and add secrets via Dashboard. Causes of the stuck states were not isolated (guesses: bundled-upload creation state; CLI secret handling on a large script); the delete-and-recreate fixes are the verified observations |
| `/admin` bounces to `/login` | Wrong `ADMIN`, secret not deployed, or cookie blocked | Reset secret, redeploy, allow cookies for the hostname (L91-111) |
| `/sub` returns nothing or auth fails | Wrong token: wrong host or UUID input to `MD5MD5(host + userID)` | Use the panel-copied URL; cross-check TOKEN in `/admin/config.json` (Section 4) |
| Browser shows plain text, client says bad subscription | Mozilla UA got the non-base64 variant (L486) | Fetch with client UA or `b64`/`base64` query flag; re-run Section 5 |
| Clash/sing-box fails, mixed works | External converter backend down (L457-467) | Deliver `mixed` first; retry target formats later; do not debug the Worker |
| All nodes timeout, panel/subscription open in browser, another CF node works on same phone/network | First suspect (likely, field-verified pattern): canonical `HOST`/SNI is a `workers.dev` bare domain and mainland carriers block/throttle that SNI/host at TLS/WS handshake; preferred IPs do not help because SNI/host is unchanged | Bind a Custom Domain (placeholder `node.example.com`), set `HOST` to it, re-issue subscription + QR (token changes with host, old QR is invalid), then re-test. Only after that check next suspects: UUID mismatch between subscription and Worker, wrong `path`, DNS not proxied/resolving to this Worker |
| All nodes timeout (custom domain already in use) | Dead entries, dead forced `PROXYIP`, or UUID/path/DNS mismatch | Confirm `PROXYIP` is unset, re-run Section 7 liveness, cross-check decoded UUID/host/sni/path against Section 5 |
| Cloudflare zone stuck `initializing`/`pending` after NS move (Route C) | (1) Zone setup wizard not actually finished — plan/step incomplete, so Cloudflare has not started provisioning (field-observed: finishing the wizard/plan step activated a zone stuck ~50 min); (2) Cloudflare internal provisioning / NS not yet recognised; global NS may already look correct while Cloudflare still provisions | Do NOT bind the domain or issue a QR yet. **First** check wizard completion: plan selected, setup step/meta/step finished where visible; complete it if not. Then confirm NS at the registrar is at the correct level, spelling exact, and exactly Cloudflare's assigned pair. Only then start the clock: poll every 15 minutes (not every minute). If >2 hours still `initializing`/`pending`: STOP and report, suggest deleting the zone and re-doing "Add a site" (often faster than indefinite waiting). Minutes-to-hours before that threshold is normal. Only bind + set HOST + re-issue subscription/QR after Active. If Route B facts exist, prefer switching to B instead of waiting on C |
| Branch D: free plan will not let you change nameservers, or DNSHE blocks NS edits | Free-domain terms restrict NS delegation | Stop; do not fake success. Offer: any registrar domain the operator can point at Cloudflare, or proceed on workers.dev with the mainland timeout risk stated. Operator decides |
| Route B: Pages custom domain says conflicting DNS record / CNAME cannot be added | An existing A/AAAA/CNAME already uses that subdomain name at the external DNS | Do not overwrite or delete it. Pick another subdomain name (e.g. `edge-node2.<YOUR_DOMAIN>`), set that as the Pages custom domain + canonical HOST, add its CNAME to `<PROJECT>.pages.dev`, re-issue subscription/QR. Apex/root is excluded from Route B by design |
| Pages browser upload stalls: drag area does nothing, no file input appears | Pages UI upload does not expose a usable file input to automation | If stuck >10 min, stop fighting the UI: create a scoped temporary token (Pages: Edit only), `npx wrangler pages deploy` for `<PROJECT>`, delete/revoke the token right after; keep browser for login/vars/domain binding (Section 6) |
| First `<PROJECT>.pages.dev` check returns 200 but content/config is not yours | The plain project name was already taken; that hostname is someone else's project and Cloudflare assigned you a suffixed hostname (e.g. `<PROJECT>-xxx.pages.dev`) | Do not report success. Read the actual assigned hostname from your own project, verify ownership, use only that hostname as CNAME target / `HOST` basis, then re-verify (Sections 6/9) |
| DNSHE (or similar registrar) save fails repeatedly with a generic backend error like `DNS操作失败` while the form values are verified correct | Expired / half-expired login session: API calls are rejected but the page has not yet bounced to login | Stop retrying the form. Re-login once (operator passes the login 确认点 if needed), then submit the same correct record once. Only debug record values after a fresh session also fails |
| Route B: binding the apex/root domain forces a move of DNS/NS to Cloudflare | Pages apex binding requires the zone on Cloudflare; Route B is designed for subdomains only | Use a `www`/other subdomain + external CNAME instead (Sections 3.4/6); do not start an NS move just to bind the root unless the operator chooses Route C |
| All preferred-IP probes fail uniformly from the Agent machine (TLS wrong-version, MITM/self-signed chain, or SNI `handshake_failure` before the custom domain is live) | Agent sandbox transparent proxy / TLS MITM, or edge has no cert for a not-yet-live hostname — probe environment, not dead IPs | Re-probe from a clean egress (e.g. operator VPS in/near `<REGION>`) with a guaranteed Cloudflare SNI (`www.cloudflare.com`) for edge liveness; SNI-specific check with `<HOST>` only after the custom domain is live (Section 7) |
| Nodes differ every refresh / list changed overnight | Still on random preferred IPs, or Stage 1 live community URL still in `ADD.txt` (list republishes about every 6h) | Section 7: set `随机IP` false and complete Stage 2 — freeze <=10 explicit probed IPs into `ADD.txt`, removing the live URL line; re-fetch and re-verify subscription |
| Nodes differ every refresh | Still on random preferred IPs (default) | Section 7 step 2: set `随机IP` false and save a curated `ADD.txt` |
| Wrong country flag | Entry forwards to another colo | Section 9 item 4; fix label or drop entry |

## 10. QR code (mandatory final deliverable) and client import

The QR encodes the full subscription URL from Section 4, never a single node URI, because the subscription URL is what clients refresh and what this code serves per-client formats from. Single-node QRs are only a fallback for a client with no subscription support, and must be labelled as such.

Generate it with the tested script in this package (`templates/make_sub_qr.py` reads the URL from an environment variable or argument so the real URL never lands in a file inside the package):

```bash
pip install "qrcode[pil]"
SUB_URL="https://<HOST>/sub?token=<TOKEN>" python3 templates/make_sub_qr.py --output /workspace/cf-subscription-qr.png
# mandatory decode check (script does it with OpenCV if available, else prints QR_DECODE_SKIPPED):
SUB_URL="https://<HOST>/sub?token=<TOKEN>" python3 templates/make_sub_qr.py --verify /workspace/cf-subscription-qr.png
```

A successful run prints `QR_DECODE_MATCH=True` against the URL you encoded. Without OpenCV the script prints `QR_DECODE_SKIPPED: ...` and the operator must scan-test with the actual phone before delivery, which is the stronger check anyway. Dependency note: on PEP 668 / externally-managed Python systems, `pip install` is refused; use a venv: `python3 -m venv .venv && .venv/bin/pip install "qrcode[pil]" opencv-python-headless` and run the script with `.venv/bin/python`.

Shadowrocket scan vs paste:

- Scan: Shadowrocket home -> scan icon (top corner) -> point at the QR. It should offer to add a subscription, not a single server. Confirm the subscription name/count after refresh.
- Paste fallback: copy the subscription URL -> Subscribe/`+` -> paste -> Done -> pull to refresh. Use paste when scanning gives a single node (wrong QR), when the QR is on the same phone (cannot scan own screen; use paste or a second display), or in bright/low-contrast conditions.
- Pitfalls: a screenshot-scaled QR with clipped quiet zone fails scanning, keep the PNG at original size with its white border; a QR encoding the quick-sub `/<KEY>` path also works (302 in code) but leaks `KEY` in every screenshot, so encode the `/sub?token=` URL and treat the PNG itself as a credential: anyone who scans it owns your subscription. Never post the real QR in an article or public repo.

Shadowrocket node checklist (do this before blaming a node; these are the exact failure classes seen in real use):

1. After subscription refresh, open one node -> Edit: confirm Transport/Host field = your canonical `<HOST>`, TLS SNI = same `<HOST>`, Path = `/` (or your configured PATH). A node whose SNI/host still shows a foreign domain or `example.com` means the subscription was built with the wrong HOST; fix HOST in the Worker, not in the client.
2. Turn UDP Relay OFF for these nodes (Shadowrocket global settings / per-node UDP forwarding): this Worker path is TCP-oriented (WS/gRPC/XHTTP); forcing UDP relay makes healthy TCP nodes look dead. (In the pinned file the WS path rejects UDP that is neither Trojan nor DNS port 53 with `UDP is not supported` (L617-619); treat UDP as unsupported for a first build.)
3. If a node connects but pages stall, switch TLS fragment options off before changing IPs (TLS分片 default is off in config; a client-side fragment setting that disagrees with the server is a stall cause). Label this a client-side guess until toggling it changes the result.

Clash / sing-box / v2rayN: import the same URL; the server selects format by target param or client UA (Section 4). If a client lets you choose, request its named target explicitly (`&target=clash`, `&target=singbox` appended after the token). Format sanity check without trusting the external converter blindly: fetch the clash URL and confirm the response content-type is `application/x-yaml` and the sing-box URL is `application/json` (both set in code at L488-494); a text/plain mixed body or an error page means the converter path failed, so fall back to `mixed` and retry the target later. Do not invent expected YAML/JSON node internals; the converter owns them.

## 11. Final Delivery Checklist (copy this into the delivery message)

- [ ] Admin URL: `https://<HOST>/admin` (login tested with operator `ADMIN`)
- [ ] Subscription URL: `https://<HOST>/sub?token=<TOKEN>` (full string delivered privately, not in a public file)
- [ ] Canonical host & route: Route A / B / C (state which; A = already-Active zone Worker Custom Domain, B = Pages + external CNAME, C = NS move waited to Active); custom domain `<HOST>` preferred; if `workers.dev`, the mainland timeout-all risk was told to the operator and the bind-custom-domain fix was left as the stated next step (changing host changes token and invalidates the old QR)
- [ ] QR image: `<ABSOLUTE_PATH_TO_QR_PNG>` (decode check: match = True / phone scan tested)
- [ ] Node count and regions: `<N>` nodes; labels `<LABEL_LIST>`; state which: random mode / 「社区源自动列表版（未逐个实测）」 (Stage 1 live URL) / 「已冻结实测版」 (Stage 2, <=10 explicit IPs, live public-list dependency removed)
- [ ] Region choice (Section 0B): requested `<REGION(S)>`; accepted labels `<LABEL(S)>`; actual verified exit `<COUNTRY/CITY>` per accepted node; method local-client or phone; operator accepted on `<DATE>`
- [ ] First client tested: `<CLIENT>` connected, exit colo `<COLO>`, date/time of test
- [ ] Quota note: Workers Free 100,000 requests/day (UTC reset); current usage seen in Metrics `<X>` requests today (or "not yet visible")
- [ ] Rotation note delivered: rotating `ADMIN`/`UUID`/`KEY` invalidates old subscription URLs and QRs; re-issue all three together
- [ ] Fallback note delivered: keep one non-CF node; this free-tier Worker is a convenience layer

## 12. Security, privacy, never-do

- `ADMIN`, `UUID`, `KEY`, subscription token/URL, QR PNG, and any API token are credentials. Placeholders only in repos, articles, screenshots, and this skill.
- This node hides traffic from the local network/ISP; sites see Cloudflare egress. It is not anonymity: Cloudflare operates edge and exit and the account is tied to the operator identity.
- Volunteer/residential entry operators can see connection metadata; ordinary browsing only, never the sole protection for sensitive accounts.
- Respect Cloudflare terms and local law; reselling free-tier nodes, public subscriptions for strangers, or quota evasion risks account suspension (check https://www.cloudflare.com/terms/).
- Never modify, restart, or reconfigure an existing production proxy panel, database, or node (including any 3x-ui/x-ui service) to help with a CF build. CF work happens only inside the operator Cloudflare account and client apps.
- Never copy credentials or subscription URLs out of an existing deployment into examples. Never claim speed, region, residential status, or unlimited-free results not measured in the current session.
- Account safety for Branch D: never collect a Google, Cloudflare, or DNSHE password/OTP/2FA code in chat — credentials go only into the browser's own login fields / the secure credential prompt the host provides. The deploying Agent drives its own cloud/browser environment for Cloudflare and DNSHE registration flows; the operator only passes 确认点 pauses (authorize/confirm login state, captcha/人机验证, 2FA/OTP, and other human-only checks) and gives explicit "好，注册 <DOMAIN>" for the exact domain shown before the Agent submits — one domain, no bulk registering, never bypass captcha, respect the registrar's current terms. If the Agent has no browser tool, it must say so honestly and fall back to guiding instead of pretending it browsed. The domain is the operator's asset: remind them to keep their own DNSHE + Cloudflare logins safe; you do not store them.
