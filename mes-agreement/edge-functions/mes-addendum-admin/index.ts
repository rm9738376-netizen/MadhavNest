import { withSupabase } from 'npm:@supabase/server'
const headers={'Content-Type':'application/json','Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'GET,POST,OPTIONS'}
const reply=(data:any,status=200)=>Response.json(data,{status,headers})
export default {fetch:withSupabase({auth:'none'},async(req,ctx)=>{
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers})
 const token=(req.headers.get('authorization')||'').replace(/^Bearer /i,'')
 if(!token)return reply({error:'Admin login required'},401)
 const {data:{user},error:authError}=await ctx.supabaseAdmin.auth.getUser(token)
 if(authError||!user)return reply({error:'Admin login required'},401)
 const db=ctx.supabaseAdmin
 const {data:admin,error:adminError}=await db.from('admin_users').select('auth_user_id').eq('auth_user_id',user.id).maybeSingle()
 if(adminError)return reply({error:'Admin authorization unavailable'},500)
 if(!admin)return reply({error:'Forbidden'},403)
 if(req.method==='GET'){
  const {data,error}=await db.from('seller_agreement_addenda').select('id,seller_id,version,accepted_at,accepted_name,pdf_key,pdf_hash,mes_approved_at,created_at').order('created_at',{ascending:false}).limit(100)
  if(error)return reply({error:error.message},500)
  return reply({addenda:(data||[]).map((a:any)=>({...a,readyForApproval:!!a.accepted_at&&!!a.pdf_key&&/^[0-9a-f]{64}$/.test(a.pdf_hash||'')&&!a.mes_approved_at}))})
 }
 if(req.method!=='POST')return reply({error:'Method not allowed'},405)
 const body=await req.json().catch(()=>null)
 if(body?.action!=='approve'||typeof body.addendumId!=='string')return reply({error:'Invalid request'},400)
 // Never approve a mere path/hash claim: verify the actual private PDF bytes.
 const {data:record,error:recordError}=await db.from('seller_agreement_addenda')
  .select('id,pdf_key,pdf_hash,accepted_at,mes_approved_at')
  .eq('id',body.addendumId).maybeSingle()
 if(recordError||!record)return reply({error:'Addendum not found'},404)
 if(!record.accepted_at||record.mes_approved_at||!record.pdf_key||!record.pdf_hash)
  return reply({error:'Addendum not ready for approval'},409)
 if(record.pdf_key!=='addenda/'+record.id+'.pdf'||!/^[0-9a-f]{64}$/.test(record.pdf_hash))
  return reply({error:'Invalid archive reference'},409)
 const {data:file,error:fileError}=await db.storage.from('mes-signed-addenda').download(record.pdf_key)
 if(fileError||!file)return reply({error:'Archived PDF not accessible'},409)
 const bytes=new Uint8Array(await file.arrayBuffer())
 if(bytes.length<100||bytes.length>1048576||new TextDecoder().decode(bytes.slice(0,5))!=='%PDF-')
  return reply({error:'Archived file is not a valid PDF candidate'},409)
 const actual=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)))
  .map(x=>x.toString(16).padStart(2,'0')).join('')
 if(actual!==record.pdf_hash)return reply({error:'Archived PDF integrity mismatch'},409)
 const {data,error}=await db.rpc('mes_approve_addendum',{p_addendum_id:body.addendumId,p_admin_id:user.id})
 if(error)return reply({error:error.message},409)
 return reply({approval:data})
})}
