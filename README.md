# DOS-65-V3.02-ROM

This is a port of Richard Leary's DOS/65 Version 3.02 ROM version for the C02 Pocket SBC.
It requires the RTC/CF-Card adapter along with a Compact Flash card of at least 64MB.
The SIM and Interface layer are configure for 7 drives at 8MB each.
Formatting the drive is simple... just fill the drive with hex "E5" and DOS/65 will figure out the rest.
The ZIP file contains DOS/65 and the latest C02BIOS and C02Monitor.
WDC Tools are required to build the ROM image, which occupies the top 16KB.
