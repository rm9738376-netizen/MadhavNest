// Draft for staging. Requires deployed mes_accept_addendum RPC and configured email OTP.
import { withSupabase } from 'npm:@supabase/server'
import { PDFDocument, StandardFonts } from 'npm:pdf-lib@1.17.1'
const cors={'Content-Type':'application/json','Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'GET,POST,OPTIONS'}
const respond=(value:any,status=200)=>Response.json(value,{status,headers:cors})
// Exact terms are controlled by the server, never supplied by the browser.
// MES countersignature and archival PDF generation must be completed before billing activation.
const ADDENDUM_V2=`Madhav Ecom Solution — Commission Addendum v2.0.
This addendum modifies the signed seller agreement only from the effective date mutually accepted by the Seller and Madhav Ecom Solution. The original 12-month term and expiry date remain unchanged. Existing 5% of Net Sales obligations earned before the effective date remain due under the original agreement.
From the accepted effective date, the service fee is INR 10 for each unique marketplace order successfully delivered to the buyer. This fee is per marketplace order ID, not per item or shipment. A fully returned or fully refunded delivered order receives one INR 10 reversal. Cancelled-before-delivery and RTO orders that were not delivered have no fee. Partial returns do not reverse the fee when some part of the order remains fulfilled. Replacement or exchange fulfillment does not cause a second fee for the same original order. MES and Seller will reconcile marketplace records, refunds and any carried-forward credits.
All other terms of the original agreement remain unchanged. This addendum requires separate Seller acceptance and MES approval before becoming effective.`
const hashTerms=async()=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(ADDENDUM_V2)))).map(x=>x.toString(16).padStart(2,'0')).join('')
export default {fetch:withSupabase({auth:'none'},async(req,ctx)=>{
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors})
 if(req.method==='GET')return respond({version:'2.0',terms:ADDENDUM_V2,sha256:await hashTerms()})
 if(req.method!=='POST')return respond({error:'Method not allowed'},405)
 const token=(req.headers.get('authorization')||'').replace(/^Bearer /i,'')
 if(!token)return respond({error:'Verified seller login required'},401)
 const {data:{user},error:authError}=await ctx.supabaseAdmin.auth.getUser(token)
 if(authError||!user?.email||!user.email_confirmed_at)return respond({error:'Verified seller login required'},401)
 const b=await req.json().catch(()=>null)
 if(b?.action!=='accept_addendum'||b?.version!=='2.0'||b?.accepted!==true||typeof b.signerName!=='string'||!b.signerName.trim())
 return respond({error:'Explicit v2.0 acceptance and signer name required'},400)
 if(b.signerName.length>200)return respond({error:'Signer name too long'},400)
 if(b.termsSha256!==await hashTerms())return respond({error:'Agreement text changed; review again before signing'},409)
 const {data,error}=await ctx.supabaseAdmin.rpc('mes_accept_addendum',{p_actor:user.id,p_terms:ADDENDUM_V2,p_signer:b.signerName.trim()})
 if(error)return respond({error:error.message},409)
 // Snapshot the exact server-owned terms and authenticated acceptance evidence.
 // The PDF is not countersigned by MES; approval is a separate action.
 try{
  const pdf=await PDFDocument.create()
  const font=await pdf.embedFont(StandardFonts.Helvetica)
  const lines=['MADHAV ECOM SOLUTION - COMMISSION ADDENDUM v2.0',
   'Seller email: '+user.email,'Signer: '+b.signerName.trim(),
   'Seller auth ID: '+user.id,'Accepted at (UTC): '+new Date().toISOString(),
   'Terms SHA-256: '+await hashTerms(),'',
   ...ADDENDUM_V2.replace(/[^\\x20-\\x7E\\n]/g,'-').split('\\n').flatMap(line=>{
    const words=line.split(/\\s+/),out=[];let current=''
    for(const word of words){if((current+' '+word).length>95){out.push(current);current=word}else current+=(current?' ':'')+word}
    if(current)out.push(current);return out
   })]
  let page=pdf.addPage([595,842]),y=800
  for(const line of lines){if(y<45){page=pdf.addPage([595,842]);y=800}page.drawText(line,{x:38,y,size:9,font});y-=15}
  const bytes=await pdf.save()
  const digest=await crypto.subtle.digest('SHA-256',bytes)
  const sha=Array.from(new Uint8Array(digest)).map(x=>x.toString(16).padStart(2,'0')).join('')
  const path='addenda/'+data.addendum_id+'.pdf'
  const {error:uploadError}=await ctx.supabaseAdmin.storage.from('mes-signed-addenda').upload(path,bytes,{contentType:'application/pdf',upsert:false})
  if(uploadError)throw uploadError
  const {error:archiveError}=await ctx.supabaseAdmin.rpc('mes_archive_addendum',{p_addendum_id:data.addendum_id,p_actor:user.id,p_pdf_key:path,p_pdf_hash:sha})
  if(archiveError)throw archiveError
  return respond({addendum:data,version:'2.0',archived:true,message:'Acceptance and PDF archived; awaiting MES approval.'})
 }catch(archiveError){
  return respond({addendum:data,version:'2.0',archived:false,error:'Acceptance recorded, but PDF archival failed. Contact MES; billing remains inactive.'},202)
 }
})}
