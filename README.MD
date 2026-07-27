<div align="center">

<img src="Assets/icon.png" alt="Bismuth icon" width="128">

# Bismuth

**An early in-development PowerPC32 instruction translator for Apple Silicon.**

[![License: GPL v3](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](LICENSE)

For the Quick Start, see [QUICKSTART.md](Docs/QUICKSTART.md).

</div>

## What is this?

Bismuth interprets old PowerPC Mac software to run on modern Apple Silicon Macs. It loads 32-bit PowerPC Mach-O executables or 32-bit PowerPC app binaries, emulates their instructions, and feeds adapted macOS framework links through it's Resolves system, and for any missing symbols, Scarlet will attempt to dynamically resolve them.

![Bismuth running iMovie '09](Assets/banner.png)

## Why in god's name would you put this out in it's current state?

Because this is exactly the point at which outside eyes are valuable. Bismuth has admittedly hitten several halts with my expertise, but I think the open-source community is a lovely bunch, and I'd cherish any contributions made deeply.

Expect breakage. Do not expect broad compatibility, reliable performance, polished packaging, or a stable interface. If you need a dependable way to run a particular PowerPC application on a modern Mac, this is probably not it yet.

## Please contribute

Contributions are not a ceremonial invitation here; they will be the project for the forseeable future. Try an application, report precisely where it fails, improve a Resolve, or sprinkle some glitter on my dirty mess.

If you open an issue, include the application and version, macOS version, Apple Silicon model, how you launched it, and any terminal output. If you send code, explain the program or behaviour it fixes and include a minimal reproduction when possible. Curious experiments and imperfect first contributions are welcome. I value every single second you spend looking at this repository.
