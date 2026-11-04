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
 const {data,error}=await db.rpc('mes_approve_addendum',{p_addendum_id:body.addendumId,p_admin_id:user.id})
 if(error)return reply({error:error.message},409)
 return reply({approval:data})
})}
