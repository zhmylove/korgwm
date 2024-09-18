#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Executor;
use strict;
use warnings;
use feature 'signatures';

use Carp;
use POSIX qw( setsid );
use List::Util qw( any );
use X11::XCB ':all';
use X11::korgwm::Common;

# Implementation of all the commands (unless some module push here additional funcs)
our @parser = (
    # Exec command
    [qr/exec\((.+)\)/, sub ($arg) { return sub {
        my $pid = fork;
        die "Cannot fork(2)" unless defined $pid;
        return if $pid;
        close $_ for *STDOUT, *STDERR, *STDIN;
        setsid();
        exec $arg;
        die "Cannot execute $arg";
    }}],

    # Set active tag
    [qr/tag_select\((\d+)\)/, sub ($arg) { return sub {
        # Prevent FocusIn events
        $prevent_focus_in = AE::timer 0, 0.2, sub { $prevent_focus_in = undef };

        $focus->{screen}->tag_set_active($arg - 1);
        $focus->{screen}->refresh();
        $X->flush();
    }}],

    # Append windows from other tag
    [qr/tag_append\((\d+)\)/, sub ($arg) { return sub {
        return unless $arg > 0;
        my $screen = $focus->{screen};
        my $tag = $screen->current_tag();
        my $other = $screen->{tags}->[ $arg - 1 ];
        $tag->append($other);
        $screen->refresh();
        $X->flush();
    }}],

    # Window close or toggle floating / maximize / always_on
    [qr/win_(close|toggle_(?:floating|maximize|always_on))\(\)/, sub ($arg) { return sub {
        my $win = $focus->{window};
        return unless defined $win;

        # Call relevant function
        $arg eq "close"             ? $win->close()             :
        $arg eq "toggle_floating"   ? $win->toggle_floating()   :
        $arg eq "toggle_maximize"   ? $win->toggle_maximize()   :
        $arg eq "toggle_always_on"  ? $win->toggle_always_on()  :
        croak "Unknown win_toggle_$arg function called"         ;

        $focus->{screen}->refresh();
        $X->flush();
    }}],

    # Window move to a particular tag
    [qr/win_move_tag\((\d+)\)/, sub ($arg) { return sub {
        my $win = $focus->{window};
        return unless defined $win;

        return if $win->{always_on};

        my $new_tag = $focus->{screen}->{tags}->[$arg - 1] or return;
        my $curr_tag = $focus->{screen}->current_tag();
        return if $new_tag == $curr_tag;

        $win->hide(); # always from visible tag to invisible
        $new_tag->win_add($win);
        $curr_tag->win_remove($win);

        $focus->{screen}->refresh();
        $X->flush();
    }}],

    # Set active screen
    [qr/screen_select\((\d+)\)/, sub ($arg) { return sub {
        while ($arg > 1) {
            return $screens[$arg - 1]->set_active() if defined $screens[$arg - 1];
            $arg--;
        }
        croak "No screens found" unless defined $screens[0];
        $screens[0]->set_active();
    }}],
    [qr/iddqd|idkfa/i, sub { print "I love KorG!\n" }],

    # Window move to particular screen
    [qr/win_move_screen\((\d+)\)/, sub ($arg) { return sub {
        my $win = $focus->{window};
        return unless defined $win;

        my $new_screen = $screens[$arg - 1] or return;
        my $old_screen = $focus->{screen};
        return if $new_screen == $old_screen;
        return if $new_screen->current_tag->{max_window} and $win->{maximized};

        my $always_on = $win->{always_on};
        $old_screen->win_remove($win);
        $new_screen->win_add($win, $always_on);

        # Follow focus
        $new_screen->{focus} = $win;
        $focus->{screen} = $new_screen;

        if ($win->{floating}) {
            my ($new_x, $new_y) = @{ $win }{qw( real_x real_y )};
            $new_x -= $old_screen->{x};
            $new_y -= $old_screen->{y};
            $new_x += $new_screen->{x};
            $new_y += $new_screen->{y};
            $win->move($new_x, $new_y);
        }

        $old_screen->refresh();
        $new_screen->set_active($win);
        $X->flush();
    }}],

    # Focus previous window (screen independent)
    [qr/focus_prev\(\)/, sub ($arg) { return sub {
        my $win = focus_prev_get();
        return unless defined $win;

        my @tags = $win->tags();
        my $tag = shift @tags // ($win->{always_on} && $win->{always_on}->current_tag());
        return carp "Window $win is visible on multiple tags, do not know how to focus_prev() to it" if @tags;
        return carp "Previous window $win has no tags and is not always_on" unless $tag;

        # Do nothing if there is another maximized window on that tag
        return if $win != ($tag->{max_window} // $win);

        # We need to move the pointer out of the screen in order to avoid ENTER_NOTIFY from improper window
        # resulting into garbaged $focus_prev
        $X->warp_pointer(0, $X->root->id, 0, 0, 0, 0, 0, 0);
        $X->flush();

        # Switch to proper tag unless it is already active
        unless (any { $tag == ($_->current_tag() // 0) } @screens) {
            $tag->{screen}->{focus} = $win;
            $tag->{screen}->tag_set_active($tag->{idx});
            $tag->{screen}->refresh();
        }

        $win->focus();
        $win->warp_pointer();
    }}],

    # Cycle focus
    [qr/focus_cycle\((.+)\)/, sub ($arg) { return sub {
        my $tag = $focus->{screen}->current_tag();
        my $win = $tag->next_window($arg eq "backward");
        return unless defined $win;
        $win->focus();
    }}],

    # Focus move
    [qr/focus_move\(([hjkl])\)/, sub ($arg) { return sub {
        my $win = $focus->{window};
        return unless defined $win;

        my $new = $win->win_by_direction({ h => "left", j => "down", k => "up", l => "right" }->{$arg});
        return unless defined $new;
        $new->focus();
        $new->warp_pointer() if $cfg->{mouse_follow};
    }}],

    # Focus swap
    [qr/focus_swap\(([hjkl])\)/, sub ($arg) { return sub {
        my $win = $focus->{window};
        return unless defined $win;

        my $new = $win->win_by_direction({ h => "left", j => "down", k => "up", l => "right" }->{$arg});
        return unless defined $new;
        $win->swap($new);
    }}],

    # Resize the layout
    [qr/layout_resize\(([hjkl])\)/, sub ($arg) { return sub {
        my $win = $focus->{window};
        return unless defined $win and not $win->{floating};

        my ($delta_x, $delta_y) =
        $arg eq "h" ? (-0.1, 0) :
        $arg eq "j" ? (0, 0.1) :
        $arg eq "k" ? (0, -0.1) :
        $arg eq "l" ? (0.1, 0) : (0, 0);

        # Select proper tag; croak if this window belongs to multiple tags
        my @visible_tags = $win->tags_visible();
        croak "Resizing layout for windows on several visible tags is not implemented" if @visible_tags > 1;
        return unless @visible_tags; # ignore requests for invisibe windows
        my $tag = $visible_tags[0];

        # Call actual resize
        $tag->{layout}->resize(0 + @{ $tag->{windows_tiled} }, @{ $win }{qw( real_i real_j )}, $delta_x, $delta_y);
        $tag->show();
        $win->warp_pointer();
    }}],

    # Expose windows
    [qr/expose\(\)/, sub ($arg) { return sub {
        &X11::korgwm::Expose::expose();
    }}],

    # Resize the layout from API
    [qr/layout_resize\((\d+\s*,\s*\d+\s*,\s*\d+\s*,\s*\d+\s*,\s*-?0\.\d+\s*,\s*-?0\.\d+)\)/, sub ($arg) { return sub {
        my ($arg_screen, $arg_tag, $arg_i, $arg_j, $arg_delta_x, $arg_delta_y) = split /\s*,\s*/, $arg;
        my $screen = $screens[$arg_screen] // return;
        my $tag = $screen->{tags}->[$arg_tag] // return;
        $tag->{layout}->resize(0 + @{ $tag->{windows_tiled} }, $arg_i, $arg_j, $arg_delta_x, $arg_delta_y);
        $tag->show();
    }}],

    # Exit from WM
    [qr/exit\(\)/, sub ($arg) { return sub {
        $X11::korgwm::exit_trigger = 1;
    }}],
);

# Define some debug internals
DEBUG and push @parser,
    [qr/dump_windows\(\)/, sub ($arg) { return sub ($hdl) {
        {
            require Data::Dumper;
            local $Data::Dumper::Sortkeys = 1;
            local $Data::Dumper::Maxdepth = 3;
            $hdl->push_write(Data::Dumper::Dumper($windows));
        }
    }}],
    [qr/dump_screen\((\d+)\)/, sub ($arg) { return sub ($hdl) {
        {
            my $screen = $screens[$arg];
            return $hdl->push_write("No such screen: $arg\n") unless $screen;
            require Data::Dumper;
            local $Data::Dumper::Sortkeys = 1;
            $hdl->push_write(Data::Dumper::Dumper($screen));
        }
    }}],
    [qr/dump_tag\((\d+\s*,\s*\d+)\)/, sub ($arg) { return sub ($hdl) {
        {
            my ($arg_screen, $arg_tag) = split /\s*,\s*/, $arg;
            my $screen = $screens[$arg_screen];
            return $hdl->push_write("No such screen: $arg_screen\n") unless $screen;
            my $tag = $screen->{tags}->[$arg_tag];
            return $hdl->push_write("No such tag: $arg_tag\n") unless $tag;
            require Storable;
            require Data::Dumper;
            local $Data::Dumper::Sortkeys = 1;
            my $ttag = Storable::dclone($tag);
            $ttag->{screen} = "<truncated screen> " . $tag->{screen}->{id};
            $hdl->push_write(Data::Dumper::Dumper($ttag));
        }
    }}],
;

# Parses $cmd and returns corresponding \&sub
sub parse($cmd) {
    for my $known (@parser) {
        return $known->[1]->($1) if $cmd =~ m{^$known->[0]$}s;
    }
    croak "Don't know how to parse $cmd";
    # In case I decide to move back to carp here
    # sub { warn "Unimplemented cmd for key pressed: $cmd" };
}

1;
