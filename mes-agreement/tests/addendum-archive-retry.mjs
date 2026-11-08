// Offline tests. Dependencies: typescript@5.9.3, pdf-lib@1.17.1
import ts from 'typescript';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {PDFDocument,StandardFonts} from 'pdf-lib';
globalThis.testPDF={PDFDocument,StandardFonts};
const src=readFileSync(new URL('../edge-functions/mes-addendum/index.ts',import.meta.url),'utf8').replace(/^import .*\n/gm,'');
const js=ts.transpileModule(src,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ES2022},reportDiagnostics:true});assert.equal(js.diagnostics.length,0);
const handler=(await import('data:text/javascript;base64,'+Buffer.from('const withSupabase=(_,fn)=>fn; const {PDFDocument,StandardFonts}=globalThis.testPDF;\n'+js.outputText).toString('base64'))).default.fetch;
let stored=null,archiveFailure=true,uploadCount=0,archiveCalls=0;
const user={id:'00000000-0000-4000-8000-000000000003',email:'seller@test.invalid',email_confirmed_at:'2026-01-01'};
const db={auth:{getUser:async()=>({data:{user},error:null})},rpc:async(name)=>{if(name==='mes_accept_addendum')return {data:{addendum_id:'synthetic',accepted_at:'2026-01-02T03:04:05.000Z',archived:false}};archiveCalls++;return {error:archiveFailure?{message:'Temporary archive error'}:null}},storage:{from:()=>({upload:async(_,bytes,options)=>{assert.equal(options.upsert,false);uploadCount++;if(stored)return {error:{message:'Already exists'}};stored=Uint8Array.from(bytes);return {error:null}},download:async()=>({data:new Blob([stored]),error:null})})},from:()=>({select(){return this},eq(){return this},maybeSingle:async()=>({data:null,error:null})})};
const terms=await (await handler(new Request('https://test.invalid'),{supabaseAdmin:db})).json();
const request=()=>new Request('https://test.invalid',{method:'POST',headers:{authorization:'Bearer valid','Content-Type':'application/json'},body:JSON.stringify({action:'accept_addendum',version:'2.0',accepted:true,signerName:'Test Seller',termsSha256:terms.sha256})});
let r=await handler(request(),{supabaseAdmin:db});assert.equal(r.status,202);assert.equal((await r.json()).archived,false);assert.ok(stored);const original=Uint8Array.from(stored);console.log('PASS upload survives temporary archive failure');
archiveFailure=false;r=await handler(request(),{supabaseAdmin:db});assert.equal(r.status,200);assert.equal((await r.json()).archived,true);assert.deepEqual(stored,original);console.log('PASS identical retry resumes archival without replacing signed bytes');
stored[20]^=1;const before=archiveCalls;r=await handler(request(),{supabaseAdmin:db});assert.equal(r.status,202);assert.equal((await r.json()).archived,false);assert.equal(archiveCalls,before);console.log('PASS different existing document rejected before archival');
