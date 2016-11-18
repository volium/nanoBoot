import os

#Initialize the environment
env = DefaultEnvironment(ENV = os.environ, tools = ['as', 'gcc', 'gnulink'])

env['CC'] ='avr-gcc'
env['AS'] ='avr-gcc'
env['OBJCOPY'] = 'avr-objcopy'
env['PROGSUFFIX'] ='.elf'

mcu = 'atmega32u4'
f_cpu = 16000000
cstandard = 'gnu99'

BOOT_START_OFFSET = 0x7E00

env['ASFLAGS']=[
    '-c',
    '-mmcu={}'.format(mcu),
    '-DF_CPU={}UL'.format(f_cpu),
    '-DBOOT_ADDRESS={0:#X}'.format(BOOT_START_OFFSET),
    '-I.',
    '-x',
    'assembler-with-cpp'
]

env['LINKFLAGS'] =[
    '-mmcu={}'.format(mcu),
    '-I.',
    '-Wl,--section-start=.text={0:#X}'.format(BOOT_START_OFFSET),
    '-nostartfiles'
]

target = 'nanoBoot'
sources = [Glob('*.S')]

elf=env.Program(target=target,source=sources)

# Custom clean action to remove lst files
Clean([elf], Glob('*.lst'))

# Generate binary files using OBJCOPY
hex=env.Command('nanoBoot.hex',elf,'$OBJCOPY -O ihex -R .eeprom -R .fuse -R .lock $SOURCE $TARGET')

# NOTE: The 'bin' file MUST be written at the correct BOOT_START_OFFSET; by default, tools will write
# the flash starting at offset 0x0000 when given a binary file.
# The 'ihex' format includes address information as part of the data stream, and thus work fine without
# further intervention. It's easier/safer to use this format when writing the bootloader.
bin=env.Command('nanoBoot.bin',elf,'$OBJCOPY -O binary -R .eeprom -R .fuse -R .lock $SOURCE $TARGET')

elfsize = env.Command('elfsize', elf, "avr-size --mcu={} --format=avr $SOURCE".format(mcu))
hexsize = env.Command('hexsize', hex, "avr-size --target=ihex $SOURCE")
binsize = env.Command('binsize', bin, "avr-size --target=binary $SOURCE")

# Add binaries and size information to list of default targets
Default(hex, bin, elfsize)

# Programmming commands (binary and hex versions)
env.Command('programbin',bin,'avrdude -p atmega32u4 -P usb -c avrispv2 -U flash:w:$SOURCE')
env.Command('programhex',hex,'avrdude -p atmega32u4 -P usb -c avrispv2 -U flash:w:$SOURCE')
