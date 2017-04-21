# nanoBoot

This repository contains the source code for the USB HID-based bootloader for ATmegaXXU4 family of devices.

The name *nanoBoot* comes from the fact that the compiled source fits in the smallest available boot size on the ATMegaXXu4 devices, 256 words or 512 bytes. The code is based on Dean Camera's [LUFA](https://github.com/abcminiuser/lufa) USB implementation, but it is **EXTREMELY** streamlined, size-optimized and targeted for the [ATmega16U4](http://www.atmel.com/devices/atmega16u4.aspx) and [ATmega32u4](http://www.atmel.com/devices/atmega32u4.aspx) devices; I had to make quite a few hardware assumptions, mostly to the fuse settings related to clock configuration for things to be as compact as possible, but the code still allows for some flexibility.

It's very likely that a few sections can be rewritten to make it even smaller, and the ultimate goal is to support EEPROM programming as well, although that would require changes to the host code.

The current version (commit #[5401f92](https://github.com/volium/nanoBoot/commit/5f84c0c44d78e907de869176c576855c8ba7a2f2)) is supported as-is in the 'hid_bootloader_loader.py' script that ships with [LUFA-151115](https://github.com/abcminiuser/lufa/releases/tag/LUFA-151115), and is exactly 508 bytes long.

The documentation is part of the source code itself, and even though some people may find it extremely verbose, I think that's better than lack of documentation; after all, assembly can be hard to read sometimes... ohhh yes, in case that was not expected, this is all written in pure GAS (GNU Assembly), compiled using the [Atmel AVR 8-bit Toolchain](http://www.atmel.com/tools/atmelavrtoolchainforwindows.aspx).

## osamu branch

This is a branch of nanoBoot maintained by osamuaoki. https://github.com/osamuaoki/nanoBoot

The core code is the same as upstream. https://github.com/volium/nanoBoot

The main difference is Linux friendly modification to the makefile.

You may also find my folk of teensy_loader_cli with selectable VID/PID which should work with this.  https://github.com/osamuaoki/teensy_loader_cli

Osamu
