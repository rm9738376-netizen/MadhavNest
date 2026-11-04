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
 // Reject oversized identifiers and notes before privileged database work.
 // Marketplace order IDs are external inputs; do not allow unbounded storage.
 if(b.orderId.trim().length>128||typeof b.sellerId!=='string'||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(b.sellerId))
  return reply({error:'Invalid seller ID or order ID length'},400)
 if(b.notes!==undefined&&(typeof b.notes!=='string'||b.notes.length>2000))
  return reply({error:'Notes must be text of at most 2000 characters'},400)
 // Validate event timestamps before attempting the privileged database RPC.
 const hasDelivery=['delivered','returned','refunded'].includes(b.status)
 const hasReturn=['returned','refunded'].includes(b.status)
 const validDate=(v:any)=>typeof v==='string' && Number.isFinite(Date.parse(v)) && /(?:Z|[+-]\d{2}:\d{2})$/.test(v)
 if(hasDelivery&&!validDate(b.deliveredAt))return reply({error:'Valid offset-aware delivery timestamp required'},400)
 if(hasReturn&&!validDate(b.returnedAt))return reply({error:'Valid offset-aware return timestamp required'},400)
 if(!hasReturn&&b.returnedAt)return reply({error:'Return timestamp not allowed for this status'},400)
 if(!hasDelivery&&(b.deliveredAt||b.returnedAt))return reply({error:'Undelivered orders cannot include event timestamps'},400)
 if(hasDelivery){
  const {data:terms,error:termError}=await db.from('seller_commission_terms')
   .select('id,effective_from,addendum_reference')
   .eq('seller_id',b.sellerId).eq('model','delivered_order_flat')
   .not('accepted_at','is',null).lte('effective_from',b.deliveredAt)
   .order('effective_from',{ascending:false}).limit(1)
  if(termError)return reply({error:'Commission policy lookup unavailable'},500)
  if(!terms?.length)return reply({error:'No approved ₹10 policy effective on delivery date; existing agreement remains applicable'},409)
  const {data:addendum,error:addendumError}=await db.from('seller_agreement_addenda')
   .select('id,mes_approved_at,pdf_key,pdf_hash')
   .eq('id',terms[0].addendum_reference).eq('seller_id',b.sellerId).maybeSingle()
  if(addendumError)return reply({error:'Agreement approval lookup unavailable'},500)
  if(!addendum?.mes_approved_at||!addendum.pdf_key||!/^[0-9a-f]{64}$/.test(addendum.pdf_hash||''))
   return reply({error:'Approved archived seller addendum required before ₹10 posting'},409)
 }
 if(!['delivered','returned','refunded','cancelled','rto'].includes(b.status))return reply({error:'Invalid status'},400)
 const {data,error}=await db.rpc('mes_record_order',{
  p_seller_id:b.sellerId,p_marketplace:b.marketplace,p_order_id:b.orderId.trim(),p_status:b.status,
  p_delivered_at:b.deliveredAt||null,p_returned_at:b.returnedAt||null,p_actor:user.id,p_notes:String(b.notes||'')
 })
 if(error)return reply({error:error.message},409)
 return reply({order:data})
})}
