// Draft for staging. Requires deployed mes_accept_addendum RPC and configured email OTP.
import { withSupabase } from 'npm:@supabase/server'
const cors={'Content-Type':'application/json','Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST,OPTIONS'}
const respond=(value:any,status=200)=>Response.json(value,{status,headers:cors})
// Exact terms are controlled by the server, never supplied by the browser.
// MES countersignature and archival PDF generation must be completed before billing activation.
const ADDENDUM_V2=`Madhav Ecom Solution — Commission Addendum v2.0.
This addendum modifies the signed seller agreement only from the effective date mutually accepted by the Seller and Madhav Ecom Solution. The original 12-month term and expiry date remain unchanged. Existing 5% of Net Sales obligations earned before the effective date remain due under the original agreement.
From the accepted effective date, the service fee is INR 10 for each unique marketplace order successfully delivered to the buyer. This fee is per marketplace order ID, not per item or shipment. A fully returned or fully refunded delivered order receives one INR 10 reversal. Cancelled-before-delivery and RTO orders that were not delivered have no fee. Partial returns do not reverse the fee when some part of the order remains fulfilled. Replacement or exchange fulfillment does not cause a second fee for the same original order. MES and Seller will reconcile marketplace records, refunds and any carried-forward credits.
All other terms of the original agreement remain unchanged. This addendum requires separate Seller acceptance and MES approval before becoming effective.`
export default {fetch:withSupabase({auth:'none'},async(req,ctx)=>{
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors})
 if(req.method!=='POST')return respond({error:'Method not allowed'},405)
 const token=(req.headers.get('authorization')||'').replace(/^Bearer /i,'')
 if(!token)return respond({error:'Verified seller login required'},401)
 const {data:{user},error:authError}=await ctx.supabaseAdmin.auth.getUser(token)
 if(authError||!user?.email||!user.email_confirmed_at)return respond({error:'Verified seller login required'},401)
 const b=await req.json().catch(()=>null)
 if(b?.action!=='accept_addendum'||b?.version!=='2.0'||b?.accepted!==true||typeof b.signerName!=='string'||!b.signerName.trim())
 return respond({error:'Explicit v2.0 acceptance and signer name required'},400)
 if(b.signerName.length>200)return respond({error:'Signer name too long'},400)
 const {data,error}=await ctx.supabaseAdmin.rpc('mes_accept_addendum',{p_actor:user.id,p_terms:ADDENDUM_V2,p_signer:b.signerName.trim()})
 if(error)return respond({error:error.message},409)
 return respond({addendum:data,version:'2.0',message:'Seller acceptance recorded; awaiting MES approval. Existing 5% terms remain active.'})
})}
