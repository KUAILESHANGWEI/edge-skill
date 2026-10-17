# 给 Meta Muse 的实测提示词（复制下面整段发给 Muse）

请测试一个 AI Skill，不要使用任何真实账号、真实域名或任何人的真实订阅。

随附的 zip 就是本 skill 的全部文件。

请你这样做：
1. 解开随附 zip，读取 SKILL.md、README.md 和 templates/ 里的全部文件，把 SKILL.md 当作一个 skill 保存/安装，然后完整读一遍。
2. 只在沙箱 / 无真实账号模式下运行这个 skill 的向导：严格遵守第 0 节门禁。缺少 Cloudflare 登录方式、Worker 名、规范主机名/zone、ADMIN 密码、UUID 决定、客户端目标时，必须停下来列出缺什么，不许编造、不许继续部署。
3. 明确禁止：不要登录或使用任何真实 Cloudflare 账号，不要使用真实域名、真实 UUID、真实令牌、真实订阅链接，不要碰任何现有 Worker、KV、节点或 3x-ui。
4. 用占位值继续本地验证：主机名用 node.example.com，占位 UUID 只用 skill 里标明的公开代码占位 00000000-0000-4000-8000-000000000000，入口 IP 只用 RFC 5737 文档 IP（如 192.0.2.10）。按 skill 的公式核对订阅 URL 形式 https://<HOST>/sub?token=<TOKEN>，并说明 TOKEN 如何派生。
5. 运行 templates/make_sub_qr.py，对占位订阅 URL https://node.example.com/sub?token=EXAMPLE_PLACEHOLDER_TOKEN_NOT_REAL 生成二维码 PNG，再做解码校验，报告 QR_DECODE_MATCH 是否为 True。
6.逐节给出 PASS / FAIL / PARTIAL：门禁、向导问答、地区选择（用户选国家、实测出口、用户拍板）、钉版 _worker.js 下载与 SHA-256 校验说明、订阅 URL、VLESS URI 示例、base64 验证、Shadowrocket 导入坑（关 UDP Relay、核对 Host/SNI/Path）、二维码闭环、最终交付清单。任何不清楚、互相矛盾、照抄会报错的步骤，单独列出来并引用原文。
7. 最后明确写：你没有完成真实部署，也没有生成可用的真实订阅二维码；示例二维码扫了不能用。不要谎称成功。

请把完整测试报告发回来。
