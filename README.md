# CF 全球边缘节点 Skill(可下载包 v2)

把一套 Cloudflare 全球边缘节点(Workers/Pages + KV 优选 IP)的搭建经验做成 AI Skill。新 Bot 只看这个 Skill,在操作者提供自己的 Cloudflare 账号/域名后,应能一路走到:真实订阅链接 + 可扫码的订阅二维码。

v2 修订(2026-10-17,依独立实测 15 条意见):新增开工前 STOP-and-ask 门禁清单、源码钉版下载+SHA-256 校验、按源码写死的订阅 URL/令牌公式、完整 VLESS URI 示例、base64 解码验证、优选 IP 先测活再写 ADD.txt、KV 自动建键对照表、强制二维码交付步骤与 Final Delivery Checklist。

## 架构

- 入口:Cloudflare 全球边缘(随机优选,或 KV `ADD.txt` 里的自选优选 IP)
- 核心:钉版单文件 Worker(`_worker.js`,上游 cmliu/edgetunnel,commit `66f1c51c4ecee058b959104cb0517e073cdb1213`,SHA-256 见 SKILL.md)
- 出口:Cloudflare Workers 出口。不是住宅出口,也不是 VPS。
- 交付物:管理面板 URL、订阅 URL(`https://<HOST>/sub?token=<TOKEN>`)、订阅二维码 PNG、已连通的客户端

## 小白模式(默认)

下载了这个 Skill 的 AI 应该进入"向导模式":一次只问一个问题(有没有 CF 账号、用免费地址还是自己的域名、面板密码、想要哪个国家),其余的它自己做,最后给用户一张二维码扫码就行。用户不需要懂部署,也不需要自己动手部署。

必需与可选,说清楚:
- Cloudflare 账号:必需,免费注册,没有它搭不了。
- 域名:不必需。先用 Cloudflare 免费的 workers.dev 地址就能跑;有自己的域名可以绑个子域名,更好记。
- 国家/地区:用户自己选。AI 按选的地区找入口、实测出口IP归属地,报"实际出口是哪儿",用户点头才定,不行就换。优选IP只能尽量偏向某地区,不能承诺任意国家、更不能承诺住宅出口;出口始终是 Cloudflare 边缘。

## 怎么用

把整个文件夹交给 AI 助理,让它先读 `SKILL.md` 第 0 节门禁:缺 Cloudflare 登录方式、Worker 名、域名决定、ADMIN 密码、UUID 决定中的任何一项,它必须停下来问你,不得自行假设。备齐后按第 6 节部署,第 10 节出二维码。

## 文件清单

| 文件 | 作用 |
|---|---|
| `SKILL.md` | Skill 本体:门禁、源码校验、变量与 HOST 关系、订阅/URI 公式、部署、优选 IP、验证、排障、二维码、交付清单 |
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

## 发布方式待确认

本包只在本地生成,未推任何外部仓库。公开分享前需操作者确认:GitHub 公开仓库、私有仓库,还是只发这个 zip。确认后也只放占位符版本。
