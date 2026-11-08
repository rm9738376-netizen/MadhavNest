// Local synthetic PostgreSQL tests only; no Supabase connection or credentials.
// Dependency: @electric-sql/pglite@0.5.15
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
const db=new PGlite();
await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;
create schema auth;create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);
create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);`);
await db.exec(readFileSync(new URL('../migrations/staging/00_minimal_parent_schema.sql',import.meta.url),'utf8'));
await db.exec(readFileSync(new URL('../migrations/20261104_delivered_order_commission.sql',import.meta.url),'utf8'));
console.log('PASS: migration applied to isolated PostgreSQL engine');
const admin='00000000-0000-4000-8000-000000000001', seller='00000000-0000-4000-8000-000000000002', user='00000000-0000-4000-8000-000000000003', agreement='00000000-0000-4000-8000-000000000004';
await db.query(`insert into auth.users values ($1,'admin@test.invalid',now()),($2,'seller@test.invalid',now())`,[admin,user]);
await db.query(`insert into public.admin_users(auth_user_id,email) values($1,'admin@test.invalid')`,[admin]);
await db.query(`insert into public.seller_users(id,auth_user_id,name,email) values($1,$2,'Synthetic Seller','seller@test.invalid')`,[seller,user]);
await db.query(`insert into public.seller_agreements(id,seller_id,terms_status) values($1,$2,'signed')`,[agreement,seller]);
let count=0;
async function test(name,fn){await fn();console.log('PASS:',name);count++;}
async function reject(fn){let failed=false;try{await fn()}catch{failed=true}if(!failed)throw Error('Expected rejection');}
const order=(id,status,delivered=null,returned=null,actor=admin)=>db.query(`select mes_record_order($1,'Meesho',$2,$3,$4,$5,$6,'test')`,[seller,id,status,delivered,returned,actor]);
await test('Delivered order without approved terms rejected',()=>reject(()=>order('early','delivered',new Date(Date.now()-60000).toISOString())));
await test('RTO without policy has zero fee',()=>order('rto','rto'));
const terms='Canonical synthetic acceptance terms for local runtime testing. '.repeat(3);
const accepted=(await db.query('select mes_accept_addendum($1,$2,$3) as data',[user,terms,'Test Seller'])).rows[0].data;
const addendum=accepted.addendum_id;
await test('Unarchived addendum cannot activate billing',()=>reject(()=>db.query('select mes_approve_addendum($1,$2)',[addendum,admin])));
await test('Null PDF hash rejected',()=>reject(()=>db.query('select mes_archive_addendum($1,$2,$3,null)',[addendum,user,`addenda/${addendum}.pdf`])));
await db.query('select mes_archive_addendum($1,$2,$3,$4)',[addendum,user,`addenda/${addendum}.pdf`,'a'.repeat(64)]);
await db.query('select mes_approve_addendum($1,$2)',[addendum,admin]);
const delivered=new Date().toISOString();
await test('Delivery charges exactly INR 10',async()=>{await order('one','delivered',delivered);const r=await db.query('select sum(amount)::text as net from order_commission_ledger');if(Number(r.rows[0].net)!==10)throw Error('Wrong charge')});
await test('Repeated delivery does not double charge',async()=>{await order('one','delivered',delivered);const r=await db.query('select count(*)::int as n from order_commission_ledger');if(r.rows[0].n!==1)throw Error('Duplicate ledger')});
const returned=new Date().toISOString();
await test('Full return and retry leave net zero',async()=>{await order('one','returned',delivered,returned);await order('one','returned',delivered,returned);const r=await db.query('select sum(amount)::text as net,count(*)::int as n from order_commission_ledger');if(Number(r.rows[0].net)!==0||r.rows[0].n!==2)throw Error('Wrong reversal')});
await test('Reversed order cannot be recharged',()=>reject(()=>order('one','delivered',delivered)));
await test('Non-admin actor rejected',()=>reject(()=>order('bad','rto',null,null,user)));
await test('Future delivery rejected',()=>reject(()=>order('future','delivered',new Date(Date.now()+86400000).toISOString())));
await test('Ledger mutation rejected',()=>reject(()=>db.exec('update order_commission_ledger set amount=10')));
await test('Original signed agreement preserved',async()=>{const r=await db.query('select terms_status,version from seller_agreements');if(r.rows[0].terms_status!=='signed'||r.rows[0].version!=='1.0')throw Error('Original changed')});
console.log(`${count} runtime tests passed; local synthetic data only.`);
await db.close();
