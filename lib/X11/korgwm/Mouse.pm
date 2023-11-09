#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Mouse;
use strict;
use warnings;
use feature 'signatures';

use Carp;
use X11::XCB ':all';
use X11::korgwm::Common;
require X11::korgwm::Config;
my ($_motion_win, %_motion_start);
my (%_on_hold, $_on_hold_w);

# Regular motion notify, used to track inter-screen movements
sub _motion_regular($evt) {
    return if @screens == 1 or $evt->{child};
    my $screen = screen_by_xy(@{ $evt }{qw( event_x event_y )}) or return;
    return if $focus->{screen} == $screen;
    $screen->focus();
    $X->flush();
}

# This is called during movement
sub _motion_resize($evt) {
    # Get movement delta
    my $delta;
    @{ $delta }{qw( w h )} = map { $evt->{"root_$_"} - $_motion_start{$_} } qw( x y );
    return unless $delta->{w} or $delta->{h};

    # Save new point
    @{ _motion_start }{qw( x y )} = @{ $evt }{qw( root_x root_y )};

    # Apply it to the window's size
    @{ $delta }{qw( w h )} = map { $_motion_win->{"real_$_"} + $delta->{$_} } qw( w h );
    $delta->{$_} < 1 and $delta->{$_} = 1 for qw( w h );

    # Perform resize
    @{ $_motion_win }{qw( w h )} = @{ $delta }{qw( w h )};
    $_motion_win->resize(@{ $delta }{qw( w h )});
    $X->flush();
}

# This is called during movement
sub _motion_move($evt) {
    # Prepare and amend the vector
    my ($new_x, $new_y) = map { $_motion_win->{$_} + $evt->{"root_$_"} - $_motion_start{$_} } qw( x y );
    $new_y = $cfg->{panel_height} if $new_y < $cfg->{panel_height};
    @{ _motion_start }{qw( x y )} = @{ $evt }{qw( root_x root_y )};

    # Execute real movement
    @{ $_motion_win }{qw( x y )} = ($new_x, $new_y);
    $_motion_win->move($new_x, $new_y);

    # Check if the pointer went outside the screen
    my $new_screen;
    if ($new_screen = screen_by_xy($evt->{event_x}, $evt->{event_y}) and $focus->{screen} != $new_screen) {
        my $always_on = $_motion_win->{always_on};
        $focus->{screen}->win_remove($_motion_win, 1);
        $focus->{screen}->{panel}->title();
        $new_screen->win_add($_motion_win, $always_on);
        $focus->{screen} = $new_screen;
        $new_screen->{panel}->title($_motion_win->title());
    }
    $X->flush();
}

sub init {
    # Motion notifies are handled differently, here we're setting the default handler
    add_event_cb(MOTION_NOTIFY, \&_motion_regular);

    add_event_cb(BUTTON_RELEASE, sub($evt) {
        replace_event_cb(MOTION_NOTIFY, \&_motion_regular);
        $_motion_win = undef;
    });

    add_event_cb(BUTTON_PRESS, sub($evt) {
        # Skip clicks on root and non-floating windows
        $_motion_win = $windows->{ $evt->{child} };
        return unless $_motion_win and $_motion_win->{floating};

        # Determine how did we got here and set proper motion notify handler
        if ($evt->{detail} == 1) {
            # Save the first point
            @{ _motion_start }{qw( x y )} = @{ $evt }{qw( root_x root_y )};

            replace_event_cb(MOTION_NOTIFY, \&_motion_move);
        } elsif ($evt->{detail} == 3) {
            # Move mouse and save the first point
            $X->warp_pointer(0, $evt->{child}, 0, 0, 0, 0, @{ $_motion_win }{qw( real_w real_h)});
            $X->flush();
            @{ _motion_start }{qw( x y )} = (
                $_motion_win->{real_x} + $_motion_win->{real_w}, $_motion_win->{real_y} + $_motion_win->{real_h}
            );

            replace_event_cb(MOTION_NOTIFY, \&_motion_resize);
        } else {
            croak "We got unexpected mouse event, detail:" . $evt->{detail};
        }
    });

    add_event_cb(ENTER_NOTIFY, sub($evt) {
        return if $_motion_win;
        my $wid = $evt->{event};

        # XXX Do we really need to ignore EnterNotifies on unknown windows? I'll leave it here waiting for bugs.
        return unless exists $windows->{$wid};

        # Ignore notifies for hidden windows
        my $win = $windows->{$wid};
        return if $win->{_hidden};

        # Ignore rapid notifies
        return if $_on_hold{$wid};
        $_on_hold{$wid} = AE::timer 0, 0.09, sub { exists $_on_hold{$wid} and delete $_on_hold{$wid} };

        my $new_screen = screen_by_xy($evt->{root_x}, $evt->{root_y});
        $new_screen->focus() if $focus->{screen} != $new_screen;

        $win->focus() if ($focus->{window} // 0) != $win;
    });

    # Grab pointer
    ## For move: mod + LMB
    $X->grab_button(0, $X->root->id,
        EVENT_MASK_BUTTON_PRESS | EVENT_MASK_BUTTON_RELEASE | EVENT_MASK_BUTTON_MOTION,
        GRAB_MODE_ASYNC, GRAB_MODE_ASYNC, 0, 0,
        BUTTON_INDEX_1, MOD_MASK_4);
    ## For resize: mod + RMB
    $X->grab_button(0, $X->root->id,
        EVENT_MASK_BUTTON_PRESS | EVENT_MASK_BUTTON_RELEASE | EVENT_MASK_BUTTON_MOTION,
        GRAB_MODE_ASYNC, GRAB_MODE_ASYNC, 0, 0,
        BUTTON_INDEX_3, MOD_MASK_4);
    $X->flush();
}

push @X11::korgwm::extensions, \&init;

1;
