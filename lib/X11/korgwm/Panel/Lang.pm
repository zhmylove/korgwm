#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Panel::Lang;
use strict;
use warnings;
use feature 'signatures';

use X11::korgwm::Common;
use X11::korgwm::Panel;

# Export function to Panel class
sub X11::korgwm::Panel::lang_set($self, $lang = "") {
    $self->{lang}->set_text(sprintf($cfg->{lang_format}, $lang));
}

# Add panel element
&X11::korgwm::Panel::add_element("lang");

1;
