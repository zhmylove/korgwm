#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Common;
use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw( $X $cfg $focus $unmap_prevent $windows %screens @screens );

our $X;
our $cfg;
our $focus;
our $unmap_prevent;
our $windows = {};
our %screens;
our @screens;

1;
