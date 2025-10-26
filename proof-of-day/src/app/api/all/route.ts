import { NextResponse } from 'next/server'
import { DB } from '@/lib/db'
export async function GET(){ return NextResponse.json({ goals: DB.goals }) }
