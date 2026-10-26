const crypto = require("node:crypto");
const { Readable } = require("node:stream");

const ORIGIN = "https://vantasm-bridge.vercel.app";
const DISCOVERY_URL = "https://raw.githubusercontent.com/lokivelli316/EARLYWINE-PRESIDENTIAL-BLUEPRINT/main/vantasm/endpoint.json";
const CLAUDE_CALLBACK = "https://claude.ai/api/mcp/auth_callback";
const SCOPE = "vantasm:operate";
const KEY_RAW = process.env.VANTASM_OAUTH_ENC_KEY;

function htmlEscape(s="") {
  return String(s).replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
}
function b64u(buf) { return Buffer.from(buf).toString("base64url"); }
function fromB64u(s) { return Buffer.from(s, "base64url"); }
function key() {
  if (!KEY_RAW) throw new Error("oauth key unavailable");
  const b = fromB64u(KEY_RAW);
  if (b.length !== 32) throw new Error("oauth key invalid");
  return b;
}
function seal(obj, ttlSec) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", key(), iv);
  const payload = Buffer.from(JSON.stringify({...obj, exp: Math.floor(Date.now()/1000)+ttlSec}));
  const ct = Buffer.concat([cipher.update(payload), cipher.final()]);
  const tag = cipher.getAuthTag();
  return "vo1." + [iv, tag, ct].map(b64u).join(".");
}
function open(token, expectedType) {
  if (!token || !token.startsWith("vo1.")) throw new Error("not oauth token");
  const parts = token.slice(4).split(".");
  if (parts.length !== 3) throw new Error("bad token");
  const [iv, tag, ct¶»§q«^