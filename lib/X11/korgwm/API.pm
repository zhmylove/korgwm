#!/usr/bin/perl
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :
package X11::korgwm::API;
use strict;
use warnings;
use feature 'signatures';

use Carp;
use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Socket;
use X11::korgwm::Common;
require X11::korgwm::Config;
require X11::korgwm::Executor;

my %clients;
my $server;

# Establish API server
sub init {
    $server = tcp_server $cfg->{api_host}, $cfg->{api_port}, sub($fh, @) {
        my $hdl;
        my $close = sub { $hdl->destroy(); undef $fh; delete $clients{$hdl}; };
        $hdl = AnyEvent::Handle->new(
            fh => $fh,
            timeout => $cfg->{api_timeout},
            on_timeout => $close,
            on_error => $close,
            on_eof => $close,
            on_read => sub {
                $hdl->push_read(line => sub {
                    return $close->() if $_[1] =~ /^(re?set|quit)$/i;
                    my $cb;
                    eval {
                        $cb = X11::korgwm::Executor::parse($_[1]);
                        1;
                    } or return $close->();
                    ref $cb eq "CODE" and $cb->();
                })
            },
        );
        $clients{$hdl} = $hdl;
    };
}

push @X11::korgwm::extensions, \&init;

1;
