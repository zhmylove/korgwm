#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
use strict;
use warnings;
use Authen::Simple::PAM;

=head1 DESCRIPTION

This file is auth module for L<XSecureLock|https://github.com/google/xsecurelock>
It leaves the window unmapped to show the video and tries to authenticate user via PAM.
Read E<xsecurelock(1)> on how to use it.

=cut

# Dirty hack to exit after some time
alarm 16;

# Process password
$_ = <>;
exit 1 unless defined;
s/\s*$//;
s/^\s*//;
s/.\010//g;
s/\010//g;
exit 1 unless length;
exit 0 if Authen::Simple::PAM->new->authenticate("".getpwuid($<), $_);
exit 1;
