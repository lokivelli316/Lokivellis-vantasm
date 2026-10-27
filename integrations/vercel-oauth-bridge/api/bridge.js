const crypto = require("node:crypto");
const { Readable } = require("node:stream");

const ORIGIN = "https://vantasm-bridge.vercel.app";
const DISCOVERY_URL = "https://raw.githubusercontent.com/lokivelli316/EARLYWINE-PRESIDENTIAL-BLUEPRINT/main/vantasm/endpoint.json";
const CLAUDE_CALLBACK = "https://claude.ai/api/mcp/auth_callback";
const SCOPE = "vantasm:operate";
const KEY_RAW = process.env.VANTASM_OAUTH_ENC_KEY;

function h(s=""){return String(s).replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]))}
function b64u(b){return Buffer.from(b).toString("base64url")}
function fb64u(s){return Buffer.from(s,"base64url")}
function key(){if(!KEY_RAW)throw new Error("oauth key unavailable");const b=fb64u(KEY_RAW);if(b.length!==32)throw new Error("oauth key invalid");return b}
function seal(obj,ttl){const iv=crypto.randomBytes(12),c=crypto.createCipheriv("aes-256-gcm",key(),iv);const p=Buffer.from(JSON.stringify({...obj,exp:Math.floor(Date.now()/1000)+ttl}));const ct=Buffer.concat([c.update(p),c.final()]),tag=c.getAuthTag();return"vo1."+[iv,tag,ct].map(b64u).join(".")}
function open(tok,type){if(!tok||!tok.startsWith("vo1."))throw new Error("not oauth token");const a=tok.slice(4).split(".");if(a.length!==3)throw new Error("bad token");const[iv,tag,ct]=a.map(fb64u),d=crypto.createDecipheriv("aes-256-gcm",key(),iv);d.setAuthTag(tag);const o=JSON.parse(Buffer.concat([d.update(ct),d.final()]).toString("utf8"));if(o.type!==type)throw new Error("wrong tok¶»§q«^