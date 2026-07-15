#!/usr/bin/env bun

import { createProgram } from "./cli";

const program = createProgram();
await program.parse();
