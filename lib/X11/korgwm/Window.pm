#!/usr/bin/perl
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Window;
use strict;
use warnings;
use feature 'signatures';
use open ':std', ':encoding(UTF-8)';
use utf8;
use Carp;
use X11::XCB ':all';

use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

our ($X, $cfg);
*X = *X11::korgwm::X;
*cfg = *X11::korgwm::cfg;

sub new($class, $id) {
    my $win = {
        id => $id,
    };
    bless $win, $class;
}

sub _get_property($wid, $prop_name, $prop_type='UTF8_STRING', $ret_length=8) {
    my $aname = $X->atom(name => $prop_name)->id;
    my $atype = $X->atom(name => $prop_type)->id;
    my $cookie = $X->get_property(0, $wid, $aname, $atype, 0, $ret_length);
    $X->get_property_reply($cookie->{sequence});
}

sub _resize_and_move($wid, $x, $y, $w, $h, $bw=$cfg->{border_width}) {
    my $mask = CONFIG_WINDOW_X | CONFIG_WINDOW_Y | CONFIG_WINDOW_WIDTH | CONFIG_WINDOW_HEIGHT |
        CONFIG_WINDOW_BORDER_WIDTH;
    $X->configure_window($wid, $mask, $x, $y, $w, $h, $bw);
}

sub _configure_notify($wid, $sequence, $x, $y, $w, $h, $above_sibling=0, $override_redirect=0,
        $bw=$cfg->{border_width}) {
    my $packed = pack('CCSLLLssSSSC', CONFIGURE_NOTIFY, 0, $sequence,
        $wid, # event
        $wid, # window
        $above_sibling, $x, $y, $w, $h, $bw, $override_redirect);
    $X->send_event(0, $wid, EVENT_MASK_STRUCTURE_NOTIFY, $packed);
}

# Generate accessors by object
INIT {
    no strict 'refs';
    for my $func (qw( get_property resize_and_move configure_notify )) {
        *{__PACKAGE__ . "::$func"} = sub {
            my $self = shift;
            croak "Undefined window" unless $self->{id};
            "_$func"->($self->{id}, @_);
        };
    }
}

sub focus($self) {
    croak "Undefined window" unless $self->{id};
    $X->change_window_attributes($self->{id}, CW_BORDER_PIXEL, $cfg->{color_focus});
    $X->configure_window($self->{id}, CONFIG_WINDOW_STACK_MODE, STACK_MODE_ABOVE);
    $X->set_input_focus(INPUT_FOCUS_POINTER_ROOT, $self->{id}, TIME_CURRENT_TIME);
    $X->flush();
}

sub reset_border($self) {
    croak "Undefined window" unless $self->{id};
    $X->change_window_attributes($self->{id}, CW_BORDER_PIXEL, $cfg->{color_normal});
}

sub attributes($self) {
    croak "Undefined window" unless $self->{id};
    $X->get_window_attributes_reply($X->get_window_attributes($self->{id})->{sequence});
}

1;
