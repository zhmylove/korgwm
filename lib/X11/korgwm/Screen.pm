#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Screen;
use strict;
use warnings;
use feature 'signatures';

use X11::XCB ':all';
use X11::korgwm::Tag;
use X11::korgwm::Common;

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
    $self->{panel} = X11::korgwm::Panel->new(0, $w, $x,
        sub ($btn, $ws) { $self->tag_set_active($ws - 1, noselect => 1) }
    );
    $self->{x} = $x;
    $self->{y} = $y;
    $self->{w} = $w;
    $self->{h} = $h;
    return $self;
}

sub destroy($self, $new_screen) {
    # Bring always_on windows back to current tag
    for my $win (@{ $self->{always_on} }) {
        $self->current_tag()->win_add($win);
        $win->{always_on} = undef;
    }
    $self->{always_on} = [];

    # Remove tags (maximized window will be transferred AS-IS)
    $_->destroy($new_screen) for @{ $self->{tags} };

    # Remove panel
    $self->{panel}->destroy();

    # Undef other fields
    %{ $self } = ();
}

# Set $tag_new_id visible for $self screen ($tag_new_id starting from 0)
# Options:
# - rotate => switch to previously selected tag if $tag_new_id is already active
# Options are also passed to $tag->show() as-is
sub tag_set_active($self, $tag_new_id, %opts) {
    $opts{rotate} //= 1;

    $tag_new_id = $self->{tag_prev} if $opts{rotate} and $tag_new_id == $self->{tag_curr};
    return if $tag_new_id == $self->{tag_curr};

    # Remember previous tag
    my $tag_old = $self->current_tag();
    $self->{tag_prev} = $self->{tag_curr};
    $self->{tag_curr} = $tag_new_id;

    # Drop appended windows
    $tag_old->drop_appends();

    # Show new tag and hide the old one
    my $tag_new = $self->current_tag();
    $tag_new->show(%opts) if defined $tag_new;
    $tag_old->hide() if defined $tag_old;

    # Update panel view
    $self->{panel}->ws_set_active(1 + $tag_new_id);
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

sub win_add($self, $win, $always_on = undef) {
    if ($always_on) {
        push @{ $self->{always_on} }, $win;
        croak "Trying to override always_on" if $win->{always_on};
        $win->{always_on} = $self;
    } else {
        my $tag = $self->current_tag();
        croak "Unhandled undefined tag situation" unless defined $tag;
        $tag->win_add($win);
    }
}

sub win_remove($self, $win, $norefresh = undef) {
    my $tag = $self->current_tag();
    croak "Unhandled undefined tag situation" unless defined $tag;
    $tag->win_remove($win, $norefresh);

    # Remove from always_on
    if (($win->{always_on} // 0) == $self) {
        my $arr = $self->{always_on};
        $win->{always_on} = undef;
        @{ $arr } = grep { $win != $_ } @{ $arr };
    }
}

sub focus($self) {
    my $tag = $self->current_tag();

    if (defined $self->{focus} and exists $self->{focus}->{on_tags}->{$tag}) {
        # self->focus already points to some window on active tag
        # This condition just looks prettier in this way, so if-clause is empty
    } else {
        # Focus some window on active tag. It's ok if it return undef
        my $win = $tag->first_window();
        $self->{focus} = $win;
    }

    # If there is a win, focus it; otherwise just reset panel title and update focus structure
    if (defined $self->{focus}) {
        # This will set focus->{screen} as well
        $self->{focus}->focus();
    } else {
        $focus->{screen} = $self;
        $self->{panel}->title();
    }
}

sub set_active($self, $window = undef) {
    $self->focus();
    $self->refresh();
    if ($window) {
        $window->warp_pointer();
    } else {
        $X->root->warp_pointer(int($self->{x} + $self->{w} / 2 - 1), int($self->{h} / 2 - 1));
    }
    $X->flush();
}

sub contains_xy($self, $x, $y) {
    $self->{x} <= $x and $self->{x} + $self->{w} > $x and $self->{y} <= $y and $self->{y} + $self->{h} > $y;
}

1;
