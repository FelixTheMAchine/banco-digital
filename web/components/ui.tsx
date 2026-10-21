"use client";
import { useEffect, useRef, useState, type ReactNode, type InputHTMLAttributes, type SelectHTMLAttributes } from "react";
import { AlertCircle, Check, Inbox, X } from "lucide-react";
import { api, ApiError } from "@/lib/api";
export function Brand(){return <span className="brand"><svg className="brand-mark" viewBox="0 0 32 34" fill="none" aria-hidden="true"><path d="M3 29 14.5 4h3L29 29h-6L16 12 9 29H3Z" fill="currentColor"/><path d="M11 23h10l2.5 6h-15l2.5-6Z" fill="currentColor" opacity=".45"/></svg>aurora<span className="sr-only"> banco simulado</span></span>}
export function Field({ label, hint, children, ...props }: InputHTMLAttributes<HTMLInputElement> & {label:string;hint?:string;children?:ReactNode}) { return <label className="field"><span>{label}</span>{children || <input {...props}/ >}{hint&&<span className="field-hint">{hint}</span>}</label>; }
export function Select({label, children,...props}: SelectHTMLAttributes<HTMLSelectElement>&{label:string}){return <label className="field"><span>{label}</span><select {...props}>{children}</select></label>}
export function Feedback({error,success}:{error?:string|null;success?:string|null}){return <>{error&&<div className="alert error" role="alert"><AlertCircle size={15} style={{display:"inline",marginRight:7,verticalAlign:"middle"}}/>{error}</div>}{success&&<div className="alert success" role="status"><Check size={15} style={{display:"inline",marginRight:7,verticalAlign:"middle"}}/>{success}</div>}</>}
export function Loading({text="Carregando sua conta…"}:{text?:string}){return <div className="loading" role="status"><span className="spinner" aria-hidden="true"/>{text}</div>}
export function Empty({children}:{children:ReactNode}){return <div className="empty"><Inbox size={28}/>{children}</div>}
export function Modal({title,children,onClose}:{title:string;children:ReactNode;onClose:()=>void}){
 const ref=useRef<HTMLDivElement>(null);
 const closeRef=useRef(onClose);
 useEffect(()=>{closeRef.current=onClose},[onClose]);
 useEffect(()=>{const previous=document.activeElement as HTMLElement|null;const el=ref.current;const focusable=()=>el?.querySelectorAll<HTMLElement>('button:not([disabled]),a[href],input,select,textarea,[tabindex="0"]');focusable()?.[0]?.focus();const handle=(event:KeyboardEvent)=>{if(event.key==="Escape")closeRef.current();if(event.key==="Tab"){const items=focusable();if(!items?.length)return;const first=items[0],last=items[items.length-1];if(event.shiftKey&&document.activeElement===first){event.preventDefault();last.focus()}else if(!event.shiftKey&&document.activeElement===last){event.preventDefault();first.focus()}}};document.addEventListener("keydown",handle);const overflow=document.body.style.overflow;document.body.style.overflow="hidden";return()=>{document.removeEventListener("keydown",handle);document.body.style.overflow=overflow;previous?.focus()}},[]);
 return <div className="modal-overlay" onMouseDown={e=>{if(e.target===e.currentTarget)onClose()}}><div className="modal" ref={ref} role="dialog" aria-modal="true" aria-label={title}><div className="card-heading"><h2>{title}</h2><button className="icon-button" aria-label="Fechar" onClick={onClose}><X size={20}/></button></div>{children}</div></div>
}
export function useResource<T>(path:string|null){
 const[data,setData]=useState<T|null>(null),[error,setError]=useState<string|null>(null),[errorStatus,setErrorStatus]=useState<number|null>(null),[loading,setLoading]=useState(!!path),[tick,setTick]=useState(0);
 useEffect(()=>{if(!path){setLoading(false);return}let alive=true;setLoading(true);setError(null);setErrorStatus(null);api<T>(path).then(value=>{if(alive)setData(value)}).catch(err=>{if(alive){setError(err instanceof Error?err.message:"Não foi possível carregar os dados.");setErrorStatus(err instanceof ApiError?err.status:null);setData(null)}}).finally(()=>{if(alive)setLoading(false)});return()=>{alive=false}},[path,tick]);
 return{data,error,errorStatus,loading,reload:()=>setTick(x=>x+1)}
}
export function useAction(){const[busy,setBusy]=useState(false),[error,setError]=useState<string|null>(null),[success,setSuccess]=useState<string|null>(null);async function run<T>(action:()=>Promise<T>,message?:string):Promise<T|undefined>{if(busy)return;setBusy(true);setError(null);setSuccess(null);try{const result=await action();if(message)setSuccess(message);return result}catch(e){setError(e instanceof Error?e.message:"Não foi possível concluir.");return undefined}finally{setBusy(false)}}return{busy,error,success,run,setError,setSuccess}}
