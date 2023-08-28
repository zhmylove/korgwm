#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
use strict;
use warnings;
use Authen::Simple::PAM;
use X11::XCB ':all';
use X11::XCB::Connection;

=head1 DESCRIPTION

This file is auth module for L<XSecureLock|https://github.com/google/xsecurelock>
It changes auth window geometry to fill the screen and tries to authenticate user via PAM.
Read E<xsecurelock(1)> on how to use it.

=cut

# Render window
my $W = $ENV{XSCREENSAVER_WINDOW} or die "No XSCREENSAVER_WINDOW set";
my $X = X11::XCB::Connection->new or die "Unable to connect X11";
my $mask = CONFIG_WINDOW_X | CONFIG_WINDOW_Y | CONFIG_WINDOW_WIDTH | CONFIG_WINDOW_HEIGHT;
$X->configure_window($W, $mask, 0, 0, map { $X->root->rect->$_ } qw( width height ));
$X->change_window_attributes($W, CW_BACK_PIXEL, 0x262729);
$X->map_window($W);
$X->flush();

# Dirty hack to exit after some time
alarm 16;

# Process password
$_ = <>;
exit 1 unless defined;
s/\s*$//;
s/^\s*//;
exit 1 unless length;
exit 0 if Authen::Simple::PAM->new->authenticate("".getpwuid($<), $_);
exit 1;
