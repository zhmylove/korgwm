#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Panel::Clock;
use strict;
use warnings;
use feature 'signatures';

use AnyEvent;
use POSIX qw( strftime );
use X11::korgwm::Common;
use X11::korgwm::Panel;

# Add panel element
&X11::korgwm::Panel::add_element("clock", sub($el) {
    AE::timer 0, 1, sub { $el->txt(strftime($cfg->{clock_format}, localtime) =~ s/  +/ /gr) };
});

1;
