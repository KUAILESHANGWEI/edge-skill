# CF 全球边缘节点 Skill(v4.2 · 通用 Agent 全自动 + 自愈版)

**任何带终端+浏览器的 AI**(Gemini 4 Argon / Antigravity、ChatGPT Agent、Claude Code、Cursor、Grok Bot…)都能照着从零搭出 Cloudflare 免费节点,直接交出小火箭订阅二维码。**你只需要登录 Cloudflare 点一下 Allow**,别的全交给 AI。不用买机场,不怕跑路,全程免费。

## 一句口令开干

复制给你的 AI:

```text
按这个仓库的 SKILL.md「★通用 Agent 全自动模式」，帮我在 Cloudflare 上搭一个免费节点，最后给我小火箭订阅二维码：
https://github.com/free-dam-man/cf-global-edge-node-skill
全部用默认值，只用免费额度，别问我问题，也别问密码。我只负责在浏览器里登录 Cloudflare 点 Allow，其余你自己跑完并自测。
```

## v4.2 改了什么(中国移动 5G 实测修好)

- **事故经过(真实)**:一个用户节点升级 v4 后,iPhone 小火箭在中国移动 5G 下 10 个节点全部超时。从 Cloudflare 侧和美国 VPS 用 xray 真连全部正常;国内多地拨测(globalping.io,中国移动 AS9808 等)显示域名 DNS 正常、HTTPS 200、优选IP 的 443 端口都通 —— **不是域名被封、不是 DNS 污染、不是 IP 被封**,问题在 VLESS-WS 这层流量本身。
- **用户实测有效的修法**(2026-10-23 01:27 北京时间,中国移动 5G,16 个节点里 14 个通,延迟约 520–960 ms):
  1. 开上游原生的 **0-RTT**(`config.json` 的 `启用0RTT: true`,节点 path 变成 `/?ed=2560`);
  2. 开上游原生的 **小火箭 TLS 分片**(`TLS分片: "Shadowrocket"`,节点带 `fragment=1,40-60,30-50,tlshello`);
  3. **混合端口**:443 之外加 2053 / 8443 / 2083(CF 免费版支持的 HTTPS 端口)。注意:优选**域名**在非 443 端口实测不通,只给 IP 加端口变体。
  4. 两个第三方反代 IP(日本、PX 各一)在国内实测超时,已删,也不置顶 —— 反代能在 CF 侧握手≠国内能用。
- `auto_deploy.sh` 默认就这样配(`CN_TUNE=1`、`MIX_PORTS=1`,都可设 0 关掉),只改上游 `config.json` 原生选项,不改上游代码。
- **CF-only(v4.2 默认开)**:`CF_ONLY=1`(部署脚本)/ `HEAL_CF_ONLY`(Worker 变量,默认 1)—— 节点只用 Cloudflare 自有 IP,巡检**永不**加入第三方反代 IP 或域名,并会移除非 CF、未置顶的条目。**隐私取舍**:第三方反代 IP 是陌生人的服务器,它能看到你的真实源 IP、连到哪个节点域名、流量时间和大小(内容仍是 TLS 加密);好处是 CF 侧能探活、Cron 能自动换掉死的。CF 自有 IP 没这个风险,代价是 Cron 测不了(CF Worker 连不了 CF 自己的 IP 段),只能靠你在自己网络里试 + 置顶。想要可测反代,自己设 `CF_ONLY=0` 并知情接受。
- **用户最终决定的节点列表**(2026-10-23,只留 CF 自有 IP,全部置顶;标签去掉"CN"免得小火箭显示中国国旗):11 个 = 5 个 CF IP × 443 + 6 个 2053/8443/2083 端口变体。实测数据:同组 16 个节点里,中国移动 5G 下 14 个通(约 520–960 ms),超时的两个都是第三方反代;随后用户决定连能用的第三方反代(新加坡一个)和两个优选域名也一并移除。
- **置顶(pin)**:KV `PINNED.txt`(每行 `host:port`)或 `ADD.txt` 备注里带 `pin` 的条目,Cron 永不删除、永不替换。用户在自己网络里验证过的节点就该置顶。升级时检测到置顶,脚本不覆盖 `ADD.txt`。
- **巡检只删"能测且确认死"的条目**:CF 官方 IP 和所有域名(可能解析到 CF)一律"无法验证",不删。
- **实话**:Cron 跑在 Cloudflare 机房,**看不到国内运营商侧的阻断**。巡检全绿≠国内能用;国内能不能用,只能在用户自己的网络里试。

## 可选:AI 每日国内侧筛选(两层自愈)

**两层,说实话:**
- **第一层 CF Cron(一直在跑)**:免费、无需任何 Agent,但它跑在 Cloudflare 机房,**看不到国内运营商的阻断**,而且测不了 CF 自有 IP(Worker 连不了 CF 段)。它只负责"不删置顶、不加第三方、不把列表写空"。
- **第二层 AI 每日国内筛选(可选)**:让任意能定时跑任务、能联网发 HTTP 请求的 Agent(Grok Bot、Muse、Gemini 定时任务等)每天跑一次,用 **Globalping**(免费公共拨测网络,无需注册)从中国大陆探针(优先中国移动 AS9808)测 CF 自有 IP,只把国内能连通的写回 KV。它**看得到国内**,但需要有个 Agent 持续在跑;Agent 停了就退回第一层。
- 订阅链接不变:只改 KV 里的 `ADD.txt` / `PINNED.txt`,不动 Worker、UUID、HOST。
- 局限:拨测只测 TCP 443/2053/8443/2083 连通,通≠代理一定好用;最终仍以你手机实测为准。Globalping 匿名额度有限,每天一次足够。

**复制给 Agent 的定时任务提示词**(把尖括号换成你自己的,别把 UUID 发到聊天里):

```text
每天 1 次(北京时间 09:00)。目标:我的 Cloudflare Worker 节点 <WORKER名> 的 KV <KV命名空间ID> 里,
ADD.txt / PINNED.txt 只保留"从中国大陆能连通"的 Cloudflare 自有 IP。
1. 读 KV 的 ADD.txt,再加候选:Cloudflare 官方 IPv4 段内的优选 IP(如 cloudflare.com/ips-v4 里的 104.16.0.0/13、172.64.0.0/13、162.159.0.0/16 中你已知好用的),只收 CF 自有 IP,不收第三方反代 IP、不收域名。
2. 对每个 IP:端口,调用 POST https://api.globalping.io/v1/measurements,
   type=ping, measurementOptions={protocol:"TCP",port:<端口>,packets:3},
   locations=[{magic:"AS9808",limit:3}](不足时退到 {country:"CN",limit:3});GET 结果直到 status=finished。
3. 判定:≥2 个国内探针丢包<100% 记为可达。按国内平均延迟排序,保留最多 12 条,每个 IP 最多 1 个非 443 端口变体。
4. 若可达条目 <3 条:不写入,只报告(防止拨测故障把列表写空)。
5. 写入前先备份旧 ADD.txt/PINNED.txt(KV 键 ADD.bak.txt / PINNED.bak.txt)。ADD.txt 用纯文本写入(每行 IP:端口#US-CF-序号,标签不要带 CN),PINNED.txt 每行 IP:端口。
6. 不改 Worker 代码、不改 UUID/变量、不删其他 KV 键;不在报告里打印 UUID 或订阅 token。
7. 报告:保留/移除了哪些条目和国内延迟,提醒我在小火箭里"更新订阅"。
```

## 排查:中国移动下所有节点超时

按顺序做,前面的成本最低:
1. 小火箭「更新订阅」,确认节点 path 是 `/?ed=2560`、带 `fragment` 参数(v4.2 默认)。
2. 换 2053/8443/2083 端口的节点试。
3. 小火箭升到最新版;有人反馈更新后要把 TLS 密钥交换改成支持 X25519MLKEM768(nodeseek post-977144)。
4. Wi-Fi 能用、5G 不能 → 运营商封了节点域名(edgetunnel issue #1221 作者答复),换一个别的主域下的自定义域名;换 IP/端口没用。
5. 还不行 → 上游选项换 XHTTP 传输(nodeseek post-977144 有人反馈移动网下更好),配合新域名。
6. ECH 先别开:有冷启动连不上的报告(edgetunnel issue #1291)。

依据:edgetunnel CHANGELOG(2026-05-29 起中国移动直连降为单路拨号;2026-07-11 新增 `TCP_CONCURRENT_DIAL`)、edgetunnel issues #1221 / #1291 / #1206(0-RTT、分片选项说明)、nodeseek post-977144(2026-10 小火箭移动网超时讨论)、以及上面这次用户实测。

## 解决问题的方法(本包的做法)

1. **先搜**:上游仓库 CHANGELOG / issues、论坛(nodeseek 等)近一个月有没有同样的现象和已验证的解法。
2. **再推理**:分层排除 —— DNS → TCP 443 → HTTPS → 代理协议层;用国内多地拨测(globalping 等)代替猜测。
3. **在用户真实环境里实测**:CF 侧/海外测通不算数,以用户的运营商和客户端为准。
4. **小步迭代**:每次只改一两个上游原生选项,先备份,保持订阅链接不变,测完再改下一步;把用户验证过的结果固化(置顶 + 默认配置)。

## v4.1 改了什么(让自愈真正干活)

- **v4 的实话**:实测一个真实用户节点,`ADD.txt` 10 条全是 Cloudflare 官方 IP,Worker 一条都测不了(unverifiable 10),等于没在自愈。v4.1 修的就是这个。
- **候选池换成可测的第三方反代 IP**:默认先拉 `cmliu/WorkerVless2sub` 的 `addressesapi.txt`(edgetunnel 作者维护)和 `ymyuuu/IPDB` 的 `bestproxy.txt`/`proxy.txt`,CF 官方优选清单只作兜底。部署时本机会用 SNI=你的域名做 TLS 握手,只把真能转到你节点的反代 IP 写进 `POOL.txt`。
- **探测更严**:不只看 TCP 能连,还发带 SNI 的 TLS ClientHello,必须收到 TLS 握手回包才算活。CF 官方段直接标"无法验证",不浪费探测次数。
- **优先可测条目**:`ADD.txt` 至少保留 5 条可测的反代 IP;不够就用活的反代 IP 替换掉末尾的 CF 官方 IP(CF 官方 IP 仍保留一部分,不删光);补不满时用 CF 官方优选兜底,节点数不缩水。
- `/heal-status` 新增 `probed`、`testable_alive`、`replaced_unverifiable` 字段。
- `auto_deploy.sh`:升级前自动备份脚本/设置/Cron;升级时用线上 Worker 实际绑定为 `KV` 的命名空间(不再按名字猜,找不到就停);不再依赖 `wrangler deployments list --name`。
- 仍然的限制:反代 IP 是第三方的,能握手≠国内三网一定快;探测在 CF 机房跑。CF 官方 IP 依旧测不了。

## v4 改了什么(自愈)

- **订阅链接固定不变**:还是你自己 workers.dev(或自定义域名)上的同一个 `/sub` 链接,节点列表在你自己的 KV。
- **免费 Cron 自动巡检**(默认每 20 分钟):测 `ADD.txt` 里的优选IP,坏的自动从候选池换掉,写回 KV。小火箭只要「更新订阅」,不用重扫码。
- 新增 `templates/heal_entry.js`(包住上游 `_worker.js`,上游一行不改);`auto_deploy.sh` 加 Cron、复用 KV、`UPGRADE=1` 原地升级。
- **老用户**:`UPGRADE=1 NAME=<你的Worker名>` 重跑脚本,同一个 Worker、同一个 UUID → 订阅链接不变。只有当初导入**单条节点链接**的人才要重扫。
- 限制实话:Workers 不能直接 TCP 探测 Cloudflare 自家 IP 段,这类优选IP只保留不判死;巡检能判的是第三方反代 IP 和域名条目。
- 可选(仅文档):VPS/PaaS 用你自己的 API Token(存成 Worker Secret)自动换 IP/重部署。

## v3 改了什么

- 新增「★ 通用 Agent 全自动模式」:默认零提问,用户只登录。
- 新增 `scripts/auto_deploy.sh`:下载校验→wrangler 登录→建 Worker/KV→生成密钥→部署→自验→优选IP冻结→二维码,一条命令。
- 新增 `AGENTS.md` / `GEMINI.md` / `CLAUDE.md`:各家 Agent 自动读取的入口说明。
- 新增 `CREDITS.md`:上游 edgetunnel(GPL-2.0)等致谢;本包不分发 `_worker.js`。
- 不再要求用户自己想面板密码、贴 API Token:密码/UUID 自动生成,只存本机。
- 原来的六步向导保留,仅在用户要求"一步一步来"时使用。

## 常见问题

- **连不上、全部超时**:大概率是 workers.dev 在大陆被卡。给 AI 一个已在 Cloudflare 激活的域名,让它绑子域名重发二维码(换优选IP没用)。
- **地区不对**:优选IP只能偏向某地区,出口永远是 Cloudflare,不是住宅IP。让 AI 换地区重跑优选步骤。
- **优选IP失效/节点越来越慢**:v4 会自动巡检替换;想立刻刷新就让 AI 重跑脚本第 8 步。看巡检结果:`https://<你的地址>/heal-status?key=<你的UUID>`。
- **报 1027**:免费额度一天 10 万次用完,北京时间早上 8 点(UTC 0 点)重置。
- **workers.dev 地址报 1101**:实测同一账号下所有 Worker(包括没升级 v4 的)的 workers.dev 地址同时报 1101,自定义域名正常,不是 v4 导致的;订阅走自定义域名即可。
- **报 1101**:让 AI 删掉本次新建的 Worker 重建,密钥改用 Dashboard 添加。

---

## 以下为 v2 原说明

把一套 Cloudflare 全球边缘节点(Workers/Pages + KV 优选 IP)的搭建经验做成 AI Skill。新 Bot 只看这个 Skill,在操作者提供自己的 Cloudflare 账号/域名后,应能一路走到:真实订阅链接 + 可扫码的订阅二维码。

v2 修订(2026-10-17,依独立实测 15 条意见):新增开工前 STOP-and-ask 门禁清单、源码钉版下载+SHA-256 校验、按源码写死的订阅 URL/令牌公式、完整 VLESS URI 示例、base64 解码验证、优选 IP 先测活再写 ADD.txt、KV 自动建键对照表、强制二维码交付步骤与 Final Delivery Checklist。

实测补充(2026-10-17):优先绑自定义域名当正式 HOST/SNI;只用 workers.dev 时大陆网络常见全部节点超时。部署方必须先自验订阅解码与握手,不得把未验证的节点批量甩给用户逐个试。

提速路线(A>B>C,详见 SKILL.md 3.4/第6节):A 域名已在 Cloudflare 激活的,直接用 API/Wrangler 绑 Worker 自定义域名,Cloudflare 自动建 DNS+证书,分钟级、不用等 NS;B 域名在别家/DNSHE 但能改 DNS 的,走 Pages + 外部 CNAME 子域名(edge-node 子域名指向 <项目>.pages.dev),跳过整域 NS 激活,根域名不行、记录冲突就换子域名名绝不覆盖;C 实在不行才迁 NS 到 Cloudflare,最慢,每15分钟查一次、超2小时还 initializing 就停下汇报并建议删区重加,激活前不绑域名不出码。用户答题时 AI 后台并行预热(下载校验程序、拉优选清单、预探候选),答完直接开工。

优选 IP 两段式(详见 SKILL.md 第7节):第一段图快,ADD.txt 只放一行社区优选列表 URL(按用户选的地区交集),交付必须明说「社区源自动列表版(未逐个实测)」;同一轮里第二段由 AI 拉清单、按地区筛、逐个 TLS 探活(SNI=正式域名),冻结最多10个明确 IP 进 ADD.txt 并去掉那行活链接,才叫「已冻结实测版」。社区源是第三方、无授权声明、可能失效或变更,只运行时引用,绝不把它们的数据文件打包进本包;BEST_SUB 默认留空,绝不把用户的 UUID/HOST 发给公共订阅生成/转换站。CloudflareSpeedTest 只作小样本兜底(-n 200 -dn 10),AI 机器上测的快不等于用户手机运营商测的快。

## 架构

- 入口:Cloudflare 全球边缘(随机优选,或 KV `ADD.txt` 里的自选优选 IP)
- 核心:钉版单文件 Worker(`_worker.js`,上游 cmliu/edgetunnel,commit `66f1c51c4ecee058b959104cb0517e073cdb1213`,SHA-256 见 SKILL.md)
- 出口:Cloudflare Workers 出口。不是住宅出口,也不是 VPS。
- 交付物:管理面板 URL、订阅 URL(`https://<HOST>/sub?token=<TOKEN>`)、订阅二维码 PNG、已连通的客户端

## 小白模式(默认)

下载了这个 Skill 的 AI 应该进入"向导模式":一次只问一个问题(有没有 CF 账号、用免费地址还是自己的域名、面板密码、想要哪个国家),其余的它自己做,最后给用户一张二维码扫码就行。用户不需要懂部署,也不需要自己动手部署。

必需与可选,说清楚:
- Cloudflare 账号:必需,免费注册,没有它搭不了。
- 域名:不必需,但有就优先用。有绑在 Cloudflare 上的域名就绑个子域名当正式地址;没有域名也能先用 workers.dev 部署,但大陆网络下 workers.dev 当节点地址常见整批节点握手超时(面板能开不代表节点能连),真超时就绑自定义域名、改 HOST 后重发订阅和二维码(换地址后旧二维码失效)。
- 国家/地区:用户自己选。AI 按选的地区找入口、实测出口IP归属地,报"实际出口是哪儿",用户点头才定,不行就换。优选IP只能尽量偏向某地区,不能承诺任意国家、更不能承诺住宅出口;出口始终是 Cloudflare 边缘。

## 向导开场预览

装好 Skill 的 AI 会先发这一张卡, 然后按 第1/6步 到 第6/6步 一步一步问, 最后一步是 第6/6步(选地区):

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

觉得太长可以对 AI 说"简单点", 它会压成三段对话来讲, 但该问的和该验的一样都不会少。

没域名也有路(第2/6步子分支 D1-D4): 第2步选 3,AI 先问是否主要在大陆网络用,不在大陆可直接跳过域名用 workers.dev;在大陆又想稳,AI 会自己打开它的云端浏览器去 [DNSHE 免费域名](https://my.dnshe.com/clientarea.php?language=chinese&autolang=1) 和 Cloudflare 全程操作注册(该站有不同年限，优先选10年期；若只有1年期，老实告知续期规则：到期前180天内免费续；以站点当期规则为准,不承诺没在现场看到的年限),你不用在自己的浏览器里动手注册。你只过几个"确认点":确认登录状态(如批准 Google 登录提示、确认"已登录")、完成 AI 做不了的人机验证/2FA 验证码、以及对着准确域名回复"好，注册 <域名>"后 AI 才提交注册。密码和验证码绝不打进聊天,只填进浏览器自己的登录框/宿主提供的安全凭据提示;AI 不得绕过人机验证、不得批量注册,一次只注一个。查域名、改 NS 到 Cloudflare、等 DNS 激活、绑 Worker 自定义域名、改 HOST、重发订阅和二维码都由 AI 在云端浏览器/后台做完再汇报;AI 若根本没有浏览器工具,必须老实说并改成一步步引导,不假装浏览过。免费套餐若不让改 NS,AI 会停下来让你选别的域名或接受 workers.dev 的超时风险,不假装成功。域名是你自己的资产,DNSHE 和 Cloudflare 的登录方式请自己收好。

电脑端实跑补记(已去敏,详见 SKILL.md 第3.3/3.4/6/9节):域名卡 `initializing` 先查建站向导/计划步骤是否走完,没走完 Cloudflare 可能还没开始开通,走完再套每15分钟查、超2小时停的规则;~5MB 大 Worker 的密钥默认走面板添加(干净重部署),CLI/API 加密钥后必须立刻验 `/login`、`/sub`,若持续 1101/500 且重传代码修不好,就删掉重建这个新建 Worker 再用面板加密钥——这是现场观察的故障模式,不是"CLI 必坏"的定论,此前 API 部署也有成功例;某些绑域名接口不收 OAuth 令牌时改走面板绑域名;排 500 用最小对照组,一次只变一个因素(无密钥/有密钥、小文件/大文件)。

手机端实跑补记(已去敏,详见 SKILL.md 第6/7/9节):Pages 网页拖拽上传 `_worker.js` 卡住超10分钟就改走 API/CLI——临时令牌只给 Pages:Edit 权限、`wrangler pages deploy` 传完即删令牌,浏览器继续管登录/变量/绑域名;`<项目>.pages.dev` 名字被占时 Cloudflare 会给带后缀的实际域名,首次 200 可能是别人的项目,先确认实际分配的域名归本项目再报成功;Agent 沙箱可能有透明代理/TLS 中间人,探活全军覆没时换干净出口(如目标地区附近的 VPS)用 `www.cloudflare.com` 这类必认的 SNI 验边缘存活,正式域名 SNI 等自定义域名生效后再验;DNSHE 表单全对却反复报后端失败,先怀疑登录会话过期、重登一次再提交,别反复重试表单;地区最终结论优先用真实客户端(如 xray)跑出的 `cdn-cgi/trace` 的 `colo`/`loc`,没有就标注未验证。免费域名年限同上:该站有不同年限，优先选10年期；若只有1年期，老实告知续期规则：到期前180天内免费续。

## 怎么用

把整个文件夹交给 AI 助理,让它先读 `SKILL.md` 第 0 节门禁:缺 Cloudflare 登录方式、Worker 名、域名决定、ADMIN 密码、UUID 决定中的任何一项,它必须停下来问你,不得自行假设。备齐后按第 6 节部署,第 10 节出二维码。

## 文件清单

| 文件 | 作用 |
|---|---|
| `SKILL.md` | Skill 本体:门禁、源码校验、变量与 HOST 关系、订阅/URI 公式、部署、优选 IP、验证、排障、二维码、交付清单 |
| `templates/heal_entry.js` | v4 自愈入口:包住上游 `_worker.js`,加 Cron 巡检 ADD.txt / 候选池补位 / `/heal-status` |
| `templates/wrangler.toml.example` | CLI 部署模板(密钥不进此文件,用 wrangler secret) |
| `templates/ADD.txt.example` | 优选 IP 格式示例(占位符,不能直接用) |
| `templates/env.example` | 变量清单(与 SKILL.md 第 3.2 节一致:首建 PROXYIP/BEST_SUB/GO2SOCKS5 留空) |
| `templates/make_sub_qr.py` | 已实测的订阅二维码生成+解码校验脚本(pip install "qrcode[pil]") |

## 费用实话(2026-10-17 查 Cloudflare 官方文档)

Workers 免费版每天 100,000 次请求,超限报 1027,UTC 零点重置;KV 免费版每天 100,000 次读、1,000 次写、账号 1 GB。个人自用一般够,触顶再考虑 Workers Paid。谁说"无限免费",让他出示官方文档。

## 安全红线

- `ADMIN`、`UUID`、`KEY`、订阅链接、二维码 PNG、API Token 都是钥匙,不要发到公开仓库、文章、截图。本包全是占位符。
- `_worker.js` 只用 SKILL.md 里的钉版地址下载,并校验 SHA-256,对不上就停。
- 这不是匿名工具:Cloudflare 是运营方,账号与操作者身份绑定。
- 先备一条非 CF 的备用线路。

## 发布方式

本仓库已开源，也可下载 zip 离线使用。仓库和 zip 里都只放占位符版本，不含任何真实账号、域名、UUID、令牌或订阅。
