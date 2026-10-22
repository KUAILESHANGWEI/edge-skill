// v4 自愈入口:包住上游 edgetunnel,追加 Cron 巡检。全部跑在用户自己的 CF 账号里(免费额度)。
// KV 键: ADD.txt(当前在用优选IP, edgetunnel 原生读取) / POOL.txt(候选池) / HEAL_STATUS.json(最近一次巡检结果)
// 订阅链接 = https://<HOST>/sub?token=md5(md5(HOST+UUID)[7:27]),只要 Worker/HOST/UUID 不变,链接永远不变。
import { connect } from "cloudflare:sockets";
import upstream from "./_worker.js";

const KEEP = 10;          // ADD.txt 目标条数
const MAX_PROBES = 40;    // 单次巡检最多探测数(免费版每次调用子请求上限 50,留余量)
const TIMEOUT_MS = 2500;
const POOL_SOURCES = [    // 社区公开候选池(可用 env.POOL_SOURCES 覆盖,逗号分隔)
  "https://raw.githubusercontent.com/LancelotRar/best-cf-ips/main/best-cf-ip-scanned-top20.txt",
  "https://raw.githubusercontent.com/joname1/BestCFip/main/ipv4.txt",
];

export function parseList(text) {
  const out = [], seen = new Set();
  for (const raw of String(text || "").split(/\r?\n|,/)) {
    const m = raw.trim().match(/^(\d{1,3}(?:\.\d{1,3}){3}|\[[0-9a-fA-F:]+\]|[A-Za-z0-9.-]+\.[A-Za-z]{2,})(?::(\d{1,5}))?(?:#(.*))?$/);
    if (!m) continue;
    const e = { host: m[1], port: Number(m[2] || 443), label: (m[3] || "CF").trim() };
    const k = e.host + ":" + e.port;
    if (!seen.has(k)) { seen.add(k); out.push(e); }
  }
  return out;
}
export const fmt = (e) => `${e.host}:${e.port}#${e.label}`;

// 返回 "ok" | "dead" | "unverifiable"(Workers 不允许 connect() 到 Cloudflare 自家 IP 段,这类不删)
export async function probe(e, connectFn = connect) {
  let sock;
  try {
    sock = connectFn({ hostname: e.host.replace(/^\[|\]$/g, ""), port: e.port });
    const t = new Promise((_, rej) => setTimeout(() => rej(new Error("timeout")), TIMEOUT_MS));
    await Promise.race([sock.opened, t]);
    return "ok";
  } catch (err) {
    const msg = String(err && err.message || err);
    return /disallow|cloudflare|not allowed|prohibited|proxy request/i.test(msg) ? "unverifiable" : "dead";
  } finally { try { sock && sock.close(); } catch {} }
}

async function loadPool(env, region) {
  let pool = parseList(await env.KV.get("POOL.txt"));
  const srcs = env.POOL_SOURCES ? String(env.POOL_SOURCES).split(",") : POOL_SOURCES;
  if (pool.length < KEEP * 2) {
    for (const s of srcs) {
      try {
        const r = await fetch(s.trim(), { cf: { cacheTtl: 3600 } });
        if (r.ok) pool = pool.concat(parseList(await r.text()));
      } catch {}
      if (pool.length >= KEEP * 3) break;
    }
  }
  if (region) pool = pool.filter((e) => e.label.toUpperCase().includes(region));
  return pool;
}

// 免费版每请求最多 6 条并发出站连接,超出会排队 → 分批 6 个探测,避免排队期间被超时误判为死
async function probeAll(list, connectFn) {
  const out = [];
  for (let i = 0; i < list.length; i += 6) out.push(...await Promise.all(list.slice(i, i + 6).map((e) => probe(e, connectFn))));
  return out;
}

export async function heal(env, connectFn = connect) {
  const region = String(env.HEAL_REGION || "").toUpperCase();
  const current = parseList(await env.KV.get("ADD.txt"));
  const status = { at: new Date().toISOString(), kept: [], removed: [], added: [], unverifiable: 0 };
  let budget = MAX_PROBES;
  const alive = [];
  const results = await probeAll(current.slice(0, budget), connectFn);
  budget -= results.length;
  current.forEach((e, i) => {
    const r = results[i] || "ok";
    if (r === "dead") status.removed.push(fmt(e)); else { alive.push(e); status.kept.push(fmt(e)); }
    if (r === "unverifiable") status.unverifiable++;
  });
  if (alive.length < KEEP && budget > 0) {
    const have = new Set(alive.map((e) => e.host + ":" + e.port));
    const dead = new Set(status.removed.map((s) => s.split("#")[0]));
    const cand = (await loadPool(env, region)).filter((e) => !have.has(e.host + ":" + e.port) && !dead.has(e.host + ":" + e.port)).slice(0, budget - 2);
    const rs = await probeAll(cand, connectFn);
    cand.forEach((e, i) => { if (rs[i] !== "dead" && alive.length < KEEP) { alive.push(e); status.added.push(fmt(e)); } });
  }
  // 只有变化时才写 KV(免费版 KV 写入 1000 次/天)
  if (alive.length && (status.removed.length || status.added.length)) await env.KV.put("ADD.txt", alive.map(fmt).join("\n"));
  await env.KV.put("HEAL_STATUS.json", JSON.stringify(status));
  return status;
}

export default {
  async fetch(request, env, ctx) {
    const u = new URL(request.url);
    if (u.pathname === "/heal-status" && env.UUID && u.searchParams.get("key") === env.UUID) {
      return new Response((await env.KV.get("HEAL_STATUS.json")) || "{}", { headers: { "content-type": "application/json" } });
    }
    return upstream.fetch(request, env, ctx);
  },
  async scheduled(event, env, ctx) { ctx.waitUntil(heal(env)); },
};
