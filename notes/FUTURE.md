# Future projects

Ideas that came up during development but are out of scope for current work.


## Potential projects

### Modernize locate database varint encoding

The fastfind locate database uses sfio's variable-length integer format:
unsigned varints use 7 data bits per byte with MSB continuation, while
signed varints put a sign flag in bit 6 of the terminal byte (6 data
bits there, 7 in continuation bytes). Negative values stored as -(v+1).

This is functionally equivalent to but byte-incompatible with protobuf's
zigzag encoding, which interleaves sign into the LSB before encoding as
unsigned. Zigzag is simpler (signed is just a wrapper around unsigned)
and is a widely-understood standard.

A format migration would require:
- New magic number for the updated database format
- Read support for both old and new formats (graceful upgrade)
- Write support for new format only
- Migration tooling or documented rebuild procedure

Low priority — the current encoding works and is self-contained in
`fastfind.c`'s `file_getu`/`file_putu`/`file_getl`/`file_putl` helpers.
The main benefit would be aligning with a well-known standard rather than
carrying a bespoke format.

Source: sfio varint defined in `src/lib/libast/sfio/_sfputl.c`,
`_sfputu.c`, `sfgetl.c`. Constants: `SFIO_UBITS=7`, `SFIO_SBITS=6`,
`SFIO_SIGN=0x40`, `SFIO_MORE=0x80` (from `sfio.h`).
