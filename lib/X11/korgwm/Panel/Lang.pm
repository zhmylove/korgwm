#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Panel::Lang;
use strict;
use warnings;
use feature 'signatures';
use open ':std', ':encoding(UTF-8)';
use utf8;
use Carp;
use X11::korgwm::Panel;

use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

our $cfg;
*cfg = *X11::korgwm::cfg;

# Export function to Panel class
sub X11::korgwm::Panel::lang_set($self, $lang = "") {
    $self->{lang}->txt(sprintf($cfg->{lang_format}, $lang));
}

# Add panel element
&X11::korgwm::Panel::add_element("lang");

1;
