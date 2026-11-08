// Offline mocked handler tests. Dependency: typescript@5.9.3
import ts from 'typescript';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const src=readFileSync(new URL('../edge-functions/mes-orders/index.ts',import.meta.url),'utf8').replace(/^import .*withSupabase.*\n/m,'');
const js=ts.transpileModule(src,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ES2022},reportDiagnostics:true});
assert.equal(js.diagnostics.length,0);
const handler=(await import('data:text/javascript;base64,'+Buffer.from('const withSupabase=(_,fn)=>fn;\n'+js.outputText).toString('base64'))).default.fetch;
const entries=Array.from({length:1205},(_,i)=>({amount:i<1100?10:-10,event_type:i<1100?'delivery_charge':'return_reversal',order_id:String(i),event_at:'2026-01-01'}));
let ranges=[],failPage=false,admin=true;
const db={auth:{getUser:async()=>({data:{user:{id:'admin'}}})},from(table){const q={select(){return q},eq(){return q},order(){return q},limit(){return Promise.resolve({data:[],error:null})},maybeSingle(){return Promise.resolve({data:admin?{auth_user_id:'admin'}:null,error:null})},range(a,b){ranges.push([a,b]);return Promise.resolve(failPage&&a===500?{data:null,error:{message:'failed'}}:{data:entries.slice(a,b+1),error:null})}};return q}};
const request=(token=true)=>new Request('https://test.invalid/orders?sellerId=synthetic',{headers:token?{authorization:'Bearer valid'}:{}});
let r=await handler(request(false),{supabaseAdmin:db});assert.equal(r.status,401);console.log('PASS missing authentication rejected');
admin=false;r=await handler(request(),{supabaseAdmin:db});assert.equal(r.status,403);console.log('PASS non-admin rejected');admin=true;
r=await handler(request(),{supabaseAdmin:db});assert.equal(r.status,200);let b=await r.json();assert.equal(b.ledger.length,1205);assert.equal(b.netCommission,9950);assert.deepEqual(ranges,[[0,499],[500,999],[1000,1499]]);console.log('PASS all 1,205 ledger entries included; net INR 9,950');
failPage=true;r=await handler(request(),{supabaseAdmin:db});assert.equal(r.status,500);b=await r.json();assert.equal(b.netCommission,undefined);console.log('PASS failed ledger page never returns partial financial total');
