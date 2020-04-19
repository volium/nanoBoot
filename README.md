# nanoBoot

[![Build Status](https://travis-ci.org/volium/nanoBoot.svg?branch=master)](https://travis-ci.org/volium/nanoBoot)

This repository contains the source code for the USB HID-based bootloader for ATmegaXXU4 family of devices.

The name *nanoBoot* comes from the fact that the compiled source fits in the smallest available boot size on the ATMegaXXu4 devices, 256 words or 512 bytes. The code is based on Dean Camera's [LUFA](https://github.com/abcminiuser/lufa) USB implementation, but it is **EXTREMELY** streamlined, size-optimized and targeted for the [ATmega16U4](http://www.atmel.com/devices/atmega16u4.aspx) and [ATmega32u4](http://www.atmel.com/devices/atmega32u4.aspx) devices; I had to make quite a few hardware assumptions, mostly to the fuse settings related to clock configuration for things to be as compact as possible, but the code still allows for some flexibility.

It's very likely that a few sections can be rewritten to make it even smaller, and the ultimate goal is to support EEPROM programming as well, although that would require changes to the host code.

<!--The current version (commit #[5401f92](https://github.com/volium/nanoBoot/commit/5f84c0c44d78e907de869176c576855c8ba7a2f2)) is supported as-is in the 'hid_bootloader_loader.py' script that ships with [LUFA-151115](https://github.com/abcminiuser/lufa/releases/tag/LUFA-151115), and is exactly 508 bytes long.-->

The current version (2020-04-03) is supported as-is in the 'hid_bootloader_loader.py' script that ships with [LUFA-151115](https://github.com/abcminiuser/lufa/releases/tag/LUFA-151115), and is exactly 512 bytes long.

## HW assumptions:

* CLK is 16 MHz Crystal and fuses are setup correctly to support it:
    * Select Clock Source (CKSEL3:CKSEL0) fuses are set to Extenal Crystal, CKSEL=1111 SUT=11
    * Divide clock by 8 fuse (CKDIV8) can be any value.
* Bootloader starts on reset; Hardware Boot Enable fuse is configured, HWBE=0
* Boot Flash Size is set correctly to 256 words (512 bytes), StartAddress=0x3F00, BOOTSZ=11
* Device signature = 0x1E9587

* Fuse Settings:
    * lfuse memory = 0xFF or 0x7F (CKDIV8=1 or 0, 16CK+65ms)
    * hfuse memory = 0xD6 (EESAVE=0, BOOTRST=0)
    * efuse memory = 0xC7 (=0xF7, No BOD)

* Alternatively BOD can be used to ease CKSEL-SUT setting requirements to
  allow teensy like FUSE setting
    * lfuse memory = 0x5F (CKDIV8=0, 16CK + 0ms)
    * hfuse memory = 0xDF (EESAVE=1, BOOTRST=1)
    * efuse memory = 0xF4 (BOD=2.4V)

The documentation is part of the source code itself, and even though some people may find it extremely verbose, I think that's better than lack of documentation; after all, assembly can be hard to read sometimes... ohhh yes, in case that was not expected, this is all written in pure GAS (GNU Assembly), compiled using the [Atmel AVR 8-bit Toolchain](http://www.atmel.com/tools/atmelavrtoolchainforwindows.aspx).
