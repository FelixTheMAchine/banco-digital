"use client";
import { useAurora } from "@/components/app-shell";
import { ProfileView } from "@/components/profile-security";
export default function Page(){const {user,updateUser}=useAurora();return <ProfileView user={user} onUpdated={updateUser}/>;}
