import { test, before, after } from 'node:test'
import assert from 'node:assert/strict'
import { execFile, spawnSync } from 'node:child_process'
import { promisify } from 'node:util'
import { createHash } from 'node:crypto'
import { createServer } from 'node:http'
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

const execFileP = promisify(execFile)
const bin = new URL('../installer/bin/dsh-arm64-install.mjs', import.meta.url).pathname
const cwd = new URL('.', import.meta.url).pathname

const dir = mkdtempSync(join(tmpdir(), 'dsh-install-test-'))
const payload = join(dir, 'payload')
mkdirSync(payload)
const tarball = join(dir, 'dsh-arm64-0.1.0-rc.6.tar.gz')
writeFileSync(join(payload, 'hello.txt'), 'hello-arm64')
spawnSync('tar', ['czf', tarball, '-C', payload, '.'])
const goodSha = createHash('sha256').update(readFileSync(tarball)).digest('hex')

let root = ''
let api = ''
const server = createServer((req, res) => {
  const asset = (sha) => [
    { name: 'dsh-arm64-0.1.0-rc.6.tar.gz', size: 1, browser_download_url: `${root}/dl/dsh-arm64-0.1.0-rc.6.tar.gz` },
    { name: 'sha256sums.txt', size: 1, browser_download_url: `${root}/dl/sha256sums-${sha}.txt` },
  ]
  if (req.url === '/releases/latest' || req.url === '/releases/tags/0.1.0-rc.6') {
    res.setHeader('content-type', 'application/json')
    res.end(JSON.stringify({ tag_name: 'v0.1.0-rc.6', assets: asset(goodSha) }))
  } else if (req.url === '/releases/tags/bad') {
    res.setHeader('content-type', 'application/json')
    res.end(JSON.stringify({ tag_name: 'v0.1.0-rc.6', assets: asset('0'.repeat(64)) }))
  } else if (req.url === '/dl/dsh-arm64-0.1.0-rc.6.tar.gz') {
    res.end(readFileSync(tarball))
  } else if (req.url === `/dl/sha256sums-${goodSha}.txt`) {
    res.end(`${goodSha}  dsh-arm64-0.1.0-rc.6.tar.gz\n`)
  } else if (req.url === `/dl/sha256sums-${'0'.repeat(64)}.txt`) {
    res.end(`${'0'.repeat(64)}  dsh-arm64-0.1.0-rc.6.tar.gz\n`)
  } else {
    res.statusCode = 404
    res.end()
  }
})

before(async () => {
  await new Promise((r) => server.listen(0, '127.0.0.1', r))
  root = `http://127.0.0.1:${server.address().port}`
  api = `${root}/releases`
})
after(() => server.close())

async function run(extra) {
  try {
    const { stdout, stderr } = await execFileP(process.execPath, [bin, '--api', api, ...extra], { encoding: 'utf8', cwd })
    return { status: 0, stdout, stderr: '' }
  } catch (e) {
    return { status: e.code ?? 1, stdout: e.stdout ?? '', stderr: e.stderr ?? '' }
  }
}

test('--print-plan does not download and exits 0', async () => {
  const r = await run(['--print-plan', '--version', '0.1.0-rc.6'])
  assert.equal(r.status, 0, r.stderr)
  assert.match(r.stdout, /0\.1\.0-rc\.6/)
  assert.match(r.stdout, /\.dsh-arm64/)
})

test('full install: download, verify sha256, unpack', async () => {
  const dest = join(dir, 'installed')
  const r = await run(['--dir', dest, '--version', '0.1.0-rc.6'])
  assert.equal(r.status, 0, r.stderr)
  assert.ok(existsSync(join(dest, 'hello.txt')), 'payload unpacked')
  assert.equal(readFileSync(join(dest, 'hello.txt'), 'utf8'), 'hello-arm64')
})

test('bad checksum exits 1 with mismatch message', async () => {
  const r = await run(['--dir', join(dir, 'bad'), '--version', 'bad'])
  assert.equal(r.status, 1)
  assert.match(r.stderr, /sha256 mismatch/)
})

test('unknown option exits 2', async () => {
  const r = await run(['--bogus'])
  assert.equal(r.status, 2)
})

test('non-arm64 platform exits 2', async () => {
  const r = await run(['--platform', 'x64'])
  assert.equal(r.status, 2)
  assert.match(r.stderr, /aarch64/)
})