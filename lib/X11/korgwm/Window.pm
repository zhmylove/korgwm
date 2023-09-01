#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Window;
use strict;
use warnings;
use feature 'signatures';
use open ':std', ':encoding(UTF-8)';
use utf8;
use Carp;
use List::Util qw( first );
use Encode qw( encode decode );
use X11::XCB ':all';

use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

our ($X, $cfg);
*X = *X11::korgwm::X;
*cfg = *X11::korgwm::cfg;

sub new($class, $id) {
    bless { id => $id, on_tags => {} }, $class;
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

sub resize_and_move($self, $x, $y, $w, $h, $bw=$cfg->{border_width}) {
    croak "Undefined window" unless $self->{id};
    @{ $self }{qw( real_x real_y real_w real_h )} = ($x, $y, $w, $h);
    _resize_and_move($self->{id}, $x, $y, $w, $h, $bw);
}

sub _stack_above($self) {
    $X->configure_window($self->{id}, CONFIG_WINDOW_STACK_MODE, STACK_MODE_ABOVE);
}

sub _stack_below($self, $upper) {
    $X->configure_window($self->{id}, CONFIG_WINDOW_SIBLING | CONFIG_WINDOW_STACK_MODE, $upper->{id}, STACK_MODE_BELOW);
}

sub focus($self) {
    croak "Undefined window" unless $self->{id};

    # Get focus pointer and reset focus for previously focused window, if any
    my $focus = $X11::korgwm::focus;
    $focus->{window}->reset_border() if $focus->{window} and $self != ($focus->{window} // 0);

    $X->change_window_attributes($self->{id}, CW_BORDER_PIXEL, $cfg->{color_border_focus});

    # TODO implement focus for several screens: check current focus, check focus for screens, select random one
    my @focus_screens = $self->screens;
    croak "Unimplemented focus for several screens: @focus_screens" unless @focus_screens == 1;

    my @visible_tags = $self->tags_visible();
    my $tag = $visible_tags[0];

    if (0 == @visible_tags) {
        # We were asked to focus invisible window, do nothing?
        carp "Trying to focus an invisible window " . $self->{id};

        # Looks like X11 sometimes manages to send EnterNotify on tag switching, so return here
        # TODO race condition should be fixed
        return;
    } elsif (@visible_tags > 1) {
        # Focusing window residing on multiple visible tags is not implemented yet
        croak "Focusing window on multiple visible tags is not supported";
    } elsif ($self->{maximized} or 0 == @{ $tag->{windows_float} }) {
        # Just raise the window if it is maximized or there are no floating windows on current tag
        $self->_stack_above();
    } else {
        # The window is not maximized and there are some floating windows
        # This procedure likely fixes the bug I observed 6 years ago in WMFS1

        # Select the most top window and place all others below
        # - if there are transient_for windows, they're floating and place them on top of the stack
        my @stack = $self->transients();
        # - if current window is floating, place it below
        push @stack, $self if $self->{floating};
        # - if there are other floating windows, place them below
        push @stack, grep { $_ != $self } @{ $tag->{windows_float} };
        # - place this window below if it's tiled
        push @stack, $self unless $self->{floating};
        # - place all others below
        push @stack, grep { $_ != $self } @{ $tag->{windows_tiled} };

        # Fist element of the @stack should be raised above others
        $stack[0]->_stack_above();

        # Other elements should be chained below
        for (my $i = 1; $i < @stack; $i++) {
            $stack[$i]->_stack_below($stack[$i - 1]);
        }
    }

    $X->set_input_focus(INPUT_FOCUS_POINTER_ROOT, $self->{id}, TIME_CURRENT_TIME);

    # Update focus structure and panel title
    $tag->{screen}->{focus} = $self;
    $tag->{screen}->{panel}->title($self->title // "");
    $focus->{window} = $self;
    $focus->{screen} = $focus_screens[0];

    $X->flush();
}

sub reset_border($self) {
    croak "Undefined window" unless $self->{id};
    # TODO update panel on focused screen..?
    $X->change_window_attributes($self->{id}, CW_BORDER_PIXEL, $cfg->{color_border});
}

sub hide($self) {
    $X11::korgwm::unmap_prevent->{$self->{id}} = 1;
    for my $screen ($self->screens) {
        $screen->{panel}->title() if $screen->{focus} == $self;
    }
    $X->unmap_window($self->{id});
}

sub show($self) {
    $X->map_window($self->{id});
}

sub tags($self) {
    values %{ $self->{on_tags} // {} };
}

sub tags_visible($self) {
    my @rc;
    for my $screen ($self->screens()) {
        my $screen_tag = $screen->current_tag();
        push @rc, grep { $screen_tag == $_ } $self->tags();
    }
    return @rc;
}

sub screens($self) {
    my %screens;
    $screens{$_} = $_ for map { $_->{screen} } $self->tags();
    values %screens;
}

# Recursively return all transient windows
sub transients($self) {
    my @siblings_xid = keys %{ $self->{siblings} };
    return () unless @siblings_xid;
    my $known = $X11::korgwm::windows;
    map { ($known->{$_}->transients(), $known->{$_}) } @siblings_xid;
}

sub toggle_floating($self) {
    # There is no way to disable floating for transient windows
    return if $self->{transient_for};

    $self->{floating} = ! $self->{floating};

    # Deal with geometry
    my ($x, $y, $w, $h) = map { defined ? $_ : 0 } @{ $self }{qw( x y w h )};
    $y = $cfg->{panel_height} if $y < $cfg->{panel_height};

    # Fix window size and/or position
    if ($w < 1 or $h < 1 or $x < 1 or $y < 1) {
        my ($screen_min_w, $screen_min_h);
        for my $screen ($self->screens()) {
            $screen_min_h = $screen->{h} if $screen->{h} < ($screen_min_h // 10**6);
            $screen_min_w = $screen->{w} if $screen->{w} < ($screen_min_w // 10**6);
        }
        die unless $screen_min_w and $screen_min_h;
        if ($w < 1 or $h < 1) {
            # Window looks uncofigured, so move it to the center
            $x = int($screen_min_w / 4);
            $y = int($screen_min_h / 4);
        }
        $w = int($screen_min_w / 2) if $w < 1;
        $h = int($screen_min_h / 2) if $h < 1;
    }

    @{ $self }{qw( x y w h )} = ($x, $y, $w, $h);

    $self->resize_and_move($x, $y, $w, $h);
    $_->win_float($self, $self->{floating}) for $self->tags();
}

sub toggle_maximize($self) {
    # TODO implement toggle_maximize
    croak "Unimplemented";

    $self->{maximized} = ! $self->{maximized};
}

sub toggle_always_on($self) {
    return unless $self->{floating};
    my $focus = $X11::korgwm::focus; # due to sub focus()

    if ($self->{always_on} = ! $self->{always_on}) {
        # Remove window from all tags and store it in always_on of current screen
        $_->win_remove($self) for $self->tags();
        push @{ $focus->{screen}->{always_on} }, $self;
    } else {
        # Remove window from always_on and store it in current tag
        my $arr = $focus->{screen}->{always_on};
        splice @{ $arr }, $_, 1 for reverse grep { $arr->[$_] == $self } 0..$#{ $arr };
        $focus->{screen}->current_tag()->win_add($self);
    }
}

sub close($self) {
    my $icccm_del_win = $X->atom(name => 'WM_DELETE_WINDOW')->id;
    my ($value, $prop) = _get_property($self->{id}, "WM_PROTOCOLS", "ATOM", 16);

    # Use ICCCM to gently ask client to close the window
    if (first { $_ == $icccm_del_win } unpack "L" x $prop->{value_len}, $value) {
        my $packed = pack('CCSLLLL', CLIENT_MESSAGE, 32, 0, $self->{id}, $X->atom(name => 'WM_PROTOCOLS')->id,
            $X->atom(name => 'WM_DELETE_WINDOW')->id, TIME_CURRENT_TIME);
        $X->send_event(0, $self->{id}, EVENT_MASK_STRUCTURE_NOTIFY, $packed);
    } else {
        # XXX xcb_destroy_window() instead of kill?
        $X->kill_client($self->{id});
    }
    $X->flush();
}

1;
