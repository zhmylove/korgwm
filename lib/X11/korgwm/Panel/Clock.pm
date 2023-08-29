#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Panel::Clock;
use strict;
use warnings;
use feature 'signatures';
use open ':std', ':encoding(UTF-8)';
use utf8;
use Carp;
use AnyEvent;
use POSIX qw(strftime);
use X11::korgwm::Panel;

use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

our $cfg;
*cfg = *X11::korgwm::cfg;

# Add panel element
&X11::korgwm::Panel::add_element("clock", sub($el) {
    AE::timer 0, 1, sub { $el->txt(strftime($cfg->{clock_format}, localtime) =~ s/  +/ /gr) };
});

1;
