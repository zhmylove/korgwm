#!/usr/bin/perl
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Screen;
use strict;
use warnings;
use feature 'signatures';
use open ':std', ':encoding(UTF-8)';
use utf8;
use Carp;
use X11::XCB ':all';
use X11::korgwm::Tag;

use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

our ($X, $cfg);
*X = *X11::korgwm::X;
*cfg = *X11::korgwm::cfg;

sub new($class, $x, $y, $w, $h) {
    my $self = bless {}, $class;
    $self->{id} = "$x,$y,$w,$h";
    # TODO handle always_on
    $self->{always_on} = [];
    $self->{focus} = undef;
    $self->{tag_curr} = 0;
    $self->{tag_prev} = 0;
    $self->{tags} = [ map { X11::korgwm::Tag->new($self) } @{ $cfg->{ws_names} } ];
    $self->{panel} = X11::korgwm::Panel->new(0, $w, $x, sub ($btn, $ws) { $self->tag_set_active($ws - 1) });
    $self->{x} = $x;
    $self->{y} = $y;
    $self->{w} = $w;
    $self->{h} = $h;
    return $self;
}

sub destroy($self) {
    $self->{panel}->destroy();
    $_->destroy() for @{ $self->{tags} };
    %{ $self } = ();
}

sub tag_set_active($self, $tag_new) {
    $tag_new = $self->{tag_prev} if $tag_new == $self->{tag_curr};
    return if $tag_new == $self->{tag_curr};

    # Hide old tag
    my $tag_curr = $self->{tags}->[$self->{tag_curr}];
    $tag_curr->hide() if defined $tag_curr;

    # Remember previous tag
    $self->{tag_prev} = $self->{tag_curr};
    $self->{tag_curr} = $tag_new;

    # Show new tag
    $tag_curr = $self->{tags}->[$self->{tag_curr}];
    $tag_curr->show() if defined $tag_curr;

    # Update panel view
    $self->{panel}->ws_set_active(1 + $tag_new);
}

sub refresh($self) {
    # Just redraw / rearrange current windows
    my $tag_curr = $self->{tags}->[$self->{tag_curr}];
    $tag_curr->show() if defined $tag_curr;
}

sub add_window($self, $win) {
    my $tag = $self->{tags}->[$self->{tag_curr}];
    croak "Unhandled undefined tag situation" unless defined $tag;
    $tag->win_add($win);
}

sub focus($self) {
    # TODO what if screen->{focus} window is on another, hidden tag?
    unless (defined $self->{focus}) {
        my $tag = $self->{tags}->[$self->{tag_curr}];
        my $win = $tag->next_window();
        $self->{focus} = $win;
    }
    return unless defined $self->{focus};
    $self->{focus}->focus();
    $self->{panel}->title($self->{focus}->title());
}

1;