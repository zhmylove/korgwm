#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::Expose;
use strict;
use warnings;
use feature 'signatures';
use open ':std', ':encoding(UTF-8)';
use utf8;
use Carp;
use X11::XCB ':all';

use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

use Glib::Object::Introspection;
use Gtk3 -init;
use File::Path;

our ($X, $cfg, $windows, %screens);
*X = *X11::korgwm::X;
*cfg = *X11::korgwm::cfg;
*windows = *X11::korgwm::windows;
*screens = *X11::korgwm::screens;

my $display;
my $destdir = "/tmp/korgwm-dump/"; # TODO remove

# Iterate through all windows and dump their pixmaps to the folder
sub win_dump_all {
    # Update pixbufs for all visible windows
    $_->_update_pixbuf() for map { $_->current_tag()->windows() } values %screens;

    # Render them TODO into a file
    $windows->{$_}->{pixbuf}->save("$destdir/$_.png", "png") for keys %{ $windows };
}

# Inverse approach is used in order to simplify Expose deletion / re-implementation
BEGIN {
    # Insert some pixbuf-specific methods 
    sub X11::korgwm::Window::_update_pixbuf($self) {
        my $win = Gtk3::Gdk::X11Window->foreign_new_for_display($display, $self->{id});
        $self->{pixbuf} = Gtk3::Gdk::pixbuf_get_from_window($win, 0, 0, @{ $self }{qw( real_w real_h )});
    }

    # Register hide hook
    push @X11::korgwm::Window::hooks_hide, sub($self) { $self->_update_pixbuf(); };
}

sub init {
    # Set up extension
    Glib::Object::Introspection->setup(basename => "GdkX11", version  => "3.0", package  => "Gtk3::Gdk");
    $display = Gtk3::Gdk::Display::get_default();
    File::Path::make_path($destdir); # TODO remove
}

# TODO see https://docs.gtk.org/gdk-pixbuf/method.Pixbuf.composite.html
# TODO see https://stuff.mit.edu/afs/athena/astaff/source/src-9.2/third/gdk-pixbuf/doc/html/gdk-pixbuf-rendering.html

push @X11::korgwm::extensions, \&init;

1;
