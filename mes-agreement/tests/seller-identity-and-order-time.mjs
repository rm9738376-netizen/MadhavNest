// Offline DOM tests. Dependency: jsdom@26.1.0
import {JSDOM} from 'jsdom';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const html=readFileSync(new URL('../index.html',import.meta.url),'utf8');
const dom=new JSDOM('<div id="modal"><div id="modalbox"></div></div>');
const document=dom.window.document;
const user={id:'seller-a',email:'seller@test.invalid'};
let currentUser=user,posts=0,resolveOtp=null;
const supabase={auth:{signInWithOtp:async()=>({error:null}),verifyOtp:async()=>resolveOtp?await new Promise(resolve=>{resolveOtp=resolve}):({data:{user,session:{access_token:'token-a'}},error:null}),getSession:async()=>({data:{session:{access_token:'token-a'}}}),getUser:async()=>({data:{user:currentUser},error:null})}};
const fetch=async(_,options)=>{if(options?.method==='POST'){posts++;return {ok:true,json:async()=>({archived:true})}}return {ok:true,json:async()=>({terms:'Canonical terms',sha256:'hash',version:'2.0'})}};
const src=html.slice(html.indexOf('async function showSellerAddendum()'),html.indexOf('function shell()'));
const show=new Function('document','supabase','fetch','SUPABASE_URL','SUPABASE_KEY',src+';return showSellerAddendum;')(document,supabase,fetch,'https://test.invalid','public');
const submit=id=>document.getElementById(id).onsubmit({preventDefault(){}});
const input=(id,value)=>{const el=document.getElementById(id);el.value=value;el.dispatchEvent(new dom.window.Event('input'))};
async function verify(){input('sellerEmail',user.email);await submit('sellerOtpRequest');document.getElementById('sellerOtp').value='123456';await submit('sellerOtpVerify');document.getElementById('sellerSigner').value='Seller';document.getElementById('sellerAccept').checked=true;}
await show();await verify();await submit('sellerAcceptForm');assert.equal(posts,1);console.log('PASS matching verified identity can submit');
input('sellerEmail','other@test.invalid');assert.equal(document.getElementById('sellerAccept').checked,false);assert.equal(document.getElementById('sellerAcceptForm').style.display,'none');await submit('sellerAcceptForm');assert.equal(posts,1);console.log('PASS email edits invalidate acceptance and require OTP again');
await verify();currentUser={id:'seller-b',email:'other@test.invalid'};await submit('sellerAcceptForm');assert.equal(posts,1);assert.match(document.getElementById('sellerAddendumMsg').textContent,/identity changed/);console.log('PASS changed session identity cannot submit');currentUser=user;
await show();input('sellerEmail',user.email);await submit('sellerOtpRequest');resolveOtp=true;const pending=submit('sellerOtpVerify');await Promise.resolve();const complete=resolveOtp;input('sellerEmail','changed@test.invalid');complete({data:{user,session:{access_token:'old'}},error:null});await pending;assert.equal(document.getElementById('sellerAcceptForm').style.display,'none');console.log('PASS stale OTP response cannot restore old email verification');
const manageSrc=html.slice(html.indexOf('async function manageSellerOrders(r)'),html.indexOf('const v=id=>'));
let posted;
const orderApi=async(method,_,body)=>{if(method==='POST'){posted=body;return {}}return {orders:[],netCommission:0}};
const manage=new Function('document','supabase','orderApi','editSeller','esc',manageSrc+';const v=id=>document.getElementById(id).value;return manageSellerOrders;')(document,supabase,orderApi,()=>{},String);
await manage({sellerId:'seller-a',legalName:'Test Seller'});
assert.equal(document.getElementById('oDelivered').type,'datetime-local');document.getElementById('oId').value='order-a';document.getElementById('oDelivered').value='2026-01-02T17:23:45';await document.getElementById('orderSave').onclick();assert.equal(posted.deliveredAt,new Date('2026-01-02T17:23:45').toISOString());assert.equal(new Date(posted.deliveredAt).getHours(),17);console.log('PASS order payload preserves entered local time instead of assuming noon');
