# nanoBoot

This repository contains the source code for the USB HID-based bootloader for ATmegaXXU4 family of devices.

The name *nanoBoot* comes from the fact that the compiled source fits in the smallest available boot size on the ATMega16u4 and ATmega32u4, 256 words or 512 bytes. It's based on Dean Camera's [LUFA](https://github.com/abcminiuser/lufa) USB implementation, but it is **EXTREMELY** streamlined, size-optimized and targetted for the [ATmega16U4](http://www.atmel.com/devices/atmega16u4.aspx) and [ATmega32u4](http://www.atmel.com/devices/atmega32u4.aspx) devices; I had to make quite a few hardware assumptions, mostly to the fuse settings related to clock configuration for things to be as compact as possible, but the code still allows for some flexibility.

It's very likely that a few sections can be rewritten to make it even smaller, and the ultimate goal is to support EEPROM programming as well, although that would require changes to the host code.

The current version (commit #[5f84c0c](https://github.com/volium/nanoBoot/commit/5f84c0c44d78e907de869176c576855c8ba7a2f2)) is supported as-is in the 'hid_bootloader_loader.py' script that ships with [LUFA-151115](https://github.com/abcminiuser/lufa/releases/tag/LUFA-151115), and is exactly 510 bytes.

The documentation is part in the source code itself, and some people may find it extremely verbose, but I think that's better than lack of documentation, after all, assembly can be hard to read sometimes... ohhh yes, in case that was not expected, this is all written in pure GAS (GNU Assembly), compiled using the AVR Toolchain.
