#!/usr/bin/perl
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Window;
use strict;
use warnings;
use feature 'signatures';
use open ':std', ':encoding(UTF-8)';
use utf8;
use Carp;
use Encode qw( encode decode );
use X11::XCB ':all';

use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

our ($X, $cfg);
*X = *X11::korgwm::X;
*cfg = *X11::korgwm::cfg;

sub new($class, $id) {
    bless { id => $id }, $class;
}

sub _get_property($wid, $prop_name, $prop_type='UTF8_STRING', $ret_length=8) {
    my $aname = $X->atom(name => $prop_name)->id;
    my $atype = $X->atom(name => $prop_type)->id;
    my $cookie = $X->get_property(0, $wid, $aname, $atype, 0, $ret_length);
    my $prop;
    eval { $prop = $X->get_property_reply($cookie->{sequence}); 1} or return undef;
    my $value = $prop ? $prop->{value} : undef;
    $value = decode('UTF-8', $value) if defined $value and $prop_type eq 'UTF8_STRING';
    ($value) = unpack('L', $value) if defined $value and $prop_type eq 'WINDOW';
    return wantarray ? ($value, $prop) : $value;
}

sub _resize_and_move($wid, $x, $y, $w, $h, $bw=$cfg->{border_width}) {
    my $mask = CONFIG_WINDOW_X | CONFIG_WINDOW_Y | CONFIG_WINDOW_WIDTH | CONFIG_WINDOW_HEIGHT |
        CONFIG_WINDOW_BORDER_WIDTH;
    $X->configure_window($wid, $mask, $x, $y, $w - 2 * $bw, $h - 2 * $bw, $bw);
}

sub _configure_notify($wid, $sequence, $x, $y, $w, $h, $above_sibling=0, $override_redirect=0,
        $bw=$cfg->{border_width}) {
    my $packed = pack('CCSLLLssSSSC', CONFIGURE_NOTIFY, 0, $sequence,
        $wid, # event
        $wid, # window
        $above_sibling, $x, $y, $w - 2 * $bw, $h - 2 * $bw, $bw, $override_redirect);
    $X->send_event(0, $wid, EVENT_MASK_STRUCTURE_NOTIFY, $packed);
}

sub _attributes($wid) {
    $X->get_window_attributes_reply($X->get_window_attributes($wid)->{sequence});
}

sub _title($wid) {
    my $title = _get_property($wid, "_NET_WM_NAME", "UTF8_STRING", int($cfg->{title_max_len} / 4));
    $title = _get_property($wid, "WM_NAME", "STRING", int($cfg->{title_max_len} / 4)) unless length $title;
    $title;
}

sub _transient_for($wid) {
    _get_property($wid, "WM_TRANSIENT_FOR", "WINDOW", 16);
}

# Generate accessors by object
INIT {
    no strict 'refs';
    for my $func (qw(
        attributes
        configure_notify
        get_property
        resize_and_move
        title
        transient_for
        )) {
        *{__PACKAGE__ . "::$func"} = sub {
            my $self = shift;
            croak "Undefined window" unless $self->{id};
            "_$func"->($self->{id}, @_);
        };
    }
}

sub focus($self) {
    croak "Undefined window" unless $self->{id};
    my $focus = $X11::korgwm::focus;
    $focus->{focus}->reset_border() if defined $focus->{focus} and $focus->{focus} != $self;
    $X->change_window_attributes($self->{id}, CW_BORDER_PIXEL, $cfg->{color_fg});
    $X->configure_window($self->{id}, CONFIG_WINDOW_STACK_MODE, STACK_MODE_ABOVE);
    $X->configure_window($_, CONFIG_WINDOW_STACK_MODE, STACK_MODE_ABOVE) for keys %{ $self->{siblings} // {} };
    $X->set_input_focus(INPUT_FOCUS_POINTER_ROOT, $self->{id}, TIME_CURRENT_TIME);
    $X11::korgwm::focus->{focus} = $self;
    $X->flush();
}

sub reset_border($self) {
    croak "Undefined window" unless $self->{id};
    $X->change_window_attributes($self->{id}, CW_BORDER_PIXEL, $cfg->{color_bg});
}

sub hide($self) {
    $X11::korgwm::unmap_prevent->{$self->{id}} = 1;
    $X->unmap_window($self->{id});
}

sub show($self) {
    $X->map_window($self->{id});
}

sub toggle_floating($self) {
    $self->{floating} = ! $self->{floating};

    # Deal with geometry
    my ($x, $y, $w, $h) = @{ $self }{qw( x y w h )};
    $y = $cfg->{panel_height} if $y < $cfg->{panel_height};

    # TODO consider valid values for this fixup of windows, which did not asked proper size
    $w = 150 if $w < 1;
    $h = 150 if $h < 1;

    $self->resize_and_move($x, $y, $w, $h);
    $_->win_float($self, $self->{floating}) for values %{ $self->{on_tags} // {} };
}

1;
