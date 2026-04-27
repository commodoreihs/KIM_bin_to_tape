# KIM_bin_to_tape
KIM-1 binary-to-tape transmitter for the PET (BASIC 4). This runs on a Commodore PET and virtually "plays" a program for the KIM-1 to load from audio cassette.

PET Requirements:
 - Must be running BASIC 4
 - Must have a user port connector
 - Doesn't seem to work on PETs with an internal speaker

The KIM-1 code is copied directly and exactly from the KIM-1 user manual. The only changes were to use a 6522 VIA instead of the 6530 RRIOT in the KIM-1.

The BASIC 4 PET disk load routine was mostly stolen from the book "Programming the PET/CBM" by Raeto Collin West.

I wrote the first version of this on May 11, 2022 and showed the concept in a YouTube video "The gory details: how saving to tape from a KIM-1 single board computer works"

That version only transmitted a small, hard-coded string. This updated version was written April 25, 2026, and allows you to transmit any random file.

Dave McMurtrie <dave@commodore.international> - April 27, 2026
