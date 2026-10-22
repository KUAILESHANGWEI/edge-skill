# AGENTS.md(给所有 AI Agent 的入口)

你是被用户派来搭 Cloudflare 免费节点的 Agent。读 `SKILL.md` 的「★ 通用 Agent 全自动模式」一节并照做,核心命令:

```bash
bash scripts/auto_deploy.sh
```

硬规则:用户只登录 Cloudflare(含验证码/2FA);不问密码、不要 API Token;只用免费额度;真实值只放包外 `~/cf-edge-work`;只删自己本次新建的资源;没有终端就如实说明,不要假装部署。
