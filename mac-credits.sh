#!/bin/bash
# macOS Qoder CN / WorkBuddy CN / Trae CN one-shot daily credits checker.
# Based on public protocol descriptions in techysy/CreditDaddy (MIT), 2026-10.
# WorkBuddy encrypted-field decoding technique: 88lin/workbuddy-auto-signin (MIT).
# No npm dependencies; Node.js >=20 is required.
# Derived in part from techysy/CreditDaddy (MIT).
# MIT License
# Copyright (c) 2026 NoName4Me
# Copyright (c) 2026 CreditDaddy contributors
# Copyright (c) 2026 88lin/workbuddy-auto-signin contributors (WorkBuddy decrypt strategy)
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
set -euo pipefail
umask 077

NODE_BIN="${NODE_BIN:-}"
if [[ -z "$NODE_BIN" ]]; then
  for n in "$(command -v node 2>/dev/null || true)" /opt/homebrew/bin/node /usr/local/bin/node "$HOME/.volta/bin/node"; do
    if [[ -n "$n" && -x "$n" ]]; then NODE_BIN="$n"; break; fi
  done
fi
if [[ -z "$NODE_BIN" ]]; then
  echo '缺少 Node.js >= 20；请先安装 Node.js。' >&2
  exit 2
fi
NODE_MAJOR="$($NODE_BIN -p 'Number(process.versions.node.split(".")[0])')"
if (( NODE_MAJOR < 20 )); then echo "需要 Node.js >=20，当前 $($NODE_BIN -v)" >&2; exit 2; fi

LABEL='com.local.mac-credits'
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
STATE="$HOME/Library/Logs/mac-credits"
mkdir -p "$STATE"
usage() {
  echo "用法：bash $0 [--check | --diagnose | --install [--time HH:MM] | --uninstall | --status]" >&2
}
case "${1:-}" in
  --install)
    SCHEDULE_TIME="10:10"
    if (( $# == 3 )) && [[ "$2" == "--time" ]]; then
      SCHEDULE_TIME="$3"
    elif (( $# != 1 )); then
      usage
      exit 2
    fi
    # launchd uses the system's local timezone. Strictly validate before modifying the task.
    if [[ ! "$SCHEDULE_TIME" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
      echo "时间格式无效：$SCHEDULE_TIME（需要 HH:MM，00:00–23:59）" >&2
      exit 2
    fi
    mkdir -p "$HOME/Library/LaunchAgents"
    SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    mkdir -p "$HOME/.local/bin"
    STABLE="$HOME/.local/bin/mac-credits.sh"
    if [[ "$SELF" != "$STABLE" ]]; then
      install -m 700 "$SELF" "$STABLE"
    fi
    "$NODE_BIN" -e '
const fs=require("node:fs");
const [script,node,logs,dest,hour,minute]=process.argv.slice(1);
const esc=s=>String(s).replaceAll("&","&amp;").replaceAll("<","&lt;").replaceAll(">","&gt;").replaceAll("\"","&quot;");
const val=s=>`<string>${esc(s)}</string>`;
const xml=`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key>${val("com.local.mac-credits")}
<key>ProgramArguments</key><array>${val("/bin/bash")}${val(script)}</array>
<key>EnvironmentVariables</key><dict><key>NODE_BIN</key>${val(node)}<key>PATH</key>${val("/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin")}</dict>
<key>RunAtLoad</key><true/>
<key>StartCalendarInterval</key><dict><key>Hour</key><integer>${Number(hour)}</integer><key>Minute</key><integer>${Number(minute)}</integer></dict>
<key>StandardOutPath</key>${val(logs+"/run.log")}
<key>StandardErrorPath</key>${val(logs+"/error.log")}
</dict></plist>`;
fs.writeFileSync(dest,xml,{mode:0o600});
' "$STABLE" "$NODE_BIN" "$STATE" "$AGENT" "${SCHEDULE_TIME%:*}" "${SCHEDULE_TIME#*:}"
    launchctl bootout "gui/$(id -u)" "$AGENT" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$AGENT"
    echo "已启用：每天本机时间 $SCHEDULE_TIME 执行；登录时也尝试执行一次。"
    echo "日志：$STATE/run.log 和 $STATE/error.log"
    exit 0 ;;
  --uninstall)
    if [[ -f "$AGENT" ]]; then
      launchctl bootout "gui/$(id -u)" "$AGENT" 2>/dev/null || true
      rm "$AGENT"
    fi
    echo '已删除定时任务（日志保留）'
    exit 0 ;;
  --status)
    if [[ -f "$AGENT" ]]; then echo "定时任务已安装：$AGENT"; else echo '未安装定时任务'; fi
    launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | grep -E 'state =|last exit code =' || true
    exit 0 ;;
  --check|--dry-run|--diagnose|'')
    if (( $# > 1 )); then usage; exit 2; fi ;;
  *) usage; exit 2 ;;
esac

# stdin heredoc avoids temporary JS files or persistence of any tokens.
"$NODE_BIN" - "${1:-}" <<'JS'
'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const {execFile, execFileSync, spawn} = require('node:child_process');
const {promisify} = require('node:util');
const exec = promisify(execFile);
const HOME = os.homedir();
const APP = path.join(HOME, 'Library', 'Application Support');
const DIAG = process.argv.includes('--diagnose');
const CHECK = DIAG || process.argv.includes('--check') || process.argv.includes('--dry-run');
let failures = 0, seen = 0;
const read = f => fs.readFileSync(f);
const json = f => JSON.parse(fs.readFileSync(f,'utf8'));
const exists = f => fs.existsSync(f);
const sha256 = v => crypto.createHash('sha256').update(v).digest();
const sha512 = v => crypto.createHash('sha512').update(v).digest();
const hex = n => crypto.randomBytes(n).toString('hex');
const jwt = token => { try {return JSON.parse(Buffer.from(token.split('.')[1], 'base64url'));} catch {return {};}};
const fail = (name, msg) => {failures++; console.log(`[失败] ${name}: ${msg}`);};
const ok = (name, status, msg='') => console.log(`[${status}] ${name}${msg ? ': '+msg : ''}`);
const errMsg = e => (e?.message || String(e)).slice(0,300).replace(/(Bearer|Cloud-IDE-JWT)\s+[^\s]+/g,'$1 [REDACTED]');
async function request(url, {method='GET', headers={}, body, timeout=16000}={}) {
  const ctrl = new AbortController();
  const tm = setTimeout(()=>ctrl.abort(),timeout);
  try {
    const res= await fetch(url,{method,headers,body,signal:ctrl.signal});
    const str = await res.text();
    let data; try { data=str.trim()?JSON.parse(str):{}; } catch { throw Error(`非 JSON 响应 (HTTP ${res.status})`); }
    return {status:res.status,data};
  } finally {clearTimeout(tm);}
}

// --- WorkBuddy 5.6.2+ sym-v1 field encryption (read-only; no persistent secrets). ---
// Adapted algorithm from 88lin/workbuddy-auto-signin (MIT); run inside installed WorkBuddy Electron.
const WB_HELPER_JS = String.raw`
'use strict';
const crypto = require('node:crypto');
const fail = why => { throw {reason:why}; };
const object = x => x !== null && typeof x === 'object' && !Array.isArray(x);
const b64 = (s, len) => {
  if (typeof s!=='string' || s.length>65536) fail('INVALID_FORMAT');
  const b=Buffer.from(s,'base64');
  if(b.toString('base64')!==s || (len!==undefined&&b.length!==len)) fail('INVALID_FORMAT');
  return b;
};
function parse(v){
  if(!object(v)||v.$wbEncrypted!==1||typeof v.envelope!=='string') fail('UNSUPPORTED_ENVELOPE');
  let e; try {e=JSON.parse(b64(v.envelope).toString('utf8'));}catch{fail('INVALID_FORMAT');}
  if(!object(e)||e.suite!==1)fail('UNSUPPORTED_ENVELOPE');
  if(typeof e.keyId!=='string'||!/^[0-9a-f]{16}$/.test(e.keyId))fail('INVALID_FORMAT');
  return {keyId:e.keyId,iv:b64(e.nonce,12),tag:b64(e.authTag,16),body:b64(e.ciphertext)};
}
function decrypt(v){
  const e=parse(v);
  let payload; try {payload=JSON.parse(process._linkedBinding('electron_browser_workbuddy_storage').loggerGet());}
  catch{fail('RUNTIME_UNAVAILABLE');}
  if(!object(payload)||payload.version!==1||typeof payload.atRestSecretKey!=='string')fail('RUNTIME_UNAVAILABLE');
  const raw=b64(payload.atRestSecretKey,32);
  if(raw.every(x=>x===0)){raw.fill(0);fail('RUNTIME_UNAVAILABLE');}
  raw.fill(0);
  const key=crypto.createHash('sha256').update(payload.atRestSecretKey,'utf8').digest();
  payload=null;
  let plain;
  try{
    if(crypto.createHash('sha256').update(key).digest('hex').slice(0,16)!==e.keyId)fail('KEY_MISMATCH');
    const lp=s=>{const b=Buffer.from(s);const n=Buffer.alloc(4);n.writeUInt32BE(b.length);return Buffer.concat([n,b]);};
    const aad=Buffer.concat([Buffer.from('WB-AAD\0','ascii'),Buffer.from([1]),lp('WBEV1'),lp('sym-v1'),Buffer.from([0,0,0,1]),lp(e.keyId),Buffer.from([2,0,0])]);
    try {
      const c=crypto.createDecipheriv('aes-256-gcm',key,e.iv,{authTagLength:16});
      c.setAAD(aad);c.setAuthTag(e.tag);plain=Buffer.concat([c.update(e.body),c.final()]);
    }catch{fail('DECRYPT_FAILED');}
    const token=plain.toString('utf8');
    if(!token||token.length>32768||!/^[A-Za-z0-9._~+/-]+=*$/.test(token))fail('INVALID_FORMAT');
    return token;
  }finally{key.fill(0);if(plain)plain.fill(0);}
}
let input=[],size=0;
function reply(v){process.stdout.write(JSON.stringify({v:1,...v}),()=>process.exit(v.ok?0:1));}
process.stdin.on('data',b=>{size+=b.length;if(size>65536)reply({ok:false,reason:'INVALID_FORMAT'});else input.push(b);});
process.stdin.on('end',()=>{
  try{ const r=JSON.parse(Buffer.concat(input).toString('utf8'));input=[];
    if(!object(r)||r.v!==1)fail('INVALID_FORMAT');
    reply({ok:true,token:decrypt(r.value)});
  }catch(e){ const allow=['INVALID_FORMAT','UNSUPPORTED_ENVELOPE','RUNTIME_UNAVAILABLE','KEY_MISMATCH','DECRYPT_FAILED'];
    reply({ok:false,reason:allow.includes(e?.reason)?e.reason:'RUNTIME_UNAVAILABLE'});
  }
});
`;
function workbuddyElectron(){
  if(process.env.WORKBUDDY_EXE){
    const f=path.resolve(process.env.WORKBUDDY_EXE);
    if(!exists(f))throw Error('WORKBUDDY_EXE 指定的可执行文件不存在');
    return f;
  }
  for(const base of ['/Applications',path.join(HOME,'Applications')]){
    const plist=path.join(base,'WorkBuddy.app','Contents','Info.plist');
    if(!exists(plist))continue;
    try{
      const exe=execFileSync('/usr/libexec/PlistBuddy',['-c','Print :CFBundleExecutable',plist],{encoding:'utf8',timeout:3000}).trim();
      if(exe && !/[/\\]/.test(exe)){
        const f=path.join(base,'WorkBuddy.app','Contents','MacOS',exe);
        if(exists(f))return f;
      }
    }catch{}
  }
  throw Error('未找到 WorkBuddy.app；可通过 WORKBUDDY_EXE 指定 Contents/MacOS 内的可执行文件');
}
async function decryptWorkBuddy(value){
  if(!value||typeof value!=='object'||value.$wbEncrypted!==1||typeof value.envelope!=='string')
    throw Error('未知 WorkBuddy 凭据对象（不是受支持的 $wbEncrypted:1 信封）');
  if(value.envelope.length>64000)throw Error('WorkBuddy 凭据信封超出大小限制');
  const exe=workbuddyElectron();
  const env={...process.env,ELECTRON_RUN_AS_NODE:'1'};
  for(const k of Object.keys(env))if(/^(NODE_|ELECTRON_|WORKBUDDY_)/i.test(k)&&k!=='ELECTRON_RUN_AS_NODE')delete env[k];
  return await new Promise((resolve,reject)=>{
    const p=spawn(exe,['-e',WB_HELPER_JS],{env,stdio:['pipe','pipe','ignore'],windowsHide:true});
    let data='',ended=false;
    const timer=setTimeout(()=>{p.kill('SIGKILL');finish(Error('WorkBuddy 运行时解密超时（10秒）'));},10000);
    const finish=(err,t)=>{if(ended)return;ended=true;clearTimeout(timer);if(err)reject(err);else resolve(t);};
    p.on('error',()=>finish(Error('无法运行 WorkBuddy 客户端的 Electron 解密助手')));
    p.stdout.on('data',b=>{data+=b.toString('utf8');if(data.length>65536){p.kill('SIGKILL');finish(Error('WorkBuddy 解密助手响应超限'));}});
    p.on('close',()=>{
      if(ended)return;
      let msg;try{msg=JSON.parse(data);}catch{return finish(Error('WorkBuddy Electron 运行时未返回有效结果'));}
      const hints={RUNTIME_UNAVAILABLE:'本机 WorkBuddy 运行时未提供解密接口',KEY_MISMATCH:'客户端密钥与会话文件不匹配',DECRYPT_FAILED:'解密认证失败（可能客户端版本变化）',UNSUPPORTED_ENVELOPE:'不支持的凭据加密格式',INVALID_FORMAT:'凭据格式异常'};
      if(msg?.v===1&&msg.ok===true&&typeof msg.token==='string'&&msg.token.length>0)return finish(null,msg.token);
      finish(Error(hints[msg?.reason]||'WorkBuddy 解密助手执行失败'));
    });
    p.stdin.on('error',()=>{});
    p.stdin.end(JSON.stringify({v:1,value}));
  });
}

// --- WorkBuddy CN, from currently logged-in client session (never refresh/rewrite) ---
async function workbuddy() {
  const dir=path.join(APP,'CodeBuddyExtension','Data','Public','auth');
  if(DIAG)console.log(`[诊断] WorkBuddy 会话目录：${dir}`);
  if(!exists(dir)){ok('WorkBuddy','跳过','未找到客户端登录目录；请确认 WorkBuddy 国内版已登录');return;}
  const entries=fs.readdirSync(dir);
  // Current desktop sessions only. Ignore historical snapshots and logged-out markers.
  const files=entries.filter(f=>/^[a-z0-9-]+\.info$/i.test(f))
    .sort((a,b)=>Number(b==='workbuddy-desktop.info')-Number(a==='workbuddy-desktop.info'));
  const counts={current:files.length,loggedOut:0,unreadable:0,noToken:0,notCN:0,invalidIssuer:0,recognized:0};
  let matched=false;
  const errorsBefore=failures;
  for(const file of files){
    if(exists(path.join(dir,`${file}.logged-out`))){counts.loggedOut++;continue;}
    let sess; try{sess=json(path.join(dir,file));}catch{counts.unreadable++;continue;}
    // 客户端版本可能采用不同容器结构；只接受能够通过发行方校验的 JWT。
    const candidates=[
      ['auth.accessToken',sess?.auth?.accessToken],
      ['accessToken',sess?.accessToken],
      ['auth.token',sess?.auth?.token],
      ['data.auth.accessToken',sess?.data?.auth?.accessToken],
      ['session.auth.accessToken',sess?.session?.auth?.accessToken],
      ['credentials.accessToken',sess?.credentials?.accessToken],
      ['data.accessToken',sess?.data?.accessToken],
      ['session.accessToken',sess?.session?.accessToken],
    ];
    const candidate=candidates.find(([,v])=>typeof v==='string'&&v.length>0);
    let token=candidate?.[1];
    if(!token && sess?.auth?.accessToken && typeof sess.auth.accessToken==='object'){
      const v=sess.auth.accessToken;
      if(v.$wbEncrypted===1){
        if(DIAG)console.log('[诊断] WorkBuddy 识别到 $wbEncrypted:1 加密信封，尝试客户端运行时解密');
        try { token=await decryptWorkBuddy(v); }
        catch(e){fail('WorkBuddy 国内版',errMsg(e));continue;}
      }
    }
    if(typeof token!=='string'||!token){
      counts.noToken++;
      if(DIAG){
        // 仅输出 JSON 属性名，不输出任何登录凭据内容/长度/前缀。
        // Token 类属性只展示属性名称，不暴露属性值。
        const authKeys=o=>o&&typeof o==='object'&&!Array.isArray(o) ? Object.keys(o).slice(0,25).join(',') : typeof o;
        const valState=(owner,key)=>{
          if(!owner||typeof owner!=='object'||!(key in owner))return '不存在';
          const v=owner[key];
          if(v===null)return 'null';
          if(typeof v==='string')return v.trim() ? '非空字符串（已隐藏）' : '空字符串';
          if(Array.isArray(v))return '数组';
          return typeof v;
        };
        const auth=sess?.auth;
        console.log(`[诊断] WorkBuddy 当前会话字段：root=[${authKeys(sess)}] auth=[${authKeys(auth)}]`);
        console.log(`[诊断] WorkBuddy auth.accessToken 值状态：${valState(auth,'accessToken')}；auth.refreshToken 值状态：${valState(auth,'refreshToken')}`);
        for(const section of ['accounts','allAccounts']){
          const list=sess?.[section];
          if(!Array.isArray(list)){console.log(`[诊断] WorkBuddy ${section}：非数组`);continue;}
          const match=list.filter(item=>{
            const cur=String(sess?.account?.uid||'');
            return cur && [item?.uid,item?.account?.uid].some(x=>String(x||'')===cur);
          });
          const nested=list.filter(item=>typeof item?.auth?.accessToken==='string'&&item.auth.accessToken.trim()).length;
          const direct=list.filter(item=>typeof item?.accessToken==='string'&&item.accessToken.trim()).length;
          console.log(`[诊断] WorkBuddy ${section}：${list.length} 项；与当前 uid 对应 ${match.length} 项；含 auth.accessToken 非空 ${nested} 项；含顶层 accessToken 非空 ${direct} 项`);
        }
      }
      continue;
    }
    if(DIAG && candidate && candidate[0]!=='auth.accessToken')console.log(`[诊断] WorkBuddy 登录凭据位置：${candidate[0]}`);
    const info=jwt(token), issuer=String(info.iss||'');
    let host; try{host=new URL(issuer).hostname.toLowerCase();}catch{counts.invalidIssuer++;continue;}
    const isCN=/(^|\.)(codebuddy\.cn|workbuddy\.cn|copilot\.tencent\.com)$/.test(host);
    if(!isCN){counts.notCN++;continue;}
    matched=true;
    counts.recognized++;
    seen++;
    const authDomain=String(sess.auth?.domain||'').toLowerCase();
    const apiHost=/^(?:[a-z0-9-]+\.)*(?:codebuddy\.cn|workbuddy\.cn|copilot\.tencent\.com)$/.test(authDomain) ? authDomain : (host==='copilot.tencent.com'?'www.codebuddy.cn':host);
    const h={Accept:'application/json','Content-Type':'application/json', Authorization:`Bearer ${token}`,
      'X-User-Id':String(info.sub||sess.account?.uid||''),'X-Domain':apiHost,'X-Product':'SaaS','User-Agent':'CLI/2.108.1 CodeBuddy/2.108.1'};
    if(sess.account?.enterpriseId){h['X-Enterprise-Id']=String(sess.account.enterpriseId);h['X-Tenant-Id']=String(sess.account.enterpriseId);}
    const name='WorkBuddy 国内版';
    try{
      const status=await request(`https://${apiHost}/v2/billing/meter/checkin-activity-status`,{method:'POST',headers:h,body:'{}'});
      if(status.status===401)throw Error('当前客户端 Token 已过期，请在 WorkBuddy 中重新登录');
      if(status.status!==200 || status.data?.code!==0)throw Error(`状态查询失败 HTTP ${status.status} code ${status.data?.code??'?'}；不尝试领取`);
      if(status.data?.data?.today_checked_in===true || status.data?.data?.checked_in===true){ok(name,'已领');continue;}
      if(CHECK){ok(name,'可签到','仅检查，没有提交领取');continue;}
      const r=await request(`https://${apiHost}/v2/billing/meter/daily-checkin`,{method:'POST',headers:h,body:'{}'});
      const code=r.data?.code ?? r.data?.error_code;
      const msg=String(r.data?.msg??r.data?.message??'');
      if(r.status>=200 && r.status<300 && (code===0||code===undefined))ok(name,'成功',`+${Number(r.data?.data?.credit??r.data?.data?.today_credit??r.data?.data?.daily_credit??status.data?.data?.daily_credit??0)} 积分`);
      else if(String(code)==='10001'||/已签到|重复签到|already|repeat/i.test(msg))ok(name,'已领');
      else if(r.status===404)ok(name,'无活动');
      else throw Error(`HTTP ${r.status}; code ${code??'?'}; ${msg}`);
    }catch(e){fail(name,errMsg(e));}
  }
  if(DIAG)console.log(`[诊断] WorkBuddy 会话统计：当前文件 ${counts.current}，登出标记 ${counts.loggedOut}，JSON 无法读取 ${counts.unreadable}，缺 accessToken ${counts.noToken}，非国内签发 ${counts.notCN}，JWT 签发方无效 ${counts.invalidIssuer}，识别成功 ${counts.recognized}；历史备份文件 ${entries.filter(f=>/\.info$/.test(f)&&!/^[a-z0-9-]+\.info$/i.test(f)).length}`);
  if(!matched && failures===errorsBefore)ok('WorkBuddy','跳过',counts.current ? '当前会话没有可用的国内版账号；可通过 --diagnose 查看分类' : '没有当前会话 .info 文件；请打开 WorkBuddy 国内版并确认已登录');
}

// --- Trae CN. Decrypt local "tc" envelope using its embedded public pepper tables. ---
// Constants/algorithm are adapted from CreditDaddy src/traeLocal.js (MIT).
const WOE=[82,9,106,213,48,54,165,56,191,64,163,158,129,243,215,251,124,227,57,130,155,47,255,135,52,142,67,68,196,222,233,203,84,123,148,50,166,194,35,61,238,76,149,11,66,250,195,78,8,46,161,102,40,217,36,178,118,91,162,73,109,139,209,37];
const VOE=[31,221,168,51,136,7,199,49,177,18,16,89,39,128,236,95,96,81,127,169,25,181,74,13,45,229,122,159,147,201,156,239,160,224,59,77,174,42,245,176,200,235,187,60,131,83,153,97,23,43,4,126,186,119,214,38,225,105,20,99,85,33,12,125];
const JOE=[191,192,216,250,122,246,220,97,31,254,98,27,8,72,71,176,135,99,96,18,127,101,203,104,211,102,191,125,37,72,150,156,51,229,121,35,17,153,141,177,110,131,150,128,172,255,254,6,18,140,55,62,236,249,135,64,135,12,117,4,89,149,168,209];
const HOE=[246,204,26,232,232,70,129,109,223,146,169,242,23,241,105,145,50,196,165,42,254,120,3,54,244,207,209,85,53,6,138,106,175,148,31,204,186,186,165,182,87,142,49,10,39,110,26,154,86,56,173,125,18,64,198,225,99,99,83,82,191,134,76,170];
function tcDecrypt(s){
  if(typeof s!=='string')return null;
  const b=Buffer.from(s.trim(),'base64');
  if(b.length<54 || !b.subarray(0,6).equals(Buffer.from([116,99,5,16,0,0])))return null;
  for(const [a,z] of [[WOE,VOE],[JOE,HOE]]){
    try{
      const pepper=Buffer.from(a.map((v,i)=>v^z[i]));
      const k=sha512(Buffer.concat([sha512(b.subarray(6,38)),pepper]));
      const dec=crypto.createDecipheriv('aes-128-cbc',k.subarray(0,16),k.subarray(16,32));
      const plain=Buffer.concat([dec.update(b.subarray(38)),dec.final()]);
      const body=plain.subarray(64);
      if(plain.length>64&&sha512(body).equals(plain.subarray(0,64)))return JSON.parse(body.toString('utf8'));
    }catch{}
  }
  return null;
}
function seed(uid,salt,n){
  const out=[];
  for(let i=0;out.length<n;i++)out.push(...sha256(`${salt}:${uid}:${i}`));
  return out.slice(0,n);
}
function findField(o,k,depth=0){
  if(!o||typeof o!=='object'||depth>2)return undefined;
  if(k in o)return o[k];
  for(const c of [o.data,o.result,o.Result]){const v=findField(c,k,depth+1);if(v!==undefined)return v;}
}
function traeHeaders(token,uid,devId){
  const market=seed(uid,'market',16);market[6]=(market[6]&15)|64;market[8]=(market[8]&63)|128;
  const h=Buffer.from(market).toString('hex');
  if(!/^\d{8,}$/.test(String(devId||'')))throw Error('缺少 Trae 客户端真实数字设备 ID，停止请求以避免风控');
  const dev=String(devId);
  return {
    accept:'*/*','accept-language':'zh-CN',authorization:`Cloud-IDE-JWT ${token.replace(/^Cloud-IDE-JWT\s+/,'').trim()}`,
    'content-type':'application/json','user-agent':'VSCode 1.107.1 (TRAE SOLO CN)','x-market-client-id':'VSCode 1.107.1',
    'x-market-user-id':`${h.slice(0,8)}-${h.slice(8,12)}-${h.slice(12,16)}-${h.slice(16,20)}-${h.slice(20)}`,
    'x-user-region':'CN','x-device-id':dev,'x-lgw-req-sdk-type':'3','package-type':'stable_cn',
    'x-request-id':hex(16),'x-lscbd-aid':'787976','x-lscbd-platform':'darwin','app-version':'0.1.45',
    'x-tt-trace-id':`00-${hex(8)}-01`,'vscode-sessionid':Buffer.from(seed(uid,'sess',32)).toString('hex')
  };
}
async function trae(){
  const base=process.env.TRAE_HOME ? [process.env.TRAE_HOME] : ['TRAE SOLO CN','Trae CN','TRAE SOLO','Trae'].map(n=>path.join(APP,n));
  const storageFile=base.map(p=>path.join(p,'User','globalStorage','storage.json')).find(exists);
  if(!storageFile){ok('Trae','跳过','未找到客户端 storage.json');return;}
  const name='Trae 国内版';seen++;
  try{
    const storage=json(storageFile), auth=tcDecrypt(storage['iCubeAuthInfo://icube.cloudide']);
    if(!auth?.token)throw Error('本机凭据无法解密或未登录（客户端加密格式可能变更）');
    const token=auth.token, uid=String(auth.userId||jwt(token)?.data?.id||'');
    if(!uid)throw Error('无法从当前登录凭据识别用户 ID');
    const devKey=Object.keys(storage).find(k=>/^iCubeAuthInfo:\/\/icube-dc:\d{8,}$/.test(k));
    const devId=devKey?.split(':').at(-1);
    const headers=traeHeaders(token,uid,devId);
    const api='https://api.trae.cn/trae/api/v2/ug/checkin_credits/';
    const post=p=>request(api+p,{method:'POST',headers,body:'{}'});
    const s=await post('status');
    if(s.status===401||Number(s.data?.code)===1001)throw Error('Trae 登录已过期，请在客户端重新登录');
    if(s.status!==200||Number(s.data?.code)!==0)throw Error(`签到状态查询失败 HTTP ${s.status} code ${s.data?.code??'?'}; ${String(s.data?.message||'').slice(0,90)}`);
    if([true,1].includes(findField(s.data,'checked_in'))){ok(name,'已领');return;}
    if(CHECK){ok(name,'可签到','仅检查，没有提交领取');return;}
    const r=await post('claim');
    if(r.status!==200||Number(r.data?.code)!==0)throw Error(`签到失败 HTTP ${r.status} code ${r.data?.code??'?'}; ${String(r.data?.message||'').slice(0,90)}`);
    const credits=findField(r.data,'credits')??findField(s.data,'credits')??findField(s.data,'extra_credits');
    ok(name,'成功',credits!==undefined ? `+${credits} 积分` : '积分数量以客户端为准');
  }catch(e){fail(name,errMsg(e));}
}

// --- Qoder CN. Read Electron safeStorage via macOS Keychain. ---
function resources(v){
  const paths=['Qoder CN IDE','Qoder CN','Qoder'].flatMap(n=>[`/Applications/${n}.app/Contents/Resources`,path.join(HOME,'Applications',`${n}.app`,'Contents','Resources')]);
  for(const p of paths)if(exists(p))return p;
  return null;
}
function version(dir){try{return json(path.join(dir,'build-manifest.json')).productVersion||'0.3.3';}catch{return '0.3.3';}}
async function decryptQoder(v){
  const file=path.join(APP,`${v.appId}.stable`,'auth.v1.dat');
  if(DIAG)console.log(`[诊断] Qoder 凭据文件：${exists(file)?'存在':'不存在'}（${file}）`);
  if(!exists(file))return null;
  const b=read(file);
  if(b.subarray(0,3).toString()!=='v10')throw Error('不支持的客户端 Safe Storage 格式');
  let hadPassword=false;
  const errors=[];
  for(const name of [...new Set(['Qoder CN App', 'Qoder App', 'Qoder CN', 'Qoder', 'Qoder CN IDE', 'Qoder IDE', v.install, v.label])]){
    const svc=`${name} Safe Storage`;
    let pass;
    try {
      // Intentionally never print, persist, or log the password/key material.
      const r=await exec('/usr/bin/security',['find-generic-password','-w','-s',svc],{timeout:20000});
      pass=r.stdout.trim();
    }catch(e){
      const code=typeof e?.code==='number'?e.code:String(e?.code||'unknown');
      errors.push(`${svc}: ${code===44?'未找到对应密钥项（status -25300，退出码 44）':`钥匙串查询失败（退出码 ${code}）`}`);
      continue;
    }
    if(!pass){errors.push(`${svc}: 返回空密钥`);continue;}
    hadPassword=true;
    try {
      const key=crypto.pbkdf2Sync(pass,'saltysalt',1003,16,'sha1');
      const dec=crypto.createDecipheriv('aes-128-cbc',key,Buffer.alloc(16,' '));
      const obj=JSON.parse(Buffer.concat([dec.update(b.subarray(3)),dec.final()]).toString('utf8'));
      if(obj.token)return obj;
      errors.push(`${svc}: 解密成功但缺少 token`);
    }catch{errors.push(`${svc}: 已读取密钥但无法解密`);}
  }
  if(DIAG && !hadPassword){
    // security dump-keychain without -d prints metadata, NOT secret payloads.
    // Do not print raw dump, labels, accounts, or generic metadata from unrelated items.
    try {
      const r=await exec('/usr/bin/security',['dump-keychain'],{timeout:20000,maxBuffer:16*1024*1024});
      const lines=r.stdout.split(/\r?\n/);
      const names=[...new Set(lines.filter(s=>/\"svce\"<blob>=/.test(s)&&/qoder/i.test(s))
        .map(s=>s.match(/\"svce\"<blob>=(.*)$/)?.[1]||'')
        .map(s=>s.replace(/^\"|\"$/g,'').slice(0,100)).filter(Boolean))];
      console.log(`[诊断] 钥匙串中带 Qoder 的服务名：${names.length?names.slice(0,12).join('、'):'未找到（仅检查默认搜索范围）'}`);
    } catch(e) {console.log(`[诊断] 无法枚举钥匙串服务名（退出码 ${typeof e?.code==='number'?e.code:'未知'}）；未输出任何密码`);}
  }
  throw Error(`${hadPassword?'Qoder 登录文件解密失败':'无法读取钥匙串 Safe Storage 密钥'}；${errors.join('；')}`);
}

function machineId(v){
  const file=path.join(APP,`${v.appId}.stable`,'auth.machine-id');
  try{const s=fs.readFileSync(file,'utf8').trim();if(/^[0-9a-f-]{36}$/i.test(s))return s;}catch{}
  const home=path.join(HOME,'.config','mac-credits');fs.mkdirSync(home,{recursive:true,mode:0o700});
  const f=path.join(home,'machine-id');if(exists(f))return fs.readFileSync(f,'utf8').trim();
  const id=crypto.randomUUID();fs.writeFileSync(f,id,{mode:0o600});return id;
}
async function qoder(v){
  const name=v.label;let auth;
  try {auth=await decryptQoder(v);}catch(e){fail(name,errMsg(e));return;}
  if(!auth){ok(name,'跳过','本机无登录凭据');return;}
  seen++;
  const dir=resources(v),base='https://openapi.qoder.com.cn';
  try{
    let token=auth.token;
    if(token.startsWith('pt-')){
      const p=await request(base+'/api/v1/jobToken/exchange',{method:'POST',headers:{'Content-Type':'application/json','User-Agent':'qodercli/1.0.0','Cosy-Version':'1.0.0','Cosy-ClientType':'5'},body:JSON.stringify({personal_token:token})});
      if(p.status!==200||!p.data?.token)throw Error(`PAT 兑换失败 HTTP ${p.status}`);
      token=p.data.token;
    }
    const headers={Authorization:`Bearer ${token}`,'Cosy-ClientType':'10','Cosy-Version':version(dir),'Cosy-MachineOS':`${process.arch==='arm64'?'aarch64':'x86_64'}_darwin`,
      'Cosy-MachineId':machineId(v),'User-Agent':'Qoder',Accept:'application/json'};
    if(/^[\x21-\x7e]{1,96}$/.test(os.hostname()))headers['Cosy-MachineHostname']=os.hostname();
    const endpoint=base+'/sash/api/v1/me/campaigns?clientType=10';
    const get=()=>request(endpoint,{headers});
    const s=await get();
    if(s.status===401||s.status===403)throw Error('当前登录 Token 已过期');
    if(s.status!==200||!Array.isArray(s.data?.campaigns))throw Error(`活动列表失败 HTTP ${s.status}`);
    const campaigns=s.data.campaigns.filter(c=>c.actionType==='CLAIM_BENEFIT');
    const claimable=campaigns.filter(c=>c.claimStatus==='CLAIMABLE');
    if(!claimable.length){ok(name,campaigns.length?'已领':'无活动');return;}
    if(CHECK){ok(name,'可签到',`${claimable.length} 个活动；仅检查，没有领取`);return;}
    let credited=0;
    for(const c of claimable){
      if(!c.campaignId)throw Error('活动缺少 campaignId');
      const r=await request(base+`/sash/api/v1/me/campaigns/${encodeURIComponent(c.campaignId)}/claim`,{method:'POST',headers});
      if(r.status<200||r.status>=300)throw Error(`活动领取 HTTP ${r.status}`);
      credited+=Number(r.data?.benefit?.amount??c.benefit?.amount??0);
    }
    ok(name,'成功',`+${credited} Credits`);
  }catch(e){fail(name,errMsg(e));}
}
async function main(){
  console.log(`--- macOS 每日额度 ${new Date().toLocaleString('zh-CN',{timeZone:'Asia/Shanghai'})}（北京时间）${CHECK?' / 只检查':''}${DIAG?' / 诊断':''} ---`);
  await qoder({label:'Qoder 国内版',install:'Qoder CN',appId:'com.qodercn.app'});
  await workbuddy();
  await trae();
  if(!seen)console.log('没有发现可执行签到的已登录账号。');
  console.log(`完成：处理账号 ${seen}，失败 ${failures}。`);
  if(failures)process.exitCode=1;
}
main().catch(e=>{console.error('发生异常：'+errMsg(e));process.exitCode=1;});
JS