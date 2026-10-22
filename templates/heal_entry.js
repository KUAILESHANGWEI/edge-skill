// v4.2 自愈入口(v4 起):包住上游 edgetunnel,追加 Cron 巡检。全部跑在用户自己的 CF 账号里(免费额度)。
// KV 键: ADD.txt(当前在用优选IP, edgetunnel 原生读取) / POOL.txt(候选池) / HEAL_STATUS.json(最近一次巡检结果)
// 订阅链接 = https://<HOST>/sub?token=md5(md5(HOST+UUID)[7:27]),只要 Worker/HOST/UUID 不变,链接永远不变。
import { connect } from "cloudflare:sockets";
import upstream from "./_worker.js";

const KEEP = 10;          // ADD.txt 目标条数
const MAX_PROBES = 40;    // 单次巡检最多探测数(免费版每次调用子请求上限 50,留余量)
const TIMEOUT_MS = 2500;
const MIN_TESTABLE = 5;   // v4.1: ADD.txt 里至少这么多条"可测"条目(第三方反代IP/域名),不够就用活的可测条目替换掉末尾的 CF 官方IP
// v4.1 候选池:先第三方反代 IP(Worker 能真测),再 CF 官方优选(测不了,只作兜底)。可用 env.POOL_SOURCES 覆盖,逗号分隔
const POOL_SOURCES = [
  "https://raw.githubusercontent.com/cmliu/WorkerVless2sub/main/addressesapi.txt", // edgetunnel 作者维护的反代IP(带端口/地区)
  "https://raw.githubusercontent.com/ymyuuu/IPDB/main/bestproxy.txt",             // 社区反代IP(精选)
  "https://raw.githubusercontent.com/ymyuuu/IPDB/main/proxy.txt",                 // 社区反代IP(全量)
  "https://raw.githubusercontent.com/LancelotRar/best-cf-ips/main/best-cf-ip-scanned-top20.txt",
  "https://raw.githubusercontent.com/joname1/BestCFip/main/ipv4.txt",
];
const SEED_CN = "172.66.44.98:443#CF,104.31.16.158:443#CF,104.18.81.19:443#CF,162.159.140.116:443#CF,162.159.128.253:443#CF,172.66.44.98:8443#CF-8443,104.31.16.158:2053#CF-2053,162.159.140.116:2083#CF-2083";
// Cloudflare 官方 IPv4 段(Worker 的 connect() 连不上这些,只能标"无法验证")
const CF_V4 = ["173.245.48.0/20","103.21.244.0/22","103.22.200.0/22","103.31.4.0/22","141.101.64.0/18","108.162.192.0/18","190.93.240.0/20","188.114.96.0/20","197.234.240.0/22","198.41.128.0/17","162.158.0.0/15","104.16.0.0/12","172.64.0.0/13","131.0.72.0/22"];
const ip2n = (ip) => ip.split(".").reduce((a, b) => a * 256 + Number(b), 0);
export function isCfIp(host) {
  if (!/^\d+\.\d+\.\d+\.\d+$/.test(host)) return false;
  const n = ip2n(host);
  return CF_V4.some((c) => { const [b, m] = c.split("/"); const size = 2 ** (32 - Number(m)); const s = ip2n(b); return n >= s && n < s + size; });
}
// v4.2: 只有"非 CF 的 IP"算可测。域名可能解析到 CF(connect 会失败被误判死),一律按无法验证处理,不删。
export const testable = (e) => /^\d+\.\d+\.\d+\.\d+$/.test(e.host) && !isCfIp(e.host);
// v4.2: 置顶条目。KV PINNED.txt(每行 host:port,可带 #备注)或 ADD.txt 里备注含 "pin" 的条目,Cron 永不删除/替换。
// 用途:在用户真实网络(如中国移动 5G)验证过的条目。CF 机房里的探测看不到国内侧的阻断,所以人工验证结果优先。
export const keyOf = (e) => e.host + ":" + e.port;
export function pinnedSet(pinText, entries) {
  const s = new Set(parseList(pinText).map(keyOf));
  for (const e of entries) if (/\bpin\b/i.test(e.label)) s.add(keyOf(e));
  return s;
}

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
// v4.1: 第三方条目不只看 TCP 能连,还发一个带 SNI=HOST 的 TLS ClientHello,必须收到 TLS 握手记录(0x16 0x03)才算活
export function clientHello(sni) {
  const name = new TextEncoder().encode(sni || "www.cloudflare.com");
  const rnd = crypto.getRandomValues(new Uint8Array(32));
  const u16 = (n) => [n >> 8 & 255, n & 255];
  const sniExt = [0, 0, ...u16(name.length + 5), ...u16(name.length + 3), 0, ...u16(name.length), ...name];
  const groups = [0, 10, 0, 4, 0, 2, 0, 23];
  const sigs = [0, 13, 0, 8, 0, 6, 4, 3, 8, 4, 4, 1];
  const alpn = [0, 16, 0, 11, 0, 9, 8, ...new TextEncoder().encode("http/1.1")];
  const ext = [...sniExt, ...groups, ...sigs, ...alpn];
  const ciphers = [0xc0, 0x2b, 0xc0, 0x2f, 0xc0, 0x2c, 0xc0, 0x30, 0xcc, 0xa9, 0xcc, 0xa8, 0x13, 0x01];
  const body = [3, 3, ...rnd, 0, ...u16(ciphers.length), ...ciphers, 1, 0, ...u16(ext.length), ...ext];
  const hs = [1, 0, ...u16(body.length), ...body];
  return new Uint8Array([22, 3, 1, ...u16(hs.length), ...hs]);
}
export async function probe(e, connectFn = connect, sni = "") {
  if (isCfIp(e.host)) return "unverifiable";
  let sock;
  try {
    sock = connectFn({ hostname: e.host.replace(/^\[|\]$/g, ""), port: e.port });
    const t = new Promise((_, rej) => setTimeout(() => rej(new Error("timeout")), TIMEOUT_MS));
    await Promise.race([sock.opened, t]);
    if (!sock.writable || !sock.readable) return "ok"; // 单测里的假 socket
    const w = sock.writable.getWriter(); await w.write(clientHello(sni)); w.releaseLock();
    const r = sock.readable.getReader();
    const { value } = await Promise.race([r.read(), t]);
    return value && value[0] === 22 && value[1] === 3 ? "ok" : "dead";
  } catch (err) {
    const msg = String(err && err.message || err);
    return /disallow|cloudflare|not allowed|prohibited|proxy request/i.test(msg) ? "unverifiable" : "dead";
  } finally { try { sock && sock.close(); } catch {} }
}

async function loadPool(env, region) {
  let pool = parseList(await env.KV.get("POOL.txt"));
  const srcs = env.POOL_SOURCES ? String(env.POOL_SOURCES).split(",") : POOL_SOURCES;
  if (pool.filter(testable).length < KEEP * 2) {
    for (const s of srcs) {
      try {
        const r = await fetch(s.trim(), { cf: { cacheTtl: 3600 } });
        // 远程清单只收 IP 条目(防止把 "ipv4.list.updated.at" 这类注释行当域名);域名条目请手动写进 POOL.txt
        if (r.ok) pool = pool.concat(parseList(await r.text()).filter((e) => !/[a-z]/i.test(e.host.replace(/^\[.*\]$/, ""))));
      } catch {}
      if (pool.filter(testable).length >= KEEP * 3) break;
    }
  }
  if (region) pool = pool.filter((e) => e.label.toUpperCase().includes(region));
  // v4.2 兜底种子:2026-10-23 在中国移动(AS9808)国内拨测 TCP 443 通、且在用户中国移动 5G 下实测可用的 CF 优选条目。
  // 只是"曾经验证过"的起点,不保证长期有效;国内可用性只能在用户网络里确认。
  const seen = new Set(pool.map(keyOf));
  for (const e of parseList(SEED_CN)) if (!seen.has(keyOf(e))) pool.push(e);
  // v4.2 CF_ONLY(默认开):只用 Cloudflare 自有 IP,绝不加入第三方反代/域名(反代运营者能看到你的连接元数据)
  if (cfOnly(env)) pool = pool.filter((e) => isCfIp(e.host));
  return pool.filter(testable).concat(pool.filter((e) => !testable(e)));
}
export const cfOnly = (env) => String(env.HEAL_CF_ONLY ?? "1") !== "0";

// 免费版每请求最多 6 条并发出站连接,超出会排队 → 分批 6 个探测,避免排队期间被超时误判为死
async function probeAll(list, connectFn, sni) {
  const out = [];
  for (let i = 0; i < list.length; i += 6) out.push(...await Promise.all(list.slice(i, i + 6).map((e) => probe(e, connectFn, sni))));
  return out;
}

export async function heal(env, connectFn = connect) {
  const region = String(env.HEAL_REGION || "").toUpperCase();
  const sni = String(env.HOST || "").split(",")[0].trim();
  const current = parseList(await env.KV.get("ADD.txt"));
  const pins = pinnedSet(await env.KV.get("PINNED.txt"), current);
  const keep = Number(env.HEAL_KEEP) > 0 ? Number(env.HEAL_KEEP) : KEEP;
  const status = { version: "4.2", cf_only: cfOnly(env), pinned: 0, at: new Date().toISOString(), probed: 0, kept: [], removed: [], added: [], replaced_unverifiable: [], unverifiable: 0 };
  let budget = MAX_PROBES;
  const results = await probeAll(current, connectFn, sni);   // CF 官方IP 不耗连接预算
  status.probed = current.filter(testable).length; budget -= status.probed;
  let alive = [];
  current.forEach((e, i) => {
    const r = results[i];
    const pin = pins.has(keyOf(e));
    // 只删"可测且确认死"的非置顶条目
    if (!pin && (r === "dead" || (cfOnly(env) && !isCfIp(e.host)))) status.removed.push(fmt(e)); else { alive.push({ e, r, pin }); status.kept.push(fmt(e)); }
  });
  const nTest = () => alive.filter((x) => x.r === "ok").length;
  if ((alive.length < keep || nTest() < MIN_TESTABLE) && budget > 0) {
    const have = new Set(alive.map((x) => x.e.host + ":" + x.e.port));
    const dead = new Set(status.removed.map((s) => s.split("#")[0]));
    const cand = (await loadPool(env, region)).filter(testable)
      .filter((e) => !have.has(e.host + ":" + e.port) && !dead.has(e.host + ":" + e.port)).slice(0, budget);
    const rs = await probeAll(cand, connectFn, sni);
    status.probed += cand.length;
    for (let i = 0; i < cand.length; i++) {
      if (rs[i] !== "ok") continue;
      if (alive.length < keep) { alive.push({ e: cand[i], r: "ok" }); status.added.push(fmt(cand[i])); continue; }
      if (nTest() >= MIN_TESTABLE) break;
      const j = alive.map((x) => (x.r === "unverifiable" && !x.pin ? 1 : 0)).lastIndexOf(1);   // 用活的可测条目替换末尾一个 CF 官方IP
      if (j < 0) break;
      status.replaced_unverifiable.push(fmt(alive[j].e)); status.kept.splice(status.kept.indexOf(fmt(alive[j].e)), 1);
      alive[j] = { e: cand[i], r: "ok" }; status.added.push(fmt(cand[i]));
    }
  }
  // 可测条目不够补满时,用 CF 官方优选兜底(标"无法验证"),保证订阅节点数不缩水
  if (alive.length < keep) {
    const have = new Set(alive.map((x) => x.e.host + ":" + x.e.port));
    for (const e of (await loadPool(env, region)).filter((e) => !testable(e) && !have.has(e.host + ":" + e.port))) {
      if (alive.length >= keep) break; alive.push({ e, r: "unverifiable" }); status.added.push(fmt(e));
    }
  }
  status.pinned = alive.filter((x) => x.pin).length;
  status.unverifiable = alive.filter((x) => x.r === "unverifiable").length;
  status.testable_alive = nTest();
  // 只有变化时才写 KV(免费版 KV 写入 1000 次/天);永远不会把 ADD.txt 写空
  if (alive.length && (status.removed.length || status.added.length)) await env.KV.put("ADD.txt", alive.map((x) => fmt(x.e)).join("\n"));
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
