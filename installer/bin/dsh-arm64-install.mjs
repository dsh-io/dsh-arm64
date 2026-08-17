#!/usr/bin/env node
import { execFileSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { createReadStream, createWriteStream } from 'node:fs'
import { mkdir, rm } from 'node:fs/promises'
import { homedir, tmpdir } from 'node:os'
import { join } from 'node:path'
import { Readable } from 'node:stream'

const REPO = 'dsh-io/dsh-arm64'
const UA = 'dsh-arm64-install/0.1.0'

const args = process.argv.slice(2)
let version = null
let dest = join(homedir(), '.dsh-arm64')
let printPlan = false
let overridePlatform = null
let apiBase = `https://api.github.com/repos/${REPO}/releases`

for (let i = 0; i < args.length; i++) {
  switch (args[i]) {
    case '--version': version = args[++i]; break
    case '--dir': dest = args[++i]; break
    case '--print-plan': printPlan = true; break
    case '--platform': overridePlatform = args[++i]; break
    case '--api': apiBase = args[++i]; break
    case '--help':
      console.log('Usage: dsh-arm64-install [--version VERSION] [--dir DIR] [--print-plan]')
      process.exit(0)
    default:
      console.error(`unknown option: ${args[i]}`)
      process.exit(2)
  }
}

const platform = overridePlatform ?? process.platform + '/' + process.arch
if (platform !== 'linux/arm64') {
  console.error(`dsh-arm64 targets Linux aarch64 only (got ${platform})`)
  process.exit(2)
}
if (!process.version || Number(process.version.match(/^v(\d+)/)?.[1] ?? 0) < 18) {
  console.error('Node.js >= 18 is required for the installer')
  process.exit(2)
}

const api = `${apiBase}/${version ? `tags/${version}` : 'latest'}`
const res = await fetch(api, { headers: { 'User-Agent': UA } })
if (!res.ok) {
  console.error(`could not resolve release (HTTP ${res.status})`)
  process.exit(1)
}
const rel = await res.json()
const tag = rel.tag_name
const tarballAsset = rel.assets.find((a) => a.name.startsWith('dsh-arm64-') && a.name.endsWith('.tar.gz'))
const sumsAsset = rel.assets.find((a) => a.name === 'sha256sums.txt')
if (!tarballAsset || !sumsAsset) {
  console.error(`release ${tag} is missing expected assets`)
  process.exit(1)
}

if (printPlan) {
  console.log(`release:      ${tag}`)
  console.log(`tarball:      ${tarballAsset.name} (${Math.round(tarballAsset.size / 1024)} KiB)`)
  console.log(`dest:         ${dest}`)
  console.log('(--print-plan: no download performed)')
  process.exit(0)
}

console.log(`resolving release ${tag} ...`)
const tmp = join(tmpdir(), `dsh-arm64-install-${Date.now()}`)
await mkdir(tmp, { recursive: true })
const tarballPath = join(tmp, tarballAsset.name)
const sumsPath = join(tmp, 'sha256sums.txt')

try {
  console.log(`downloading ${tarballAsset.name} ...`)
  const t = await fetch(tarballAsset.browser_download_url, { headers: { 'User-Agent': UA } })
  if (!t.ok) throw new Error(`HTTP ${t.status}`)
  await new Promise((resolve, reject) => {
    const out = createWriteStream(tarballPath)
    Readable.fromWeb(t.body).pipe(out)
    out.on('finish', resolve)
    out.on('error', reject)
  })

  const s = await fetch(sumsAsset.browser_download_url, { headers: { 'User-Agent': UA } })
  if (!s.ok) throw new Error(`HTTP ${s.status}`)
  const sums = await s.text()
  const expected = sums.split('\n').find((l) => l.includes(tarballAsset.name))?.split(/\s+/)[0]
  if (!expected) throw new Error('checksum file does not list tarball')

  console.log('verifying sha256 ...')
  const hash = await sha256File(tarballPath)
  if (hash !== expected) throw new Error(`sha256 mismatch: got ${hash}, expected ${expected}`)

  console.log(`unpacking to ${dest} ...`)
  await mkdir(dest, { recursive: true })
  execFileSync('tar', ['xzf', tarballPath, '-C', dest], { stdio: 'inherit' })
} finally {
  await rm(tmp, { recursive: true, force: true })
}

console.log('\ninstalled to ' + dest)
console.log('start the harness:   ' + join(dest, 'node_modules', '.bin', 'dsh') + ' web')
console.log('first run walks you through API key and profile setup (dsh built-in init).')
console.log('remove it:           rm -rf ' + dest)

async function sha256File(path) {
  const hash = createHash('sha256')
  await new Promise((resolve, reject) => {
    const s = createReadStream(path)
    s.on('data', (c) => hash.update(c))
    s.on('end', resolve)
    s.on('error', reject)
  })
  return hash.digest('hex')
}