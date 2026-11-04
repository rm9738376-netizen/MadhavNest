// Draft only. Deploy after schema migration, agreement acceptance flow and staging tests.
// Admin-only manual order entry. No public table policies.
import { withSupabase } from 'npm:@supabase/server'
const cors={'Content-Type':'application/json','Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'GET,POST,OPTIONS'}
const reply=(data:any,status=200)=>Response.json(data,{status,headers:cors})
export default {fetch:withSupabase({auth:'none'},async(req,ctx)=>{
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors})
 const token=(req.headers.get('authorization')||'').replace(/^Bearer /i,'')
 if(!token)return reply({error:'Authentication required'},401)
 const {data:{user},error:authError}=await ctx.supabaseAdmin.auth.getUser(token)
 if(authError||!user)return reply({error:'Authentication required'},401)
 const db=ctx.supabaseAdmin
 const {data:admin,error:adminError}=await db.from('admin_users').select('auth_user_id').eq('auth_user_id',user.id).maybeSingle()
 if(adminError)return reply({error:'Admin authorization unavailable'},500)
 if(!admin)return reply({error:'Forbidden'},403)
 if(req.method==='GET'){
  const sellerId=new URL(req.url).searchParams.get('sellerId')
  if(!sellerId)return reply({error:'sellerId required'},400)
  const {data:orders,error}=await db.from('seller_orders').select('id,marketplace,marketplace_order_id,status,delivered_at,returned_at,created_at').eq('seller_id',sellerId).order('created_at',{ascending:false}).limit(500)
  if(error)return reply({error:error.message},500)
  const {data:ledger,error:ledgerError}=await db.from('order_commission_ledger').select('amount,event_type,order_id,event_at').eq('seller_id',sellerId)
  if(ledgerError)return reply({error:ledgerError.message},500)
  return reply({orders,ledger,netCommission:(ledger||[]).reduce((s:number,x:any)=>s+Number(x.amount),0)})
 }
 if(req.method!=='POST')return reply({error:'Method not allowed'},405)
 const b=await req.json().catch(()=>null)
 if(!b||!['Flipkart','Meesho'].includes(b.marketplace)||!['delivered','returned','refunded','cancelled','rto'].includes(b.status)||typeof b.orderId!=='string'||!b.orderId.trim()||!b.sellerId)return reply({error:'Invalid order details'},400)
 if(['delivered','returned','refunded'].includes(b.status)){
 const {data:terms,error:termError}=await db.from('seller_commission_terms').select('id,effective_from,accepted_at,model,rate').eq('seller_id',b.sellerId).eq('model','delivered_order_flat').not('accepted_at','is',null).lte('effective_from',new Date().toISOString()).order('effective_from',{ascending:false}).limit(1)
 if(termError)return reply({error:termError.message},500)
 if(!terms?.length)return reply({error:'Seller has not accepted the ₹10 agreement; old agreement remains active'},409)
 }
 if(!['delivered','returned','refunded','cancelled','rto'].includes(b.status))return reply({error:'Invalid status'},400)
 const {data,error}=await db.rpc('mes_record_order',{
  p_seller_id:b.sellerId,p_marketplace:b.marketplace,p_order_id:b.orderId.trim(),p_status:b.status,
  p_delivered_at:b.deliveredAt||null,p_returned_at:b.returnedAt||null,p_actor:user.id,p_notes:String(b.notes||'')
 })
 if(error)return reply({error:error.message},409)
 return reply({order:data})
})}
