# nanoBoot

[![Build](https://github.com/volium/nanoBoot/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/volium/nanoBoot/actions/workflows/build.yml)

This repository contains the source code for the USB HID-based bootloader for ATmegaXXU4 family of devices.

The name *nanoBoot* comes from the fact that the compiled source fits in the smallest available boot size on the ATMegaXXu4 devices, 256 words or 512 bytes. The code is based on Dean Camera's [LUFA](https://github.com/abcminiuser/lufa) USB implementation, but it is **EXTREMELY** streamlined, size-optimized and targeted for the [ATmega16U4](http://www.atmel.com/devices/atmega16u4.aspx) and [ATmega32u4](http://www.atmel.com/devices/atmega32u4.aspx) devices; I had to make quite a few hardware assumptions, mostly to the fuse settings related to clock configuration for things to be as compact as possible, but the code still allows for some flexibility.

It's very likely that a few sections can be rewritten to make it even smaller, and the ultimate goal is to support EEPROM programming as well, although that would require changes to the host code.

The current version (commit #[d0ea26b](https://github.com/volium/nanoBoot/commit/d0ea26bb01e764340dc8ad7b473ad98cefdb52eb)) is supported as-is in the 'hid_bootloader_loader.py' script that ships with [LUFA-151115](https://github.com/abcminiuser/lufa/releases/tag/LUFA-151115).

Binary size:
* 478 bytes (as is)
* 484 bytes (enable LED support with "LED_ACTIVE_LEVEL  1" (Leonardo, Nano, Teensy 2.0-type)
* 486 bytes (enable LED support with "LED_ACTIVE_LEVEL  0" (Promicro-type)

Here, LED supports require user to uncomment few lines in `nanoBoot.S`.

## HW assumptions:

* CLK is 16 MHz Crystal and fuses are setup correctly to support it:
    * Select Clock Source (CKSEL3:CKSEL0) fuses are set to Extenal Crystal, CKSEL=1111 SUT=11
    * Divide clock by 8 fuse (CKDIV8) can be set to either 0 or 1
* Bootloader starts on reset; Hardware Boot Enable fuse is configured, HWBE=0
* Boot Flash Size is set correctly to 256 words (512 bytes), StartAddress=0x3F00, BOOTSZ=11
* Device signature = 0x1E9587

* Fuse Settings:
    * lfuse memory = 0xFF or 0x7F (CKDIV8=1 or 0, 16CK+65ms)
    * hfuse memory = 0xD6 (EESAVE=0, BOOTRST=0)
    * efuse memory = 0xC7 (=0xF7, No BOD)

* Alternatively, BOD can be used to ease CKSEL-SUT setting requirements to
  allow teensy-like FUSE settings:
    * lfuse memory = 0x5F (CKDIV8=0, 16CK + 0ms)
    * hfuse memory = 0xDF (EESAVE=1, BOOTRST=1)
    * efuse memory = 0xF4 (BOD=2.4V)

The documentation is part of the source code itself, and even though some people may find it extremely verbose, I think that's better than lack of documentation; after all, assembly can be hard to read sometimes... ohhh yes, in case that was not expected, this is all written in pure GAS (GNU Assembly), compiled using the [Atmel AVR 8-bit Toolchain](http://www.atmel.com/tools/atmelavrtoolchainforwindows.aspx).

## Toolchain installation

 - ### MacOS
    - Install [Homebrew](https://brew.sh/):

        `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
    
    - Install the avr-gcc toolchain via [osx-cross/avr](https://github.com/osx-cross/homebrew-avr):
        
        - Make sure **Xcode Command Line Tools** are installed:
        
            `xcode-select --install`
        
        - If **Xcode Command Line Tools** are installed, make sure they are up-to-date:
            
            `softwareupdate --all --install --force `
        
        - Install the latest version of avr-gcc:
            
            `brew tap osx-cross/avr`
            
            `brew install avr-gcc`
        
            **NOTE:** I personally experienced an issue with unidentified `___gmpz_X` symbols for `architecture arm64` during the installation on a new M1 MacBook Pro 14 inch; I was able to resolve this by completely removing `gmp` (`brew uninstall --force gmp`) and retrying the installation.

        - Install avrdude to be able to flash the device:
            
            `brew install avrdude`
