# DOS-65-V3.03-ROM

This is a port/rewrite of Richard Leary's DOS/65 Version 3.02 ROM version for the C02 Pocket SBC.

This is my own version, hence the V3.03. Changes include:
 - CCM module now uses several CMOS instructions and addressing modes and is smaller
 - PEM module now uses several CMOS instructions and addressing modes and is smaller
 - SIM module includes calls directly to C02BIOS Version 3.04 (no hardware interface module required)

This version is a bit smaller than the previous version, now only 6.5KB of ROM space required.

It requires the RTC/CF-Card adapter along with a Compact Flash card of at least 64MB.
The Interface layer in SIM is configured for 8 drives at 8MB each.
 - note that only 7 drives (A: - G:) are configured in SIM for access from CCM/PEM.

Formatting the drive is simple... just fill the drive with hex "E5" and DOS/65 will figure out the rest.
WDC Tools are required to build all required software components!
 - TIDE is used to build C02BIOS and C02Monitor
  -  (see RTC/CF Card Adapter repository for BIOS and Monitor code)

 - TIDE is used to build DOS/65 utilities (XMODEM, SUB, UCOPY, SD, etc.)
 - A Batch file is used to build the DOS/65 ROM image

Default ROM starting locations are:
 - $C000 for DOS/65 image
 - $E000 for C02 Monitor
 - $F800 for C02 BIOS
 - I/O is located at $FE00 (only 160 bytes = 5- I/O selects @ 32 bytes each)

