; MIT License
;
; nanoBoot
;
; Copyright (c) 2016 Rodrigo Torres
;
; Permission is hereby granted, free of charge, to any person obtaining a copy
; of this software and associated documentation files (the "Software"), to deal
; in the Software without restriction, including without limitation the rights
; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
; copies of the Software, and to permit persons to whom the Software is
; furnished to do so, subject to the following conditions:
;
; The above copyright notice and this permission notice shall be included in all
; copies or substantial portions of the Software.
;
; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
; SOFTWARE.


; Original source for nanoBoot
; Simple HID USB Bootloader for AVR Microcontrollers (ATMEGA16U4/ATMEGA32U4)


; HW assumptions:
; CLK is 16 MHz Crystal and fuses are setup correctly to support it:
;
;     Select Clock Source (CKSEL3:CKSEL0) fuses are set to Extenal Crystal, CKSEL=1111 SUT=11
;     Divide clock by 8 fuse (CKDIV8) can be set to either 0 or 1
;
; Bootloader starts on reset; Hardware Boot Enable fuse is configured, HWBE=0
; Boot Flash Size is set correctly to 256 words (512 bytes), StartAddress=0x3F00, BOOTSZ=11

; Fuse Settings: (Pro Micro like)
; Device signature = 0x1E9587
; lfuse memory = 0xFF
; hfuse memory = 0xD6
; efuse memory = 0xC7

; Fuse Settings: (Teensy 2.0 like)
; Device signature = 0x1E9587
; lfuse memory = 0x5F
; hfuse memory = 0xDF
; efuse memory = 0xC4


; ==========================================================
; LED SUPPORT START

; Turn LED on while bootloader is active
; NOTE: This feature uses 6 bytes for active high and 8 bytes for active low;
; see "Enable LED" in the "run_bootloader" section for details.

; Uncomment the following line to enable LED feature
; #define LED_ENABLED

; LED Configuration
; Uncomment or add a new LED configuration for your specific board

; Adafruit's Atmega32u4 Breakout Board (Product ID: 296) - Now discontinued
; https://www.adafruit.com/product/296
;   -- LED is ON with ATmega32u4 PIN E6 HIGH
; #define LED_BIT           6
; #define LED_CONF          DDRE
; #define LED_PORT          PORTE
; #define LED_ACTIVE_LEVEL  1

; Teensy 2.0 compatible board
;   -- LED is ON with ATmega32u4 PIN D6 HIGH
; #define LED_BIT           6
; #define LED_CONF          DDRD
; #define LED_PORT          PORTD
; #define LED_ACTIVE_LEVEL  1

; Leonardo/Nano compatible board
;   -- LED is ON with ATmega32u4 PIN C7 HIGH
; #define LED_BIT           7
; #define LED_CONF          DDRC
; #define LED_PORT          PORTC
; #define LED_ACTIVE_LEVEL  1

; Pro Micro compatible board
;   -- LED is ON with ATmega32u4 PIN D5 LOW
; #define LED_BIT           5
; #define LED_CONF          DDRD
; #define LED_PORT          PORTD
; #define LED_ACTIVE_LEVEL  0

; Pro Micro compatible board
;   -- LED is ON with ATmega32u4 PIN B3 LOW
; #define LED_BIT           3
; #define LED_CONF          DDRB
; #define LED_PORT          PORTB
; #define LED_ACTIVE_LEVEL  0

#if defined(LED_ENABLED)
    #if !defined(LED_PORT) || !defined(LED_CONF) || !defined(LED_BIT) || !defined(LED_ACTIVE_LEVEL)
        #error "If LED feature is enabled, the following need to be defined: LED_BIT, LED_CONF, LED_PORT, LED_ACTIVE_LEVEL"
    #else
         ; Set IO register as output for LED
        #define ENABLE_LED_OUTPUT   sbi _SFR_IO_ADDR(LED_CONF), LED_BIT
        #if LED_ACTIVE_LEVEL == 1
            #define TURN_LED_ON     sbi _SFR_IO_ADDR(LED_PORT), LED_BIT
            #define TURN_LED_OFF    cbi _SFR_IO_ADDR(LED_PORT), LED_BIT
        #elif LED_ACTIVE_LEVEL == 0
            #define TURN_LED_ON     cbi _SFR_IO_ADDR(LED_PORT), LED_BIT
            #define TURN_LED_OFF    sbi _SFR_IO_ADDR(LED_PORT), LED_BIT
        #else
            #error "LED_ACTIVE_LEVEL needs to be either 1 (active high) or 0 (active low)"
        #endif
    #endif
#endif

; LED SUPPORT END
; ==========================================================


; SW assumptions:
; The bootloader only "needs" endpoint 0; however, the HID spec requires any HID device to have an
; Interrupt IN endpoint, and the host can decide to poll that endpoint even when the HID report
; descriptor does not actually declare any input reports. Because of this, endpoints 0 and 1 are
; configured (in reversed order). See commit bd1bd68e200485aa16445c9d22dd53bb205ee102 for details.


; Register Assignments:
; R0  =  temp
; R1  =  temp (traditionally, R1 stores constant 0, but we use it as temp because SPM uses R1:R0)
; R29 =  0 (common constant, use instead of traditional R1 since YH is always 0 within bootloader)
; R2     unused
; R3  =  1 (common constant, number is used constantly in the code)
; R4  =  copy of MCUSR (MCU Status Register)
; R4  ... R15  unused
; R16          local variable
; R17          local variable
; R18 ... R25  local array variable used by USB
; R26, R27     X index register
; R28, R29      index register
;     R28 = YL = lo8(USB_BASE) or lo8(EIO_BASE)
;     R29 = YH = 0 = rZERO
; R30, R31     Z index register

; Global Flags:
; T Flag (SREG) = BootLoaderActive


; Global Defines:

#define rZERO              r29
#define rONE               r3
#define rMCUSR             r4

; #define rMagicBootKeyL     r26    ; currently not used - XL
; #define rMagicBootKeyH     r27    ; currently not used - XH

; To make things easier, we are going to handle all Setup Paquets
; the same way, and store the values coming in to the same registers:

;   R18 = bmRequestType
;   R19 = bRequest
;   R20 = wValueL
;   R21 = wValueH
;   R22 = wIndexL
;   R23 = wIndexH
;   R24 = wLengthL
;   R25 = wLengthH

#define reg_bmRequestType     r18
#define reg_bRequest          r19
#define reg_wValueL           r20
#define reg_wValueH           r21
#define reg_wIndexL           r22
#define reg_wIndexH           r23
#define reg_wLengthL          r24
#define reg_wLengthH          r25

;
; To facilitate coding, we will use the Y register to point to the first USB register;
; We can then use LDD / STD (Y+oU....) to address USB registers (USB_BASE + relative offset)
;
#define USB_BASE     UHWCON
#define oUHWCON      (UHWCON  - USB_BASE)
#define oUSBCON      (USBCON  - USB_BASE)
#define oUSBSTA      (USBSTA  - USB_BASE)
#define oUSBINT      (USBINT  - USB_BASE)
#define oUDCON       (UDCON   - USB_BASE)
#define oUDINT       (UDINT   - USB_BASE)
#define oUDIEN       (UDIEN   - USB_BASE)
#define oUDADDR      (UDADDR  - USB_BASE)
#define oUEINTX      (UEINTX  - USB_BASE)
#define oUENUM       (UENUM   - USB_BASE)
#define oUERST       (UERST   - USB_BASE)
#define oUECONX      (UECONX  - USB_BASE)
#define oUECFG0X     (UECFG0X - USB_BASE)
#define oUECFG1X     (UECFG1X - USB_BASE)
#define oUESTA0X     (UESTA0X - USB_BASE)
#define oUESTA1X     (UESTA1X - USB_BASE)
#define oUEIENX      (UEIENX  - USB_BASE)
#define oUEDATX      (UEDATX  - USB_BASE)
#define oUEBCX       (UEBCX   - USB_BASE)
#define oUEBCLX      (UEBCLX  - USB_BASE)
#define oUEBCHX      (UEBCHX  - USB_BASE)
#define oUEINT       (UEINT   - USB_BASE)   ; This register has the bits to identify which endpoint triggered an interrupt

;
; To facilitate coding, we will also use the Y register to point to the first Extended IO register;
; We can then use LDD / STD (Y+oU....) to address non-USB extended IO registers (EIO_BASE + relative offset)
; (These are used only in start-up and exit routines when USB is not active)
;
#define EIO_BASE     WDTCSR
#define oWDTCSR      (WDTCSR  - EIO_BASE)
#define oCLKPR       (CLKPR   - EIO_BASE)

#include <avr/io.h>

#ifndef BOOT_ADDRESS
# error "BOOT_ADDRESS not defined!!"
# define BOOT_ADDRESS 0
#endif

      .section    .vectors

      ; We still want the reset vector to jump to "main"
      .global     reset_vector

reset_vector:
;     cli                     ; Dropped cli for size by Sergey
                              ; ... but is this safe for soft-reset, Osamu?
      clr         rZERO       ; Initialize rZERO (YH = R29 register = zero)
      rjmp        main        ; Jump to main

; We are "hiding" the USB descriptors in the Interrupt Vector Table
; NOTE: The 2 instructions above take 4 bytes total

;       .long       0       /* External Interrupt Request 0 */
;       .long       0       /* External Interrupt Request 1 */
;       .long       0       /* External Interrupt Request 2 */
;       .long       0       /* External Interrupt Request 3 */
;       .long       0       /* Reserved */
;       .long       0       /* Reserved */
;       .long       0       /* External Interrupt Request 6 */
;       .long       0       /* Reserved */
;       .long       0       /* Pin Change Interrupt Request 0 */

; We have a total 9 LWORDS (9*4=36 bytes; see NOTE above) to hide part of
; the USB descriptors. We could just hide the Device Descriptor there, but we
; would waste 18 bytes since the config_descriptor would have to be moved after
; the USB-related ISRs (USB General Interrupt Request and the USB Endpoint
; Interrupt Request); instead, we hide the WHOLE Configuration Descriptor,
; including the length prefix, config_descriptor, interface_descriptor, hid_descriptor and
; endpoint_descriptor which is:
; 1 + 9 + 9 + 9 + 7 = 35 bytes, and just leave the device_descriptor and
; hid_report_descriptor (18 + 21 = 39 bytes) defined after the USB-related ISRs.

; 1 byte
config_descriptor_prefix:
   .byte       config_descriptor_end - config_descriptor + 0x80

; 9 bytes
config_descriptor:
   // configuration descriptor, USB spec 9.6.3, page 264-266, Table 9-10
   .byte       9              // bLength              -- Size of Descriptor in Bytes
   .byte       2              // bDescriptorType      -- Configuration Descriptor (0x02)
   .word       9+9+9+7        // wTotalLength         -- Total length in bytes of data returned   ->  ; this is for the whole configuration (4 descriptors)
   .byte       1              // bNumInterfaces       -- Number of Interfaces
   .byte       1              // bConfigurationValue  -- Value to use as an argument to select this configuration
   .byte       0              // iConfiguration       -- Index of String Descriptor describing this configuration
   .byte       0x80           // bmAttributes         -- D7 Reserved (set to 1), D6 Self Powered, D5 Remote Wakeup, D4..D0 Reserved (set to 0)
   .byte       50             // bMaxPower            -- Maximum Power Consumption in 2mA units (50 = 100mA)

; 9 bytes
interface_descriptor:
   // interface descriptor, USB spec 9.6.5, page 267-269, Table 9-12
   .byte       9              // bLength              -- Size of Descriptor in Bytes (9 Bytes)
   .byte       4              // bDescriptorType      -- Interface Descriptor (0x04)
   .byte       0              // bInterfaceNumber     -- Number of Interface
   .byte       0              // bAlternateSetting    -- Value used to select alternative setting
   .byte       1              // bNumEndpoints        -- Number of Endpoints used for this interface
   .byte       0x03           // bInterfaceClass      -- Class Code (0x03 = HID class | 0xFF = Vendor Specific)
   .byte       0x00           // bInterfaceSubClass   -- Subclass Code
   .byte       0x00           // bInterfaceProtocol   -- Protocol Code
   .byte       0              // iInterface           -- Index of String Descriptor Describing this interface

; 9 bytes
hid_descriptor:
   .byte       9              // bLength              -- Size of Descriptor in Bytes (9 Bytes)
   .byte       0x21           // bDescriptorType      -- HID Descriptor (0x21)
   .word       0x0111         // bcdHID               -- HID specification release number (BCD) (1.1)
   .byte       0              // bCountryCode         -- Numeric expression identifying the country for localized hardware
   .byte       1              // bNumDescriptors      -- Number of Report Descriptors
   .byte       0x22           // bDescriptorType      -- The type of a class-specific descriptor that follows (Report Descriptor = 0x22)
   .word       21             // wDescriptorLength    --  Total length of the descriptor identified above (length of Report Descriptor = 21 bytes)

; 7 bytes
endpoint_descriptor:
   .byte       7              // bLength              -- Size of Descriptor in Bytes (7 Bytes)
   .byte       0x05           // bDescriptorType      -- Enpoint Descriptor (0x05)
   .byte       0x81           // bEndpointAddress     -- Endpoint number and direction (0x80 Input | 0x01 Address)
   .byte       0x03           // bmAttributes         -- Transfer type = interrupt
   .word       64             // wMaxPacketSize       -- Maximum packet size supported in bytes (64)
   .byte       5              // bInterval            -- Polling interval (milliseconds)

config_descriptor_end:

; USB-related ISRs are here!!!

      .org        reset_vector + 0x28
      .global     USB_General_Vector
USB_General_Vector:

      ; The following is an optimization by "osamuaoki" that saves 2 bytes.
      ; It uses the full space (4 bytes) of the USB_General_Vector to store an
      ; instruction (std) that used to be part of the USB_General_ISR, which
      ; gets called from here anyway; so it makes sense to pack it here. This
      ; can only be done because the following assumption is valid:

      ; ASSUMPTION!
      ; We know we ONLY enable End Of Reset Interrupt (EORSTE) during USB
      ; Initialization, so we don't need to check that; basically, if we enter
      ; this interrupt (USB General) it's because we need to service the End Of
      ; Reset Interrupt (EORSTI).

      ; This following line will be necessary if the assumption above ever
      ; changes, since we would need to filter invidual interrupt sources
      ; ldd         r17, Y+oUDINT                 ; Load r17 with the value in the USB Device Interrupt Flag Register (UDINT), create a copy of the interrupt flags

      ; Given the assumption above, we can simply clear the whole USB Device Interrupt Flag Register (UDINT) to acknowledge the interrupt
      std         Y+oUDINT, rZERO               ; Load the USB Device Interrupt Flag Register (UDINT) with zero (clear all USB-related interrupts)

      ; If we ever need to distinguish among multiple interrupt sources, we can filter them using code like the following
      ; sbrs        r17, EORSTI                   ; Skip the next instruction if the End Of Reset Interrupt Flag (EORSTI) is set;
                                                  ; Don't jump if “End Of Reset” has been detected by the USB controller; thus service the End Of Reset interrupt
      ; rjmp        not_EORSTI

      ; IMPORTANT NOTE: If the code above ever changes (grows), it will need to
      ; be moved back to the USB_General_ISR section, since interrupt vectors
      ; only allocate 4 bytes, basically enough space to jump to actual ISR.

      rjmp        USB_General_ISR     /* USB General Interrupt Request */

      .org        reset_vector + 0x2c
      .global     USB_Endpoint_Vector
USB_Endpoint_Vector:
      rjmp        USB_Endpoint_ISR    /* USB Endpoint/Pipe Interrupt Communication Request */

; 18 bytes
device_descriptor:
   .byte       18             // bLength              -- Size of the Descriptor in Bytes (18 bytes)
   .byte       1              // bDescriptorType      -- Device Descriptor (0x01)
   .word       0x0110         // bcdUSB               -- USB Specification Number which device complies to
   .byte       0              // bDeviceClass         -- Class Code
   .byte       0              // bDeviceSubClass      -- Subclass Code
   .byte       0              // bDeviceProtocol      -- Protocol Code
   .byte       64             // bMaxPacketSize0      -- Maximum Packet Size for Zero Endpoint (64 bytes)
   .word       0x03EB         // idVendor             -- Vendor ID (Atmel VID, from LUFA)
   .word       0x2067         // idProduct            -- Product ID (HID Class Bootloader PID, from LUFA)
   .word       0x0001         // bcdDevice            -- Device Release Number
   .byte       0              // iManufacturer        -- Index of Manufacturer String Descriptor
   .byte       1              // iProduct             -- Index of Product String Descriptor
   .byte       0              // iSerialNumber        -- Index of Serial Number String Descriptor
   .byte       1              // bNumConfigurations   -- Number of Possible Configuration

; 1 byte
hid_report_descriptor_prefix:
   .byte       hid_report_descriptor_end - hid_report_descriptor + 0x80

; 21 bytes
hid_report_descriptor:
   .byte       0x06, 0xDC, 0xFF  // Usage Page (Vendor Defined 0xDCFF)
   .byte       0x09, 0xFB        // Usage (0xFB)
   .byte       0xA1, 0x01        // Collection (Application)
   .byte       0x09, 0x02        //   Usage (0x02)
   .byte       0x15, 0x00        //   Logical Minimum (0)
   .byte       0x25, 0xFF        //   Logical Maximum (255)
   .byte       0x75, 0x08        //   Report Size (8)
   .byte       0x96, 0x82, 0x00  //   Report Count (130) -> SPM_PAGESIZE (128 bytes) + 2
   .byte       0x91, 0x02        //   Output (Data,Var,Abs,No Wrap,Linear,Preferred State,No Null Position,Non-volatile)
   .byte       0xC0              // End Collection
hid_report_descriptor_end:

; 4 bytes
string_descriptor_0:
   .byte       4              // bLength              -- Size of the Descriptor in Bytes (4 bytes)
   .byte       3              // bDescriptorType      -- String Descriptor (0x03)
   .word       0x0409         // wLANGID              -- Language code supported by the device (en-US)

string_descriptor_1:
   .byte       string_descriptor_1_end - string_descriptor_1    // bLength         -- Size of the Descriptor in Bytes (4 bytes)
   .byte       3                                                // bDescriptorType -- String Descriptor (0x03)
   .word       'n,'a,'n,'o,'B,'o,'o,'t
string_descriptor_1_end:

descriptor_table:
      .byte       0x01, lo8(device_descriptor)
      .byte       0x02, lo8(config_descriptor_prefix)
      .byte       0x21, lo8(hid_descriptor)
      .byte       0x22, lo8(hid_report_descriptor_prefix)
      .byte       0xFE, lo8(string_descriptor_0)
      .byte       0xFF, lo8(string_descriptor_1)
descriptor_table_end:

; =================================================================
; ==  Entry point!
; =================================================================

      .section    .text

      .global     main

; =================================================================
; = Check if bootloader/application should execute
;   Watchdog Timer Reset
;   TODO: Add magic word check?
; =================================================================

main:
; =================================================================
; = Initialize constants
; =================================================================
      ; Set R3=rONE
      clr         rONE                          ; Initialize rONE as 0 (application may have set this before RESET)
      inc         rONE                          ; Initialize rONE  (R3 register = one)

      ; Create a copy of the MCUSR (MCU Status Register) as soon as possible
      in          rMCUSR, _SFR_IO_ADDR(MCUSR)   ; Load MCU Status Register to rMCUSR
      out         _SFR_IO_ADDR(MCUSR), rZERO    ; Load MCU Status Register with rZERO (clear reset flags, particularly clear WDRF in MCUSR), necessary before disabling the Watchdog

      ; Use Y+ for different purpose with YH=R29 to 0 for addressing extended io for any 64 bytes of YL specified section
      ; * WDT initialization routine:  YL=lo8(EIO_BASE)   --- (wdt_init) -- start and end of bootloader
      ; * USB communication routine:   YL=lo8(USB_BASE)   --- (usb_init) -- main part of bootloader
      ;                                YH=rZERO = 0 : good for hi8(USB_BASE) = hi8(EIO_BASE) = 0

      ; We MUST disable the Watchdog Timer first, otherwise it will remain enabled and will keep resetting the system, so...
      ; Disable Watchdog Timer
      mov         r17,  rZERO                   ; Load r17 with zero to disable the Watchdog Timer completely

      rcall       set_watchdog_timer            ; Call the subroutine that sets the watchdog timer with the value loaded in r17

; check_reset_flags:
      sbrs        rMCUSR, EXTRF                 ; Skip the next instruction if EXTRF is set (if External Reset Flag, skip next instruction, go to run_bootloader)

run_application:                                ; We get here if the cause of the reset was anything but an Extenal Reset (push-button)
      jmp         0                             ; Simply jump to 0x0000 (application) IMPORTANT NOTE!! This CANNOT be an 'rjmp'!!

run_bootloader:
      set                                       ; Initialize BootLoaderActive flag (T flag in SREG)

; Enable LED
#if defined(LED_ENABLED)
      ; Set IO register as output for LED
      ENABLE_LED_OUTPUT

      ; If the LED is active low, we need to turn it off here (set LED_BIT) since the MCU IO port is
      ; initialized as 0. This is a 2-byte penalty when using active low LED.
      #if LED_ACTIVE_LEVEL == 0
            TURN_LED_OFF
      #endif
#endif



; =================================================================
; = Setup IRQ Vector Table
; =================================================================

; Move the IRQ Vector Table to the beginning of the Boot Flash Space
; ONLY if the BOOT_ADDRESS is not zero!

#if (BOOT_ADDRESS != 0)
      ldi         r17, _BV(IVSEL)               ; Load r17 with the value needed to set the Interrupt Vectors to the beginning of the Boot Loader section of the Flash
                                                ; Set a logic one to the Interrupt Vector Select bit (IVSEL); for this to work, the Vector Change Enable bit (IVCE) MUST be set to logic zero!

                                                ; Set a logic one to the Interrupt Vector Change Enable bit (IVCE)
      out         _SFR_IO_ADDR(MCUCR), rONE     ; Store MCU Control Register (MCUCR) with the value needed to "unlock" the Interrupt Vector Change Configuration
      out         _SFR_IO_ADDR(MCUCR), r17      ; Store r17 to the MCU Control Register (MCUCR)
#endif

; =================================================================
; = Setup Stack
; = UNNECESARY SINCE ATMEGA32U4 DOES THIS AUTOMATICALLY!
; =================================================================

; Set up the stack (TODO: is this necessary?), we won't be using the stack anyway
      ; ldi         r16, hi8(RAMEND)              ; Load r16 with the most significant 8 bits of RAMEND
      ; ldi         r17, lo8(RAMEND)              ; Load r17 with the least significant 8 bits of RAMEND
      ; out         _SFR_IO_ADDR(SPH), r16        ; Set the Stack Pointer High byte (SPH) with the value in r16
      ; out         _SFR_IO_ADDR(SPL), r17        ; Set the Stack Pointer Low byte (SPL) with the value in r17


; =================================================================
; = Setup System Clock (16 MHz XTAL)
; = UNNECESARY SINCE FUSES TAKE CARE OF THIS!!
; =================================================================

      ; lds         r16, CLKSEL0                  ; Load the value of Clock Selection Register 0 (CLKSEL0) to r16
      ; ori         r16, _BV(EXTE) | _BV(CLKS)    ; Set Enable External Clock (EXTE) and Clock Selector (CLKS) bits in the value loaded in r16
      ; sts         CLKSEL0, r16                  ; Store r16 to the Clock Selection Register 0 (CLKSEL0)
; 1:    lds         r17, CLKSTA                   ; Load the value of  Clock Status Register (CLKSTA) to r17
      ; sbrs        r17, EXTON                    ; Skip the next instruction if the External Clock On bit (EXTON) is set (External Clk is running); basically, move on
      ; rjmp        1b                            ; Jump to 1Backwards if the External Clock On bit (EXTON) is not set (External Clk not running)

      ; The following is a functional improvement by "osamuaoki", after he was
      ; able to free up enough space to fit this in. Basically, this allows the
      ; "Divide clock by 8" fuse (CKDIV8) to be set to any value (0 or 1), since
      ; we are setting the clock prescaler to zero here, effectively setting the
      ; System Clock to 16 MHz, which is one of the HW assumptions made for the
      ; code to work as expected.

      ldi         r17, _BV(CLKPCE)                ; Load r17 with the value needed to "unlock" the prescaler of the Clock; Clock Prescaler Change Enable bit (CLKPCE) set to one, all other bits set to zero.
                                                  ; still YH=0, YL=lo8(EIO_BASE)  initial routine
      std         Y+oCLKPR, r17                   ; Store r17 to the Clock Prescaler Register (CLKPR)
      std         Y+oCLKPR, rZERO                 ; Store rZERO to the Clock Prescaler Register (CLKPR), setting CLKPS3, CLKPS2, CLKPS1 and CLKPS0 to zero (Clock Division Factor = 1; System Clock is 16 MHz)

; =================================================================
; = Basic device setup is NOW COMPLETE!!
; =================================================================

; =================================================================
; = USB Initialization
; = Configure Y register to point to USB_BASE (UHWCON register)
; =================================================================

      ldi         YL, lo8(USB_BASE)             ; Load YL with the least significant 8 bits of USB_BASE (usb_init)
                                                ; still YH=0
      ; ldi         YH, hi8(USB_BASE)           ; Load YH with the most significant 8 bits of USB_BASE

      ; =================================================================
      ; = From LUFA simplified - USB_Init:_start
      ; =================================================================

      ; Reset USB Interface
      ; The reset value of the USB Controller Register (USBCON) is USBE = 0, FRZCLK = 1, OTGPADE = 0, VBUSTE = 0

      ; The following is a workaround for AVR8 bootloaders that fail to turn off the OTG pad before
      ; running the loaded application. This causes VBUS detection to fail unless we first force it
      ; off to reset it.

      ; Force disable VBUS Pad (OTGPADE), also disable all USB-related Interrupts (VBUSTE) and reset the USB controller (USBE)
      ; USBCON &= ~(1 << OTGPADE);
      ; USBCON &= ~(1 << VBUSTE);
      ; USBCON &= ~(1 << USBE);

      ; SIZE OPTIMIZATION: Instead of resetting just some specific bits, initialize the whole USBCON
      ; register with its reset value (although even this could be omitted, this initialization is left
      ; here in case the application tries to enter the bootloader in a slightly incorrect way).
      ; As a further optimization, the USBCON register value is left in r16 for use in subsequent code
      ; which modifies various bits of that register.
      ldi         r16, _BV(FRZCLK)              ; Load r16 with the reset value for the USB Configuration Register (USBCON)
      std         Y+oUSBCON, r16                ; Store r16 to the USB Configuration Register (USBCON)

      ; Enable USB Regulator (USB_REG_On)
      ; UHWCON |=  (1 << UVREGE);
                                                ; Set a logic one to the USB pad regulator bit (UVREGE)
      std         Y+oUHWCON, rONE               ; Store USB Hardware Configuration Register (UHWCON) with the value needed to enable the USB pad regulator

      ; SIZE OPTIMIZATION: Not needed due to known reset value (Zero)
      ; ; Disable all USB Device-related Interrupts
      ; ; UDIEN = 0;
      ; std         Y+oUDIEN, rZERO               ; Load the USB Device Interrupt Enable Register (UDIEN) with zero (disable all USB Device-related interrupts)

      ; SIZE OPTIMIZATION: Not needed due to known reset value (Zero)
      ; ; Clear all USB-related Interrupts
      ; ; USBINT = 0;
      ; ; UDINT  = 0;
      ; std         Y+oUSBINT, rZERO              ; Load the USB General Interrupt Flag Register (USBINT) with zero (clear the IVBUS Transition Interrupt Flag (VBUSTI))
      ; std         Y+oUDINT, rZERO               ; Load the USB Device Interrupt Flag Register (UDINT) with zero (clear all USB Device-related interrupts)

      ; Enable the USB Controller
      ; USBCON |=  (1 << USBE);
      ori         r16, _BV(USBE)                ; The right value of USBCON is already in r16, just set the USB macro Enable Bit (USBE)
      std         Y+oUSBCON, r16                ; Store r16 to the USB Configuration Register (USBCON)

      ; Set PLL Output Frequency to 48MHz
      ; PLLFRQ = (1 << PDIV2);
      ldi         r17, _BV(PDIV2)               ; Load r17 with the value needed to set the PLL Lock Frequency to 48MHz (only PDIV2 bit set to 1)
                                                ; The PLL Input Multiplexer (PMUX) bit is set to 0 because the PLL input is connected to the PLL Prescaler, which has the Primary System Clock as source
                                                ; The PLL Postcaler for USB Peripheral (PLLUSB) is set to 0 because we don't need further division (PDIV2 set to 1 -> PLL Output = 48MHz)
      out         _SFR_IO_ADDR(PLLFRQ), r17     ; Store r17 to the PLL Frequency Control Register (PLLFRQ)

      ; Unfreeze USB Clk
      ; USBCON &= ~(1 << FRZCLK);
      andi        r16, ~(_BV(FRZCLK))           ; The right value of USBCON is already in r16, just clear the Freeze Clock bit (FRZCLK)
      std         Y+oUSBCON, r16                ; Store r16 to the USB Configuration Register (USBCON)

      ; Enable USB PLL (USB_PLL_On)
      ; PLLCSR = (1 << PINDIV);
      ; PLLCSR = ((1 << PINDIV) | (1 << PLLE));
      ldi         r17, _BV(PINDIV)              ; Load r17 with the value needed to set the PLL input prescaler to generate the 8MHz input clock for the PLL
                                                ; When using a 16MHz clock source, PINDIV PLL Input Prescaler (PINDIV) bit must be set to 1 before enabling PLL
      out         _SFR_IO_ADDR(PLLCSR), r17     ; Store r17 to the PLL Control and Status Register (PLLCSR)

      ldi         r17, (_BV(PINDIV) | _BV(PLLE)); Load r17 with the value needed to enable the PLL, set PLL Enable bit (PLLE), we are also setting PINDIV to keep the PLL input prescaler configuration
      out         _SFR_IO_ADDR(PLLCSR), r17     ; Store r17 to the PLL Control and Status Register (PLLCSR)

      ; Wait for PLL Lock Detector to assert
      ; while (!(USB_PLL_IsReady()));
wait_pll_lock:
      in          r17, _SFR_IO_ADDR(PLLCSR)     ; Load r17 with the value of the PLL Control and Status Register (PLLCSR)
      sbrs        r17, PLOCK                    ; Skip the next instruction if the PLL Lock Detector bit (PLOCK) is set (PLL is locked to the reference clock)
      rjmp        wait_pll_lock                 ; Loop while PLOCK is not set

      ; Enable ONLY "End Of Reset Interrupt"
      ; UDIEN  |= (1 << EORSTE);
      ; NOTE: We are not ORing the value of UDIEN, because we really just want EORSTE enabled
      ldi         r17, _BV(EORSTE)              ; Load r17 with the value needed to enable the USB-related interrupts we care about, EORSTE
      std         Y+oUDIEN, r17                 ; Store r17 to the USB Interrupt Enable Register (UDIEN)

      ; Attach device to USB Bus and select USB Full speed mode (also clears USB reset CPU bit <RSTCPU> and remote wake-up bit <RMWKUP>)
      ; IMPORTANT!! The reset value of UDCON is not 0x00, it's 0x01 (DETACH bit = 1), so we MUST write ZERO to it here!!
      ; UDCON  = 0;
      std         Y+oUDCON, rZERO               ; Store rZERO to the USB Device Configuration Register (UDCON); clear Detach Bit (DETACH);
                                                ; This reconnects the device, and sets FULL SPEED Mode, LSM bit set to 0 (D+ internal pull-up)

      ; Enable VBUS Pad (USB_OTGPAD_On), while keeping USB macro Enable bit set
      ; USBCON |=  (1 << OTGPADE);
      ldi         r16, (_BV(USBE)|_BV(OTGPADE)) ; Load r16 with the value needed to enable the USB controller, enable clock;
                                                ; USB macro Enable Bit (USBE) is set to 1 (enable the USB controller)
                                                ; Freeze Clock bit (FRZCLK) set to 0 (enable the clock inputs)
                                                ; VBUS Pad Enable bit (OTGPADE) set to 1 (enable the VBUS pad)
                                                ; VBUS Transition Interrupt Enable Bit (VBUSTE) set to 0 (disable the VBUS Transition interrupt generation)
      std         Y+oUSBCON, r16                ; Store r16 to the USB Configuration Register (USBCON)

      ; =================================================================
      ; = From LUFA simplified - USB_Init:_end
      ; =================================================================

; =================================================================
; = USB Initialization is NOW COMPLETE!!
; =================================================================

      sei                                       ; Set Global Interrupt Flag (Enable system interrupts)

; =================================================================
; = USB is running, interrupts enabled!!
; =================================================================

; =================================================================
; = Main Bootloader Loop
; =================================================================

main_loop:
      brts        main_loop                     ; Loop while the T (BootLoaderActive) flag in SREG is set

exit_bootloader:
      ; Detach device from USB Bus
      ; UDCON  |= (1 << DETACH);
      ; SIZE OPTIMIZATION: All other UDCON bits except DETACH can be set to 0 at this time, and the value
      ; of _BV(DETACH) is 0x01, therefore we can just store rONE into UDCON.
      ; In theory this step could even be removed completely, because the watchdog reset should set the
      ; DETACH bit anyway, but doing this here ensures that the host detects the USB device detach before
      ; the application is started, which could avoid issues if the application does not add some delay
      ; before enabling USB.
      std         Y+oUDCON, rONE                ; Store _BV(DETACH) (== 0x01) to the USB Device Configuration Register (UDCON)

; =================================================================
; = Watchdog Timer initialization
; =================================================================

      ; NOTE!! This part of the code assumes MCUSR has already been cleared

      ; Enable WDT, ~250 ms timeout (force a timeout to reset the AVR)
      ldi         r17, _BV(WDE) | _BV(WDP2)     ; Load r17 with the value needed to set the desired Watchdog Configuration (WDCE = 0, not set!)
                                                ; Write the WDE and Watchdog prescaler bits (WDP); System Reset Mode (WDE = 1) and ~250 ms timeout (WDP2 = 1)

      rcall       set_watchdog_timer            ; Call the subroutine that sets the watchdog timer with the value loaded in r17

   ; for (;;);
final_loop:
   rjmp           final_loop                    ; keep looping here until the Watchdog timer kicks in,
                                                ; this will reset the MCU the new app should run


; =================================================================
; = USB General ISR
; =================================================================

; This just watches for EORSTI (End of Reset Interrupt) and enables
; Endpoint 0.

      .global     USB_General_ISR
USB_General_ISR:

; WARNING: REGISTERS/CONTEXT NOT SAVED!

; service_EORSTI:                              ; unused label

; =================================================================
; = Configure Endpoints
; =================================================================

      ; Even though the bootloader uses only endpoint 0, the HID spec requires any HID device to have an
      ; Interrupt IN endpoint, and the host can decide to poll that endpoint even when the HID report
      ; descriptor does not actually declare any input reports.  Polling an unconfigured endpoint causes
      ; USB errors, therefore endpoint 1 must be configured here too.

      ; Enable and configure endpoint 1 as Interrupt IN:
      ; UENUM = 1;
      ; UECONX |= (1 << EPEN);
      ; UECFG0X = (1 << EPTYPE1) | (1 << EPTYPE0) | (1 << EPDIR);
      ; UECFG1X = (1 << EPSIZE1) | (1 << EPSIZE0) | (1 << ALLOC);

      std         Y+oUENUM, rONE                ; Select Endpoint 1

                                                ; Set Endpoint Enable Bit (EPEN), all other bits set to zero has no effect on UECONX
      std         Y+oUECONX, rONE               ; Store the USB Endpoint Configuration Register (UECONX) with the value needed to enable Endpoint 1

      ldi         r16, (_BV(EPTYPE1) | _BV(EPTYPE0) | _BV(EPDIR)) ; Load r16 with the value to configure Endpoint 1
                                                                  ; Endpoint Type Bits (EPTYPE1:0); 11 to set as Interrupt Endpoint
                                                                  ; Endpoint Direction Bit (EPDIR); set to configure IN direction

      std         Y+oUECFG0X, r16               ; Store r16 to the USB Endpoint Configuration0 Register (UECFG0X);

      ldi         r16, (_BV(EPSIZE1) | _BV(EPSIZE0) | _BV(ALLOC)) ; Load r16 with the value to configure Endpoint 1 (and also 0 below)
                                                                  ; Endpoint Size Bits (EPSIZE2:0); 011 to set to 64 bytes
                                                                  ; Endpoint Bank Bits (EPBK1:0); 00 to set One bank
                                                                  ; Endpoint Allocation Bit (ALLOC); set to allocate the endpoint memory

      std         Y+oUECFG1X, r16               ; Store r16 to the USB Endpoint Configuration1 Register (UECFG1X);

      ; Enable and configure endpoint 0 as Control (this is done last, so that endpoint 0 will remain selected):
      ; UENUM = 0;
      ; UECONX |= (1 << EPEN);
      ; UECFG0X = 0;
      ; UECFG1X = (1 << EPSIZE1) | (1 << EPSIZE0) | (1 << ALLOC);

      std         Y+oUENUM, rZERO               ; Select Endpoint0

                                                ; Set Endpoint Enable Bit (EPEN), all other bits set to zero has no effect on UECONX
      std         Y+oUECONX, rONE               ; Store the USB Endpoint Configuration Register (UECONX) with the value needed to enable Endpoint 0

      ; SIZE OPTIMIZATION: Not needed due to known reset value (Zero)
      ; std         Y+oUECFG0X, rZERO             ; Store rZERO to the USB Endpoint Configuration0 Register (UECFG0X);
                                                ; Endpoint Type Bits (EPTYPE1:0): 00 to set as Control Endpoint
                                                ; Endpoint Direction Bit (EPDIR): clear to configure OUT direction; needed for Control Endpoint

      ; SIZE OPTIMIZATION: r16 is already loaded with the required value while configuring endpoint 1 above

      std         Y+oUECFG1X, r16               ; Store r16 to the USB Endpoint Configuration1 Register (UECFG1X);

      ; Enable "Received SETUP Interrupt"
      ; UEIENX |= (1 << RXSTPE);
      ldi         r16, _BV(RXSTPE)              ; Load r16 with the value to needed to enable an endpoint interrupt (EPINTx) when RXSTPI is sent.
                                                ; Received SETUP Interrupt Enable Bit (RXSTPE) set to 1
      std         Y+oUEIENX, r16                ; Store r16 to the USB Endpoint Interrupt Enable Register (UEIENX);

not_EORSTI:
      reti                                      ; Return from interrupt


; =================================================================
; = USB Endpoint Interrupt
; =================================================================

; ASSUMPTION!!!
; Since only EP0 is ever enabled, this should be for that endpoint.
; If some other EP interrupts, we don't handle it.
; Also, since we only enable RXSTPE, this must be to handle RXSTPI

        .global     USB_Endpoint_ISR
USB_Endpoint_ISR:

; =================================================================
; = Process USB Control Request
; =================================================================

      ; Get the 8-byte setup packet

      ; The following code is a slightly shorter version of:
      ; ldd         reg_bmRequestType, Y+oUEDATX  ; bmRequestType
      ; ldd         reg_bRequest,      Y+oUEDATX  ; bRequest
      ; ldd         reg_wValueL,       Y+oUEDATX  ; wValueL
      ; ldd         reg_wValueH,       Y+oUEDATX  ; wValueH
      ; ldd         reg_wIndexL,       Y+oUEDATX  ; wIndexL
      ; ldd         reg_wIndexH,       Y+oUEDATX  ; wIndexH
      ; ldd         reg_wLengthL,      Y+oUEDATX  ; wLengthL
      ; ldd         reg_wLengthH,      Y+oUEDATX  ; wLengthH

      ; Shorter version
      clr         XH                            ; Clear XH Register
      ldi         XL, 18                        ; Load XL Register with number 18 (this will be used to refer to r18)
load: ldd         r0, Y+oUEDATX                 ; Load r0 with the value in the USB Endpoint Data Register (UEDATX)
      st          X+, r0                        ; Store the value of r0 to the location pointed by X (r18), post increment X (X now points to r19)
      cpi         XL, 18+8                      ; Compare XL with the location past the last byte that we need to read
      brne        load                          ; Jump back to 'load' if there are still bytes to read

      ; Our response is based on data direction...
      sbrc        reg_bmRequestType, 7          ; Skip the next instruction if bit 7 of bmRequestType is not set; for host to device (OUT) transaction, bit 7 is cleared
      rjmp        DEVICE_TO_HOST                ; If bit 7 of bmRequestType is set, this is a device to host (IN) transaction, jump to DEVICE_TO_HOST

; OUT transactions
HOST_TO_DEVICE:

      ; For OUT transactions, here we ONLY handle standard requests targeted for the device
      cpi         reg_bmRequestType, 0x00       ; Compare r18 (bmRequestType) with value 0x00 (OUT Type Resquest, USB Standard Request, Recipient is the device)
      breq        HANDLE_USB_STANDARD_DEVICE    ; If bmRequestType is 0x00, we know it's either a SET_ADDRESS or SET_CONFIGURATION request, so jump to HANDLE_USB_STANDARD_DEVICE

      cpi         reg_bmRequestType, ((1 << 5) | (1 << 0))  ; Compare bmRequestType with the value that defines the request type and recipient we care about HID_SET_REPORT (REQTYPE_CLASS | REQREC_INTERFACE)
      brne        UNHANDLED_SETUP_REQUEST       ; jump to UNHANDLED_SETUP_REQUEST if not equal
                                                ; fallthrough to HANDLE_USB_CLASS_INTERFACE if equal
HANDLE_USB_CLASS_INTERFACE:
      cpi         reg_bRequest, 0x09            ; Compare bRequest with value 0x05 (HID_REQ_SetReport)
      brne        UNHANDLED_SETUP_REQUEST       ; If reg_bmRequestType is not 0x00 or bRequest is not 0x05 or 0x09, we don't handle those cases, so jump to UNHANDLED_SETUP_REQUEST
      ; fallthrough to SET_HID_REPORT

SET_HID_REPORT:

      ; Acknowledge the SETUP packet and wait for command from the host
      ldi         r17, ~(_BV(RXSTPI))           ; Clear the Received SETUP Interrupt Flag (RXSTPI) in r17
      rcall       clear_bit_and_wait_RXOUTI     ; This function loads r17 with value of UEINTX

load_page_address:
      ldd         r30, Y+oUEDATX                ; Load r30 with LSB of page address
      ldd         r31, Y+oUEDATX                ; Load r31 with MSB of page address

check_page_address:
      ; Protect against overwriting the bootloader - allow flash write only if the specified address is
      ; less than the bootloader start address.  Only the high byte needs to be tested, because the
      ; bootloader start is guaranteed to be on a 256 bytes boundary.
      cpi         r31, hi8(reset_vector)        ; Compare high byte of page address against the high byte of the bootloader start addresss
      brcs        erase_page                    ; If the address is below the bootloader start, allow the flash write operation

      ; The address is definitely not correct for a flash write operation; however, simply jumping to
      ; finish_hid_request would not just fail this SET_HID_REPORT request - apparently not reading the
      ; OUT data properly results in the bootloader not responding to any subsequent USB requests too.
      ; Instead of doing that, we run the normal flash write loop even if the address was bad, but set
      ; the "disable flash write" bit, so that the actual flash write instructions will be skipped.
      ; Bit 7 of reg_bRequest is used for that purpose - is is known to be 0 in the normal case.
      sbr         reg_bRequest, _BV(7)          ; Set the "disable flash write" bit

      ; If the address is out of the allowed range for flash write, it may be the special value for the
      ; START_APPLICATION command (0xffff); check for that value in the shortest way possible.
      adiw        r30, 1                        ; Increment the address to turn 0xffff into 0x0000
      brne        erase_page                    ; If the address was out of range and not 0xffff, jump to the regular flash write code
                                                ; (which would just consume the OUT data to make USB work properly).
      clt                                       ; Otherwise (the address was 0xffff) clear the BootLoaderActive flag (T flag in SREG),
                                                ; then fallthrough to the regular flash write code too.

erase_page:

      ldi         r17, (_BV(PGERS)|_BV(SPMEN))  ; load r17 with the value needed to erase the currently specified page
      rcall       do_SPM                        ; execute page erase (this function requires r17 to be loaded first with the right value for SPMCSR)

clear_current_page_byte_address:
      ldi         r16, (SPM_PAGESIZE/2)         ; load r16 with the number of words per page (128 bytes/2 = 64 words)
                                                ; r16 will be decremented for every word (2 bytes) we write to the page buffer

check_endpoint_for_more_data:

      ; if (!(((uint16_t)UEBCHX << 8) | UEBCLX))
      ; we just check for UEBCLX, we know we can't accept more than 130 bytes at a time (hid_report_descriptor)
      ; ldd         r27, Y+oUEBCHX                ; load r27 with the value of USB Endpoint Byte Count High Register (UEBCHX)
      ldd         r26, Y+oUEBCLX                ; load r26 with the value of USB Endpoint Byte Count Low Register (UEBCLX)
      ; or          r27, r27
      or          r26, r26
      brne        fill_page_buffer              ; if r26 is not zero, it means there's data in the endpoint which we can use to fill the page buffer, jump there

      ; Acknowledge the OUT packet and wait for more data from the host
      ldi         r17, ~(_BV(RXOUTI))           ; Clear the Received OUT Data Interrupt Flag (RXOUTI) in r17
      rcall       clear_bit_and_wait_RXOUTI     ; This function loads r17 with value of UEINTX

fill_page_buffer:                               ; There's data at the endpoint buffer, start fill_page_buffer sequence

load_word_data:
      ldd         r0, Y+oUEDATX                 ; Load r0 with LSB of data word
      ldd         r1, Y+oUEDATX                 ; Load r1 with MSB of data word

write_page_buffer:
      ldi         r17, _BV(SPMEN)               ; load r17 with the value needed to write the current word to the page buffer
      rcall       do_SPM                        ; execute page buffer write (this function requires r17 to be loaded first with the right value for SPMCSR)

increment_byte_address:
      subi        r30, -2                       ; Increment the current address by 2.
                                                ; Only the low byte needs to be incremented, because the block start address must be page aligned,
                                                ; therefore any carry to the high byte may happen only past the end of the block.

      dec         r16                           ; decrement r16 (number of words per page)
      brne        check_endpoint_for_more_data  ; loop while r16 is not equal to SPM_PAGESIZE (128)

      ; Restore the page address in Z-Register
      subi        r30, SPM_PAGESIZE             ; Move the address back to the start of page (again only the low byte needs to be changed).

write_page_to_flash:
      ldi         r17, (_BV(PGWRT)|_BV(SPMEN))  ; load r17 with the value needed to commit the current page buffer to the flash
      rcall       do_SPM                        ; execute page write to flash (this function requires r17 to be loaded first with the right value for SPMCSR)

reenable_rww_section:
      ldi         r17, (_BV(RWWSRE)|_BV(SPMEN)) ; load r17 with the value needed to reebable the rww section
      rcall       do_SPM                        ; execute re-enable rww section (this function requires r17 to be loaded first with the right value for SPMCSR)

finish_hid_request:

      ; Acknowledge the OUT packet and wait for TXINI (OK to transmit)
      ldi         r17, ~(_BV(RXOUTI))           ; Clear the Received OUT Data Interrupt Flag (RXOUTI) in r17
      rcall       clear_bit_and_wait_TXINI      ; This function loads r17 with value of UEINTX

      ; Clear Transmitter Ready Flag
      ldi         r17, ~(_BV(TXINI))            ; Clear the Transmitter Ready Interrupt Flag (TXINI) in r17
      rjmp        clear_UEINTX_bit_and_reti     ; Store r17 to the USB Endpoint Interrupt Register (UEINTX), then return from interrupt

HANDLE_USB_STANDARD_DEVICE:

      ; Once we know we support the OUT transaction, we need to filter it based on the value in bRequest
      cpi         reg_bRequest, 0x05            ; Compare bRequest with value 0x05 (REQ_SetAddress)
      breq        SET_ADDRESS                   ; jump to SET_ADDRESS
      cpi         reg_bRequest, 0x09            ; Compare bRequest with value 0x09 (REQ_SetConfiguration)
      breq        SET_CONFIGURATION             ; jump to SET_CONFIGURATION  if equal
                                                ; fallthrough to UNHANDLED_SETUP_REQUEST if not equal
UNHANDLED_SETUP_REQUEST:

      ; if (Endpoint_IsSETUPReceived())
      ; (UEINTX & (1 << RXSTPI))
      ldd         r16, Y+oUEINTX                 ; Load r16 with the value in the USB Endpoint Interrupt Register (UEINTX);
      sbrs        r16, RXSTPI                    ; Skip the next instruction if the Received SETUP Interrupt Flag (RXSTPI) is set; received SETUP packet?
      reti                                       ; Return if RXSTPI is not set, SETUP packet already handled

      ; If we reach this part, the SETUP packet has not been handled, so we need to acknowledge it and request a stall

      ; Acknowledge the SETUP packet
      ldi         r17, ~(_BV(RXSTPI))           ; Clear the Received SETUP Interrupt Flag (RXSTPI) in r17
      std         Y+oUEINTX, r17                ; Store r17 to the USB Endpoint Interrupt Register (UEINTX)

      ; STALL transaction

      ; // Endpoint_StallTransaction();
      ; UECONX |= (1 << STALLRQ);
      ldd         r16, Y+oUECONX                ; Load r16 with the value in the USB Endpoint Configuration Register (UECONX)
      ori         r16, _BV(STALLRQ)             ; Set the STALL Request Handshake Bit (STALLRQ) in r16
      std         Y+oUECONX, r16                ; Store r16 to the USB Endpoint Configuration Register (UECONX)


EP_ISR_END:

      reti                                      ; Return from interrupt

SET_CONFIGURATION:
#if defined(LED_ENABLED)
      ; Turn LED on towards the end of enumeration (SET_CONFIGURATION is done after SET_ADDRESS)
      ; TODO: If we ever have space, we could add a flag here to mark the fact that we have entered
      ; this state, and turn the LED on at the end of the setup request. For now this is the best we
      ; can do.
      TURN_LED_ON
#endif

      ; Optimization by "sigprof" that saves 2 bytes
      ; Dirty trick: We don't need to do anything for SET_CONFIGURATION except process_Host2Device,
      ; so we reuse the SET_ADDRESS code by making it reload the same value to UDADDR.

      ldd         reg_wValueL, Y+oUDADDR        ; load the existing UDADDR value where the SET_ADDRESS code would expect the new address

SET_ADDRESS:

      ; Set device address; for this we only need to copy the value in wValueL which contains the address
      ; for the device set by the host to the USB Device Address Register (UDADDR); since the SET_ADDRESS
      ; request is only executed once during enumeration, and because allowed address values are 1 through
      ; 127 (7 LSBs), we don't need to care about the ADDEN bit (bit 7). We can also simply set the ADDEN
      ; bit and store the value again in UDADDR to enable the USB Device Address.

      std         Y+oUDADDR, reg_wValueL        ; Store wValueL to the USB Device Address Register (UDADDR)

      rcall       process_Host2Device           ; This function affects r17

      ; EnableDeviceAddress
      ; UDADDR |= (1 << ADDEN)
      ori         reg_wValueL, _BV(ADDEN)       ; In order to save space, we simply OR the address value already in reg_wValueL (r20) with the ADDEN bit to enable the USB Address
      std         Y+oUDADDR, reg_wValueL        ; Store reg_wValueL to the USB Device Address Register (UDADDR)
      rjmp        UNHANDLED_SETUP_REQUEST       ; Go to UNHANDLED_SETUP_REQUEST

; IN transactions
DEVICE_TO_HOST:

      ; If we get here, we know bit 7 of bmRequestType is set, meaning it is a DEVICE_TO_HOST (IN) request,
      ; now we need to filter out any unhandled requests

      ; SIZE OPTIMIZATION: The only bmRequestType values that we care about are:
      ;  - 0x80 - IN Type Request, USB Standard Request, Recipient is the device
      ;  - 0x81 - IN Type Request, USB Standard Request, Recipient is the interface
      ; At this step it is known that bmRequestType >= 0x80, therefore checking for bmRequestType < 0x82
      ; is enough to detect whether bmRequestType has one of the above values.

      cpi         reg_bmRequestType, 0x82       ; Check whether bmRequestType is less than 0x82 (then it must be either 0x80 or 0x81)
      brcc        UNHANDLED_SETUP_REQUEST       ; If bmRequestType >= 0x82, this request type is not handled here (it's not a GET_DESCRIPTOR request)

      cpi         reg_bRequest, 0x06            ; Compare bRequest with value 0x06 (REQ_GetDescriptor)
      brne        UNHANDLED_SETUP_REQUEST       ; jump to UNHANDLED_SETUP_REQUEST if not equal
                                                ; fallthrough to GET_DESCRIPTOR if equal
GET_DESCRIPTOR:

      ; Just get the descriptor address into
      ; [RAMPZ:]Z, and the length into r16

      subi        reg_wValueL, 2                ; Shift the string descriptor index into the 0xFE...0xFF range
      cpi         reg_wValueH, 0x03             ; Check whether the request is for a string descriptor (0x03)
      breq        find_descriptor               ; If a string descriptor is requested, the search key is now prepared in reg_wValueL
      mov         reg_wValueL, reg_wValueH      ; If any other descriptor is requested, use its code as the search key
find_descriptor:
      ldi         ZH, hi8(descriptor_table)     ; Load the high address part of descriptor_table into ZH (this part is assumed to be common for all descriptor data)
      ldi         ZL, lo8(descriptor_table)     ; Load the low address part of descriptor_table into ZL
find_descriptor_loop:
      lpm         r0, Z+                        ; Load the search key from the descriptor table
      lpm         r1, Z+                        ; Load the low part of the descriptor address from the descriptor table
      cp          r0, reg_wValueL               ; Compare the search key for the current table item with the requested search key
      brlo        find_descriptor_loop          ; If the requested key is less than the key for the current item in the table, continue the search
      brne        UNHANDLED_SETUP_REQUEST       ; Otherwise, if the keys are not equal, the table does not have a matching entry, so reject the request with STALL
      mov         ZL, r1                        ; Load the low part of the descriptor address into ZL (ZH is assumed to be the same)
      lpm         r16, Z                        ; Load the descriptor length from the first byte of the descriptor
      sbrc        r16, 7                        ; Skip the next instruction if bit 7 of the length is not set (the length is actually a part of the descriptor)
      inc         ZL                            ; Otherwise the length is actually a prefix, and the descriptor data starts from the next byte, so adjust the address
      cbr         r16, 0x80                     ; Clear bit 7 of the length which may have been used as a prefix flag

process_descriptor:

      ; Acknowledge the SETUP packet
      ldi         r17, ~(_BV(RXSTPI))           ; Clear the Received SETUP Interrupt Flag (RXSTPI) in r17
      std         Y+oUEINTX, r17                ; Store r17 to the USB Endpoint Interrupt Register (UEINTX)

verifyMaxDescriptorLength:
      cp          reg_wLengthL, r16             ; Compare the value in r24 (wLengthL) against the value in r16 (length of descriptor to send)
      brlo        send_descriptor               ; If the value in reg_wLengthL is smaller, use it to send the descriptor, jump to that tag
      mov         reg_wLengthL, r16             ; Otherwise, copy the value in r16 (which is the smaller of the two) to reg_wLengthL, and use that to send the descriptor

send_descriptor:

      ; Abort if RXSTPI is set
      ldd         r17, Y+oUEINTX                ; Load r17 with the value in the USB Endpoint Interrupt Register (UEINTX);
      sbrc        r17, RXSTPI                   ; Skip the next instruction if the Received SETUP Interrupt Flag (RXSTPI) is cleared
      reti                                      ; Return if RXSTPI is set, we need to prioritize SETUP packets

      ; NOTE: R17 already has the most current value of UEINTX, no need to load it again
      sbrs        r17, RXOUTI                   ; Skip the next instruction if the Received OUT Data Interrupt Flag (RXOUTI) is set (there's an OUT packet from the host)
      sbrs        r17, TXINI                    ; Skip the next instruction if the Transmitter Ready Interrupt Flag (TXINI) is set (endpoint is ready to send data)
      rjmp        wait_finish_transfer          ; jump to finish_transfer

      ; ASSUMPTION!! reg_wLengthL already has the maximum valid length we can use to send the descriptor,
      ; so we can just keep decrementing it until it reaches Zero
transfer_descriptor:
      lpm         r16, Z+                       ; Load r16 with the value pointed by the Z-Register (descriptor to send), post-increment Z-Register
      std         y+oUEDATX, r16                ; Store the value in r16 to the USB Endpoint Data Register (UEDATX)
      dec         reg_wLengthL                  ; Decrement the value in reg_wLengthL
      brne        transfer_descriptor           ; While reg_wLengthL is not Zero, loop back to transfer_descriptor

      ; The data to be sent has been written to the UEDATX register
      ; We must now signal the packet to send is complete

send_packet_done:

      ; Clear Transmitter Ready Flag
      ldi         r17, ~(_BV(TXINI))            ; Clear the Transmitter Ready Interrupt Flag (TXINI) in r17
      std         Y+oUEINTX, r17                ; Store r17 to the USB Endpoint Interrupt Register (UEINTX)

      ; Wait for the host to send an OUT packet (RXOUTI to assert), but abort if a SETUP packet is received
wait_finish_transfer:
      ldd         r17, Y+oUEINTX                ; Load r17 with the most current value in the USB Endpoint Interrupt Register (UEINTX);
      sbrc        r17, RXSTPI                   ; Skip the next instruction if the Received SETUP Interrupt Flag (RXSTPI) is cleared
      reti                                      ; Return if RXSTPI is set, we need to prioritize SETUP packets
      sbrs        r17, RXOUTI                   ; Skip the next instruction if the Received OUT Data Interrupt Flag (RXOUTI) is set (there's already an OUT packet from the host)
      rjmp        wait_finish_transfer          ; Loop back to finish_transfer if none of RXSTPI or RXOUTI flags are set

      ; Acknowledge the OUT packet
      ldi         r17, ~(_BV(RXOUTI))           ; Clear the Received OUT Data Interrupt Flag (RXOUTI) in r17

clear_UEINTX_bit_and_reti:
      std         Y+oUEINTX, r17                ; Store r17 to the USB Endpoint Interrupt Register (UEINTX)
      rjmp        UNHANDLED_SETUP_REQUEST



; =================================================================
; = Helper Functions
; =================================================================

set_watchdog_timer:

      ; IMPORTANT!! This function assumes the correct value for the WDTCSR register
      ; configuration is already loaded onto r17; it also modifies r16.

      ; always set YH to hi(EIO_BASE) before calling
      ldi         YL, lo8(EIO_BASE)             ; Load YL with EIO_BASE (wdt_init)

      wdr                                       ; Reset the Watchdog Timer

      ldi         r16, _BV(WDCE) | _BV(WDE)     ; Load r16 with the value needed to "unlock" the Watchdog Timer Configuration
                                                ; Write a logic one to the Watchdog Change Enable bit (WDCE) and Watchdog System Reset Enable (WDE)
      std         Y+oWDTCSR, r16                ; Store r16 to the Watchdog Timer Control Register (WDTCSR)

      ; Load the desired configuration to the Watchdog Timer Control Register (WDTCSR)
      std         Y+oWDTCSR, r17                ; Store r17 to the Watchdog Timer Control Register (WDTCSR)

      ret


process_Host2Device:

      ; IMPORTANT!! This function is common for all HOST_TO_DEVICE transactions, if you make any
      ; changes here, make sure all requests that depend on this code don't need to be modified.

      ; NOTE: All the functions here affect r17

      ; Acknowledge the SETUP packet and wait for TXINI (OK to transmit)
      ldi         r17, ~(_BV(RXSTPI))           ; Clear the Received SETUP Interrupt Flag (RXSTPI) in r17
      rcall       clear_bit_and_wait_TXINI      ; This function loads r17 with value of UEINTX

      ; Clear Transmitter Ready Flag and wait for TXINI (OK to transmit)
      ldi         r17, ~(_BV(TXINI))            ; Clear the Transmitter Ready Interrupt Flag (TXINI) in r17
clear_bit_and_wait_TXINI:
      std         Y+oUEINTX, r17                ; Store r17 to the USB Endpoint Interrupt Register (UEINTX)
wait_TXINI:

      ; NOTE: This function uses r17, we can use this fact to code other stuff
      ; that happens before and after this functions is called

      ; Wait for TXINI (OK to transmit)
      ldd         r17, Y+oUEINTX                ; Load r17 with the value in the USB Endpoint Interrupt Register (UEINTX)
      sbrs        r17, TXINI                    ; Check the value of bit TXINI in r17, skip the next instruction if set
      rjmp        wait_TXINI                    ; Bit TXINI is not set, keep waiting

      ret                                       ; Return from call


clear_bit_and_wait_RXOUTI:
      std         Y+oUEINTX, r17                ; Store r17 to the USB Endpoint Interrupt Register (UEINTX)
wait_RXOUTI:

      ; NOTE: This function uses r17, we can use this fact to code other stuff
      ; that happens before and after this functions is called

      ; Wait for RXOUTI (OUT data received from the host)
      ldd         r17, Y+oUEINTX                ; Load r17 with the value in the USB Endpoint Interrupt Register (UEINTX);
      sbrs        r17, RXOUTI                   ; Skip the next instruction if the Received OUT Data Interrupt Flag (RXOUTI) is set
      rjmp        wait_RXOUTI                   ; Bit RXOUTI not set, keep waiting

      ret                                       ; Return from call


do_SPM:

      ; NOTE: This function assumes r17 already has the correct value for the SPMCSR register, depending on the
      ; desired SPM operation
      ; NOTE: If bit 7 of reg_bRequest is set to 1, the actual SPM instruction will not be executed
      ; (the wait loop will still run, but should just complete immediately).
      out         _SFR_IO_ADDR(SPMCSR), r17     ; store value in r17 to the Store Program Memory Control and Status Register (SPMCSR)
      sbrs        reg_bRequest, 7               ; Skip the actual flash operation if the "disable flash write" bit is set.
                                                ; This is apparently safe, because the SPM instruction must be executed within 4 cycles after setting SPMEN,
                                                ; and the sbrs instruction takes just 1 cycle when not skipping.
      spm                                       ; execute spm instruction based on the value loaded to SPMCSR

wait_SPM:
      in          r17, _SFR_IO_ADDR(SPMCSR)     ; load r17 with value of Store Program Memory Control and Status Register (SPMCSR)
      sbrc        r17, SPMEN                    ; check value of SPMEN bit
      rjmp        wait_SPM                      ; loop while SPMEN is set

      ret                                       ; Return from call


      .end
