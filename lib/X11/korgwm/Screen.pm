#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Screen;
use strict;
use warnings;
use feature 'signatures';
use open ':std', ':encoding(UTF-8)';
use utf8;
use Carp;
use List::Util qw( first );
use X11::XCB ':all';
use X11::korgwm::Tag;

use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

our ($X, $cfg);
*X = *X11::korgwm::X;
*cfg = *X11::korgwm::cfg;

sub new($class, $x, $y, $w, $h) {
    my $idx = 0;
    my $self = bless {}, $class;
    $self->{id} = "$x,$y,$w,$h";
    $self->{always_on} = [];
    $self->{focus} = undef;
    $self->{tag_curr} = 0;
    $self->{tag_prev} = 0;
    $self->{tags} = [ map { X11::korgwm::Tag->new($self) } @{ $cfg->{ws_names} } ];
    $_->{idx} = $idx++ for @{ $self->{tags} };
    $self->{panel} = X11::korgwm::Panel->new(0, $w, $x, sub ($btn, $ws) { $self->tag_set_active($ws - 1) });
    $self->{x} = $x;
    $self->{y} = $y;
    $self->{w} = $w;
    $self->{h} = $h;
    return $self;
}

sub destroy($self, $new_screen) {
    # Remove tags
    $_->destroy($new_screen) for @{ $self->{tags} };

    # Remove panel
    $self->{panel}->destroy();

    # Undef other filds
    %{ $self } = ();
}

sub tag_set_active($self, $tag_new) {
    $tag_new = $self->{tag_prev} if $tag_new == $self->{tag_curr};
    return if $tag_new == $self->{tag_curr};

    # Hide old tag
    my $tag_curr = $self->current_tag();
    $tag_curr->hide() if defined $tag_curr;

    # Remember previous tag
    $self->{tag_prev} = $self->{tag_curr};
    $self->{tag_curr} = $tag_new;

    # Show new tag
    $tag_curr = $self->current_tag();
    $tag_curr->show() if defined $tag_curr;

    # Update panel view
    $self->{panel}->ws_set_active(1 + $tag_new);
}

# Return current tag
sub current_tag($self) {
    $self->{tags}->[ $self->{tag_curr} ];
}

sub refresh($self) {
    # Just redraw / rearrange current windows
    my $tag_curr = $self->current_tag();
    $tag_curr->show() if defined $tag_curr;
}

sub win_add($self, $win) {
    my $tag = $self->current_tag();
    croak "Unhandled undefined tag situation" unless defined $tag;
    $tag->win_add($win);
}

sub win_remove($self, $win) {
    my $tag = $self->current_tag();
    croak "Unhandled undefined tag situation" unless defined $tag;
    $tag->win_remove($win);
}

sub focus($self) {
    my $tag = $self->current_tag();

    if (defined $self->{focus} and exists $self->{focus}->{on_tags}->{$tag}) {
        # self->focus already points to some window on active tag
        # This condition just looks prettier in this way, so if-clause is empty
    } else {
        # Focus some window on active tag
        my $win = $tag->first_window();
        $self->{focus} = $win;
    }

    # If there is a win, focus it; otherwise just reset panel title and update focus structure
    if (defined $self->{focus}) {
        $self->{focus}->focus();
    } else {
        $X11::korgwm::focus->{screen} = $self;
        $self->{panel}->title();
    }
}

sub set_active($self, $window = undef) {
    $self->focus();
    $self->refresh();
    if ($window) {
        $window->warp_pointer();
    } else {
        $X->root->warp_pointer(int($self->{x} + $self->{w} / 2), int($self->{h} / 2));
    }
    $X->flush();
}

1;
