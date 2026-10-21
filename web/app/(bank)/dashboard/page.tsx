"use client";
import { useAurora } from "@/components/app-shell";
import { DashboardView } from "@/components/banking";
export default function Page(){const {user}=useAurora();return <DashboardView user={user}/>;}
