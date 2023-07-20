#!/usr/bin/perl
use strict;
use warnings;
use v5.30;

use X11::Protocol;

my $X = X11::Protocol->new();
$X->init_extension("XINERAMA") or die "XINERAMA not available";

use Data::Dumper;
say Dumper [ $X->XineramaIsActive(), $X->XineramaQueryScreens() ];
