#!/usr/bin/env node
import os from 'os'

const totalMemMB = Math.floor(os.totalmem() / 1024 / 1024)
const freeMemMB = Math.floor(os.freemem() / 1024 / 1024)

const targetByTotal = Math.floor(totalMemMB * 0.7)
const safeByFree = Math.floor(freeMemMB * 0.8)

let memLimit = Math.min(targetByTotal, safeByFree)

const MIN_MEM = 1000
const MAX_MEM = 32000

if (memLimit < MIN_MEM) memLimit = MIN_MEM
if (memLimit > MAX_MEM) memLimit = MAX_MEM

process.stdout.write(memLimit.toString())
