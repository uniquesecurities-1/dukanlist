
## Function region (vercel.json `regions`)
`bom1` (Mumbai). Checked 2026-09-30: `db.<ref>.supabase.co` resolves into AWS
`2406:da1a::/35` = ap-south-1 (Mumbai), so functions sit next to the database.
Do not move to sin1/iad1. Note lives here because vercel.json rejects unknown
keys — a `_regions_note` key broke three production deploys on 2026-10-01.
git add vercel.json docs/DEPLOY-NOTES.md && git commit -q -m "fix deploy: vercel.json rejects unknown keys — drop _regions_note (broke 3 deploys); note moved to docs/DEPLOY-NOTES.md" && git log --oneline -1

## Function region (vercel.json `regions`)
`bom1` (Mumbai). Checked 2026-09-30: `db.<ref>.supabase.co` resolves into AWS `2406:da1a::/35` = ap-south-1 (Mumbai), so functions sit next to the database. Do not move to sin1/iad1.
Note lives here because vercel.json rejects unknown keys - a `_regions_note` key broke three production deploys on 2026-10-01.
